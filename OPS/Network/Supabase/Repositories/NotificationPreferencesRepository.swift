//
//  NotificationPreferencesRepository.swift
//  OPS
//
//  Repository for notification_preferences Supabase table.
//  Handles fetch (upsert-read), partial updates, and single-channel toggles.
//

import Foundation
import Supabase

class NotificationPreferencesRepository {
    private let client: SupabaseClient

    init() {
        self.client = SupabaseService.shared.client
    }

    // MARK: - Fetch

    /// Fetch preferences for user+company. Creates a default row if none exists.
    func fetchPreferences(userId: String, companyId: String) async throws -> NotificationPreferencesDTO {
        // Try to read existing row first
        let existing: [NotificationPreferencesDTO] = try await client
            .from("notification_preferences")
            .select()
            .eq("user_id", value: userId)
            .eq("company_id", value: companyId)
            .execute()
            .value

        if let row = existing.first {
            return row
        }

        // No row exists — insert defaults then read back
        struct InsertPayload: Codable {
            let userId: String
            let companyId: String

            enum CodingKeys: String, CodingKey {
                case userId   = "user_id"
                case companyId = "company_id"
            }
        }

        let result: NotificationPreferencesDTO = try await client
            .from("notification_preferences")
            .insert(InsertPayload(userId: userId, companyId: companyId))
            .select()
            .single()
            .execute()
            .value
        return result
    }

    // MARK: - Update (partial)

    /// Partial update using AnyJSON dict. For channel_preferences, uses read-modify-write to merge.
    func updatePreferences(userId: String, companyId: String, updates: [String: AnyJSON]) async throws {
        var payload = updates
        payload["updated_at"] = .string(isoNow())

        try await client
            .from("notification_preferences")
            .update(payload)
            .eq("user_id", value: userId)
            .eq("company_id", value: companyId)
            .execute()
    }

    // MARK: - Update Channel Preference (single event+channel)

    /// Toggle a single event type's channel (push or email). Uses read-modify-write on the JSONB column.
    func updateChannelPreference(
        userId: String,
        companyId: String,
        eventType: String,
        channel: String,
        enabled: Bool
    ) async throws {
        // 1. Read current channel_preferences
        let current = try await fetchPreferences(userId: userId, companyId: companyId)

        // 2. Merge the change
        var merged = current.channelPreferences
        var toggle = merged[eventType] ?? ChannelToggle(push: true, email: false)
        switch channel {
        case "push":
            toggle.push = enabled
        case "email":
            toggle.email = enabled
        default:
            break
        }
        merged[eventType] = toggle

        // 3. Encode the full JSONB and write back
        let jsonData = try JSONEncoder().encode(merged)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NotificationPreferencesError.encodingFailed
        }

        let payload: [String: AnyJSON] = [
            "channel_preferences": .string(jsonString),
            "updated_at": .string(isoNow())
        ]

        // Use RPC or raw update with the encoded JSON
        // Since AnyJSON.string wraps in quotes, we need to use a different approach:
        // Encode the merged dict as AnyJSON directly
        try await updateChannelPreferencesJSON(userId: userId, companyId: companyId, merged: merged)
    }

    /// Write the full channel_preferences JSONB column from a Swift dictionary.
    func updateChannelPreferencesJSON(
        userId: String,
        companyId: String,
        merged: [String: ChannelToggle]
    ) async throws {
        // Convert [String: ChannelToggle] → [String: AnyJSON] for the JSONB column
        var jsonObj: [String: AnyJSON] = [:]
        for (key, toggle) in merged {
            jsonObj[key] = .object([
                "push": .bool(toggle.push),
                "email": .bool(toggle.email)
            ])
        }

        let payload: [String: AnyJSON] = [
            "channel_preferences": .object(jsonObj),
            "updated_at": .string(isoNow())
        ]

        try await client
            .from("notification_preferences")
            .update(payload)
            .eq("user_id", value: userId)
            .eq("company_id", value: companyId)
            .execute()
    }

    // MARK: - Update Quiet Hours

    /// Update quiet hours (pass nil to disable)
    func updateQuietHours(
        userId: String,
        companyId: String,
        start: String?,
        end: String?
    ) async throws {
        var payload: [String: AnyJSON] = [
            "updated_at": .string(isoNow())
        ]
        if let start {
            payload["quiet_hours_start"] = .string(start)
        } else {
            payload["quiet_hours_start"] = .null
        }
        if let end {
            payload["quiet_hours_end"] = .string(end)
        } else {
            payload["quiet_hours_end"] = .null
        }

        try await client
            .from("notification_preferences")
            .update(payload)
            .eq("user_id", value: userId)
            .eq("company_id", value: companyId)
            .execute()
    }

    // MARK: - Helpers

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - Errors

enum NotificationPreferencesError: Error, LocalizedError {
    case encodingFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode channel preferences"
        case .notFound:
            return "Notification preferences not found"
        }
    }
}
