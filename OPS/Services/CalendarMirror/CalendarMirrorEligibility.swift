//
//  CalendarMirrorEligibility.swift
//  OPS
//
//  Pure predicates for "should this row be in the mirror right now?"
//  Window: past 30 days → future 12 months from a reference date.
//

import Foundation

enum CalendarMirrorEligibility {

    /// The mirror window: [now - 30d, now + 365d].
    static func windowBounds(now: Date = Date()) -> (lower: Date, upper: Date) {
        let cal = Calendar.current
        let lower = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let upper = cal.date(byAdding: .day, value: 365, to: now) ?? now
        return (lower, upper)
    }

    static func isInWindow(start: Date, end: Date, now: Date = Date()) -> Bool {
        let (lower, upper) = windowBounds(now: now)
        return end >= lower && start <= upper
    }

    // MARK: - CalendarUserEvent

    static func isEligible(event: CalendarUserEvent, currentUserId: String, now: Date = Date()) -> Bool {
        guard event.deletedAt == nil else { return false }
        guard isInWindow(start: event.startDate, end: event.endDate, now: now) else { return false }

        let isOwner = event.userId == currentUserId
        let isTarget = (event.teamMemberIds ?? []).contains(currentUserId)
        return isOwner || isTarget
    }

    // MARK: - ProjectTask

    static func isEligible(task: ProjectTask, currentUserId: String, now: Date = Date()) -> Bool {
        guard task.deletedAt == nil else { return false }
        guard let start = task.startDate, let end = task.endDate else { return false }
        guard isInWindow(start: start, end: end, now: now) else { return false }
        return task.schedulingTeamMemberIds.contains(currentUserId)
    }
}
