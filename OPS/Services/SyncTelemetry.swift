//
//  SyncTelemetry.swift
//  OPS
//
//  Logs per-entity sync failures into `app_events` so production failures
//  (e.g., the invisible inventory pull regression — Bug 2837ddae) become
//  diagnosable without device access.
//

import Foundation
import Supabase

enum SyncTelemetry {

    /// Build the analytics payload for a sync failure. Pulled out as a pure
    /// function so it's easy to unit-test.
    static func buildEvent(
        entityType: String,
        error: Error,
        isFullSync: Bool,
        companyId: String,
        userId: String?
    ) -> [String: Any] {
        let nsError = error as NSError
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let buildNumber = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown"

        var event: [String: Any] = [
            "event_name": "sync_entity_failed",
            "entity_type": entityType,
            "error_class": nsError.domain,
            "error_code": nsError.code,
            "error_message": nsError.localizedDescription,
            "sync_phase": isFullSync ? "full" : "delta",
            "company_id": companyId,
            "app_version": appVersion,
            "build_number": buildNumber,
            "platform": "ios",
            "occurred_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let userId = userId {
            event["user_id"] = userId
        }
        return event
    }

    /// Fire-and-forget log of a sync failure to `app_events`.
    /// Best-effort: any failure here is itself swallowed because we'd otherwise
    /// recurse into the sync error path.
    @discardableResult
    static func logError(
        entityType: String,
        error: Error,
        isFullSync: Bool,
        companyId: String,
        userId: String?,
        reportIdentity: AutoBugReportIdentity? = nil,
        bugReporter: SyncBugReporter = .live,
        persistEvent: (@Sendable (String, String?, Data) async throws -> Void)? = nil
    ) -> Task<Void, Never> {
        let event = buildEvent(
            entityType: entityType, error: error,
            isFullSync: isFullSync, companyId: companyId, userId: userId
        )
        // Console log first — survives even if Supabase write fails.
        print("[SyncTelemetry] sync_entity_failed entity=\(entityType) err=\(error.localizedDescription)")

        if reportIdentity?.companyID == companyId.lowercased(),
           reportIdentity?.firebaseUserID == userId {
            bugReporter.reportPermanent(error, entityType: entityType,
                operationType: "pull", identity: reportIdentity)
        }

        let writeEvent = persistEvent ?? Self.persistEvent
        return Task.detached {
            do {
                let propsJSON = try JSONSerialization.data(withJSONObject: event)
                try await writeEvent(companyId, userId, propsJSON)
            } catch {
                print("[SyncTelemetry] failed to persist failure event: \(error)")
            }
        }
    }

    private static func persistEvent(companyId: String, userId: String?, properties: Data) async throws {
        struct AppEventInsert: Codable {
            let user_id: String?
            let company_id: String
            let event_name: String
            let properties: AnyJSON
        }
        let payload = AppEventInsert(user_id: userId, company_id: companyId,
            event_name: "sync_entity_failed",
            properties: try JSONDecoder().decode(AnyJSON.self, from: properties))
        _ = try await SupabaseService.shared.client.from("app_events").insert(payload).execute()
    }
}
