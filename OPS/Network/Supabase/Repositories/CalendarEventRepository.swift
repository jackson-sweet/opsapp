//
//  CalendarEventRepository.swift
//  OPS
//
//  Repository for CalendarEvent entity operations via Supabase.
//  Table: calendar_events
//
//  Column note: There is NO `task_id`, `all_day`, or `event_type` column on this table.
//  Task linkage is resolved via project_tasks.calendar_event_id (the foreign key lives
//  on the task, not the event). `all_day` and `event_type` are iOS-only model fields.
//

import Foundation
import Supabase

class CalendarEventRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll(since: Date? = nil) async throws -> [SupabaseCalendarEventDTO] {
        var query = client
            .from("calendar_events")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        let response: [SupabaseCalendarEventDTO] = try await query
            .order("start_date", ascending: true)
            .execute()
            .value
        return response
    }

    /// Fetches all events whose start_date falls within the given range (inclusive).
    func fetchForRange(start: Date, end: Date) async throws -> [SupabaseCalendarEventDTO] {
        let response: [SupabaseCalendarEventDTO] = try await client
            .from("calendar_events")
            .select()
            .eq("company_id", value: companyId)
            .gte("start_date", value: isoString(start))
            .lte("start_date", value: isoString(end))
            .order("start_date", ascending: true)
            .execute()
            .value
        return response
    }

    // MARK: - Create

    func create(_ dto: SupabaseCalendarEventDTO) async throws -> SupabaseCalendarEventDTO {
        try await client
            .from("calendar_events")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseCalendarEventDTO) async throws {
        try await client
            .from("calendar_events")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update

    func update(_ id: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())
        try await client
            .from("calendar_events")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    func updateTeamMembers(_ id: String, memberIds: [String]) async throws {
        struct TeamUpdate: Codable {
            let team_member_ids: [String]
            let updated_at: String
        }
        let payload = TeamUpdate(team_member_ids: memberIds, updated_at: isoNow())
        try await client
            .from("calendar_events")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("calendar_events")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
