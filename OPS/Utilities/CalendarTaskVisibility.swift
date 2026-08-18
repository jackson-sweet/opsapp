//
//  CalendarTaskVisibility.swift
//  OPS
//
//  Bug 9997c11c — archiving a job did nothing to the calendar. Nothing in the
//  calendar layer had ever consulted project status, so a filed-away job kept
//  drawing on the week canvas, kept holding month-grid rows, and kept
//  manufacturing phantom conflicts inside the scheduler sheet's day inspector.
//
//  Bug 8351d7a7 widened the rule to the front of the pipeline: unwon work was
//  drawing on the schedule too. A quoted job's pencilled dates are a guess at
//  when it MIGHT run; putting them on the same canvas as committed work makes
//  the week read as busier than it is and manufactures conflicts against days
//  that are actually free.
//
//  This is the one place that answers "may this task appear on a calendar?".
//  Applied at the CONSUMER layer only — `CalendarViewModel.applyTaskFilters`
//  (week canvas, per-day cache, month grid) and `CalendarSchedulerSheet`.
//  Deliberately NOT inside DataController's shared fetchers: those also feed
//  conflict math and auto-scheduling owned by other surfaces, and quietly
//  shrinking their results would change behaviour far outside the calendar.
//
//  Scope of the rule — the calendar is the COMMITMENT board:
//   • `.rfq` / `.estimated` are hidden. The work is not won, so its dates are
//     not a commitment to anybody.
//   • `.archived` stays hidden. Filed away is not scheduled.
//   • `.accepted` / `.inProgress` are the live schedule.
//   • `.completed` / `.closed` stay VISIBLE. They are finished, not filed
//     away — that work genuinely happened on those days, and blanking the
//     past out of the calendar would destroy the record operators look back
//     at. `Status.isActive` alone (accepted + inProgress) was rejected for
//     exactly that reason.
//

import Foundation
import SwiftData

enum CalendarTaskVisibility {

    /// Project statuses whose work may draw on a calendar: won work, plus the
    /// finished record of it.
    static let visibleStatuses: Set<Status> = [
        .accepted, .inProgress, .completed, .closed
    ]

    /// Statuses the calendar's own filter may offer. The hidden statuses are
    /// absent on purpose: the calendar can never show that work, so listing
    /// them would ship controls that always return nothing.
    static let filterableStatuses: [Status] = [
        .accepted, .inProgress, .completed, .closed
    ]

    /// Whether a project in this status may put work on a calendar.
    static func admits(_ status: Status) -> Bool {
        visibleStatuses.contains(status)
    }

    /// Ids of every project the calendar must not draw, resolved once per
    /// rebuild.
    ///
    /// Keyed by id rather than walking `task.project` per row: the calendar
    /// already fetches every ProjectTask on each rebuild, and faulting a
    /// relationship for each one is the expensive shape. One Project fetch and
    /// a set membership test is strictly cheaper than the work it guards.
    ///
    /// Fetched whole and filtered in memory instead of via `#Predicate`, which
    /// is unreliable over SwiftData's custom `Status` enum column.
    static func hiddenProjectIds(in context: ModelContext?) -> Set<String> {
        guard let context else { return [] }
        guard let projects = try? context.fetch(FetchDescriptor<Project>()) else { return [] }
        return Set(projects.lazy.filter { !admits($0.status) }.map(\.id))
    }

    /// Whether a task belonging to `projectId` may appear on a calendar.
    ///
    /// A task is hidden ONLY when its project is positively known to be in a
    /// hidden status. An id that matches no local project row — the project
    /// has not synced down yet, or the task's `project` relationship has not
    /// been linked — stays VISIBLE. This is the deliberate inverse of
    /// `TaskReviewQuery`'s `?? false`: there, an unresolvable project means
    /// "not schedulable work, leave it out of the loose-ends list". Here it
    /// would mean silently dropping a real day of work off the crew's
    /// schedule. An unsynced relationship must never hide scheduled work.
    static func includes(projectId: String, hiddenProjectIds: Set<String>) -> Bool {
        !hiddenProjectIds.contains(projectId)
    }

    /// The calendar-visible subset of `tasks`, order preserved.
    static func visible(_ tasks: [ProjectTask], hiddenProjectIds: Set<String>) -> [ProjectTask] {
        guard !hiddenProjectIds.isEmpty else { return tasks }
        return tasks.filter { includes(projectId: $0.projectId, hiddenProjectIds: hiddenProjectIds) }
    }
}
