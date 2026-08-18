//
//  DataActor+CalendarGrid.swift
//  OPS
//
//  The Schedule's two rebuild passes, computed off the main thread
//  (bug 1bade6dd: rescheduling a job froze the screen for seconds — one commit
//  toggles `scheduledTasksDidChange`, and both the week canvas and the month grid
//  answered it with a full O(every live dated task) walk on the main context,
//  faulting `project` and `teamMembers` per row).
//
//  Scoping contract: the CALLER decides. `CalendarTaskScope` is built on the main
//  actor from PermissionStore and the operator's own filter selections; this actor
//  fetches in its own context and applies exactly that scope, never re-deriving
//  visibility — so the off-main rebuild cannot disagree with the on-screen surfaces.
//  Same contract, same reason, as DataActor+HomeRollup.
//
//  Only ids and value types cross back. `@Model` instances belong to the context
//  that fetched them.
//

import Foundation
import SwiftData

extension DataActor {

    /// The week canvas's per-day cache for the 21-day window around `weekStart`.
    func calendarWeekCache(
        scope: CalendarTaskScope,
        weekStart: Date,
        calendar: Calendar = .current
    ) -> CalendarWeekCacheSnapshot {
        // No date bound, deliberately: a task is admitted to a day by OVERLAP, so a
        // long job that began before the window still belongs to it. Any lower bound
        // on startDate would silently drop running work off the canvas.
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> {
                $0.deletedAt == nil && $0.startDate != nil
            }
        )
        guard let allTasks = try? modelContext.fetch(descriptor) else {
            return CalendarWeekCacheSnapshot(weekStart: weekStart, taskIdsByDay: [:], countsByDay: [:])
        }

        let hiddenProjectIds = CalendarTaskVisibility.hiddenProjectIds(in: modelContext)
        let visible = allTasks.filter {
            CalendarTaskScoping.admitsForWeekCanvas($0, scope: scope)
                && CalendarTaskScoping.passesFilters($0, scope: scope, hiddenProjectIds: hiddenProjectIds)
        }

        return CalendarWeekCacheBuilder.snapshot(tasks: visible, weekStart: weekStart, calendar: calendar)
    }

    /// The month grid's badge cache for every scheduled task since `cutoff`.
    /// User-event badges are folded in by the caller — those rows are already in
    /// hand on the main actor and carry no relationship to fault.
    func calendarMonthPreviews(
        scope: CalendarTaskScope,
        since cutoff: Date,
        tutorialOnly: Bool,
        calendar: Calendar = .current
    ) -> [String: [ScheduledTaskPreview]] {
        // `?? unscheduledFloor` only satisfies the optional comparison — the
        // `!= nil` conjunct means it never decides a row.
        let unscheduledFloor = Date.distantPast
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.deletedAt == nil
                    && task.startDate != nil
                    && (task.startDate ?? unscheduledFloor) >= cutoff
            }
        )
        guard let allTasks = try? modelContext.fetch(descriptor) else { return [:] }

        // Same order the main-thread path ran in: scope gate, then sort, then the
        // tutorial cut, then the operator's filters.
        var tasks = allTasks
            .filter { CalendarTaskScoping.admitsForMonthGrid($0, scope: scope) }
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }

        if tutorialOnly {
            tasks = tasks.filter { $0.id.hasPrefix("DEMO_") }
        }

        let hiddenProjectIds = CalendarTaskVisibility.hiddenProjectIds(in: modelContext)
        tasks = tasks.filter {
            CalendarTaskScoping.passesFilters($0, scope: scope, hiddenProjectIds: hiddenProjectIds)
        }

        return CalendarMonthPreviewBuilder.previews(tasks: tasks, calendar: calendar)
    }
}
