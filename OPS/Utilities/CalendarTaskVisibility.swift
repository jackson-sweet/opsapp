//
//  CalendarTaskVisibility.swift
//  OPS
//
//  Bug 9997c11c — archiving a job did nothing to the calendar. Nothing in the
//  calendar layer had ever consulted project status, so a filed-away job kept
//  drawing on the week canvas, kept holding month-grid rows, and kept
//  manufacturing phantom conflicts inside the scheduler sheet's day inspector.
//
//  This is the one place that answers "may this task appear on a calendar?".
//  Applied at the CONSUMER layer only — `CalendarViewModel.applyTaskFilters`
//  (week canvas, per-day cache, month grid) and `CalendarSchedulerSheet`.
//  Deliberately NOT inside DataController's shared fetchers: those also feed
//  conflict math and auto-scheduling owned by other surfaces, and quietly
//  shrinking their results would change behaviour far outside the calendar.
//
//  Scope of the rule — ONLY `.archived`:
//   • `.closed` jobs still belong on a calendar. They are finished, not filed
//     away, and operators routinely look back at them.
//   • `Status.isActive` was rejected outright: it covers only accepted and
//     inProgress, so using it would have erased every legitimately scheduled
//     rfq/estimated job.
//

import Foundation
import SwiftData

enum CalendarTaskVisibility {

    /// Statuses the calendar's own filter may offer. Archived is absent on
    /// purpose: the calendar can never show archived work, so listing it would
    /// ship a control that always returns nothing.
    static let filterableStatuses: [Status] = [
        .rfq, .estimated, .accepted, .inProgress, .completed, .closed
    ]

    /// Ids of every archived project in the store, resolved once per rebuild.
    ///
    /// Keyed by id rather than walking `task.project` per row: the calendar
    /// already fetches every ProjectTask on each rebuild, and faulting a
    /// relationship for each one is the expensive shape. One Project fetch and
    /// a set membership test is strictly cheaper than the work it guards.
    ///
    /// Fetched whole and filtered in memory instead of via `#Predicate`, which
    /// is unreliable over SwiftData's custom `Status` enum column.
    static func archivedProjectIds(in context: ModelContext?) -> Set<String> {
        guard let context else { return [] }
        guard let projects = try? context.fetch(FetchDescriptor<Project>()) else { return [] }
        return Set(projects.lazy.filter { $0.status == .archived }.map(\.id))
    }

    /// Whether a task belonging to `projectId` may appear on a calendar.
    ///
    /// A task is hidden ONLY when its project is positively known to be
    /// archived. An id that matches no local project row — the project has not
    /// synced down yet, or the task's `project` relationship has not been
    /// linked — stays VISIBLE. This is the deliberate inverse of
    /// `TaskReviewQuery`'s `?? false`: there, an unresolvable project means
    /// "not schedulable work, leave it out of the loose-ends list". Here it
    /// would mean silently dropping a real day of work off the crew's
    /// schedule. An unsynced relationship must never hide scheduled work.
    static func includes(projectId: String, archivedProjectIds: Set<String>) -> Bool {
        !archivedProjectIds.contains(projectId)
    }

    /// The calendar-visible subset of `tasks`, order preserved.
    static func visible(_ tasks: [ProjectTask], archivedProjectIds: Set<String>) -> [ProjectTask] {
        guard !archivedProjectIds.isEmpty else { return tasks }
        return tasks.filter { includes(projectId: $0.projectId, archivedProjectIds: archivedProjectIds) }
    }
}
