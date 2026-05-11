//
//  TaskPairSpawner.swift
//  OPS
//
//  When a task of type A is created, scans all task types B whose dependencies
//  reference A with auto_create=true and spawns a paired task of each type B
//  on the same project. The spawned task:
//    • is linked back via `paired_from_task_id`
//    • inherits crew from predecessor (or falls back to type's defaults)
//    • is auto-scheduled per the dependency's earliestStart() if predecessor has dates
//
//  Spawn is invoked from outbound creation paths only (DataController.createTask).
//  Inbound sync MUST NOT trigger spawning — the other client already spawned and
//  the paired task arrives via normal sync.
//

import Foundation
import SwiftData

struct TaskPairSpawner {

    struct SpawnResult {
        let spawned: [ProjectTask]
        /// Spawned tasks paired with the dependency config that triggered them,
        /// so the caller can include rule context in sync payloads or notifications.
        let configs: [(task: ProjectTask, config: TaskTypeDependency, dependentType: TaskType)]
    }

    /// Find every task type whose dependencies declare auto-create against
    /// `predecessor.taskTypeId`, then spawn a paired task for each.
    ///
    /// - Parameters:
    ///   - predecessor: The task that was just created.
    ///   - context: Active SwiftData model context.
    ///   - companyId: Company scope for queries.
    /// - Returns: SpawnResult with the newly inserted tasks plus the configs
    ///   that triggered them. Empty when nothing matched or all candidates were
    ///   skipped (duplicate / cycle / missing data).
    @MainActor
    static func spawnPairs(
        forPredecessor predecessor: ProjectTask,
        in context: ModelContext,
        companyId: String
    ) -> SpawnResult {
        guard !predecessor.taskTypeId.isEmpty else {
            return SpawnResult(spawned: [], configs: [])
        }

        // 1. Fetch all non-deleted task types for the company.
        let typeDescriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { tt in
                tt.companyId == companyId && tt.deletedAt == nil
            }
        )
        let allTypes = (try? context.fetch(typeDescriptor)) ?? []
        guard !allTypes.isEmpty else { return SpawnResult(spawned: [], configs: []) }

        // 2. Filter to candidates: types whose dependencies contain an entry
        //    with dependsOnTaskTypeId == predecessor.taskTypeId AND autoCreate.
        let predecessorTypeId = predecessor.taskTypeId
        var candidates: [(type: TaskType, config: TaskTypeDependency)] = []
        for tt in allTypes {
            // Don't spawn a task of the same type as the predecessor — that
            // would create infinite recursion if someone misconfigured it.
            if tt.id == predecessorTypeId { continue }

            for dep in tt.dependencies where dep.autoCreate && dep.dependsOnTaskTypeId == predecessorTypeId {
                candidates.append((tt, dep))
                break  // Only one config per type counts; first match wins.
            }
        }
        guard !candidates.isEmpty else { return SpawnResult(spawned: [], configs: []) }

        // 3. Pre-fetch all tasks already on this project so we can check
        //    idempotency (don't double-spawn for the same predecessor).
        let projectId = predecessor.projectId
        let projectTasksDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { t in
                t.projectId == projectId && t.deletedAt == nil
            }
        )
        let projectTasks = (try? context.fetch(projectTasksDescriptor)) ?? []

        // 4. Cycle-prevention reference. SchedulingEngine.wouldCreateCycle
        //    operates on (id, dependencies) tuples — build that list once.
        let typeRefs: [(id: String, dependencies: [TaskTypeDependency])] =
            allTypes.map { ($0.id, $0.dependencies) }

        var spawned: [ProjectTask] = []
        var configRefs: [(task: ProjectTask, config: TaskTypeDependency, dependentType: TaskType)] = []

        for (dependentType, depConfig) in candidates {
            // Idempotency: if a task on this project is already paired from
            // this exact predecessor for this dependent type, skip.
            let predecessorId = predecessor.id
            let dependentTypeId = dependentType.id
            let duplicateExists = projectTasks.contains { t in
                t.pairedFromTaskId == predecessorId && t.taskTypeId == dependentTypeId
            }
            if duplicateExists { continue }

            // Cycle prevention. Adding `dependentType → predecessor` is already
            // implied by `depConfig.dependsOnTaskTypeId == predecessorTypeId`,
            // but verify the existing graph won't loop back.
            if SchedulingEngine.wouldCreateCycle(
                taskTypeId: dependentType.id,
                newDependsOnId: predecessorTypeId,
                allTaskTypes: typeRefs
            ) {
                continue
            }

            // Crew: inherit from predecessor if requested and non-empty,
            // else fall back to the dependent type's default crew.
            let predecessorCrew = predecessor.getTeamMemberIds()
            let typeDefaultCrew = dependentType.defaultTeamMemberIdsString.isEmpty
                ? []
                : dependentType.defaultTeamMemberIdsString.components(separatedBy: ",")
            let crew = (depConfig.inheritCrew && !predecessorCrew.isEmpty)
                ? predecessorCrew
                : typeDefaultCrew

            // Dates: only compute if predecessor has dates. Use the dependent
            // type's defaultDuration for the spawn's duration.
            let spawnDuration = max(dependentType.defaultDuration, 1)
            var spawnStart: Date? = nil
            var spawnEnd: Date? = nil
            if let predStart = predecessor.startDate {
                let predDuration = max(predecessor.duration, 1)
                let start = depConfig.earliestStart(
                    predecessorStart: predStart,
                    predecessorDuration: predDuration
                )
                spawnStart = start
                spawnEnd = Calendar.current.date(byAdding: .day, value: max(spawnDuration - 1, 0), to: start)
            }

            // Build the spawn.
            let newId = UUID().uuidString.lowercased()
            let spawn = ProjectTask(
                id: newId,
                projectId: predecessor.projectId,
                taskTypeId: dependentType.id,
                companyId: companyId,
                status: .active,
                taskColor: dependentType.color.isEmpty ? "#59779F" : dependentType.color
            )
            spawn.startDate = spawnStart
            spawn.endDate = spawnEnd
            spawn.duration = spawnStart == nil ? spawnDuration : spawnDuration
            spawn.pairedFromTaskId = predecessor.id
            spawn.scheduleLocked = false
            spawn.setTeamMemberIds(crew)
            spawn.needsSync = true
            spawn.createdAt = Date()

            // Wire the relationship eagerly so cascades and project rollups
            // pick up the spawn without waiting for SwiftData to re-resolve.
            spawn.project = predecessor.project
            spawn.taskType = dependentType

            context.insert(spawn)

            spawned.append(spawn)
            configRefs.append((spawn, depConfig, dependentType))
        }

        if !spawned.isEmpty {
            try? context.save()
        }

        return SpawnResult(spawned: spawned, configs: configRefs)
    }
}
