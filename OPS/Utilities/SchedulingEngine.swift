//
//  SchedulingEngine.swift
//  OPS
//
//  Pure logic engine for dependency-aware scheduling.
//  No UI or SwiftData imports — operates on protocol-based task representations.
//

import Foundation

// MARK: - Protocols

/// Minimal task representation for scheduling calculations.
/// ProjectTask conforms to this automatically via its existing stored properties.
protocol SchedulableTask {
    var id: String { get }
    var taskTypeId: String { get }
    var startDate: Date? { get }
    var endDate: Date? { get }
    var duration: Int { get }
    var effectiveDependencies: [TaskTypeDependency] { get }
    var displayOrder: Int { get }
    var schedulingTeamMemberIds: Set<String> { get }
    var schedulingProjectId: String { get }
    /// True when the user has manually edited this task's start date.
    /// Cascade logic skips locked tasks — they no longer auto-shift when a
    /// predecessor moves. Defaults to false for value-typed VirtualTask.
    var schedulingLocked: Bool { get }
    /// True when the task is eligible for placement. Auto-schedule only places
    /// active tasks; completed/cancelled tasks are excluded from the to-place
    /// set (but still seen as commitments). Defaults to true for value types.
    var schedulingIsActive: Bool { get }
}

extension SchedulableTask {
    /// Default conformance for types that don't track manual edits (the
    /// scheduling engine's internal VirtualTask). Real ProjectTask overrides.
    var schedulingLocked: Bool { false }
    /// Default conformance for value-typed tasks (VirtualTask) — always eligible.
    /// Real ProjectTask overrides to gate on `status == .active`.
    var schedulingIsActive: Bool { true }
}

// MARK: - SchedulingEngine

struct SchedulingEngine {

    // MARK: - Result Types

    struct CascadeResult {
        let changes: [TaskDateChange]

        struct TaskDateChange: Identifiable {
            let id: String
            let taskTypeId: String
            let oldStartDate: Date?
            let oldEndDate: Date?
            let newStartDate: Date
            let newEndDate: Date
        }
    }

    struct AutoScheduleResult {
        let placements: [TaskPlacement]

        struct TaskPlacement: Identifiable {
            let id: String
            let taskTypeId: String
            let startDate: Date
            let endDate: Date
        }
    }

    // MARK: - Push (Single Task)

    /// Push a single task by N days. Returns new start and end dates.
    static func pushByDays(
        task: any SchedulableTask,
        days: Int,
        skipWeekends: Bool = false
    ) -> (newStart: Date, newEnd: Date) {
        let calendar = Calendar.current
        guard let start = task.startDate else {
            let now = Date()
            return (now, calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: now) ?? now)
        }

        var newStart = calendar.date(byAdding: .day, value: days, to: start) ?? start
        if skipWeekends {
            newStart = skipToWeekday(date: newStart, calendar: calendar)
        }
        let newEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: newStart) ?? newStart
        return (newStart, newEnd)
    }

    /// Push a task by whole calendar weeks. This preserves the original
    /// weekday even when the company auto-scheduler skips weekends; a "+1 week"
    /// quick action is a calendar-week move (exactly 7 days, same weekday), not
    /// "seven days then weekend-normalize" — the latter over-advances a
    /// weekend-anchored task to +9. Used by every week push affordance so the
    /// result is identical on every surface.
    static func pushByCalendarWeeks(
        task: any SchedulableTask,
        weeks: Int
    ) -> (newStart: Date, newEnd: Date) {
        let calendar = Calendar.current
        guard let start = task.startDate else {
            let now = Date()
            return (now, calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: now) ?? now)
        }

        let newStart = calendar.date(byAdding: .weekOfYear, value: weeks, to: start) ?? start
        let newEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: newStart) ?? newStart
        return (newStart, newEnd)
    }

    // MARK: - Cascade

    /// Calculate cascade effects when a task is pushed.
    /// Returns all tasks that need to move (not including the pushed task itself).
    static func calculateCascade(
        pushedTaskId: String,
        newStartDate: Date,
        newEndDate: Date,
        allProjectTasks: [any SchedulableTask],
        skipWeekends: Bool = false
    ) -> CascadeResult {
        let calendar = Calendar.current

        // Track new dates for all tasks
        var newDates: [String: (start: Date, end: Date)] = [:]
        newDates[pushedTaskId] = (newStartDate, newEndDate)

        // Topological sort
        let sorted = topologicalSort(tasks: allProjectTasks)

        var changes: [CascadeResult.TaskDateChange] = []

        for task in sorted {
            if task.id == pushedTaskId { continue }
            // Respect manual schedule lock — once a user has hand-edited a
            // paired task's date, predecessor movements no longer auto-shift it.
            if task.schedulingLocked { continue }

            // Check if any of this task's dependencies have moved
            var latestEarliestStart: Date? = nil

            for dep in task.effectiveDependencies {
                let predecessors = allProjectTasks.filter { $0.taskTypeId == dep.dependsOnTaskTypeId }
                for pred in predecessors {
                    let predStart = newDates[pred.id]?.start ?? pred.startDate ?? Date()
                    let predDuration = pred.duration
                    let earliest = dep.earliestStart(predecessorStart: predStart, predecessorDuration: predDuration)

                    if let current = latestEarliestStart {
                        if earliest > current { latestEarliestStart = earliest }
                    } else {
                        latestEarliestStart = earliest
                    }
                }
            }

            // If this task needs to move forward
            if let earliest = latestEarliestStart,
               let currentStart = task.startDate,
               earliest > currentStart {
                var adjustedStart = earliest
                if skipWeekends {
                    adjustedStart = skipToWeekday(date: adjustedStart, calendar: calendar)
                }
                let adjustedEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: adjustedStart) ?? adjustedStart

                newDates[task.id] = (adjustedStart, adjustedEnd)
                changes.append(CascadeResult.TaskDateChange(
                    id: task.id,
                    taskTypeId: task.taskTypeId,
                    oldStartDate: task.startDate,
                    oldEndDate: task.endDate,
                    newStartDate: adjustedStart,
                    newEndDate: adjustedEnd
                ))
            }
        }

        return CascadeResult(changes: changes)
    }

    // MARK: - Auto-Schedule

    /// Auto-schedule unscheduled tasks starting from an anchor date.
    /// Respects dependency order; falls back to displayOrder when no dependencies.
    static func autoSchedule(
        unscheduledTasks: [any SchedulableTask],
        allProjectTasks: [any SchedulableTask],
        anchorDate: Date,
        skipWeekends: Bool = false
    ) -> AutoScheduleResult {
        let calendar = Calendar.current

        let sorted = topologicalSort(tasks: unscheduledTasks)

        // Track placed dates (include already-scheduled tasks)
        var placedDates: [String: (start: Date, end: Date)] = [:]
        for task in allProjectTasks {
            if let start = task.startDate, let end = task.endDate {
                placedDates[task.id] = (start, end)
            }
        }

        var placements: [AutoScheduleResult.TaskPlacement] = []
        var nextAvailable = skipWeekends ? skipToWeekday(date: anchorDate, calendar: calendar) : anchorDate

        for task in sorted {
            var taskStart = nextAvailable

            // Check dependency constraints
            for dep in task.effectiveDependencies {
                let predecessors = allProjectTasks.filter { $0.taskTypeId == dep.dependsOnTaskTypeId }
                for pred in predecessors {
                    if let predDates = placedDates[pred.id] {
                        let earliest = dep.earliestStart(predecessorStart: predDates.start, predecessorDuration: pred.duration)
                        if earliest > taskStart {
                            taskStart = earliest
                        }
                    }
                }
            }

            if skipWeekends {
                taskStart = skipToWeekday(date: taskStart, calendar: calendar)
            }

            let taskEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: taskStart) ?? taskStart

            placedDates[task.id] = (taskStart, taskEnd)
            placements.append(AutoScheduleResult.TaskPlacement(
                id: task.id,
                taskTypeId: task.taskTypeId,
                startDate: taskStart,
                endDate: taskEnd
            ))

            // Pack tight: next task starts day after this one
            let dayAfter = calendar.date(byAdding: .day, value: 1, to: taskEnd) ?? taskEnd
            if dayAfter > nextAvailable {
                nextAvailable = dayAfter
            }
        }

        return AutoScheduleResult(placements: placements)
    }

    // MARK: - Topological Sort

    /// Sort tasks by dependency order. Tasks with no deps come first.
    /// Within the same dependency level, sorted by displayOrder.
    static func topologicalSort(tasks: [any SchedulableTask]) -> [any SchedulableTask] {
        let taskTypeIds = Set(tasks.map { $0.taskTypeId })

        // Build adjacency: taskTypeId -> [taskTypeIds it depends on]
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]

        for task in tasks {
            let typeId = task.taskTypeId
            if inDegree[typeId] == nil { inDegree[typeId] = 0 }

            for dep in task.effectiveDependencies {
                if taskTypeIds.contains(dep.dependsOnTaskTypeId) {
                    inDegree[typeId, default: 0] += 1
                    dependents[dep.dependsOnTaskTypeId, default: []].append(typeId)
                }
            }
        }

        // Kahn's algorithm
        var queue = inDegree.filter { $0.value == 0 }.map { $0.key }.sorted()
        var orderedTypeIds: [String] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            orderedTypeIds.append(current)

            for dep in (dependents[current] ?? []) {
                inDegree[dep, default: 0] -= 1
                if inDegree[dep] == 0 {
                    queue.append(dep)
                }
            }
        }

        // Circular deps go at end
        for typeId in taskTypeIds where !orderedTypeIds.contains(typeId) {
            orderedTypeIds.append(typeId)
        }

        // Map back to tasks, sorted by type order then displayOrder
        let typeOrder = Dictionary(uniqueKeysWithValues: orderedTypeIds.enumerated().map { ($1, $0) })
        return tasks.sorted { a, b in
            let orderA = typeOrder[a.taskTypeId] ?? Int.max
            let orderB = typeOrder[b.taskTypeId] ?? Int.max
            if orderA != orderB { return orderA < orderB }
            return a.displayOrder < b.displayOrder
        }
    }

    // MARK: - Cycle Detection

    /// Check if adding a dependency would create a circular reference.
    static func wouldCreateCycle(
        taskTypeId: String,
        newDependsOnId: String,
        allTaskTypes: [(id: String, dependencies: [TaskTypeDependency])]
    ) -> Bool {
        var visited: Set<String> = []
        var queue: [String] = [newDependsOnId]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == taskTypeId { return true }
            if visited.contains(current) { continue }
            visited.insert(current)

            if let deps = allTaskTypes.first(where: { $0.id == current })?.dependencies {
                for dep in deps {
                    queue.append(dep.dependsOnTaskTypeId)
                }
            }
        }
        return false
    }

    // MARK: - Helpers

    /// Advance date to next weekday if it falls on a weekend.
    private static func skipToWeekday(date: Date, calendar: Calendar) -> Date {
        var result = date
        while calendar.isDateInWeekend(result) {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
        }
        return result
    }
}
