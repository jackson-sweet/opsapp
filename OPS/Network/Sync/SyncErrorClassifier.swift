//
//  SyncErrorClassifier.swift
//  OPS
//
//  Single source of truth for how the offline-first outbound sync engine reacts
//  to a failed push. Every error splits into one of three dispositions, and a
//  paired pure state-transition policy applies that disposition to a
//  SyncOperation identically on BOTH outbound paths (DataActor +
//  OutboundProcessor) so the two can never drift.
//
//  Born from the 2026-07-22 outage (SYNC RECOVERY spec §3): a permanent 400
//  (auto-lead `source_thread_key` rejection) burned the same 20-retry budget as
//  a transient 504, then parked invisibly. The distinction below is the fix —
//  permanent rejections park immediately (never auto-retry), transient failures
//  keep the existing retry+backoff budget, auth failures route to re-auth.
//
//  NOTE — intentionally distinct from `UploadErrorClassifier`:
//    * `UploadErrorClassifier` folds auth (401/403/PGRST3) into transient so its
//      retry path forces a fresh Firebase token. That subsystem has no re-auth
//      escalation, so refresh-on-retry is the right call there.
//    * Here, auth is its OWN disposition routed to the existing `.authExpired`
//      branch (posts `.syncAuthExpired` → re-authentication). Per SYNC RECOVERY
//      spec §3 the auth row is `PGRST301 / JWT / 401`.
//  Do NOT "reconcile" the two — the divergence is by design.
//

import Foundation
import Supabase

// MARK: - Disposition

/// How the sync engine should treat a failed outbound push.
enum SyncFailureDisposition: Equatable {
    /// Retry-worthy: bad signal, server hiccup, serialization/lock contention.
    /// Consumes the existing retry budget (2^n≤60s backoff, cap 20 → `failed`).
    case transient
    /// The server rejected the request and will keep rejecting it (4xx / data /
    /// integrity / syntax / deliberate raise). Park immediately; NEVER auto-retry.
    case permanent
    /// Expired / invalid JWT. Route to the existing auth-expired handling
    /// (re-authentication), unchanged.
    case auth
}

// MARK: - Classifier

enum SyncErrorClassifier {

    /// Classify any error thrown by the outbound push into a disposition.
    ///
    /// Precedence: typed matches first (URLError → PostgrestError.code →
    /// HTTPError.statusCode → our own SyncError), then a string-heuristic fallback
    /// for errors that only surface via `localizedDescription` (wrapped /
    /// re-thrown), then `.transient` — never park on a guess.
    static func disposition(for error: Error) -> SyncFailureDisposition {
        // Site-visit writes deliberately preserve repository failure semantics
        // across both outbound engines. RLS/auth asks the app to re-authenticate;
        // FK/schema/data failures park for actionable recovery; transport retries.
        if let siteVisitError = error as? SiteVisitRepositoryError {
            switch siteVisitError {
            case .authorization:
                return .auth
            case .dependency, .schemaCapability, .malformedServerData,
                 .companyMismatch, .visitNotFound:
                return .permanent
            case .transport:
                return .transient
            case let .server(code, message, _, _):
                if code == "42501"
                    || code?.hasPrefix("PGRST3") == true
                    || message.contains("401")
                    || message.localizedCaseInsensitiveContains("JWT") {
                    return .auth
                }
                if code == "PGRST202"
                    || code == "PGRST204"
                    || code?.hasPrefix("PGRST2") == true {
                    return .permanent
                }
                if let disposition = disposition(forPostgrestCode: code) {
                    return disposition
                }
                return stringDisposition(
                    for: siteVisitError.localizedDescription
                ) ?? .transient
            }
        }
        // Media failures split on whether the bytes still exist. An absent file
        // can never come back (the local copy was the only one until upload) —
        // that is terminal. A file that is present but unreadable right now
        // (Data Protection during a locked-device drain) must retry, or a
        // perfectly good photo gets written off.
        if let mediaError = error as? SiteVisitMediaSyncError {
            switch mediaError {
            case .localFileMissing, .invalidRemoteURL:
                return .permanent
            case .localFileUnreadable:
                return .transient
            }
        }

        // 1. URLError — Foundation network layer.
        if let urlError = error as? URLError {
            return disposition(forURLError: urlError)
        }

        // 2. PostgrestError — supabase-swift's typed PostgREST error. `.code`
        //    carries the Postgres SQLSTATE (e.g. "40001", "23514") or a PostgREST
        //    code (e.g. "PGRST301"). The gold standard when present.
        if let pgError = error as? PostgrestError {
            if let typed = disposition(forPostgrestCode: pgError.code) {
                return typed
            }
            // Unknown / nil code — let the message heuristics decide, else transient.
            return stringDisposition(for: pgError.message) ?? .transient
        }

        // 3. HTTPError — supabase-swift's catch-all when the body wasn't a
        //    PostgrestError. Classify on the HTTP status.
        if let httpError = error as? HTTPError {
            return disposition(forHTTPStatus: httpError.response.statusCode)
        }

        // 4. SyncError — our own wrapper (some paths throw it before the raw
        //    transport error reaches here).
        if let syncError = error as? SyncError {
            return disposition(forSyncError: syncError)
        }

        // 5. Wrapped / unknown — fall back to localizedDescription heuristics,
        //    then transient (never park on a guess).
        return stringDisposition(for: error.localizedDescription) ?? .transient
    }

    // MARK: URLError

    static func disposition(forURLError error: URLError) -> SyncFailureDisposition {
        switch error.code {
        case .notConnectedToInternet,   // offline
             .networkConnectionLost,     // connection dropped mid-flight
             .timedOut,                  // timeout
             .cannotConnectToHost,       // host unreachable right now
             .dataNotAllowed:            // cellular data disabled / low-data mode
            return .transient
        case .userAuthenticationRequired:
            // Preserve existing `classifySyncError` behavior (→ authExpired).
            return .auth
        default:
            // Every other URLError is network-layer and retry-safe. Never park
            // outbound work on a network guess.
            return .transient
        }
    }

    // MARK: PostgrestError code

    private static let transientSQLStates: Set<String> = ["40001", "40P01", "55P03", "57014"]
    private static let permanentSQLClasses: Set<String> = ["22", "23", "42"]

    /// Returns a disposition for a PostgREST/Postgres error code, or nil when the
    /// code is empty or in no known bucket (caller falls back to message heuristics).
    static func disposition(forPostgrestCode code: String?) -> SyncFailureDisposition? {
        guard let code, !code.isEmpty else { return nil }

        // PostgREST JWT/auth namespace (PGRST3xx) → re-authentication.
        if code.hasPrefix("PGRST3") {
            return .auth
        }

        // Transient Postgres SQLSTATEs — serialization / lock / cancel. THE outage
        // class: a concurrent-write conflict that succeeds on replay.
        //   40001 serialization_failure   40P01 deadlock_detected
        //   55P03 lock_not_available      57014 query_canceled (statement timeout)
        if transientSQLStates.contains(code) {
            return .transient
        }

        // Permanent Postgres SQLSTATE classes — the request will keep failing:
        //   22xxx data_exception (bad value/format, e.g. 22023 invalid_parameter_value)
        //   23xxx integrity_constraint_violation (unique/fk/check/not-null)
        //   42xxx syntax_error_or_access_rule_violation (incl. 42501 RLS)
        // plus deliberate SECURITY DEFINER raises:
        //   P0001 raise_exception, P0002 no_data_found
        let sqlClass = String(code.prefix(2))
        if permanentSQLClasses.contains(sqlClass) { return .permanent }
        if code == "P0001" || code == "P0002" { return .permanent }

        // Any other code (PGRST1xx API-request, PGRST2xx schema-cache, connection
        // classes, …) → undecided; caller defaults to transient (never park on a guess).
        return nil
    }

    // MARK: HTTPError status

    static func disposition(forHTTPStatus status: Int) -> SyncFailureDisposition {
        // 401 → re-authentication (the "401-ish auth signal" from spec §3).
        if status == 401 { return .auth }
        // 5xx server error, 429 rate-limit, 408 request-timeout → transient.
        if (500...599).contains(status) || status == 429 || status == 408 {
            return .transient
        }
        // Every other 4xx → permanent (403/404/409/422/…): the request will keep
        // being rejected.
        if (400...499).contains(status) { return .permanent }
        // Non-error / unexpected status → transient (never park on a guess).
        return .transient
    }

    // MARK: SyncError wrapper

    static func disposition(forSyncError error: SyncError) -> SyncFailureDisposition {
        switch error {
        case .authExpired, .unauthorized, .missingUserId, .missingCompanyId:
            return .auth
        case .serverError(let statusCode, _):
            return disposition(forHTTPStatus: statusCode)
        case .apiError(let underlying), .unknown(let underlying):
            return disposition(for: underlying)   // recurse into the wrapped error
        case .encodingFailed:
            // Deterministic client-side failure — an identical retry fails
            // identically. Park rather than burn the budget.
            return .permanent
        default:
            // networkUnavailable, timeout, notConnected, conflict, dependencyNotMet,
            // decodingFailed, dataCorruption, quotaExceeded, entityNotFound,
            // alreadySyncing → retry-safe. Never park on a guess.
            return .transient
        }
    }

    // MARK: String fallback

    /// Last-resort classification for errors that only expose a message string
    /// (wrapped / re-thrown so the typed error is lost). Mirrors the existing
    /// `classifySyncError` auth heuristics and matches unambiguous Postgres
    /// phrases. Returns nil when nothing matches (caller defaults to transient).
    static func stringDisposition(for text: String) -> SyncFailureDisposition? {
        // Auth — same heuristics as classifySyncError (preserve existing behavior).
        if text.contains("PGRST301") || text.contains("JWT") || text.contains("401") {
            return .auth
        }

        // Transient — serialization / lock / cancel, by code or canonical phrase.
        if text.contains("40001") || text.contains("40P01")
            || text.contains("55P03") || text.contains("57014") {
            return .transient
        }
        let lower = text.lowercased()
        if lower.contains("could not serialize")
            || lower.contains("deadlock detected")
            || lower.contains("canceling statement due to statement timeout")
            || lower.contains("lock not available")
            || lower.contains("lock timeout") {
            return .transient
        }

        // Permanent — unambiguous integrity / data-exception / deliberate-raise
        // phrases. Conservative on purpose: only park when the wording leaves no
        // doubt (never park on a guess).
        if lower.contains("violates foreign key constraint")
            || lower.contains("violates check constraint")
            || lower.contains("violates not-null constraint")
            || lower.contains("violates unique constraint")   // non-PK (PK handled earlier)
            || lower.contains("invalid input syntax")
            || lower.contains("value too long")
            || lower.contains("out of range")
            || lower.contains("unsupported_opportunity_field") {  // RC1 22023, pre-M1
            return .permanent
        }
        if text.contains("P0001") || text.contains("P0002") {
            return .permanent
        }

        return nil
    }
}

// MARK: - Failure Policy (shared state transition)

/// What `SyncOperationFailurePolicy.apply` did — lets each outbound path fire the
/// matching analytics / notification side-effects without re-deriving the decision.
enum SyncFailureOutcome: Equatable {
    /// Permanent rejection — status set to `parked`, no retry consumed.
    case parked
    /// Transient — retryCount incremented, status back to `pending`.
    case retryScheduled(retryCount: Int)
    /// Transient — retry budget exhausted, status set to `failed` (recoverable).
    case exhausted(retryCount: Int)
    /// Auth — status set to `failed`; caller posts `.syncAuthExpired`.
    case authExpired
}

/// The ONE place the post-catch SyncOperation state transition lives, so the two
/// mirrored outbound paths (`DataActor.executeOperation` +
/// `OutboundProcessor.executeOperation`) cannot drift. Pure: mutates the passed
/// operation's status/retryCount/lastError and returns the outcome. Does NOT
/// persist — the caller wraps it in the appropriate save/transaction and fires
/// the matching side-effects. PK-violation idempotency is handled by the caller
/// BEFORE this runs (a 23505 would otherwise classify permanent).
enum SyncOperationFailurePolicy {

    /// Retry budget: a transient op flips to `failed` (recoverable) at this count.
    /// The single source of truth for the outbound retry cap.
    static let maxRetries = 20

    @discardableResult
    static func apply(
        _ disposition: SyncFailureDisposition,
        to operation: SyncOperation,
        errorDescription: String
    ) -> SyncFailureOutcome {
        operation.lastError = errorDescription

        switch disposition {
        case .auth:
            operation.status = "failed"
            return .authExpired

        case .permanent:
            // Park immediately — never auto-retry. retryCount is untouched
            // (no budget consumed); only user Retry / Discard moves it out.
            operation.status = "parked"
            return .parked

        case .transient:
            operation.retryCount += 1
            if operation.retryCount >= maxRetries {
                operation.status = "failed"
                return .exhausted(retryCount: operation.retryCount)
            } else {
                operation.status = "pending"
                return .retryScheduled(retryCount: operation.retryCount)
            }
        }
    }
}
