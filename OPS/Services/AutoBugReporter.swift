//
//  AutoBugReporter.swift
//  OPS
//
//  Files a bug_reports row when a previously-silent catch site in the upload /
//  sync layer fires with a permanent error (or transient retry exhaustion).
//
//  Background: May-12 outage. The project_photos INSERT RLS policy tightened
//  to require projects.edit; Crew + Unassigned users lost photo uploads
//  silently for 3 days because a `try { ... } catch { print(...) }` block
//  swallowed the 42501. AutoBugReporter exists so the next time this shape
//  of bug happens, the dev team sees it the day it starts.
//
//  Contract with the catch site:
//    - Call AutoBugReporter.shared.report(...) from the catch block.
//    - It NEVER throws. The auto-bug fire must not break the original retry /
//      UI flow at the call site.
//    - Server-side dedupe (via the partial unique index on bug_reports) means
//      it's safe to call on every fire — repeats collapse into one ticket.
//    - In-memory client-side rate-limit prevents RPC flood during offline
//      drain reattempts: same dedupe hash within 1 hour is skipped entirely.
//
//  Out of scope: BugReportSubmissionService stays the user-facing bug filer.
//  AutoBugReporter is the silent-catch counterpart and is intentionally
//  thinner — no screenshot, no console log capture, just enough context to
//  identify the failure shape.
//

import Foundation
import Supabase

@MainActor
final class AutoBugReporter {
    static let shared = AutoBugReporter()

    /// Set once at app launch from OPSApp / DataController initialization so
    /// network_type can be sourced from the live ConnectivityManager. Falls
    /// back to "unknown" when not configured (test harnesses, early-launch
    /// catch sites that fire before DataController is built).
    private weak var connectivity: ConnectivityManager?

    func configure(connectivity: ConnectivityManager) {
        self.connectivity = connectivity
    }

    /// Category for the bug_reports row. Always "bug" for data-loss class
    /// failures. The bug_reports.category check constraint allows
    /// {bug, ui_issue, crash, feature_request, other}.
    static let defaultCategory = "bug"

    /// Priority for auto-filed bugs. "high" puts them at the top of triage
    /// queues; the dev team can downgrade after assessment.
    static let defaultPriority = "high"

    /// Client-side dedupe TTL. Prevents the AutoBugReporter from flooding
    /// the RPC with identical fires during offline drain reattempts when the
    /// queue retries the same poisoned upload every 30s. The server-side
    /// partial unique index would dedupe anyway, but skipping the round-trip
    /// keeps the user's data plane clean.
    private static let clientDedupeTTL: TimeInterval = 3600 // 1 hour

    /// In-memory cache of recently-fired dedupe hashes. Keys are the same
    /// SHA-256 hashes the server computes; values are the timestamp of the
    /// last fire. Cleared on app cold-launch.
    private var recentFires: [String: Date] = [:]

    private init() {}

    // MARK: - Public entry

    /// File an auto-bug. Never throws; never blocks the caller's retry flow.
    ///
    /// - Parameters:
    ///   - screen: stable identifier for the catch site's logical surface.
    ///     Used as a dedupe seed — distinct screens produce distinct rows.
    ///     Examples: "ImageSyncManager.saveImages", "PhotoProcessor.upload",
    ///     "DimensionedPhotoSyncManager.annotationInsert".
    ///   - suspectedFile: Swift file the catch lives in. Same dedupe seed.
    ///   - errorCode: stable code derived from the classified error.
    ///     For permanent errors this is the SQLSTATE / HTTP code; for
    ///     transient retry exhaustion it's the transient reason. Distinct
    ///     codes produce distinct rows even within the same screen + file.
    ///   - summary: human-readable description for the bug_reports row.
    ///     Shown verbatim in the dev triage UI.
    ///   - metadata: optional JSONB payload for additional context (the
    ///     project id, upload id, retry count, etc.). Caller-controlled.
    func report(
        screen: String,
        suspectedFile: String,
        errorCode: String,
        summary: String,
        metadata: [String: Any] = [:]
    ) async {
        let hash = clientDedupeHash(
            category: Self.defaultCategory,
            screen: screen,
            suspectedFile: suspectedFile,
            errorCode: errorCode
        )

        if let lastFire = recentFires[hash],
           Date().timeIntervalSince(lastFire) < Self.clientDedupeTTL {
            // Within the 1-hour TTL — skip the RPC entirely. The server's
            // partial unique index would dedupe anyway, but we save the round
            // trip during offline-drain storms.
            return
        }

        recentFires[hash] = Date()

        await postToRPC(
            screen: screen,
            suspectedFile: suspectedFile,
            errorCode: errorCode,
            summary: summary,
            metadata: metadata
        )
    }

    /// Convenience overload that classifies the error first and only fires
    /// if it's permanent (or unknown + caller flagged it as exhausted retry).
    /// Returns the classified kind so the caller can drive retry / UI logic
    /// off the same classification without re-running it.
    @discardableResult
    func reportIfPermanent(
        _ error: Error,
        screen: String,
        suspectedFile: String,
        summary: String,
        metadata: [String: Any] = [:]
    ) async -> UploadErrorKind {
        let kind = UploadErrorClassifier.classify(error)
        if case .permanent(let code, let reason) = kind {
            var fullMetadata = metadata
            fullMetadata["error_reason"] = reason
            fullMetadata["error_kind"] = "permanent"
            await report(
                screen: screen,
                suspectedFile: suspectedFile,
                errorCode: code,
                summary: summary,
                metadata: fullMetadata
            )
        }
        return kind
    }

    /// Force-fire variant for retry-exhausted catch sites. Used after the
    /// in-session backoff loop (4 attempts) hits its cap with no success
    /// AND the error is NOT just bad-signal transient. Pass the classified
    /// kind so the dedupe code stays consistent.
    func reportRetryExhausted(
        kind: UploadErrorKind,
        attempts: Int,
        screen: String,
        suspectedFile: String,
        summary: String,
        metadata: [String: Any] = [:]
    ) async {
        // Bad-signal transient is normal in the field — never auto-bug for
        // pure transient even after exhaustion. The cross-session offline
        // queue handles that case via LocalPhoto.status = "failed".
        if case .transient = kind { return }

        var fullMetadata = metadata
        fullMetadata["attempts"] = attempts
        fullMetadata["error_kind"] = "\(kind)"

        await report(
            screen: screen,
            suspectedFile: suspectedFile,
            errorCode: "EXHAUSTED_\(kind.dedupeCode)",
            summary: summary,
            metadata: fullMetadata
        )
    }

    // MARK: - RPC call

    private func postToRPC(
        screen: String,
        suspectedFile: String,
        errorCode: String,
        summary: String,
        metadata: [String: Any]
    ) async {
        let deviceInfo = BugReportCaptureService.shared.captureDeviceInfo()
        let networkType = currentNetworkType()

        let params = RecordAutoBugParams(
            p_category: Self.defaultCategory,
            p_priority: Self.defaultPriority,
            p_screen: screen,
            p_suspected_file: suspectedFile,
            p_error_code: errorCode,
            p_summary: summary,
            p_metadata: AnyJSONCodable(metadata.merging(["screen": screen, "file": suspectedFile, "error_code": errorCode]) { current, _ in current }),
            p_app_version: deviceInfo["appVersion"] as? String ?? "unknown",
            p_build_number: deviceInfo["buildNumber"] as? String ?? "unknown",
            p_os_version: deviceInfo["osVersion"] as? String ?? "unknown",
            p_device_model: deviceInfo["deviceModel"] as? String ?? "unknown",
            p_network_type: networkType
        )

        do {
            try await SupabaseService.shared.client
                .rpc("record_auto_bug", params: params)
                .execute()
        } catch {
            // Auto-bug fire failed. Do NOT throw to the caller — the entire
            // point of this helper is that it never breaks the original flow.
            // Log to the local debug logger so the next user-filed bug carries
            // the trail. Don't log to print() — that's what got us into May-12
            // in the first place.
            DebugLogger.shared.log(
                "AutoBugReporter RPC failed for \(screen)/\(errorCode): \(error)",
                level: .warning,
                category: "AutoBugReporter"
            )
        }
    }

    // MARK: - Helpers

    private func currentNetworkType() -> String {
        // Mirror BugReportSubmissionService.networkType derivation: read off
        // the live ConnectivityManager that DataController wired in at launch.
        // Falls back to "unknown" if configure(connectivity:) hasn't been
        // called yet — early-launch catch sites (rare) get a soft default
        // rather than blocking the auto-bug fire.
        guard let connectivity else { return "unknown" }
        if connectivity.shouldAttemptSync {
            let quality = connectivity.state.quality
            return (quality == .excellent || quality == .good) ? "wifi" : "cellular"
        }
        return "none"
    }

    /// Same hash formula the server uses for dedupe. Keeps client cache
    /// keys in lockstep with the partial unique index so the 1-hour TTL
    /// behaves predictably.
    private func clientDedupeHash(
        category: String,
        screen: String,
        suspectedFile: String,
        errorCode: String
    ) -> String {
        // Plain string concat — we just need a stable cache key, not a
        // cryptographic property. The server side does the real SHA-256.
        return "\(category):\(screen):\(suspectedFile):\(errorCode)"
    }
}

// MARK: - RPC param payload

/// Mirrors the record_auto_bug RPC signature exactly. snake_case keys are
/// intentional — supabase-swift's `rpc(_:params:)` encodes the struct as
/// JSON and PostgREST matches arg names verbatim.
private struct RecordAutoBugParams: Encodable {
    let p_category: String
    let p_priority: String
    let p_screen: String
    let p_suspected_file: String
    let p_error_code: String
    let p_summary: String
    let p_metadata: AnyJSONCodable
    let p_app_version: String
    let p_build_number: String
    let p_os_version: String
    let p_device_model: String
    let p_network_type: String
}

/// Type-erasing JSON wrapper so `[String: Any]` metadata can ride through
/// the Encodable RPC payload. Only encoder semantics matter; decoder isn't
/// used (the RPC returns jsonb but we discard the response).
private struct AnyJSONCodable: Encodable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (key, raw) in value {
            let codingKey = DynamicKey(stringValue: key)!
            try Self.encode(raw, forKey: codingKey, into: &container)
        }
    }

    private static func encode<C: KeyedEncodingContainerProtocol>(
        _ raw: Any,
        forKey key: C.Key,
        into container: inout C
    ) throws {
        if let s = raw as? String { try container.encode(s, forKey: key) }
        else if let i = raw as? Int { try container.encode(i, forKey: key) }
        else if let d = raw as? Double { try container.encode(d, forKey: key) }
        else if let b = raw as? Bool { try container.encode(b, forKey: key) }
        else if let dict = raw as? [String: Any] {
            try container.encode(AnyJSONCodable(dict), forKey: key)
        } else if let arr = raw as? [Any] {
            try container.encode(AnyJSONArrayCodable(arr), forKey: key)
        } else {
            try container.encode(String(describing: raw), forKey: key)
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }
}

private struct AnyJSONArrayCodable: Encodable {
    let value: [Any]
    init(_ value: [Any]) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for raw in value {
            if let s = raw as? String { try container.encode(s) }
            else if let i = raw as? Int { try container.encode(i) }
            else if let d = raw as? Double { try container.encode(d) }
            else if let b = raw as? Bool { try container.encode(b) }
            else if let dict = raw as? [String: Any] {
                try container.encode(AnyJSONCodable(dict))
            } else if let arr = raw as? [Any] {
                try container.encode(AnyJSONArrayCodable(arr))
            } else {
                try container.encode(String(describing: raw))
            }
        }
    }
}
