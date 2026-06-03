//
//  AutoScheduleManager.swift
//  OPS
//
//  Centralized scheduling intelligence. Wraps SchedulingEngine with team availability,
//  geographic grouping, and configurable scheduling windows.
//
//  Pure logic — no database writes, no UI imports. Returns a SchedulePlan
//  for the caller to apply.
//

import Foundation

struct AutoScheduleManager {

    // MARK: - Run Accumulator Types

    /// One already-placed task in a batch run; seen by later tasks as a commitment.
    struct PlacedRecord {
        let id: String
        let taskTypeId: String
        let startDate: Date
        let endDate: Date
        let teamMemberIds: Set<String>
        let projectId: String
    }

    /// Mutable accumulator threaded through a batch/priority run.
    private struct RunState {
        var placements: [TaskPlacement] = []
        var conflicts: [ScheduleConflict] = []
        var warnings: [String] = []
        var placed: [PlacedRecord] = []
        var proximityGroups = 0
    }

    // MARK: - Public Entry Point

    static func schedule(request: ScheduleRequest, provider: ScheduleDataProvider) -> SchedulePlan {
        let calendar = Calendar.current

        // Clamp anchor to today minimum
        let today = calendar.startOfDay(for: Date())
        let anchor = max(calendar.startOfDay(for: request.anchorDate), today)

        switch request.mode {
        case .single(let task, let teamMemberIds):
            return scheduleSingle(
                task: task,
                teamMemberIds: teamMemberIds,
                anchor: anchor,
                constraints: request.constraints,
                provider: provider
            )

        case .projectBatch(let projectId):
            return scheduleBatch(
                projectIds: [projectId],
                anchor: anchor,
                constraints: request.constraints,
                provider: provider
            )

        case .multiProjectBatch(let projectIds):
            return scheduleBatch(
                projectIds: projectIds,
                anchor: anchor,
                constraints: request.constraints,
                provider: provider
            )

        case .taskPriorityQueue(let orderedTaskIds, let includeUnranked):
            return schedulePriorityQueue(
                orderedTaskIds: orderedTaskIds,
                includeUnranked: includeUnranked,
                anchor: anchor,
                constraints: request.constraints,
                provider: provider
            )

        case .projectPriorityQueue(let orderedProjectIds):
            return scheduleBatch(
                projectIds: orderedProjectIds,
                respectOrder: true,
                anchor: anchor,
                constraints: request.constraints,
                provider: provider
            )
        }
    }

    // MARK: - Single Task Scheduling

    private static func scheduleSingle(
        task: any SchedulableTask,
        teamMemberIds: Set<String>,
        anchor: Date,
        constraints: ScheduleConstraints,
        provider: ScheduleDataProvider
    ) -> SchedulePlan {
        let calendar = Calendar.current
        var warnings: [String] = []
        var conflicts: [ScheduleConflict] = []

        // Pass 1: Dependency floor
        let projectTasks = provider.tasksForProject(task.schedulingProjectId)
        let dependencyFloor = calculateDependencyFloor(
            for: task,
            allProjectTasks: projectTasks,
            anchor: anchor,
            skipWeekends: constraints.skipWeekends
        )

        // Pass 2: Team availability
        let effectiveDuration = max(task.duration, 1) // G1: zero duration → 1 day

        if teamMemberIds.isEmpty {
            // A6: No crew — schedule on dependency floor, warn
            conflicts.append(ScheduleConflict(
                id: task.id,
                type: .noCrewAssigned,
                message: "No crew assigned — availability not checked"
            ))

            let startDate = constraints.skipWeekends
                ? skipToWeekday(date: dependencyFloor, calendar: calendar)
                : dependencyFloor
            let endDate = calendar.date(byAdding: .day, value: max(effectiveDuration - 1, 0), to: startDate) ?? startDate

            let placement = TaskPlacement(
                id: task.id,
                taskTypeId: task.taskTypeId,
                startDate: startDate,
                endDate: endDate,
                startTime: nil,
                endTime: nil,
                alternative: nil
            )

            return SchedulePlan(
                placements: [placement],
                conflicts: conflicts,
                metadata: ScheduleMetadata(
                    totalGapDays: 0,
                    proximityGroupsFound: 0,
                    weatherDependentTaskCount: 0,
                    weatherDeferrals: 0,
                    downstreamUnscheduledCount: countDownstreamUnscheduled(task: task, projectTasks: projectTasks),
                    warnings: warnings
                )
            )
        }

        // Get all existing commitments for these team members
        let existingCommitments = provider.allScheduledTasksForMembers(teamMemberIds, from: dependencyFloor)

        // Find first available contiguous window
        let slot = findAvailableSlot(
            memberIds: teamMemberIds,
            duration: effectiveDuration,
            from: dependencyFloor,
            existingCommitments: existingCommitments,
            constraints: constraints,
            calendar: calendar
        )

        let endDate = calendar.date(byAdding: .day, value: max(effectiveDuration - 1, 0), to: slot) ?? slot

        // Pass 3: Geographic grouping (scan for alternatives)
        let alternative = findGeographicAlternative(
            task: task,
            teamMemberIds: teamMemberIds,
            primaryStart: slot,
            duration: effectiveDuration,
            existingCommitments: existingCommitments,
            constraints: constraints,
            provider: provider,
            calendar: calendar
        )

        if let alt = alternative {
            warnings.append("Geographic grouping opportunity found: \(alt.nearbyTaskCount) nearby tasks, \(alt.deferralDays) days deferral")
        }

        let placement = TaskPlacement(
            id: task.id,
            taskTypeId: task.taskTypeId,
            startDate: slot,
            endDate: endDate,
            startTime: nil,
            endTime: nil,
            alternative: alternative
        )

        return SchedulePlan(
            placements: [placement],
            conflicts: conflicts,
            metadata: ScheduleMetadata(
                totalGapDays: 0,
                proximityGroupsFound: alternative != nil ? 1 : 0,
                weatherDependentTaskCount: 0,
                weatherDeferrals: 0,
                downstreamUnscheduledCount: countDownstreamUnscheduled(task: task, projectTasks: projectTasks),
                warnings: warnings
            )
        )
    }

    // MARK: - Per-Task Placement

    /// Places a single task into a run, mutating `state` to record the placement,
    /// any conflicts/warnings, and a `PlacedRecord` so later tasks see it as a
    /// commitment. Extracted verbatim from `scheduleBatch`'s inner loop so a
    /// priority-queue sequencer can reuse the exact same placement logic.
    ///
    /// `dependencyVisibleTasks` is the base set of tasks visible when computing
    /// this task's dependency floor (in batch mode, the current project's DB
    /// tasks); already-placed records for the same project are layered on top as
    /// virtual scheduled tasks.
    private static func placeNext(
        _ task: any SchedulableTask,
        dependencyVisibleTasks: [any SchedulableTask],
        anchor: Date,
        constraints: ScheduleConstraints,
        provider: ScheduleDataProvider,
        state: inout RunState
    ) {
        let calendar = Calendar.current

        let teamMemberIds = task.schedulingTeamMemberIds
        let effectiveDuration = max(task.duration, 1)
        let projectId = task.schedulingProjectId

        // Pass 1: Dependency floor (consider both DB tasks and already-placed tasks)
        var allKnownTasks: [any SchedulableTask] = dependencyVisibleTasks

        // Add already-placed tasks from this batch as virtual scheduled tasks
        for placed in state.placed where placed.projectId == projectId {
            let virtual = VirtualTask(
                id: placed.id,
                taskTypeId: placed.taskTypeId,
                startDate: placed.startDate,
                endDate: placed.endDate,
                duration: calendar.dateComponents([.day], from: placed.startDate, to: placed.endDate).day.map { $0 + 1 } ?? 1,
                effectiveDependencies: [],
                displayOrder: 0,
                schedulingTeamMemberIds: placed.teamMemberIds,
                schedulingProjectId: placed.projectId
            )
            allKnownTasks.append(virtual)
        }

        let dependencyFloor = calculateDependencyFloor(
            for: task,
            allProjectTasks: allKnownTasks,
            anchor: anchor,
            skipWeekends: constraints.skipWeekends
        )

        // Pass 2: Team availability
        if teamMemberIds.isEmpty {
            state.conflicts.append(ScheduleConflict(
                id: task.id, type: .noCrewAssigned,
                message: "No crew assigned — availability not checked"
            ))

            let startDate = constraints.skipWeekends
                ? skipToWeekday(date: dependencyFloor, calendar: calendar)
                : dependencyFloor
            let endDate = calendar.date(byAdding: .day, value: max(effectiveDuration - 1, 0), to: startDate) ?? startDate

            state.placements.append(TaskPlacement(
                id: task.id, taskTypeId: task.taskTypeId,
                startDate: startDate, endDate: endDate,
                startTime: nil, endTime: nil, alternative: nil
            ))

            state.placed.append(PlacedRecord(
                id: task.id, taskTypeId: task.taskTypeId,
                startDate: startDate, endDate: endDate,
                teamMemberIds: teamMemberIds, projectId: projectId
            ))
            return
        }

        // Get existing + already-placed commitments for these members
        var existingCommitments = provider.allScheduledTasksForMembers(teamMemberIds, from: dependencyFloor)

        // Add already-placed batch tasks as virtual commitments
        for placed in state.placed {
            if !placed.teamMemberIds.isDisjoint(with: teamMemberIds) {
                existingCommitments.append(VirtualTask(
                    id: placed.id,
                    taskTypeId: placed.taskTypeId,
                    startDate: placed.startDate,
                    endDate: placed.endDate,
                    duration: calendar.dateComponents([.day], from: placed.startDate, to: placed.endDate).day.map { $0 + 1 } ?? 1,
                    effectiveDependencies: [],
                    displayOrder: 0,
                    schedulingTeamMemberIds: placed.teamMemberIds,
                    schedulingProjectId: placed.projectId
                ))
            }
        }

        let slot = findAvailableSlot(
            memberIds: teamMemberIds,
            duration: effectiveDuration,
            from: dependencyFloor,
            existingCommitments: existingCommitments,
            constraints: constraints,
            calendar: calendar
        )

        let endDate = calendar.date(byAdding: .day, value: max(effectiveDuration - 1, 0), to: slot) ?? slot

        // Pass 3: Geographic alternative
        let alternative = findGeographicAlternative(
            task: task,
            teamMemberIds: teamMemberIds,
            primaryStart: slot,
            duration: effectiveDuration,
            existingCommitments: existingCommitments,
            constraints: constraints,
            provider: provider,
            calendar: calendar
        )

        if alternative != nil { state.proximityGroups += 1 }

        state.placements.append(TaskPlacement(
            id: task.id, taskTypeId: task.taskTypeId,
            startDate: slot, endDate: endDate,
            startTime: nil, endTime: nil, alternative: alternative
        ))

        state.placed.append(PlacedRecord(
            id: task.id, taskTypeId: task.taskTypeId,
            startDate: slot, endDate: endDate,
            teamMemberIds: teamMemberIds, projectId: projectId
        ))
    }

    // MARK: - Batch Scheduling

    private static func scheduleBatch(
        projectIds: [String],
        respectOrder: Bool = false,
        anchor: Date,
        constraints: ScheduleConstraints,
        provider: ScheduleDataProvider
    ) -> SchedulePlan {
        let calendar = Calendar.current

        // Sort projects by priority (won date → estimate approved → created),
        // or preserve explicit caller order when respectOrder is true.
        let sortedProjectIds = respectOrder
            ? projectIds
            : projectIds.sorted { a, b in
                let dateA = provider.priorityDateForProject(a) ?? Date.distantFuture
                let dateB = provider.priorityDateForProject(b) ?? Date.distantFuture
                return dateA < dateB
            }

        var state = RunState()

        for projectId in sortedProjectIds {
            let projectTasks = provider.tasksForProject(projectId)
            let unscheduled = projectTasks.filter { $0.startDate == nil || $0.endDate == nil }

            if unscheduled.isEmpty { continue }

            // Topological sort within project
            let sorted = SchedulingEngine.topologicalSort(tasks: unscheduled)

            for task in sorted {
                placeNext(
                    task,
                    dependencyVisibleTasks: projectTasks,
                    anchor: anchor,
                    constraints: constraints,
                    provider: provider,
                    state: &state
                )
            }
        }

        // Pass 4: Calculate gap days
        let totalGapDays = calculateTotalGapDays(placements: state.placements, calendar: calendar)

        return SchedulePlan(
            placements: state.placements,
            conflicts: state.conflicts,
            metadata: ScheduleMetadata(
                totalGapDays: totalGapDays,
                proximityGroupsFound: state.proximityGroups,
                weatherDependentTaskCount: 0,
                weatherDeferrals: 0,
                downstreamUnscheduledCount: 0,
                warnings: state.warnings
            )
        )
    }

    // MARK: - Priority-Queue Scheduling

    /// Schedules a flat, cross-project task list in explicit priority order,
    /// deferring any task whose predecessors aren't placed yet so dependencies
    /// always win. Reuses placeNext — the SAME placement logic as the batch path.
    private static func schedulePriorityQueue(
        orderedTaskIds: [String],
        includeUnranked: Bool,
        anchor: Date,
        constraints: ScheduleConstraints,
        provider: ScheduleDataProvider
    ) -> SchedulePlan {
        let calendar = Calendar.current
        var state = RunState()

        // Candidate set in priority order; unranked tail appended when requested.
        var candidates = provider.schedulableTasks(forIds: orderedTaskIds)
        if includeUnranked {
            candidates.append(contentsOf: provider.unrankedActiveSchedulableTasks())
        }

        // Only schedule tasks that still need it (no dates). Already-dated tasks act
        // as fixed commitments via provider.allScheduledTasksForMembers (inside placeNext).
        var remaining = candidates.filter { $0.startDate == nil || $0.endDate == nil }
        guard !remaining.isEmpty else { return .empty }

        // Priority-respecting topological traversal: among tasks whose predecessors
        // (matched by taskTypeId, still in the to-place set) are already placed, take
        // the highest-priority (earliest in `remaining`) and place it. Repeat.
        func predecessorsSatisfied(_ task: any SchedulableTask) -> Bool {
            let placedTypeIds = Set(state.placed.map(\.taskTypeId))
            for dep in task.effectiveDependencies {
                let stillToPlace = remaining.contains { $0.taskTypeId == dep.dependsOnTaskTypeId }
                if stillToPlace && !placedTypeIds.contains(dep.dependsOnTaskTypeId) {
                    return false
                }
            }
            return true
        }

        var safety = remaining.count * remaining.count + 1
        while !remaining.isEmpty && safety > 0 {
            safety -= 1
            if let idx = remaining.firstIndex(where: predecessorsSatisfied) {
                let task = remaining.remove(at: idx)
                let visible = provider.tasksForProject(task.schedulingProjectId)
                placeNext(task, dependencyVisibleTasks: visible, anchor: anchor, constraints: constraints, provider: provider, state: &state)
            } else {
                // Cycle / unresolvable predecessor: place the rest in priority order.
                for task in remaining {
                    let visible = provider.tasksForProject(task.schedulingProjectId)
                    placeNext(task, dependencyVisibleTasks: visible, anchor: anchor, constraints: constraints, provider: provider, state: &state)
                }
                remaining.removeAll()
            }
        }

        let totalGapDays = calculateTotalGapDays(placements: state.placements, calendar: calendar)
        return SchedulePlan(
            placements: state.placements,
            conflicts: state.conflicts,
            metadata: ScheduleMetadata(
                totalGapDays: totalGapDays,
                proximityGroupsFound: state.proximityGroups,
                weatherDependentTaskCount: 0,
                weatherDeferrals: 0,
                downstreamUnscheduledCount: 0,
                warnings: state.warnings
            )
        )
    }

    // MARK: - Pass 1: Dependency Floor

    private static func calculateDependencyFloor(
        for task: any SchedulableTask,
        allProjectTasks: [any SchedulableTask],
        anchor: Date,
        skipWeekends: Bool
    ) -> Date {
        let calendar = Calendar.current
        var floor = anchor

        for dep in task.effectiveDependencies {
            // Find predecessors by taskTypeId
            let predecessors = allProjectTasks.filter { $0.taskTypeId == dep.dependsOnTaskTypeId }
            for pred in predecessors {
                guard let predStart = pred.startDate else { continue }
                let earliest = dep.earliestStart(predecessorStart: predStart, predecessorDuration: pred.duration)
                if earliest > floor {
                    floor = earliest
                }
            }
        }

        if skipWeekends {
            floor = Self.skipToWeekday(date: floor, calendar: calendar)
        }

        return floor
    }

    // MARK: - Pass 2: Find Available Slot

    private static func findAvailableSlot(
        memberIds: Set<String>,
        duration: Int,
        from startDate: Date,
        existingCommitments: [any SchedulableTask],
        constraints: ScheduleConstraints,
        calendar: Calendar
    ) -> Date {
        // Build a set of booked days for each member
        var bookedDays: [String: Set<Date>] = [:]
        for memberId in memberIds {
            bookedDays[memberId] = Set<Date>()
        }

        for commitment in existingCommitments {
            guard let cStart = commitment.startDate else { continue }
            let cEnd = commitment.endDate ?? cStart

            // Get member IDs from this commitment via protocol
            let commitmentMemberIds = commitment.schedulingTeamMemberIds

            // Mark booked days for overlapping members
            let overlappingMembers = memberIds.intersection(commitmentMemberIds)
            guard !overlappingMembers.isEmpty else { continue }

            var day = calendar.startOfDay(for: cStart)
            let endDay = calendar.startOfDay(for: cEnd)
            while day <= endDay {
                for memberId in overlappingMembers {
                    bookedDays[memberId, default: Set()].insert(day)
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
        }

        // Scan forward from startDate to find contiguous block where ALL members are free
        var candidateStart = calendar.startOfDay(for: startDate)

        // Safety limit: don't scan more than 365 days ahead
        let maxScanDays = 365
        var scannedDays = 0

        while scannedDays < maxScanDays {
            if constraints.skipWeekends {
                candidateStart = Self.skipToWeekday(date: candidateStart, calendar: calendar)
            }

            // Check if contiguous block of `duration` days is free for all members
            var blockIsFree = true
            for dayOffset in 0..<duration {
                var checkDay = calendar.date(byAdding: .day, value: dayOffset, to: candidateStart) ?? candidateStart
                if constraints.skipWeekends {
                    // Count only weekdays for duration
                    var weekdayCount = 0
                    var scanDay = candidateStart
                    while weekdayCount < dayOffset {
                        scanDay = calendar.date(byAdding: .day, value: 1, to: scanDay) ?? scanDay
                        if !calendar.isDateInWeekend(scanDay) {
                            weekdayCount += 1
                        }
                    }
                    checkDay = scanDay
                }
                let checkDayStart = calendar.startOfDay(for: checkDay)

                for memberId in memberIds {
                    if bookedDays[memberId]?.contains(checkDayStart) == true {
                        blockIsFree = false
                        break
                    }
                }
                if !blockIsFree { break }
            }

            if blockIsFree {
                return candidateStart
            }

            // Advance one day
            candidateStart = calendar.date(byAdding: .day, value: 1, to: candidateStart) ?? candidateStart
            scannedDays += 1
        }

        // Fallback: if no slot found in 365 days, return the start date
        return calendar.startOfDay(for: startDate)
    }

    // MARK: - Pass 3: Geographic Grouping

    private static func findGeographicAlternative(
        task: any SchedulableTask,
        teamMemberIds: Set<String>,
        primaryStart: Date,
        duration: Int,
        existingCommitments: [any SchedulableTask],
        constraints: ScheduleConstraints,
        provider: ScheduleDataProvider,
        calendar: Calendar
    ) -> AlternativePlacement? {
        // Get this task's project coordinates
        let projectId = task.schedulingProjectId
        guard !projectId.isEmpty else { return nil }

        guard let coords = provider.coordinatesForProject(projectId) else { return nil }

        // Scan existing commitments for same-crew tasks at nearby projects
        var nearbyFutureTasks: [(date: Date, projectId: String, distance: Double)] = []

        for commitment in existingCommitments {
            guard let cStart = commitment.startDate, cStart > primaryStart else { continue }

            let commitProjectId = commitment.schedulingProjectId
            guard !commitProjectId.isEmpty else { continue }

            // Skip same project (that's gap minimization, not geographic grouping)
            if commitProjectId == projectId { continue }

            guard let otherCoords = provider.coordinatesForProject(commitProjectId) else { continue }

            let distance = HaversineDistance.km(
                lat1: coords.lat, lon1: coords.lng,
                lat2: otherCoords.lat, lon2: otherCoords.lng
            )

            if distance <= constraints.proximityRadiusKm {
                nearbyFutureTasks.append((cStart, commitProjectId, distance))
            }
        }

        guard !nearbyFutureTasks.isEmpty else { return nil }

        // Find the best grouping cluster — the date window with most nearby tasks
        // Group by week to find concentration
        let grouped = Dictionary(grouping: nearbyFutureTasks) { task in
            calendar.component(.weekOfYear, from: task.date)
        }

        guard let bestWeek = grouped.max(by: { $0.value.count < $1.value.count }),
              bestWeek.value.count >= 1 else { return nil }

        // Target date: day before the first nearby task in that cluster
        guard let clusterStart = bestWeek.value.map({ $0.date }).min() else { return nil }
        let targetDate = calendar.date(byAdding: .day, value: -1, to: clusterStart) ?? clusterStart

        // Only suggest if it's actually later than primary (deferral, not advancement)
        guard targetDate > primaryStart else { return nil }

        // Verify team availability at the alternative date
        let altSlot = findAvailableSlot(
            memberIds: teamMemberIds,
            duration: duration,
            from: targetDate,
            existingCommitments: existingCommitments,
            constraints: constraints,
            calendar: calendar
        )

        let deferralDays = calendar.dateComponents([.day], from: primaryStart, to: altSlot).day ?? 0
        guard deferralDays > 0 else { return nil }

        let altEnd = calendar.date(byAdding: .day, value: max(duration - 1, 0), to: altSlot) ?? altSlot
        let avgDistance = bestWeek.value.map { $0.distance }.reduce(0, +) / Double(bestWeek.value.count)

        return AlternativePlacement(
            startDate: altSlot,
            endDate: altEnd,
            startTime: nil,
            endTime: nil,
            reason: .geographicGrouping,
            deferralDays: deferralDays,
            nearbyTaskCount: bestWeek.value.count,
            estimatedDistanceSavedKm: avgDistance * Double(bestWeek.value.count),
            benefitingCrewMemberIds: teamMemberIds
        )
    }

    // MARK: - Pass 4: Gap Calculation

    private static func calculateTotalGapDays(placements: [TaskPlacement], calendar: Calendar) -> Int {
        guard placements.count > 1 else { return 0 }

        let sorted = placements.sorted { $0.startDate < $1.startDate }
        var totalGap = 0

        for i in 1..<sorted.count {
            let prevEnd = sorted[i - 1].endDate
            let nextStart = sorted[i].startDate
            let gap = calendar.dateComponents([.day], from: prevEnd, to: nextStart).day ?? 0
            if gap > 1 { // 1 day gap is normal (end Friday → start Monday)
                totalGap += gap - 1
            }
        }

        return totalGap
    }

    // MARK: - Helpers

    private static func countDownstreamUnscheduled(task: any SchedulableTask, projectTasks: [any SchedulableTask]) -> Int {
        projectTasks.filter { other in
            other.id != task.id &&
            other.startDate == nil &&
            other.effectiveDependencies.contains { $0.dependsOnTaskTypeId == task.taskTypeId }
        }.count
    }

    private static func skipToWeekday(date: Date, calendar: Calendar) -> Date {
        var result = date
        while calendar.isDateInWeekend(result) {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
        }
        return result
    }
}

// MARK: - VirtualTask

/// Lightweight task representing an already-placed batch task.
/// Used during batch scheduling so later tasks see earlier placements as commitments.
private struct VirtualTask: SchedulableTask {
    let id: String
    let taskTypeId: String
    let startDate: Date?
    let endDate: Date?
    let duration: Int
    let effectiveDependencies: [TaskTypeDependency]
    let displayOrder: Int
    let schedulingTeamMemberIds: Set<String>
    let schedulingProjectId: String
}
