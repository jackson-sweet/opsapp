//
//  TaskTypeManagement.swift
//  OPS
//
//  Invariant-safe local task-type mutations. The same SwiftData transaction
//  that updates the visible cache appends one durable server command.
//

import Foundation
import SwiftData

struct TaskTypeReassignmentResult: Equatable {
    let movedTaskIds: [String]
    let commandId: UUID
}

enum TaskTypeReassignmentError: Error, Equatable, LocalizedError {
    case modelContextUnavailable
    case noTasksSelected
    case sourceNotFound
    case targetNotFound
    case sameTaskType
    case sourceDeleted
    case targetDeleted
    case defaultTypeProtected
    case companyMismatch
    case taskNotFound(String)
    case taskDeleted(String)
    case taskCompanyMismatch(String)
    case taskNoLongerUsesSource(String)

    var errorDescription: String? {
        switch self {
        case .modelContextUnavailable:
            return "Task types aren’t ready. Try again."
        case .noTasksSelected:
            return "Select at least one task."
        case .sourceNotFound:
            return "The source task type is no longer available."
        case .targetNotFound:
            return "The destination task type is no longer available."
        case .sameTaskType:
            return "Choose a different task type."
        case .sourceDeleted:
            return "The source task type was already deleted."
        case .targetDeleted:
            return "The destination task type was deleted."
        case .defaultTypeProtected:
            return "Default task types can’t be merged or deleted."
        case .companyMismatch:
            return "These task types belong to different companies."
        case .taskNotFound:
            return "One selected task is no longer available."
        case .taskDeleted:
            return "One selected task was already deleted."
        case .taskCompanyMismatch:
            return "One selected task belongs to another company."
        case .taskNoLongerUsesSource:
            return "One selected task changed. Refresh and try again."
        }
    }
}

enum TaskTypeDeletionError: Error, Equatable, LocalizedError {
    case modelContextUnavailable
    case notFound
    case defaultTypeProtected
    case stillInUse(activeTaskCount: Int)
    case referencedByConfiguration(referenceCount: Int)

    var errorDescription: String? {
        switch self {
        case .modelContextUnavailable:
            return "Task types aren’t ready. Try again."
        case .notFound:
            return "This task type is no longer available."
        case .defaultTypeProtected:
            return "Default task types can’t be deleted."
        case .stillInUse(let count):
            return "Reassign \(count) task\(count == 1 ? "" : "s") before deleting this type."
        case .referencedByConfiguration:
            return "This type is still linked to tasks or setup. Merge it instead."
        }
    }
}

extension DataController {
    @MainActor
    func reassignTasks(
        taskIds: [String],
        fromTaskTypeId sourceTaskTypeId: String,
        toTaskTypeId targetTaskTypeId: String
    ) throws -> TaskTypeReassignmentResult {
        guard let context = modelContext else {
            throw TaskTypeReassignmentError.modelContextUnavailable
        }

        let selectedIds = Self.canonicalUniqueIds(taskIds)
        guard !selectedIds.isEmpty else {
            throw TaskTypeReassignmentError.noTasksSelected
        }

        let taskTypes = try context.fetch(FetchDescriptor<TaskType>())
        let sourceId = sourceTaskTypeId.lowercased()
        let targetId = targetTaskTypeId.lowercased()
        guard sourceId != targetId else {
            throw TaskTypeReassignmentError.sameTaskType
        }
        guard let source = taskTypes.first(where: {
            $0.id.lowercased() == sourceId
        }) else {
            throw TaskTypeReassignmentError.sourceNotFound
        }
        guard let target = taskTypes.first(where: {
            $0.id.lowercased() == targetId
        }) else {
            throw TaskTypeReassignmentError.targetNotFound
        }
        guard source.deletedAt == nil else {
            throw TaskTypeReassignmentError.sourceDeleted
        }
        guard target.deletedAt == nil else {
            throw TaskTypeReassignmentError.targetDeleted
        }
        guard source.companyId == target.companyId else {
            throw TaskTypeReassignmentError.companyMismatch
        }

        let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
        let tasksById = Dictionary(
            allTasks.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let selectedTasks = try selectedIds.map { taskId in
            guard let task = tasksById[taskId] else {
                throw TaskTypeReassignmentError.taskNotFound(taskId)
            }
            guard task.deletedAt == nil else {
                throw TaskTypeReassignmentError.taskDeleted(task.id)
            }
            guard task.companyId == source.companyId else {
                throw TaskTypeReassignmentError.taskCompanyMismatch(task.id)
            }
            guard task.taskTypeId.lowercased() == sourceId else {
                throw TaskTypeReassignmentError.taskNoLongerUsesSource(task.id)
            }
            return task
        }

        let commandId = UUID()
        let operation = try TaskTypeMutationSync.makeReassignmentOperation(
            sourceTaskTypeId: source.id,
            targetTaskTypeId: target.id,
            taskIds: selectedTasks.map(\.id),
            commandId: commandId
        )
        let sourceTemplateIds = Set(
            try context.fetch(FetchDescriptor<TaskTypeReminder>())
                .filter {
                    $0.deletedAt == nil
                        && $0.companyId.lowercased()
                            == source.companyId.lowercased()
                        && $0.taskTypeId.lowercased() == sourceId
                }
                .map { $0.id.lowercased() }
        )
        let openTaskIds = Set(
            selectedTasks
                .filter { $0.status == .active }
                .map { $0.id.lowercased() }
        )
        let retiredReminders = try context
            .fetch(FetchDescriptor<TaskReminder>())
            .filter {
                $0.deletedAt == nil
                    && $0.acknowledgedAt == nil
                    && $0.dismissedAt == nil
                    && $0.companyId.lowercased()
                        == source.companyId.lowercased()
                    && openTaskIds.contains($0.taskId.lowercased())
                    && $0.sourceTemplateId.map {
                        sourceTemplateIds.contains($0.lowercased())
                    } == true
            }
        var protectedChanges = selectedTasks.map {
            TaskTypeMutationSync.ProtectionChange(
                entityType: SyncEntityType.projectTask.rawValue,
                entityId: $0.id,
                changedFields: ["task_type_id", "task_color"],
                previousValues: [
                    "task_type_id": .string($0.taskTypeId),
                    "task_color": .string($0.taskColor),
                    "needsSync": .boolean($0.needsSync),
                ]
            )
        }
        protectedChanges.append(
            contentsOf: [source, target].map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType: SyncEntityType.taskType.rawValue,
                    entityId: $0.id,
                    changedFields: [],
                    previousValues: [:]
                )
            }
        )
        protectedChanges.append(
            contentsOf: retiredReminders.map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType: SyncEntityType.taskReminder.rawValue,
                    entityId: $0.id,
                    changedFields: ["deletedAt"],
                    previousValues: [
                        "deletedAt": .date($0.deletedAt),
                        "needsSync": .boolean($0.needsSync),
                    ]
                )
            }
        )
        let protectionOperations = try TaskTypeMutationSync
            .makeProtectionOperations(
                for: operation,
                changes: protectedChanges
            )
        let retirementDate = Date()

        try context.transaction {
            for task in selectedTasks {
                task.taskTypeId = target.id
                task.taskType = target
                task.taskColor = target.color
                task.needsSync = true
            }
            for reminder in retiredReminders {
                reminder.deletedAt = retirementDate
                reminder.needsSync = true
            }
            context.insert(operation)
            for protectionOperation in protectionOperations {
                context.insert(protectionOperation)
            }
        }
        for reminder in retiredReminders {
            NotificationManager.shared.cancelTaskReminder(reminder.id)
        }
        syncEngine.notifyDurableOperationQueued(pullAfterPush: true)

        return TaskTypeReassignmentResult(
            movedTaskIds: selectedTasks.map(\.id),
            commandId: commandId
        )
    }

    @MainActor
    func mergeTaskType(
        sourceTaskTypeId: String,
        intoTaskTypeId targetTaskTypeId: String
    ) throws -> TaskTypeReassignmentResult {
        guard let context = modelContext else {
            throw TaskTypeReassignmentError.modelContextUnavailable
        }

        let sourceId = sourceTaskTypeId.lowercased()
        let targetId = targetTaskTypeId.lowercased()
        guard sourceId != targetId else {
            throw TaskTypeReassignmentError.sameTaskType
        }

        let taskTypes = try context.fetch(FetchDescriptor<TaskType>())
        guard let source = taskTypes.first(where: {
            $0.id.lowercased() == sourceId
        }) else {
            throw TaskTypeReassignmentError.sourceNotFound
        }
        guard let target = taskTypes.first(where: {
            $0.id.lowercased() == targetId
        }) else {
            throw TaskTypeReassignmentError.targetNotFound
        }
        guard source.deletedAt == nil else {
            throw TaskTypeReassignmentError.sourceDeleted
        }
        guard target.deletedAt == nil else {
            throw TaskTypeReassignmentError.targetDeleted
        }
        guard !source.isDefault else {
            throw TaskTypeReassignmentError.defaultTypeProtected
        }
        guard source.companyId == target.companyId else {
            throw TaskTypeReassignmentError.companyMismatch
        }

        let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
        let movedTasks = allTasks
            .filter {
                $0.deletedAt == nil
                    && $0.companyId.lowercased()
                        == source.companyId.lowercased()
                    && $0.taskTypeId.lowercased() == sourceId
            }
        let linkedProducts = try context.fetch(FetchDescriptor<Product>())
            .filter {
            $0.companyId.lowercased() == source.companyId.lowercased()
                && (
                    $0.taskTypeRef?.lowercased() == sourceId
                        || $0.taskTypeId?.lowercased() == sourceId
                )
        }
        let linkedTemplates = try context
            .fetch(FetchDescriptor<TaskTemplate>())
            .filter {
            $0.deletedAt == nil
                && $0.companyId.lowercased()
                    == source.companyId.lowercased()
                && (
                    $0.taskTypeRef?.lowercased() == sourceId
                        || $0.taskTypeId.lowercased() == sourceId
                )
        }
        let affectedDependencyTypes = taskTypes.filter {
            $0.deletedAt == nil
                && $0.companyId.lowercased()
                    == source.companyId.lowercased()
                && $0.id.lowercased() != sourceId
                && $0.dependencies.contains {
                    $0.dependsOnTaskTypeId.lowercased() == sourceId
                }
        }
        let rewrittenTaskOverrides = allTasks.compactMap {
            task -> (task: ProjectTask, dependencies: [TaskTypeDependency])? in
            guard task.deletedAt == nil,
                  task.companyId.lowercased()
                    == source.companyId.lowercased(),
                  let dependencies = Self.explicitDependencies(for: task),
                  dependencies.contains(where: {
                      $0.dependsOnTaskTypeId.lowercased() == sourceId
                  }) else {
                return nil
            }
            let ownerTaskTypeId = task.taskTypeId.lowercased() == sourceId
                ? target.id
                : task.taskTypeId
            return (
                task,
                Self.rewrittenDependencies(
                    dependencies,
                    ownerTaskTypeId: ownerTaskTypeId,
                    sourceTaskTypeId: source.id,
                    targetTaskTypeId: target.id
                )
            )
        }
        let sourceReminderTemplates = try context
            .fetch(FetchDescriptor<TaskTypeReminder>())
            .filter {
                $0.deletedAt == nil
                    && $0.companyId.lowercased()
                        == source.companyId.lowercased()
                    && $0.taskTypeId.lowercased() == sourceId
            }
        let sourceReminderTemplateIds = Set(
            sourceReminderTemplates.map { $0.id.lowercased() }
        )
        let openMovedTaskIds = Set(
            movedTasks
                .filter { $0.status == .active }
                .map { $0.id.lowercased() }
        )
        let retiredReminders = try context
            .fetch(FetchDescriptor<TaskReminder>())
            .filter {
                $0.deletedAt == nil
                    && $0.acknowledgedAt == nil
                    && $0.dismissedAt == nil
                    && $0.companyId.lowercased()
                        == source.companyId.lowercased()
                    && openMovedTaskIds.contains($0.taskId.lowercased())
                    && $0.sourceTemplateId.map {
                        sourceReminderTemplateIds.contains($0.lowercased())
                    } == true
            }

        let commandId = UUID()
        let operation = try TaskTypeMutationSync.makeMergeOperation(
            sourceTaskTypeId: source.id,
            targetTaskTypeId: target.id,
            commandId: commandId
        )
        let deletionDate = Date()
        var protectedChanges = movedTasks.map {
            TaskTypeMutationSync.ProtectionChange(
                entityType: SyncEntityType.projectTask.rawValue,
                entityId: $0.id,
                changedFields: ["task_type_id", "task_color"],
                previousValues: [
                    "task_type_id": .string($0.taskTypeId),
                    "task_color": .string($0.taskColor),
                    "needsSync": .boolean($0.needsSync),
                ]
            )
        }
        protectedChanges.append(
            TaskTypeMutationSync.ProtectionChange(
                entityType: SyncEntityType.taskType.rawValue,
                entityId: target.id,
                changedFields: [],
                previousValues: [:]
            )
        )
        protectedChanges.append(
            contentsOf: rewrittenTaskOverrides.map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType: SyncEntityType.projectTask.rawValue,
                    entityId: $0.task.id,
                    changedFields: ["dependency_overrides"],
                    previousValues: [
                        "dependency_overrides": .optionalString(
                            $0.task.dependencyOverridesJSON
                        ),
                        "needsSync": .boolean($0.task.needsSync),
                    ]
                )
            }
        )
        protectedChanges.append(
            contentsOf: linkedProducts.map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType: SyncEntityType.product.rawValue,
                    entityId: $0.id,
                    changedFields: ["taskTypeId", "taskTypeRef"],
                    previousValues: [
                        "taskTypeId": .optionalString($0.taskTypeId),
                        "taskTypeRef": .optionalString($0.taskTypeRef),
                    ]
                )
            }
        )
        protectedChanges.append(
            contentsOf: linkedTemplates.map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType:
                        TaskTypeMutationSync.taskTemplateEntityType,
                    entityId: $0.id,
                    changedFields: ["taskTypeId", "taskTypeRef"],
                    previousValues: [
                        "taskTypeId": .string($0.taskTypeId),
                        "taskTypeRef": .optionalString($0.taskTypeRef),
                        "needsSync": .boolean($0.needsSync),
                    ]
                )
            }
        )
        protectedChanges.append(
            contentsOf: affectedDependencyTypes.map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType: SyncEntityType.taskType.rawValue,
                    entityId: $0.id,
                    changedFields: ["dependenciesJSON"],
                    previousValues: [
                        "dependenciesJSON": .string(
                            $0.dependenciesJSON
                        ),
                        "needsSync": .boolean($0.needsSync),
                    ]
                )
            }
        )
        protectedChanges.append(
            contentsOf: sourceReminderTemplates.map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType:
                        SyncEntityType.taskTypeReminder.rawValue,
                    entityId: $0.id,
                    changedFields: ["deletedAt"],
                    previousValues: [
                        "deletedAt": .date($0.deletedAt),
                        "needsSync": .boolean($0.needsSync),
                    ]
                )
            }
        )
        protectedChanges.append(
            contentsOf: retiredReminders.map {
                TaskTypeMutationSync.ProtectionChange(
                    entityType: SyncEntityType.taskReminder.rawValue,
                    entityId: $0.id,
                    changedFields: ["deletedAt"],
                    previousValues: [
                        "deletedAt": .date($0.deletedAt),
                        "needsSync": .boolean($0.needsSync),
                    ]
                )
            }
        )
        protectedChanges.append(
            TaskTypeMutationSync.ProtectionChange(
                entityType: SyncEntityType.taskType.rawValue,
                entityId: source.id,
                changedFields: ["deletedAt"],
                previousValues: [
                    "deletedAt": .date(source.deletedAt),
                    "needsSync": .boolean(source.needsSync),
                ]
            )
        )
        let protectionOperations = try TaskTypeMutationSync
            .makeProtectionOperations(
                for: operation,
                changes: protectedChanges
            )

        try context.transaction {
            for task in movedTasks {
                task.taskTypeId = target.id
                task.taskType = target
                task.taskColor = target.color
                task.needsSync = true
            }
            for product in linkedProducts {
                product.taskTypeId = target.id
                product.taskTypeRef = target.id
            }
            for template in linkedTemplates {
                template.taskTypeId = target.id
                template.taskTypeRef = target.id
                template.needsSync = true
            }
            for taskType in affectedDependencyTypes {
                taskType.dependencies = Self.rewrittenDependencies(
                    taskType.dependencies,
                    ownerTaskTypeId: taskType.id,
                    sourceTaskTypeId: source.id,
                    targetTaskTypeId: target.id
                )
                taskType.needsSync = true
            }
            for item in rewrittenTaskOverrides {
                item.task.setDependencyOverrides(item.dependencies)
                item.task.needsSync = true
            }
            for template in sourceReminderTemplates {
                template.deletedAt = deletionDate
                template.needsSync = true
            }
            for reminder in retiredReminders {
                reminder.deletedAt = deletionDate
                reminder.needsSync = true
            }
            source.deletedAt = deletionDate
            source.needsSync = true
            context.insert(operation)
            for protectionOperation in protectionOperations {
                context.insert(protectionOperation)
            }
        }
        for reminder in retiredReminders {
            NotificationManager.shared.cancelTaskReminder(reminder.id)
        }
        syncEngine.notifyDurableOperationQueued(pullAfterPush: true)

        return TaskTypeReassignmentResult(
            movedTaskIds: movedTasks.map(\.id),
            commandId: commandId
        )
    }

    private static func canonicalUniqueIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { rawId in
            let id = rawId.lowercased()
            return seen.insert(id).inserted ? id : nil
        }
    }

    private static func rewrittenDependencies(
        _ dependencies: [TaskTypeDependency],
        ownerTaskTypeId: String,
        sourceTaskTypeId: String,
        targetTaskTypeId: String
    ) -> [TaskTypeDependency] {
        let ownerId = ownerTaskTypeId.lowercased()
        let sourceId = sourceTaskTypeId.lowercased()
        let targetId = targetTaskTypeId.lowercased()
        let alreadyHasTarget = dependencies.contains {
            $0.dependsOnTaskTypeId.lowercased() == targetId
        }
        var seen = Set<String>()

        return dependencies.compactMap { dependency in
            let predecessorId = dependency.dependsOnTaskTypeId.lowercased()
            if predecessorId == sourceId && alreadyHasTarget {
                return nil
            }
            let rewrittenId = predecessorId == sourceId
                ? targetTaskTypeId
                : dependency.dependsOnTaskTypeId
            let canonicalRewrittenId = rewrittenId.lowercased()
            guard canonicalRewrittenId != ownerId,
                  seen.insert(canonicalRewrittenId).inserted else {
                return nil
            }
            guard predecessorId == sourceId else { return dependency }
            return TaskTypeDependency(
                dependsOnTaskTypeId: rewrittenId,
                overlapPercentage: dependency.overlapPercentage,
                overlapMode: dependency.overlapMode,
                overlapConstantDays: dependency.overlapConstantDays,
                autoCreate: dependency.autoCreate,
                inheritCrew: dependency.inheritCrew,
                minGapDaysAfterEnd: dependency.minGapDaysAfterEnd,
                weekdayConstraint: dependency.weekdayConstraint
            )
        }
    }

    private static func explicitDependencies(
        for task: ProjectTask
    ) -> [TaskTypeDependency]? {
        guard let json = task.dependencyOverridesJSON,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(
            [TaskTypeDependency].self,
            from: data
        )
    }
}
