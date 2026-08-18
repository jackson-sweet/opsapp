//
//  CalendarUserEventRepository.swift
//  OPS
//
//  Repository for CalendarUserEvent entity via Supabase.
//  Table: calendar_user_events
//

import Foundation
import Supabase

/// Seam for creating the time-off decision rail row. Conformed to by
/// `NotificationRepository` (the `notify_time_off_decision` RPC); tests
/// substitute a spy.
protocol TimeOffDecisionNotifying {
    /// Returns the server's verdict for the event's recorded decision.
    @discardableResult
    func notifyTimeOffDecision(eventId: String) async throws -> String
}

extension NotificationRepository: TimeOffDecisionNotifying {}

class CalendarUserEventRepository {
    private let client: SupabaseClient
    private let companyId: String

    /// Injected so tests can observe the decision dispatch without a network
    /// call. A defaulted property rather than an init parameter: this
    /// repository is constructed at nine unrelated call sites, none of which
    /// should have to know the notification seam exists.
    var notifySyncer: TimeOffDecisionNotifying = NotificationRepository.shared

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
            .executeResilient(label: "calendar_user_events")
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
        let result: CalendarUserEventDTO = try await client
            .from("calendar_user_events")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        let opsId = result.id
        Task { @MainActor in
            await CalendarMirrorService.shared.mirrorEvent(opsId: opsId, source: .calendarUserEvent)
        }
        return result
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
        Task { @MainActor in
            await CalendarMirrorService.shared.mirrorEvent(opsId: eventId, source: .calendarUserEvent)
        }
    }

    /// Update status and notify the requesting user of the decision.
    /// Call this instead of updateStatus() when you want the notification sent automatically.
    func updateStatusWithNotification(
        eventId: String,
        userId: String,
        status: CalendarUserEventStatus,
        reviewedBy: String,
        reviewerName: String,
        eventTitle: String
    ) async throws {
        // Persist the decision FIRST. The rail RPC reads the RECORDED state
        // off the row — it requires `type = time_off`, a status of approved /
        // denied, and an actor matching the row's `reviewed_by` — so it can
        // only run once this write has landed.
        try await updateStatus(eventId, status: status, reviewedBy: reviewedBy)

        // Push copy, built client-side from the reviewer and title the caller
        // already resolved for the UI. The in-app rail row below renders its
        // own copy server-side from the same recorded decision.
        let isApproved = status == .approved
        let notificationType = isApproved ? "time_off_approved" : "time_off_denied"
        let title = isApproved ? "Time Off Approved" : "Time Off Denied"
        let body = isApproved
            ? "\(reviewerName) approved your time off request: \(eventTitle)"
            : "\(reviewerName) denied your time off request: \(eventTitle)"

        // Create in-app notification
        await dispatchDecisionNotification(eventId: eventId)

        // Send push
        try? await OneSignalService.shared.sendToUser(
            userId: userId,
            title: title,
            body: body,
            data: ["type": notificationType, "screen": "schedule"]
        )
    }

    /// Create the in-app rail row for a decision already recorded on the
    /// event row. The server derives the requester recipient and renders the
    /// copy; direct `notifications` inserts have failed 42501 for app roles
    /// since the 2026-07-15 notification-creation hardening.
    ///
    /// Best-effort by design: the approve/deny itself is already persisted,
    /// so a transport failure here must never fail the caller.
    func dispatchDecisionNotification(eventId: String) async {
        _ = try? await notifySyncer.notifyTimeOffDecision(eventId: eventId)
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
        Task { @MainActor in
            await CalendarMirrorService.shared.unmirrorEvent(opsId: eventId)
        }
    }

    // MARK: - Series fetch / update / delete (Apple-Calendar scopes)

    /// Fetch every non-deleted row in the same series. Used by "edit all" and
    /// "delete all" scopes to enumerate siblings for downstream batch ops.
    func fetchSeries(_ seriesId: String) async throws -> [CalendarUserEventDTO] {
        return try await client
            .from("calendar_user_events")
            .select()
            .eq("series_id", value: seriesId)
            .is("deleted_at", value: nil)
            .order("start_date", ascending: true)
            .execute()
            .value
    }

    /// Fetch this row + every later non-deleted sibling in the series. Used by
    /// the "edit future" / "delete future" scopes — `from` is the start_date
    /// of the row the user tapped.
    func fetchSeriesFromDate(_ seriesId: String, from: Date) async throws -> [CalendarUserEventDTO] {
        let iso = ISO8601DateFormatter()
        return try await client
            .from("calendar_user_events")
            .select()
            .eq("series_id", value: seriesId)
            .gte("start_date", value: iso.string(from: from))
            .is("deleted_at", value: nil)
            .order("start_date", ascending: true)
            .execute()
            .value
    }

    /// Editable fields for an existing event. Time-shifted writes ("edit
    /// future" / "edit all") preserve each row's original date but rewrite
    /// the time-of-day, since each sibling sits on a different calendar day.
    struct EventFieldUpdate: Codable {
        let title: String
        let notes: String?
        let allDay: Bool
        let teamMemberIds: [String]?
        /// New start, ISO8601. Caller decides whether to shift each sibling
        /// to its own date (for series ops) or use one absolute value.
        let startDate: String
        let endDate: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case title
            case notes
            case allDay = "all_day"
            case teamMemberIds = "team_member_ids"
            case startDate = "start_date"
            case endDate = "end_date"
            case updatedAt = "updated_at"
        }
    }

    /// Update a single row by primary key. Used by "edit this only" after
    /// detaching the row from the series.
    func updateEvent(_ eventId: String, fields: EventFieldUpdate) async throws {
        try await client
            .from("calendar_user_events")
            .update(fields)
            .eq("id", value: eventId)
            .execute()
        Task { @MainActor in
            await CalendarMirrorService.shared.mirrorEvent(opsId: eventId, source: .calendarUserEvent)
        }
    }

    /// Detach a row from its series — sets series_id to NULL so subsequent
    /// "edit all" / "delete all" calls won't include it. Called when the user
    /// chooses "edit this event only" or "delete this event only".
    func detachFromSeries(_ eventId: String) async throws {
        struct DetachPayload: Codable {
            let series_id: String?
            let updated_at: String
        }
        let payload = DetachPayload(series_id: nil, updated_at: isoNow())
        try await client
            .from("calendar_user_events")
            .update(payload)
            .eq("id", value: eventId)
            .execute()
    }

    /// Soft-delete every row in the series. "Delete all events" scope.
    func softDeleteSeries(_ seriesId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("calendar_user_events")
            .update(payload)
            .eq("series_id", value: seriesId)
            .is("deleted_at", value: nil)
            .execute()
        Task { @MainActor in
            await CalendarMirrorService.shared.reconcileAll()
        }
    }

    /// Soft-delete every row in the series whose start_date is on or after
    /// `from`. "Delete future events" scope.
    func softDeleteSeriesFromDate(_ seriesId: String, from: Date) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let iso = ISO8601DateFormatter()
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("calendar_user_events")
            .update(payload)
            .eq("series_id", value: seriesId)
            .gte("start_date", value: iso.string(from: from))
            .is("deleted_at", value: nil)
            .execute()
        Task { @MainActor in
            await CalendarMirrorService.shared.reconcileAll()
        }
    }
}

// MARK: - Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}
