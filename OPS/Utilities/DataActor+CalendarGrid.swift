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
    ) throws -> CalendarWeekCacheSnapshot {
        try checkActiveModelSession()
        let window = CalendarWeekWindow(weekStart: weekStart, calendar: calendar)
        let start = window.start
        let endExclusive = window.endExclusive
        let companyId = scope.companyId ?? ""
        let distantPast = Date.distantPast
        let distantFuture = Date.distantFuture

        // Two bounded predicates preserve overlap semantics without asking
        // SwiftData to translate optional-date coalescing across both cases.
        // A long-running task is retained when its end reaches the window; a
        // single-day task with nil end is bounded directly by its start.
        let rangedDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.deletedAt == nil
                    && task.companyId == companyId
                    && (task.startDate ?? distantFuture) < endExclusive
                    && (task.endDate ?? distantPast) >= start
            }
        )
        let startsInsideDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.deletedAt == nil
                    && task.companyId == companyId
                    && (task.startDate ?? distantPast) >= start
                    && (task.startDate ?? distantFuture) < endExclusive
            }
        )
        guard let rangedTasks = try? modelContext.fetch(rangedDescriptor),
              let startsInsideTasks = try? modelContext.fetch(startsInsideDescriptor) else {
            return CalendarWeekCacheSnapshot(weekStart: weekStart, taskIdsByDay: [:], countsByDay: [:])
        }
        let singleDayTasks = startsInsideTasks.filter { $0.endDate == nil }
        let allTasks = rangedTasks + singleDayTasks

        let hiddenProjectIds = CalendarTaskVisibility.hiddenProjectIds(in: modelContext)
        let visible = allTasks.filter {
            CalendarTaskScoping.admitsForWeekCanvas($0, scope: scope)
                && CalendarTaskScoping.passesFilters($0, scope: scope, hiddenProjectIds: hiddenProjectIds)
        }

        return CalendarWeekCacheBuilder.snapshot(tasks: visible, weekStart: weekStart, calendar: calendar)
    }

    /// All sources needed to draw the calendar, prepared in DataActor's private
    /// context. Only identifiers and value snapshots cross back to the UI.
    func calendarLoadSnapshot(
        taskScope: CalendarTaskScope,
        auxiliaryScope: CalendarAuxiliaryScope,
        weekStart: Date,
        centerDate: Date,
        calendar: Calendar = .current
    ) throws -> CalendarLoadSnapshot {
        try checkActiveModelSession()
        return try CalendarLoadSnapshot(
            week: calendarWeekCache(scope: taskScope, weekStart: weekStart, calendar: calendar),
            auxiliary: calendarAuxiliarySnapshot(
                scope: auxiliaryScope,
                centerDate: centerDate,
                calendar: calendar
            )
        )
    }

    /// Date-bounded personal/time-off events and booked visits. The previous
    /// main-context path fetched every company row, then filtered visibility in
    /// memory while the app was trying to reveal the Schedule tab.
    private func calendarAuxiliarySnapshot(
        scope: CalendarAuxiliaryScope,
        centerDate: Date,
        calendar: Calendar
    ) -> CalendarAuxiliarySnapshot {
        let window = CalendarAuxiliaryWindow(centerDate: centerDate, calendar: calendar)
        let companyId = scope.companyId
        let start = window.start
        let endExclusive = window.endExclusive

        let eventDescriptor = FetchDescriptor<CalendarUserEvent>(
            predicate: #Predicate<CalendarUserEvent> { event in
                event.companyId == companyId
                    && event.deletedAt == nil
                    && event.startDate < endExclusive
                    && event.endDate > start
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let userEvents = ((try? modelContext.fetch(eventDescriptor)) ?? []).filter { event in
            if scope.canViewAllCalendar { return true }
            if event.userId == scope.userId { return true }
            if event.teamMemberIds?.contains(scope.userId) == true { return true }
            return scope.canApproveTimeOff && event.type == CalendarUserEventType.timeOff.rawValue
        }

        let unscheduledFloor = Date.distantPast
        let visitDescriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> { visit in
                visit.companyId == companyId
                    && visit.bookedAt != nil
                    && visit.deletedAt == nil
                    && visit.scheduledAt != nil
                    && (visit.scheduledAt ?? unscheduledFloor) >= start
                    && (visit.scheduledAt ?? unscheduledFloor) < endExclusive
            },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        let canonicalUser = scope.userId.lowercased()
        let visits = ((try? modelContext.fetch(visitDescriptor)) ?? []).filter { visit in
            guard visit.status == .scheduled || visit.status == .inProgress else { return false }
            if scope.canViewAllCalendar { return true }
            return visit.assigneeIds.contains(canonicalUser) || visit.createdBy == canonicalUser
        }

        return CalendarAuxiliarySnapshot(
            window: window,
            userEventIds: userEvents.map(\.id),
            bookedVisitIds: visits.map(\.id)
        )
    }

    /// The month grid's badge cache for every scheduled task since `cutoff`.
    /// User-event badges are folded in by the caller — those rows are already in
    /// hand on the main actor and carry no relationship to fault.
    func calendarMonthPreviews(
        scope: CalendarTaskScope,
        since cutoff: Date,
        tutorialOnly: Bool,
        calendar: Calendar = .current
    ) throws -> [String: [ScheduledTaskPreview]] {
        try checkActiveModelSession()
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
