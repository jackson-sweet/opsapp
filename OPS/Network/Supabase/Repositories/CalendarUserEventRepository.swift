//
//  CalendarUserEventRepository.swift
//  OPS
//
//  Repository for CalendarUserEvent entity via Supabase.
//  Table: calendar_user_events
//

import Foundation
import Supabase

class CalendarUserEventRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch (current user's events in a date range)

    func fetchForUser(_ userId: String, from startDate: Date, to endDate: Date) async throws -> [CalendarUserEventDTO] {
        let iso = ISO8601DateFormatter()
        return try await client
            .from("calendar_user_events")
            .select()
            .eq("user_id", value: userId)
            .is("deleted_at", value: nil)
            .gte("end_date", value: iso.string(from: startDate))
            .lte("start_date", value: iso.string(from: endDate))
            .order("start_date", ascending: true)
            .execute()
            .value
    }

    // MARK: - Fetch (company admin — for time-off review)

    func fetchTimeOffRequestsForCompany() async throws -> [CalendarUserEventDTO] {
        return try await client
            .from("calendar_user_events")
            .select()
            .eq("company_id", value: companyId)
            .eq("type", value: "time_off")
            .is("deleted_at", value: nil)
            .order("start_date", ascending: true)
            .execute()
            .value
    }

    // MARK: - Create

    func create(_ dto: CreateCalendarUserEventDTO) async throws -> CalendarUserEventDTO {
        return try await client
            .from("calendar_user_events")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Update Status (admin approve/deny time off)

    func updateStatus(_ eventId: String, status: CalendarUserEventStatus, reviewedBy: String) async throws {
        let payload = CalendarUserEventStatusUpdateDTO(
            status: status.rawValue,
            reviewedBy: reviewedBy,
            reviewedAt: isoNow(),
            updatedAt: isoNow()
        )
        try await client
            .from("calendar_user_events")
            .update(payload)
            .eq("id", value: eventId)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ eventId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("calendar_user_events")
            .update(payload)
            .eq("id", value: eventId)
            .execute()
    }
}

// MARK: - Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
