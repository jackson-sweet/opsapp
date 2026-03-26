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

    /// Update status and notify the requesting user of the decision.
    /// Call this instead of updateStatus() when you want the notification sent automatically.
    func updateStatusWithNotification(
        eventId: String,
        userId: String,
        status: CalendarUserEventStatus,
        reviewedBy: String,
        reviewerName: String,
        eventTitle: String,
        companyId: String
    ) async throws {
        // Update the status
        try await updateStatus(eventId, status: status, reviewedBy: reviewedBy)

        // Send notification to the requesting user
        let isApproved = status == .approved
        let notificationType = isApproved ? "time_off_approved" : "time_off_denied"
        let title = isApproved ? "Time Off Approved" : "Time Off Denied"
        let body = isApproved
            ? "\(reviewerName) approved your time off request: \(eventTitle)"
            : "\(reviewerName) denied your time off request: \(eventTitle)"

        // Create in-app notification
        let dto = NotificationRepository.CreateNotificationDTO(
            userId: userId,
            companyId: companyId,
            type: notificationType,
            title: title,
            body: body,
            projectId: nil,
            noteId: nil,
            expenseId: nil,
            batchId: nil,
            deepLinkType: "schedule"
        )
        try? await NotificationRepository().createNotification(dto)

        // Send push
        try? await OneSignalService.shared.sendToUser(
            userId: userId,
            title: title,
            body: body,
            data: ["type": notificationType, "screen": "schedule"]
        )
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
