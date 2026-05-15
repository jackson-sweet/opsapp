//
//  UploadErrorClassifier.swift
//  OPS
//
//  Classifies upload / sync errors into transient (retry-worthy) vs permanent
//  (server-rejected and not retryable) buckets. Drives:
//
//    1. In-session retry decisions in ImageSyncManager / PhotoProcessor /
//       DimensionedPhotoSyncManager.
//    2. Whether AutoBugReporter fires on the catch site — only permanent
//       errors auto-bug. Transient errors are normal in the field (gloves on,
//       wifi blinking, truck moving through dead zones) and noise.
//
//  Background: a May-12 outage tightened the RLS policy on project_photos
//  INSERT; iOS catches printed and continued, so Crew / Unassigned users lost
//  uploads silently for 3 days. The fix is two-pronged — auto-bug-report
//  permanent failures, AND surface a per-tile failed state to the user.
//

import Foundation
import Supabase

/// Triage bucket for any error thrown by the upload / sync layer.
enum UploadErrorKind: Equatable {
    /// Retryable: network, timeout, server overload. Bad signal is normal in
    /// the field; never auto-bug for transient.
    case transient(reason: String)

    /// Server rejected the request and will keep rejecting it. RLS violation,
    /// validation error, schema mismatch, 4xx. Auto-bug + surface failed state.
    /// `errorCode` is the dedupe seed — pass it to AutoBugReporter so repeats
    /// collapse into one ticket per (category, screen, file, code) quadruple.
    case permanent(errorCode: String, reason: String)

    /// Unknown shape. Treat as transient for retry purposes but auto-bug if
    /// the in-session retry cap is exhausted — an unknown error that keeps
    /// firing IS a bug.
    case unknown(reason: String)

    /// Convenience — true when the bucket warrants an AutoBugReporter fire
    /// at this catch site without waiting for retry exhaustion.
    var shouldAutoBugImmediately: Bool {
        if case .permanent = self { return true }
        return false
    }

    /// Convenience — stable code for AutoBugReporter dedupe. Transient errors
    /// only generate auto-bugs after retry exhaustion; the seed for those is
    /// the underlying reason category.
    var dedupeCode: String {
        switch self {
        case .transient(let reason): return "TRANSIENT_\(String(reason.prefix(40)))"
        case .permanent(let code, _): return code
        case .unknown(let reason): return "UNKNOWN_\(String(reason.prefix(40)))"
        }
    }
}

enum UploadErrorClassifier {

    /// Classify any Error thrown by the upload / sync layer.
    static func classify(_ error: Error) -> UploadErrorKind {
        // PostgrestError — supabase-swift's Postgrest wrapper. Carries the
        // Postgres SQLSTATE code, which is the gold standard for permanent
        // vs transient. RLS rejections always arrive here as code "42501".
        if let pgError = error as? PostgrestError {
            let code = pgError.code ?? ""
            return classifyPostgresCode(code, message: pgError.message)
        }

        // HTTPError — supabase-swift's catch-all HTTP wrapper. Classify on
        // status code. 5xx = transient (server hiccup), 4xx = permanent
        // (request will keep getting rejected).
        if let httpError = error as? HTTPError {
            return classifyHTTPStatus(
                httpError.response.statusCode,
                context: "supabase-http"
            )
        }

        // Local PresignedURLUploadService.UploadError (cases scoped to S3
        // upload pipeline). The statusCode payload comes from the inner
        // HTTPURLResponse.
        if let uploadError = error as? UploadError {
            switch uploadError {
            case .invalidResponse:
                return .transient(reason: "invalid_response")
            case .invalidURL:
                return .permanent(errorCode: "INVALID_URL", reason: "invalid upload URL")
            case .presignError(let code):
                return classifyHTTPStatus(code, context: "presign")
            case .s3Error(let code):
                return classifyHTTPStatus(code, context: "s3")
            }
        }

        // SupabaseService.ServiceError — local wrapper. notAuthenticated
        // means the user signed out mid-upload; not a bug, just stop.
        if let serviceError = error as? SupabaseService.ServiceError {
            switch serviceError {
            case .notAuthenticated:
                return .permanent(errorCode: "NOT_AUTHENTICATED", reason: "not authenticated")
            case .networkError:
                return .transient(reason: "network_error")
            }
        }

        // URLError — Foundation's network-layer error. The codes that mean
        // "the user's signal blinked" are all retryable; everything else is
        // unknown and gets escalated only on retry exhaustion.
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }

        // Unknown shape — treat as transient (retry), but escalate on exhaust.
        return .unknown(reason: String(describing: type(of: error)))
    }

    // MARK: - Postgres SQLSTATE

    /// SQLSTATE 5-char codes. See https://www.postgresql.org/docs/current/errcodes-appendix.html
    /// We treat the entire class 23 (integrity_constraint_violation) and class
    /// 42 (syntax_error_or_access_rule_violation, which includes RLS) as
    /// permanent. Class 53 (insufficient_resources), 57 (operator_intervention),
    /// 58 (system_error) are transient.
    private static func classifyPostgresCode(_ code: String, message: String) -> UploadErrorKind {
        guard !code.isEmpty else {
            return .unknown(reason: "empty postgres code: \(message)")
        }

        let cls = String(code.prefix(2))
        switch cls {
        case "23", "42", "22":
            // 23 = integrity, 42 = access/syntax (incl 42501 RLS), 22 = data exception
            return .permanent(errorCode: "PG_\(code)", reason: message)
        case "08":
            // 08 = connection exception — transient
            return .transient(reason: "pg_connection_\(code)")
        case "53", "57", "58":
            return .transient(reason: "pg_system_\(code)")
        default:
            return .unknown(reason: "pg_\(code): \(message)")
        }
    }

    // MARK: - HTTP status

    private static func classifyHTTPStatus(_ statusCode: Int, context: String) -> UploadErrorKind {
        switch statusCode {
        case 401, 403:
            // Auth-layer rejection. Treat as transient so the retry path
            // exercises a fresh Firebase ID token before giving up. A truly
            // permanent auth failure (user actually signed out elsewhere,
            // session revoked) will fail through all retry attempts and
            // exhaust as transient — reportRetryExhausted intentionally
            // skips transient exhaustion, so the dev team never gets noise
            // for normal token-rotation events. The cost of a false-negative
            // (real auth bug never auto-bugged) is bounded because the user
            // already sees a failed tile and surfaces it via in-app support.
            return .transient(reason: "\(context)_auth_\(statusCode)_refresh")
        case 408, 425, 429:
            // request timeout, too early, too many requests — transient with backoff
            return .transient(reason: "\(context)_\(statusCode)")
        case 400...499:
            // client error — permanent. Includes 404 not found, 409 conflict,
            // 422 validation. 401/403 are handled above.
            return .permanent(errorCode: "HTTP_\(statusCode)", reason: "\(context) returned \(statusCode)")
        case 500...599:
            return .transient(reason: "\(context)_5xx_\(statusCode)")
        default:
            return .unknown(reason: "\(context)_status_\(statusCode)")
        }
    }

    // MARK: - URLError

    private static func classifyURLError(_ error: URLError) -> UploadErrorKind {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .dnsLookupFailed,
             .cannotConnectToHost,
             .cannotFindHost,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable,
             .secureConnectionFailed:
            return .transient(reason: "url_\(error.code.rawValue)")

        case .badURL,
             .unsupportedURL,
             .badServerResponse,
             .cannotParseResponse,
             .userCancelledAuthentication,
             .userAuthenticationRequired:
            return .permanent(
                errorCode: "URL_\(error.code.rawValue)",
                reason: error.localizedDescription
            )

        default:
            return .unknown(reason: "url_\(error.code.rawValue)")
        }
    }
}
