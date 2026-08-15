//
//  SiteVisitBookingLookup.swift
//  OPS
//
//  One answer to "does this lead hold an open booking?" — shared by every
//  visit affordance so the NOW/BOOK branch, the day-sheet panel, and the
//  detail menu can never disagree about the same lead. Predicate-scoped,
//  fetchLimit-1 (the site-visit merge's hard rule — never a table scan).
//
//  "Open booking" is precisely the server's one-open-booking boundary:
//  booked (bookedAt non-nil), still status=scheduled, not deleted. A started,
//  completed, or cancelled visit frees the slot.
//

import Foundation
import SwiftData

enum SiteVisitBookingLookup {

    /// The lead's open booking, if any. The predicate scopes to this lead's
    /// visit rows — `opportunityId` is lowercase everywhere (model init and
    /// SiteVisitWire both normalize), so one comparison suffices. Booking and
    /// status checks happen in Swift: a lead holds a handful of visits, ever,
    /// and #Predicate cannot compare the stored enum (LeadSiteVisitResolver
    /// documents the same shape).
    @MainActor
    static func openBooking(
        forOpportunityId opportunityId: String,
        in context: ModelContext
    ) -> SiteVisit? {
        let lower = opportunityId.lowercased()
        let descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> { $0.opportunityId == lower }
        )
        let visits = (try? context.fetch(descriptor)) ?? []
        return visits.first {
            $0.bookedAt != nil && $0.deletedAt == nil && $0.status == .scheduled
        }
    }

    /// The reschedule-sheet snapshot for an open booking.
    static func snapshot(of visit: SiteVisit) -> BookSiteVisitForm.BookingSnapshot? {
        guard visit.isBookedAppointment, let scheduledAt = visit.scheduledAt else { return nil }
        return BookSiteVisitForm.BookingSnapshot(
            siteVisitId: visit.id,
            scheduledAt: scheduledAt,
            durationMinutes: visit.durationMinutes,
            assigneeIds: visit.assigneeIds,
            reminderLeadMinutes: visit.reminderLeadMinutes
        )
    }

    /// "THU 10:30AM" — the booked token every lead surface prints. Sits next
    /// to DaySheetDateToken's day() grammar; minutes matter for appointments.
    static func bookedToken(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        "\(DaySheetDateToken.day(date, now: now, calendar: calendar)) \(timeFormatter.string(from: date).uppercased())"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        return formatter
    }()
}
