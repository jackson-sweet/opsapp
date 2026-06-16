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
            /// Why this task is moving — drives the grouped cascade preview.
            enum Reason {
                /// Shares a crew member with the pushed task (forward consolidation).
                case crew
                /// Task-type dependency on a task that moved.
                case dependency
            }
            let id: String
            let taskTypeId: String
            let oldStartDate: Date?
            let oldEndDate: Date?
            let newStartDate: Date
            let newEndDate: Date
            var reason: Reason = .dependency
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
    /// - Parameter seededDates: tasks already repositioned by an earlier pass
    ///   (e.g. crew consolidation). These are used as the baseline a dependency
    ///   must beat to move a task further, and are read when resolving a moved
    ///   predecessor's date — so a dependency only ever pushes a task *later*
    ///   than its crew-shifted position, never earlier. Crew-seeded tasks are
    ///   NOT emitted here; the caller owns those change records.
    static func calculateCascade(
        pushedTaskId: String,
        newStartDate: Date,
        newEndDate: Date,
        allProjectTasks: [any SchedulableTask],
        skipWeekends: Bool = false,
        seededDates: [String: (start: Date, end: Date)] = [:]
    ) -> CascadeResult {
        let calendar = Calendar.current

        // Track new dates for all tasks. Seed the pushed task plus any
        // pre-positioned (crew-shifted) tasks so the dependency pass reads
        // their new dates and only pushes further when a dependency demands it.
        var newDates: [String: (start: Date, end: Date)] = seededDates
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

            // Baseline is the task's crew-shifted position when present, else its
            // current start — so a dependency only moves it further forward.
            let baselineStart = newDates[task.id]?.start ?? task.startDate

            // If this task needs to move forward
            if let earliest = latestEarliestStart,
               let currentStart = baselineStart,
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
                    newEndDate: adjustedEnd,
                    reason: .dependency
                ))
            }
        }

        return CascadeResult(changes: changes)
    }

    // MARK: - Crew Consolidation

    /// Forward-only consolidation of a crew member's schedule after a push.
    ///
    /// When a task is cascade-pushed, the rest of that task's crew's jobs pack
    /// tightly forward to close the gap the push opens — but no job is ever
    /// moved earlier than its current start (the field-safe direction: pushing
    /// a job later is safe; pulling one earlier can break a customer/material
    /// commitment). Cross-project: evaluates the full task set passed in.
    ///
    /// Locked crew jobs are treated as fixed obstacles — never moved, always
    /// packed around — so two auto-moved jobs can never land on the same day.
    /// Completed/cancelled and crew-disjoint jobs are ignored. Returns one
    /// `.crew` change per task that actually moves (excludes the pushed task).
    static func calculateCrewConsolidation(
        pushedTask: any SchedulableTask,
        pushedOriginalStart: Date,
        pushedNewStart: Date,
        pushedNewEnd: Date,
        allTasks: [any SchedulableTask],
        skipWeekends: Bool = false
    ) -> [CascadeResult.TaskDateChange] {
        let calendar = Calendar.current
        let crew = pushedTask.schedulingTeamMemberIds
        guard !crew.isEmpty else { return [] }

        let anchorDay = calendar.startOfDay(for: pushedOriginalStart)

        // Crew jobs at/after the pushed job's original day, excluding the pushed
        // job and crew-disjoint/inactive jobs. Locked jobs stay in as obstacles.
        let window = allTasks.filter { task in
            guard task.id != pushedTask.id,
                  task.schedulingIsActive,
                  !task.schedulingTeamMemberIds.isDisjoint(with: crew),
                  let start = task.startDate else { return false }
            return calendar.startOfDay(for: start) >= anchorDay
        }.sorted { a, b in
            let sa = a.startDate ?? Date.distantFuture
            let sb = b.startDate ?? Date.distantFuture
            if sa != sb { return sa < sb }
            if a.displayOrder != b.displayOrder { return a.displayOrder < b.displayOrder }
            return a.id < b.id
        }

        // Day-ranges occupied by locked crew jobs — moved jobs pack around them.
        let lockedRanges: [(start: Date, end: Date)] = window.compactMap { task in
            guard task.schedulingLocked, let start = task.startDate else { return nil }
            let end = task.endDate ?? start
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        }

        var changes: [CascadeResult.TaskDateChange] = []
        var cursorEnd = calendar.startOfDay(for: pushedNewEnd)

        for task in window where !task.schedulingLocked {
            guard let originalStart = task.startDate else { continue }
            let originalDay = calendar.startOfDay(for: originalStart)
            let dayAfterCursor = calendar.date(byAdding: .day, value: 1, to: cursorEnd) ?? cursorEnd
            // Forward-only floor: a job never starts before its own current day.
            let earliest = max(dayAfterCursor, originalDay)

            // If the pack hasn't caught up to this job, leave it exactly where it
            // is (never pulled earlier, never normalized off a weekend it already
            // sits on) — UNLESS it already overlaps a locked crew job, in which
            // case it must pack forward around that obstacle.
            if earliest == originalDay {
                let stayEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: originalDay) ?? originalDay
                let overlapsLocked = lockedRanges.contains { rangesOverlap(originalDay, stayEnd, $0.start, $0.end) }
                if !overlapsLocked {
                    cursorEnd = max(cursorEnd, stayEnd)
                    continue
                }
            }

            // The job must move forward to clear the previous job (or a locked
            // obstacle) — land it in the next free slot, dodging weekends and
            // locked crew jobs, never earlier than its own current day.
            let targetDay = nextFreeDay(
                from: earliest,
                duration: task.duration,
                lockedRanges: lockedRanges,
                skipWeekends: skipWeekends,
                calendar: calendar
            )
            let placedEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: targetDay) ?? targetDay
            cursorEnd = max(cursorEnd, placedEnd)

            let shiftDays = calendar.dateComponents([.day], from: originalDay, to: targetDay).day ?? 0
            guard shiftDays != 0 else { continue }

            // Preserve the stored time-of-day by shifting the original date.
            let newStart = calendar.date(byAdding: .day, value: shiftDays, to: originalStart) ?? originalStart
            let newEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: newStart) ?? newStart
            changes.append(CascadeResult.TaskDateChange(
                id: task.id,
                taskTypeId: task.taskTypeId,
                oldStartDate: task.startDate,
                oldEndDate: task.endDate,
                newStartDate: newStart,
                newEndDate: newEnd,
                reason: .crew
            ))
        }

        return changes
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

    /// Advance a start day forward until the `[start, start+duration-1]` span
    /// clears every weekend (when enabled) and every locked crew job range.
    /// Used by crew consolidation to pack moved jobs into truly-free slots.
    private static func nextFreeDay(
        from start: Date,
        duration: Int,
        lockedRanges: [(start: Date, end: Date)],
        skipWeekends: Bool,
        calendar: Calendar
    ) -> Date {
        var day = start
        // Bounded loop — a year of working days is far past any real schedule.
        for _ in 0..<366 {
            if skipWeekends && calendar.isDateInWeekend(day) {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                continue
            }
            let endDay = calendar.date(byAdding: .day, value: max(duration - 1, 0), to: day) ?? day
            if let conflict = lockedRanges.first(where: { rangesOverlap(day, endDay, $0.start, $0.end) }) {
                day = calendar.date(byAdding: .day, value: 1, to: conflict.end) ?? day
                continue
            }
            return day
        }
        return day
    }

    /// Inclusive overlap test for two day-ranges.
    private static func rangesOverlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        aStart <= bEnd && bStart <= aEnd
    }
}
