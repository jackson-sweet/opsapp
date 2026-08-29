//
//  SiteVisitBookingDayContext.swift
//  OPS
//
//  Pure planning for the booking sheet's WHEN surface: which days already
//  hold booked visits, what the selected day carries, whether the chosen
//  window collides, and how a day pick merges with the held time-of-day.
//  No SwiftUI, no network — BookSiteVisitForm's discipline applied to the
//  rail, so every rule here is provable in isolation.
//

import Foundation

/// One already-booked visit, reduced to what the WHEN surface renders.
struct BookingDayVisit: Equatable, Identifiable {
    let id: String
    let opportunityId: String?
    let start: Date
    let durationMinutes: Int

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

enum SiteVisitBookingDayContext {

    /// Visits the WHEN surface may show: booked appointments still standing
    /// (scheduled or on site), visibility-scoped exactly like Schedule
    /// (CalendarViewModel.visibleBookedVisits), excluding the booking being
    /// moved — an appointment never collides with itself. Sorted by start.
    static func contextVisits(
        in visits: [SiteVisit],
        currentUserId: String,
        canViewAllCalendar: Bool,
        excluding excludedVisitId: String?
    ) -> [BookingDayVisit] {
        let excluded = excludedVisitId?.lowercased()
        return CalendarViewModel.visibleBookedVisits(
            visits,
            currentUserId: currentUserId,
            canViewAllCalendar: canViewAllCalendar
        )
        .filter { $0.id != excluded }
        .compactMap { visit in
            guard let start = visit.scheduledAt else { return nil }
            return BookingDayVisit(
                id: visit.id,
                opportunityId: visit.opportunityId,
                start: start,
                durationMinutes: visit.durationMinutes
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// Rail markers: visit count per startOfDay.
    static func countsByDay(
        _ visits: [BookingDayVisit],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        visits.reduce(into: [:]) { counts, visit in
            counts[calendar.startOfDay(for: visit.start), default: 0] += 1
        }
    }

    /// The selected day's visits, earliest first (input is already sorted).
    static func visits(
        _ visits: [BookingDayVisit],
        on day: Date,
        calendar: Calendar = .current
    ) -> [BookingDayVisit] {
        visits.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    /// First same-day visit the chosen window intersects. Touching edges
    /// (10–11 then 11–12) are NOT an overlap. Nil = clear.
    static func overlap(
        chosenStart: Date,
        durationMinutes: Int,
        against visits: [BookingDayVisit],
        calendar: Calendar = .current
    ) -> BookingDayVisit? {
        let chosenEnd = chosenStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return visits.first { visit in
            calendar.isDate(visit.start, inSameDayAs: chosenStart)
                && chosenStart < visit.end
                && visit.start < chosenEnd
        }
    }

    /// Move the held appointment to another day, preserving the wall-clock
    /// hour:minute (component-based, so a DST boundary can't shift the time).
    static func merging(
        day: Date,
        timeOfDayFrom current: Date,
        calendar: Calendar = .current
    ) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: current)
        return calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
    }
}

/// The appointment sheet's clock grammar. "2D 4H" / "3H 12M" / "18M";
/// nil once the window is open (now >= start) — the caller switches copy.
enum SiteVisitCountdown {
    static func token(until start: Date, now: Date) -> String? {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        guard seconds >= 60 else { return "1M" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return hours > 0 ? "\(days)D \(hours)H" : "\(days)D" }
        if hours > 0 { return minutes > 0 ? "\(hours)H \(minutes)M" : "\(hours)H" }
        return "\(minutes)M"
    }
}
