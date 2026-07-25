//
//  TaskTypeMutationSync.swift
//  OPS
//
//  Durable, idempotent commands for task-type reassignment and merge.
//  Each command maps to one all-or-nothing Postgres transaction.
//

import Foundation
import Supabase
import SwiftData

enum TaskTypeMutationSync {
    static let entityType = "taskTypeMutation"
    static let reassignOperationType = "reassign"
    static let mergeOperationType = "merge"
    static let protectionOperationType = "taskTypeMutationGuard"
    static let taskTemplateEntityType = "taskTemplate"

    static let sourceTaskTypeIdKey = "source_task_type_id"
    static let targetTaskTypeIdKey = "target_task_type_id"
    static let taskIdsKey = "task_ids"
    static let idempotencyKey = "idempotency_key"

    static let reassignmentPayloadKeys = [
        sourceTaskTypeIdKey,
        targetTaskTypeIdKey,
        taskIdsKey,
        idempotencyKey,
    ]

    static let mergePayloadKeys = [
        sourceTaskTypeIdKey,
        targetTaskTypeIdKey,
        idempotencyKey,
    ]

    private static let unresolvedStatuses = Set([
        "pending",
        "inProgress",
        "failed",
        "parked",
    ])

    struct RollbackValue: Codable, Equatable {
        let value: String?

        static func string(_ value: String) -> Self {
            Self(value: value)
        }

        static func optionalString(_ value: String?) -> Self {
            Self(value: value)
        }

        static func boolean(_ value: Bool) -> Self {
            Self(value: value ? "true" : "false")
        }

        static func date(_ value: Date?) -> Self {
            Self(
                value: value.map {
                    String($0.timeIntervalSince1970)
                }
            )
        }
    }

    struct ProtectionChange {
        let entityType: String
        let entityId: String
        let changedFields: [String]
        let previousValues: [String: RollbackValue]
    }

    struct RejectionRollbackResult: Equatable {
        let restoredCommandIds: [String]
        let restoredEntityCount: Int
        let reminderStateChanged: Bool

        static let none = Self(
            restoredCommandIds: [],
            restoredEntityCount: 0,
            reminderStateChanged: false
        )

        var didRollback: Bool {
            !restoredCommandIds.isEmpty
        }
    }

    struct DiscardPlan {
        let commandIds: Set<UUID>
        let operationIds: Set<UUID>
        let restoresDirectDelete: Bool
    }

    enum RollbackError: LocalizedError {
        case missingSnapshot(entityType: String, entityId: String)
        case missingEntity(entityType: String, entityId: String)
        case invalidSnapshotValue(field: String, value: String?)

        var errorDescription: String? {
            switch self {
            case .missingSnapshot(let entityType, let entityId):
                return "Missing rollback snapshot for \(entityType) \(entityId)."
            case .missingEntity(let entityType, let entityId):
                return "Missing rollback entity \(entityType) \(entityId)."
            case .invalidSnapshotValue(let field, let value):
                return "Invalid rollback value for \(field): \(value ?? "null")."
            }
        }
    }

    struct ProtectedEntity: Hashable {
        let entityType: String
        let entityId: String

        init(entityType: String, entityId: String) {
            self.entityType = entityType
            self.entityId = entityId.lowercased()
        }
    }

    static func makeReassignmentOperation(
        sourceTaskTypeId: String,
        targetTaskTypeId: String,
        taskIds: [String],
        commandId: UUID
    ) throws -> SyncOperation {
        try makeOperation(
            operationType: reassignOperationType,
            payload: [
                sourceTaskTypeIdKey: sourceTaskTypeId.lowercased(),
                targetTaskTypeIdKey: targetTaskTypeId.lowercased(),
                taskIdsKey: taskIds.map { $0.lowercased() },
                idempotencyKey: commandId.uuidString.lowercased(),
            ],
            payloadKeys: reassignmentPayloadKeys,
            commandId: commandId
        )
    }

    static func makeMergeOperation(
        sourceTaskTypeId: String,
        targetTaskTypeId: String,
        commandId: UUID
    ) throws -> SyncOperation {
        try makeOperation(
            operationType: mergeOperationType,
            payload: [
                sourceTaskTypeIdKey: sourceTaskTypeId.lowercased(),
                targetTaskTypeIdKey: targetTaskTypeId.lowercased(),
                idempotencyKey: commandId.uuidString.lowercased(),
            ],
            payloadKeys: mergePayloadKeys,
            commandId: commandId
        )
    }

    static func makeProtectionOperations(
        for command: SyncOperation,
        changes: [ProtectionChange]
    ) throws -> [SyncOperation] {
        var fieldsByKey: [ProtectedEntity: Set<String>] = [:]
        var previousValuesByKey:
            [ProtectedEntity: [String: RollbackValue]] = [:]
        for entry in changes {
            let key = ProtectedEntity(
                entityType: entry.entityType,
                entityId: entry.entityId
            )
            fieldsByKey[key, default: []].formUnion(entry.changedFields)
            for (field, value) in entry.previousValues
            where previousValuesByKey[key]?[field] == nil {
                previousValuesByKey[key, default: [:]][field] = value
            }
        }

        return try fieldsByKey
            .sorted { lhs, rhs in
                if lhs.key.entityType != rhs.key.entityType {
                    return lhs.key.entityType < rhs.key.entityType
                }
                return lhs.key.entityId < rhs.key.entityId
            }
            .map { key, fields in
                let previousValues = try JSONEncoder().encode(
                    previousValuesByKey[key] ?? [:]
                )
                return SyncOperation(
                    entityType: key.entityType,
                    entityId: key.entityId,
                    operationType: protectionOperationType,
                    payload: Data("{}".utf8),
                    changedFields: fields.sorted(),
                    previousValues: previousValues,
                    priority: 2,
                    dependsOnId: command.id.uuidString.lowercased()
                )
            }
    }

    static func bypassesGenericCoalescing(
        _ operation: SyncOperation
    ) -> Bool {
        operation.entityType == entityType
            || operation.operationType == protectionOperationType
    }

    static func isReadyForExecution(
        _ operation: SyncOperation,
        in context: ModelContext
    ) throws -> Bool {
        try isReadyForExecution(
            operation,
            in: context.fetch(FetchDescriptor<SyncOperation>())
        )
    }

    static func isReadyForExecution(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) throws -> Bool {
        guard operation.entityType == entityType else { return true }
        guard operation.status == "pending" else { return false }

        let hasEarlierMutation = operations.contains { candidate in
            candidate.id != operation.id
                && candidate.entityType == entityType
                && mutationBlocksOrdering(candidate, in: operations)
                && isEarlier(candidate, than: operation)
        }
        guard !hasEarlierMutation else { return false }

        let commandId = operation.id.uuidString.lowercased()
        let protectedEntities = Set(
            operations.compactMap { candidate -> ProtectedEntity? in
                guard candidate.operationType == protectionOperationType,
                      candidate.dependsOnId?.lowercased() == commandId else {
                    return nil
                }
                return ProtectedEntity(
                    entityType: candidate.entityType,
                    entityId: candidate.entityId
                )
            }
        )

        return !operations.contains { candidate in
            guard candidate.id != operation.id,
                  candidate.operationType != protectionOperationType,
                  unresolvedStatuses.contains(candidate.status),
                  isEarlier(candidate, than: operation) else {
                return false
            }
            return protectedEntities.contains(
                ProtectedEntity(
                    entityType: candidate.entityType,
                    entityId: candidate.entityId
                )
            )
        }
    }

    static func isBlockedByUnresolvedMutation(
        _ operation: SyncOperation,
        in context: ModelContext
    ) throws -> Bool {
        try isBlockedByUnresolvedMutation(
            operation,
            in: context.fetch(FetchDescriptor<SyncOperation>())
        )
    }

    static func isBlockedByUnresolvedMutation(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> Bool {
        guard operation.entityType != entityType,
              operation.operationType != protectionOperationType else {
            return false
        }

        let operationEntity = ProtectedEntity(
            entityType: operation.entityType,
            entityId: operation.entityId
        )
        let operationsById = Dictionary(
            uniqueKeysWithValues: operations.map {
                ($0.id.uuidString.lowercased(), $0)
            }
        )

        return operations.contains { guardOperation in
            guard guardOperation.operationType == protectionOperationType,
                  unresolvedStatuses.contains(guardOperation.status),
                  ProtectedEntity(
                      entityType: guardOperation.entityType,
                      entityId: guardOperation.entityId
                  ) == operationEntity,
                  let dependencyId =
                      guardOperation.dependsOnId?.lowercased(),
                  let command = operationsById[dependencyId],
                  command.entityType == entityType,
                  unresolvedStatuses.contains(command.status) else {
                return false
            }
            return isEarlier(command, than: operation)
        }
    }

    static func readyPendingPipelineOperationIds(
        in operations: [SyncOperation],
        now: Date = Date()
    ) -> Set<UUID> {
        let operationsById = Dictionary(
            uniqueKeysWithValues: operations.map {
                ($0.id.uuidString.lowercased(), $0)
            }
        )
        let guards = operations.filter {
            $0.operationType == protectionOperationType
        }

        return Set(operations.compactMap { operation -> UUID? in
            guard operation.status == "pending",
                  operation.operationType != protectionOperationType else {
                return nil
            }
            if operation.retryCount > 0,
               let lastAttemptedAt = operation.lastAttemptedAt,
               now < lastAttemptedAt.addingTimeInterval(
                   operation.backoffDelay
               ) {
                return nil
            }
            if let dependencyId = operation.dependsOnId?.lowercased(),
               !dependencyId.isEmpty,
               operationsById[dependencyId]?.status != "completed" {
                return nil
            }

            if operation.entityType == entityType {
                return ((try? isReadyForExecution(
                    operation,
                    in: operations
                )) == true) ? operation.id : nil
            }

            let operationEntity = ProtectedEntity(
                entityType: operation.entityType,
                entityId: operation.entityId
            )
            let followsTaskTypeMutation = guards.contains { guardOperation in
                guard ProtectedEntity(
                    entityType: guardOperation.entityType,
                    entityId: guardOperation.entityId
                ) == operationEntity,
                let commandId =
                    guardOperation.dependsOnId?.lowercased(),
                let command = operationsById[commandId],
                command.entityType == entityType else {
                    return false
                }
                return isEarlier(command, than: operation)
            }
            guard followsTaskTypeMutation,
                  !isBlockedByUnresolvedMutation(
                      operation,
                      in: operations
                  ) else {
                return nil
            }
            return operation.id
        })
    }

    static func discardPlanIfHandled(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> DiscardPlan? {
        if operation.entityType == SyncEntityType.taskType.rawValue,
           operation.operationType == "delete" {
            return DiscardPlan(
                commandIds: [operation.id],
                operationIds: [operation.id],
                restoresDirectDelete: true
            )
        }
        guard operation.entityType == entityType else { return nil }

        let guardsByCommand = Dictionary(
            grouping: operations.filter {
                $0.operationType == protectionOperationType
                    && $0.dependsOnId != nil
            },
            by: { $0.dependsOnId!.lowercased() }
        )
        let initialId = operation.id.uuidString.lowercased()
        let initialGuards = guardsByCommand[initialId] ?? []
        var selectedCommands = [operation]
        var selectedIds = Set([initialId])
        var affectedEntities = Set(
            initialGuards.map {
                ProtectedEntity(
                    entityType: $0.entityType,
                    entityId: $0.entityId
                )
            }
        )

        var didExpand: Bool
        repeat {
            didExpand = false
            for candidate in operations where
                candidate.entityType == entityType
                    && candidate.id != operation.id
                    && unresolvedStatuses.contains(candidate.status)
                    && isEarlier(operation, than: candidate)
            {
                let candidateId =
                    candidate.id.uuidString.lowercased()
                guard !selectedIds.contains(candidateId),
                      let candidateGuards =
                        guardsByCommand[candidateId] else {
                    continue
                }
                let candidateEntities = Set(
                    candidateGuards.map {
                        ProtectedEntity(
                            entityType: $0.entityType,
                            entityId: $0.entityId
                        )
                    }
                )
                guard !affectedEntities.isDisjoint(
                    with: candidateEntities
                ) else {
                    continue
                }
                selectedCommands.append(candidate)
                selectedIds.insert(candidateId)
                affectedEntities.formUnion(candidateEntities)
                didExpand = true
            }
        } while didExpand

        let commandIds = Set(selectedCommands.map(\.id))
        let operationIds = Set(
            operations.compactMap { candidate -> UUID? in
                if commandIds.contains(candidate.id) {
                    return candidate.id
                }
                guard candidate.operationType == protectionOperationType,
                      let dependencyId =
                        candidate.dependsOnId?.lowercased(),
                      selectedIds.contains(dependencyId) else {
                    return nil
                }
                return candidate.id
            }
        )
        return DiscardPlan(
            commandIds: commandIds,
            operationIds: operationIds,
            restoresDirectDelete: false
        )
    }

    @discardableResult
    static func prepareForRetryIfHandled(
        _ operation: SyncOperation,
        in context: ModelContext
    ) throws -> Bool {
        guard operation.entityType == entityType else { return false }
        guard operation.status == "failed"
                || operation.status == "parked" else {
            return false
        }

        let commandId = operation.id.uuidString.lowercased()
        let guards = try context.fetch(
            FetchDescriptor<SyncOperation>()
        ).filter {
            $0.operationType == protectionOperationType
                && $0.dependsOnId?.lowercased() == commandId
        }
        let wasRolledBack = !guards.isEmpty
            && guards.allSatisfy { $0.status == "completed" }

        if wasRolledBack {
            for guardOperation in guards {
                guardOperation.previousValues = try currentSnapshot(
                    for: guardOperation,
                    in: context
                )
            }
        }
        for guardOperation in guards {
            guardOperation.status = "pending"
            guardOperation.retryCount = 0
            guardOperation.lastAttemptedAt = nil
            guardOperation.completedAt = nil
            guardOperation.lastError = nil
        }
        operation.status = "pending"
        operation.retryCount = 0
        operation.lastAttemptedAt = nil
        operation.completedAt = nil
        operation.lastError = nil
        return true
    }

    static func claimForExecutionIfHandled(
        _ operation: SyncOperation,
        context: ModelContext,
        refreshFromStore: Bool,
        now: Date = Date()
    ) throws -> Bool? {
        guard operation.entityType == entityType else { return nil }
        if refreshFromStore {
            context.rollback()
        }

        var didClaim = false
        try context.transaction {
            let operationId = operation.id
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate { $0.id == operationId }
            )
            guard let persisted = try context.fetch(descriptor).first,
                  persisted.status == "pending" else {
                return
            }
            let operations = try context.fetch(
                FetchDescriptor<SyncOperation>()
            )
            guard try isReadyForExecution(
                persisted,
                in: operations
            ) else {
                return
            }
            persisted.status = "inProgress"
            persisted.lastAttemptedAt = now
            didClaim = true
        }
        return didClaim
    }

    static func completeProtectionOperations(
        for command: SyncOperation,
        in context: ModelContext,
        completedAt: Date = Date()
    ) throws {
        guard command.entityType == entityType else { return }
        let commandId = command.id.uuidString.lowercased()
        let operations = try context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let guards = operations.filter {
            $0.operationType == protectionOperationType
                && $0.dependsOnId?.lowercased() == commandId
        }
        let templateIds = Set(
            guards
                .filter {
                    $0.entityType
                        == SyncEntityType.taskTypeReminder.rawValue
                }
                .map { $0.entityId.lowercased() }
        )
        let reminderIds = Set(
            guards
                .filter {
                    $0.entityType == SyncEntityType.taskReminder.rawValue
                }
                .map { $0.entityId.lowercased() }
        )
        let taskTemplateIds = Set(
            guards
                .filter {
                    $0.entityType == taskTemplateEntityType
                }
                .map { $0.entityId.lowercased() }
        )

        for guardOperation in guards {
            guardOperation.status = "completed"
            guardOperation.completedAt = completedAt
            guardOperation.lastError = nil
        }

        if !templateIds.isEmpty {
            for template in try context.fetch(
                FetchDescriptor<TaskTypeReminder>()
            ) where templateIds.contains(template.id.lowercased()) {
                template.needsSync = false
            }
        }
        if !reminderIds.isEmpty {
            for reminder in try context.fetch(
                FetchDescriptor<TaskReminder>()
            ) where reminderIds.contains(reminder.id.lowercased()) {
                reminder.needsSync = false
            }
        }
        if !taskTemplateIds.isEmpty {
            for template in try context.fetch(
                FetchDescriptor<TaskTemplate>()
            ) where taskTemplateIds.contains(template.id.lowercased()) {
                template.needsSync = false
            }
        }
    }

    @discardableResult
    static func rollbackRejectedMutation(
        _ rejectedCommand: SyncOperation,
        in context: ModelContext,
        rolledBackAt: Date = Date()
    ) throws -> RejectionRollbackResult {
        guard rejectedCommand.entityType == entityType,
              unresolvedStatuses.contains(rejectedCommand.status),
              rejectedCommand.status != "inProgress" else {
            return .none
        }

        let operations = try context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let guardsByCommand = Dictionary(
            grouping: operations.filter {
                $0.operationType == protectionOperationType
                    && $0.dependsOnId != nil
            },
            by: { $0.dependsOnId!.lowercased() }
        )
        let rejectedId = rejectedCommand.id.uuidString.lowercased()
        guard let rejectedGuards = guardsByCommand[rejectedId],
              !rejectedGuards.isEmpty else {
            return .none
        }

        var selectedCommands = [rejectedCommand]
        var selectedIds = Set([rejectedId])
        var affectedEntities = Set(
            rejectedGuards.map {
                ProtectedEntity(
                    entityType: $0.entityType,
                    entityId: $0.entityId
                )
            }
        )

        var didExpand: Bool
        repeat {
            didExpand = false
            for candidate in operations where
                candidate.entityType == entityType
                    && candidate.id != rejectedCommand.id
                    && unresolvedStatuses.contains(candidate.status)
                    && isEarlier(rejectedCommand, than: candidate)
            {
                let candidateId =
                    candidate.id.uuidString.lowercased()
                guard !selectedIds.contains(candidateId),
                      let candidateGuards =
                        guardsByCommand[candidateId] else {
                    continue
                }
                let candidateEntities = Set(
                    candidateGuards.map {
                        ProtectedEntity(
                            entityType: $0.entityType,
                            entityId: $0.entityId
                        )
                    }
                )
                guard !affectedEntities.isDisjoint(
                    with: candidateEntities
                ) else {
                    continue
                }

                selectedCommands.append(candidate)
                selectedIds.insert(candidateId)
                affectedEntities.formUnion(candidateEntities)
                didExpand = true
            }
        } while didExpand

        let commandsInRollbackOrder = selectedCommands.sorted {
            isEarlier($1, than: $0)
        }
        var restoredEntityCount = 0
        var reminderStateChanged = false

        for command in commandsInRollbackOrder {
            let commandId = command.id.uuidString.lowercased()
            guard let guards = guardsByCommand[commandId],
                  !guards.isEmpty else {
                continue
            }

            for guardOperation in guards
            where guardOperation.status != "completed" {
                try restoreSnapshot(
                    from: guardOperation,
                    in: context
                )
                restoredEntityCount += 1
                if guardOperation.entityType
                    == SyncEntityType.taskReminder.rawValue {
                    reminderStateChanged = true
                }
            }

            if command.id != rejectedCommand.id {
                command.status = "parked"
                command.lastError =
                    "Not sent because an earlier task type change "
                    + "was rejected and rolled back."
                command.lastAttemptedAt = rolledBackAt
            }
            try completeProtectionOperations(
                for: command,
                in: context,
                completedAt: rolledBackAt
            )
        }

        return RejectionRollbackResult(
            restoredCommandIds: commandsInRollbackOrder.map {
                $0.id.uuidString.lowercased()
            },
            restoredEntityCount: restoredEntityCount,
            reminderStateChanged: reminderStateChanged
        )
    }

    @discardableResult
    static func restoreRejectedDirectDelete(
        _ operation: SyncOperation,
        in context: ModelContext
    ) throws -> Bool {
        guard operation.entityType == SyncEntityType.taskType.rawValue,
              operation.operationType == "delete" else {
            return false
        }
        let taskTypeId = operation.entityId.lowercased()
        guard let taskType = try context.fetch(
            FetchDescriptor<TaskType>()
        ).first(where: { $0.id.lowercased() == taskTypeId }) else {
            return false
        }
        taskType.deletedAt = nil
        taskType.needsSync = false
        return true
    }

    @MainActor
    static func executeIfHandled(
        entityType: String,
        operationType: String,
        payload: [String: Any]
    ) async throws -> Bool {
        guard entityType == self.entityType else { return false }

        let sourceTaskTypeId = try requiredString(
            payload,
            key: sourceTaskTypeIdKey
        )
        let targetTaskTypeId = try requiredString(
            payload,
            key: targetTaskTypeIdKey
        )
        let commandId = try requiredString(payload, key: idempotencyKey)

        switch operationType {
        case reassignOperationType:
            guard let taskIds = payload[taskIdsKey] as? [String],
                  !taskIds.isEmpty else {
                throw SyncError.encodingFailed(
                    detail: "task-type reassignment payload has no task ids"
                )
            }

            struct Parameters: Encodable {
                let p_source_task_type_id: String
                let p_target_task_type_id: String
                let p_task_ids: [String]
                let p_idempotency_key: String
            }

            try await SupabaseService.shared.client
                .rpc(
                    "reassign_project_tasks_task_type",
                    params: Parameters(
                        p_source_task_type_id: sourceTaskTypeId,
                        p_target_task_type_id: targetTaskTypeId,
                        p_task_ids: taskIds,
                        p_idempotency_key: commandId
                    )
                )
                .execute()
            return true

        case mergeOperationType:
            struct Parameters: Encodable {
                let p_source_task_type_id: String
                let p_target_task_type_id: String
                let p_idempotency_key: String
            }

            try await SupabaseService.shared.client
                .rpc(
                    "merge_task_type",
                    params: Parameters(
                        p_source_task_type_id: sourceTaskTypeId,
                        p_target_task_type_id: targetTaskTypeId,
                        p_idempotency_key: commandId
                    )
                )
                .execute()
            return true

        default:
            throw SyncError.encodingFailed(
                detail: "unknown task-type mutation operation \(operationType)"
            )
        }
    }

    private static func makeOperation(
        operationType: String,
        payload: [String: Any],
        payloadKeys: [String],
        commandId: UUID
    ) throws -> SyncOperation {
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        return SyncOperation(
            entityType: entityType,
            entityId: commandId.uuidString.lowercased(),
            operationType: operationType,
            payload: data,
            changedFields: payloadKeys,
            priority: 2
        )
    }

    private static func isEarlier(
        _ lhs: SyncOperation,
        than rhs: SyncOperation
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString.lowercased()
            < rhs.id.uuidString.lowercased()
    }

    private static func mutationBlocksOrdering(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> Bool {
        guard unresolvedStatuses.contains(operation.status) else {
            return false
        }
        guard operation.status == "parked" else {
            return true
        }

        let commandId = operation.id.uuidString.lowercased()
        let dependentGuards = operations.filter {
            $0.operationType == protectionOperationType
                && $0.dependsOnId?.lowercased() == commandId
        }
        return dependentGuards.isEmpty
            || dependentGuards.contains { $0.status != "completed" }
    }

    private static func restoreSnapshot(
        from guardOperation: SyncOperation,
        in context: ModelContext
    ) throws {
        guard let data = guardOperation.previousValues else {
            throw RollbackError.missingSnapshot(
                entityType: guardOperation.entityType,
                entityId: guardOperation.entityId
            )
        }
        let values = try JSONDecoder().decode(
            [String: RollbackValue].self,
            from: data
        )
        guard !values.isEmpty else { return }
        let entityId = guardOperation.entityId.lowercased()

        switch guardOperation.entityType {
        case SyncEntityType.projectTask.rawValue:
            guard let task = try context.fetch(
                FetchDescriptor<ProjectTask>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if let value = values["task_type_id"] {
                task.taskTypeId = try requiredString(
                    value,
                    field: "task_type_id"
                )
                let taskTypeId = task.taskTypeId.lowercased()
                task.taskType = try context.fetch(
                    FetchDescriptor<TaskType>()
                ).first(where: {
                    $0.id.lowercased() == taskTypeId
                })
            }
            if let value = values["task_color"] {
                task.taskColor = try requiredString(
                    value,
                    field: "task_color"
                )
            }
            if let value = values["dependency_overrides"] {
                task.dependencyOverridesJSON = value.value
            }
            if let value = values["needsSync"] {
                task.needsSync = try requiredBool(
                    value,
                    field: "needsSync"
                )
            }

        case SyncEntityType.product.rawValue:
            guard let product = try context.fetch(
                FetchDescriptor<Product>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if let value = values["taskTypeId"] {
                product.taskTypeId = value.value
            }
            if let value = values["taskTypeRef"] {
                product.taskTypeRef = value.value
            }

        case taskTemplateEntityType:
            guard let template = try context.fetch(
                FetchDescriptor<TaskTemplate>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if let value = values["taskTypeId"] {
                template.taskTypeId = try requiredString(
                    value,
                    field: "taskTypeId"
                )
            }
            if let value = values["taskTypeRef"] {
                template.taskTypeRef = value.value
            }
            if let value = values["needsSync"] {
                template.needsSync = try requiredBool(
                    value,
                    field: "needsSync"
                )
            }

        case SyncEntityType.taskType.rawValue:
            guard let taskType = try context.fetch(
                FetchDescriptor<TaskType>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if let value = values["deletedAt"] {
                taskType.deletedAt = try optionalDate(
                    value,
                    field: "deletedAt"
                )
            }
            if let value = values["dependenciesJSON"] {
                taskType.dependenciesJSON = try requiredString(
                    value,
                    field: "dependenciesJSON"
                )
            }
            if let value = values["needsSync"] {
                taskType.needsSync = try requiredBool(
                    value,
                    field: "needsSync"
                )
            }

        case SyncEntityType.taskTypeReminder.rawValue:
            guard let template = try context.fetch(
                FetchDescriptor<TaskTypeReminder>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if let value = values["deletedAt"] {
                template.deletedAt = try optionalDate(
                    value,
                    field: "deletedAt"
                )
            }
            if let value = values["needsSync"] {
                template.needsSync = try requiredBool(
                    value,
                    field: "needsSync"
                )
            }

        case SyncEntityType.taskReminder.rawValue:
            guard let reminder = try context.fetch(
                FetchDescriptor<TaskReminder>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if let value = values["deletedAt"] {
                reminder.deletedAt = try optionalDate(
                    value,
                    field: "deletedAt"
                )
            }
            if let value = values["needsSync"] {
                reminder.needsSync = try requiredBool(
                    value,
                    field: "needsSync"
                )
            }

        default:
            throw RollbackError.missingEntity(
                entityType: guardOperation.entityType,
                entityId: entityId
            )
        }
    }

    private static func currentSnapshot(
        for guardOperation: SyncOperation,
        in context: ModelContext
    ) throws -> Data {
        guard let previousValues = guardOperation.previousValues else {
            throw RollbackError.missingSnapshot(
                entityType: guardOperation.entityType,
                entityId: guardOperation.entityId
            )
        }
        let existingValues = try JSONDecoder().decode(
            [String: RollbackValue].self,
            from: previousValues
        )
        let fields = Set(existingValues.keys)
        guard !fields.isEmpty else {
            return try JSONEncoder().encode(
                [String: RollbackValue]()
            )
        }
        let entityId = guardOperation.entityId.lowercased()
        var values: [String: RollbackValue] = [:]

        switch guardOperation.entityType {
        case SyncEntityType.projectTask.rawValue:
            guard let task = try context.fetch(
                FetchDescriptor<ProjectTask>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if fields.contains("task_type_id") {
                values["task_type_id"] = .string(task.taskTypeId)
            }
            if fields.contains("task_color") {
                values["task_color"] = .string(task.taskColor)
            }
            if fields.contains("dependency_overrides") {
                values["dependency_overrides"] = .optionalString(
                    task.dependencyOverridesJSON
                )
            }
            if fields.contains("needsSync") {
                values["needsSync"] = .boolean(task.needsSync)
            }

        case SyncEntityType.product.rawValue:
            guard let product = try context.fetch(
                FetchDescriptor<Product>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if fields.contains("taskTypeId") {
                values["taskTypeId"] = .optionalString(
                    product.taskTypeId
                )
            }
            if fields.contains("taskTypeRef") {
                values["taskTypeRef"] = .optionalString(
                    product.taskTypeRef
                )
            }

        case taskTemplateEntityType:
            guard let template = try context.fetch(
                FetchDescriptor<TaskTemplate>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if fields.contains("taskTypeId") {
                values["taskTypeId"] = .string(template.taskTypeId)
            }
            if fields.contains("taskTypeRef") {
                values["taskTypeRef"] = .optionalString(
                    template.taskTypeRef
                )
            }
            if fields.contains("needsSync") {
                values["needsSync"] = .boolean(template.needsSync)
            }

        case SyncEntityType.taskType.rawValue:
            guard let taskType = try context.fetch(
                FetchDescriptor<TaskType>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if fields.contains("deletedAt") {
                values["deletedAt"] = .date(taskType.deletedAt)
            }
            if fields.contains("dependenciesJSON") {
                values["dependenciesJSON"] = .string(
                    taskType.dependenciesJSON
                )
            }
            if fields.contains("needsSync") {
                values["needsSync"] = .boolean(taskType.needsSync)
            }

        case SyncEntityType.taskTypeReminder.rawValue:
            guard let template = try context.fetch(
                FetchDescriptor<TaskTypeReminder>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if fields.contains("deletedAt") {
                values["deletedAt"] = .date(template.deletedAt)
            }
            if fields.contains("needsSync") {
                values["needsSync"] = .boolean(template.needsSync)
            }

        case SyncEntityType.taskReminder.rawValue:
            guard let reminder = try context.fetch(
                FetchDescriptor<TaskReminder>()
            ).first(where: { $0.id.lowercased() == entityId }) else {
                throw RollbackError.missingEntity(
                    entityType: guardOperation.entityType,
                    entityId: entityId
                )
            }
            if fields.contains("deletedAt") {
                values["deletedAt"] = .date(reminder.deletedAt)
            }
            if fields.contains("needsSync") {
                values["needsSync"] = .boolean(reminder.needsSync)
            }

        default:
            throw RollbackError.missingEntity(
                entityType: guardOperation.entityType,
                entityId: entityId
            )
        }
        return try JSONEncoder().encode(values)
    }

    private static func requiredString(
        _ value: RollbackValue,
        field: String
    ) throws -> String {
        guard let string = value.value else {
            throw RollbackError.invalidSnapshotValue(
                field: field,
                value: nil
            )
        }
        return string
    }

    private static func requiredBool(
        _ value: RollbackValue,
        field: String
    ) throws -> Bool {
        switch value.value {
        case "true":
            return true
        case "false":
            return false
        default:
            throw RollbackError.invalidSnapshotValue(
                field: field,
                value: value.value
            )
        }
    }

    private static func optionalDate(
        _ value: RollbackValue,
        field: String
    ) throws -> Date? {
        guard let rawValue = value.value else {
            return nil
        }
        guard let timestamp = TimeInterval(rawValue) else {
            throw RollbackError.invalidSnapshotValue(
                field: field,
                value: rawValue
            )
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func requiredString(
        _ payload: [String: Any],
        key: String
    ) throws -> String {
        guard let value = payload[key] as? String, !value.isEmpty else {
            throw SyncError.encodingFailed(
                detail: "task-type mutation payload is missing \(key)"
            )
        }
        return value
    }
}
