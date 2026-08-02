//
//  TaskTypeManagementTests.swift
//  OPSTests
//
//  Regression coverage for invariant-safe task-type reassignment and deletion.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class TaskTypeManagementTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "feature.useDataActor")
        super.tearDown()
    }

    func testBulkReassignmentUpdatesEveryLocalRepresentationAndQueuesOneAtomicCommand() throws {
        let fixture = try makeFixture()

        let result = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id, fixture.secondTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )

        XCTAssertEqual(Set(result.movedTaskIds), Set([fixture.firstTask.id, fixture.secondTask.id]))
        for task in [fixture.firstTask, fixture.secondTask] {
            XCTAssertEqual(task.taskTypeId, fixture.target.id)
            XCTAssertEqual(task.taskType?.id, fixture.target.id)
            XCTAssertEqual(task.taskColor, fixture.target.color)
            XCTAssertTrue(task.needsSync)
        }
        XCTAssertEqual(fixture.unrelatedTask.taskTypeId, fixture.other.id)
        XCTAssertEqual(fixture.unrelatedTask.taskType?.id, fixture.other.id)

        let operations = try taskTypeMutationOperations(in: fixture.context)
        let operation = try XCTUnwrap(operations.only)
        XCTAssertEqual(operation.entityId, result.commandId.uuidString.lowercased())
        XCTAssertEqual(operation.operationType, TaskTypeMutationSync.reassignOperationType)
        XCTAssertEqual(
            Set(operation.getChangedFields()),
            Set(TaskTypeMutationSync.reassignmentPayloadKeys)
        )

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
        )
        XCTAssertEqual(payload[TaskTypeMutationSync.sourceTaskTypeIdKey] as? String, fixture.source.id)
        XCTAssertEqual(payload[TaskTypeMutationSync.targetTaskTypeIdKey] as? String, fixture.target.id)
        XCTAssertEqual(
            Set(payload[TaskTypeMutationSync.taskIdsKey] as? [String] ?? []),
            Set([fixture.firstTask.id, fixture.secondTask.id])
        )
        XCTAssertEqual(
            payload[TaskTypeMutationSync.idempotencyKey] as? String,
            result.commandId.uuidString.lowercased()
        )
        let guards = try protectionOperations(in: fixture.context)
        XCTAssertEqual(
            Set(guards.map(\.entityId)),
            Set([
                fixture.firstTask.id,
                fixture.secondTask.id,
                fixture.source.id,
                fixture.target.id,
            ])
        )
        let taskGuards = guards.filter {
            $0.entityType == SyncEntityType.projectTask.rawValue
        }
        XCTAssertTrue(taskGuards.allSatisfy {
            $0.operationType == TaskTypeMutationSync.protectionOperationType
                && $0.dependsOnId?.lowercased()
                    == operation.id.uuidString.lowercased()
                && Set($0.getChangedFields())
                    == Set(["task_type_id", "task_color"])
        })
        XCTAssertEqual(
            Set(
                guards
                    .filter {
                        $0.entityType
                            == SyncEntityType.taskType.rawValue
                    }
                    .map(\.entityId)
            ),
            Set([fixture.source.id, fixture.target.id])
        )
        XCTAssertEqual(operation.priority, 2)
    }

    func testBulkReassignmentUsesScalarSourceWhenRelationshipIsMissing() throws {
        let fixture = try makeFixture()
        fixture.firstTask.taskType = nil
        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.source.id)
        try fixture.context.save()

        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )

        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.target.id)
        XCTAssertEqual(fixture.firstTask.taskType?.id, fixture.target.id)
        XCTAssertEqual(fixture.firstTask.taskColor, fixture.target.color)
        XCTAssertTrue(fixture.firstTask.needsSync)
        XCTAssertEqual(try taskTypeMutationOperations(in: fixture.context).count, 1)
    }

    func testBulkReassignmentValidatesEverySelectionBeforeMutatingAnything() throws {
        let fixture = try makeFixture()
        fixture.secondTask.taskTypeId = fixture.other.id
        fixture.secondTask.taskType = fixture.other
        try fixture.context.save()

        XCTAssertThrowsError(
            try fixture.dataController.reassignTasks(
                taskIds: [fixture.firstTask.id, fixture.secondTask.id],
                fromTaskTypeId: fixture.source.id,
                toTaskTypeId: fixture.target.id
            )
        ) { error in
            XCTAssertEqual(
                error as? TaskTypeReassignmentError,
                .taskNoLongerUsesSource(fixture.secondTask.id)
            )
        }

        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.source.id)
        XCTAssertEqual(fixture.firstTask.taskType?.id, fixture.source.id)
        XCTAssertEqual(fixture.firstTask.taskColor, fixture.source.color)
        XCTAssertTrue(try taskTypeMutationOperations(in: fixture.context).isEmpty)
    }

    func testBulkReassignmentRejectsDeletedTaskAndCrossCompanyTarget() throws {
        let fixture = try makeFixture()
        fixture.firstTask.deletedAt = Date()
        let crossCompany = TaskType(
            id: "cross-company",
            display: "Other company",
            color: "#847B77",
            companyId: "company-b"
        )
        fixture.context.insert(crossCompany)
        try fixture.context.save()

        XCTAssertThrowsError(
            try fixture.dataController.reassignTasks(
                taskIds: [fixture.firstTask.id],
                fromTaskTypeId: fixture.source.id,
                toTaskTypeId: fixture.target.id
            )
        ) { error in
            XCTAssertEqual(error as? TaskTypeReassignmentError, .taskDeleted(fixture.firstTask.id))
        }

        XCTAssertThrowsError(
            try fixture.dataController.reassignTasks(
                taskIds: [fixture.secondTask.id],
                fromTaskTypeId: fixture.source.id,
                toTaskTypeId: crossCompany.id
            )
        ) { error in
            XCTAssertEqual(error as? TaskTypeReassignmentError, .companyMismatch)
        }
    }

    func testBulkReassignmentRetiresActionableSourceReminder() throws {
        let fixture = try makeFixture()
        let template = TaskTypeReminder(
            id: "selective-source-template",
            taskTypeId: fixture.source.id,
            companyId: fixture.source.companyId,
            label: "Confirm material"
        )
        let reminder = TaskReminder(
            id: "selective-source-reminder",
            taskId: fixture.firstTask.id,
            companyId: fixture.source.companyId,
            sourceTemplateId: template.id,
            label: template.label,
            leadTimeDays: 1,
            fireTimeLocalSeconds: 9 * 3600,
            requiresAck: false,
            recipientMode: .taskCrew,
            recipientConfig: .empty
        )
        fixture.context.insert(template)
        fixture.context.insert(reminder)
        try fixture.context.save()

        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )

        XCTAssertNil(template.deletedAt)
        XCTAssertNotNil(reminder.deletedAt)
        XCTAssertTrue(reminder.needsSync)
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).contains {
                $0.entityType == SyncEntityType.taskReminder.rawValue
                    && $0.entityId == reminder.id
                    && $0.getChangedFields() == ["deletedAt"]
            }
        )
    }

    func testWholeMergeMovesEveryLocalScalarReferenceAndQueuesOneAtomicCommand() throws {
        let fixture = try makeFixture()
        fixture.firstTask.taskType = nil
        fixture.secondTask.status = .completed
        try fixture.context.save()

        let result = try fixture.dataController.mergeTaskType(
            sourceTaskTypeId: fixture.source.id,
            intoTaskTypeId: fixture.target.id
        )

        XCTAssertEqual(
            Set(result.movedTaskIds),
            Set([fixture.firstTask.id, fixture.secondTask.id])
        )
        for task in [fixture.firstTask, fixture.secondTask] {
            XCTAssertEqual(task.taskTypeId, fixture.target.id)
            XCTAssertEqual(task.taskType?.id, fixture.target.id)
            XCTAssertEqual(task.taskColor, fixture.target.color)
            XCTAssertTrue(task.needsSync)
        }
        XCTAssertNotNil(fixture.source.deletedAt)
        XCTAssertTrue(fixture.source.needsSync)

        let operations = try taskTypeMutationOperations(in: fixture.context)
        let operation = try XCTUnwrap(operations.only)
        XCTAssertEqual(operation.entityId, result.commandId.uuidString.lowercased())
        XCTAssertEqual(operation.operationType, TaskTypeMutationSync.mergeOperationType)
        XCTAssertEqual(
            Set(operation.getChangedFields()),
            Set(TaskTypeMutationSync.mergePayloadKeys)
        )
        XCTAssertEqual(operation.priority, 2)
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).contains {
                $0.entityType == SyncEntityType.taskType.rawValue
                    && $0.entityId == fixture.source.id
                    && $0.getChangedFields().contains("deletedAt")
            }
        )
    }

    func testTaskTypeMutationWaitsForEarlierAffectedWrites() throws {
        let fixture = try makeFixture()
        let pendingCreate = SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: fixture.firstTask.id,
            operationType: "create",
            payload: Data("{}".utf8),
            changedFields: ["task_type_id"]
        )
        fixture.context.insert(pendingCreate)
        let pendingTargetCreate = SyncOperation(
            entityType: SyncEntityType.taskType.rawValue,
            entityId: fixture.target.id,
            operationType: "create",
            payload: Data("{}".utf8),
            changedFields: ["display"]
        )
        fixture.context.insert(pendingTargetCreate)
        try fixture.context.save()

        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )

        let mutation = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context).only
        )
        XCTAssertFalse(
            try TaskTypeMutationSync.isReadyForExecution(
                mutation,
                in: fixture.context
            )
        )

        pendingCreate.status = "completed"
        pendingCreate.completedAt = Date()
        try fixture.context.save()

        XCTAssertFalse(
            try TaskTypeMutationSync.isReadyForExecution(
                mutation,
                in: fixture.context
            )
        )

        pendingTargetCreate.status = "completed"
        pendingTargetCreate.completedAt = Date()
        try fixture.context.save()

        XCTAssertTrue(
            try TaskTypeMutationSync.isReadyForExecution(
                mutation,
                in: fixture.context
            )
        )
    }

    func testLaterAffectedWriteWaitsBehindTaskTypeMutation() throws {
        let fixture = try makeFixture()
        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )
        let mutation = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context).only
        )
        let laterEdit = SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: fixture.firstTask.id,
            operationType: "update",
            payload: Data("{}".utf8),
            changedFields: ["custom_title"]
        )
        fixture.context.insert(laterEdit)
        try fixture.context.save()

        XCTAssertTrue(
            TaskTypeMutationSync.isBlockedByUnresolvedMutation(
                laterEdit,
                in: try fixture.context.fetch(
                    FetchDescriptor<SyncOperation>()
                )
            )
        )

        try fixture.context.transaction {
            mutation.status = "completed"
            mutation.completedAt = Date()
            try TaskTypeMutationSync.completeProtectionOperations(
                for: mutation,
                in: fixture.context
            )
        }

        XCTAssertFalse(
            TaskTypeMutationSync.isBlockedByUnresolvedMutation(
                laterEdit,
                in: try fixture.context.fetch(
                    FetchDescriptor<SyncOperation>()
                )
            )
        )
        XCTAssertTrue(
            TaskTypeMutationSync.readyPendingPipelineOperationIds(
                in: try fixture.context.fetch(
                    FetchDescriptor<SyncOperation>()
                )
            ).contains(laterEdit.id)
        )
    }

    func testWholeMergeRetiresOnlyActionableSourceReminders() throws {
        let fixture = try makeFixture()
        let template = TaskTypeReminder(
            id: "source-reminder-template",
            taskTypeId: fixture.source.id,
            companyId: fixture.source.companyId,
            label: "Order material"
        )
        template.taskType = fixture.source
        let activeReminder = TaskReminder(
            id: "active-source-reminder",
            taskId: fixture.firstTask.id,
            companyId: fixture.source.companyId,
            sourceTemplateId: template.id,
            label: template.label,
            leadTimeDays: 1,
            fireTimeLocalSeconds: 9 * 3600,
            requiresAck: false,
            recipientMode: .taskCrew,
            recipientConfig: .empty
        )
        activeReminder.notifiedAt = Date()
        activeReminder.task = fixture.firstTask
        let historicalReminder = TaskReminder(
            id: "historical-source-reminder",
            taskId: fixture.secondTask.id,
            companyId: fixture.source.companyId,
            sourceTemplateId: template.id,
            label: template.label,
            leadTimeDays: 1,
            fireTimeLocalSeconds: 9 * 3600,
            requiresAck: true,
            recipientMode: .taskCrew,
            recipientConfig: .empty
        )
        historicalReminder.acknowledgedAt = Date()
        historicalReminder.task = fixture.secondTask
        fixture.context.insert(template)
        fixture.context.insert(activeReminder)
        fixture.context.insert(historicalReminder)
        try fixture.context.save()

        _ = try fixture.dataController.mergeTaskType(
            sourceTaskTypeId: fixture.source.id,
            intoTaskTypeId: fixture.target.id
        )

        XCTAssertNotNil(template.deletedAt)
        XCTAssertTrue(template.needsSync)
        XCTAssertNotNil(activeReminder.deletedAt)
        XCTAssertTrue(activeReminder.needsSync)
        XCTAssertNil(historicalReminder.deletedAt)

        let guards = try protectionOperations(in: fixture.context)
        XCTAssertTrue(guards.contains {
            $0.entityType == SyncEntityType.taskTypeReminder.rawValue
                && $0.entityId == template.id
        })
        XCTAssertTrue(guards.contains {
            $0.entityType == SyncEntityType.taskReminder.rawValue
                && $0.entityId == activeReminder.id
        })

        let mutation = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context).only
        )
        try fixture.context.transaction {
            try TaskTypeMutationSync.completeProtectionOperations(
                for: mutation,
                in: fixture.context
            )
        }
        XCTAssertFalse(template.needsSync)
        XCTAssertFalse(activeReminder.needsSync)
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).allSatisfy {
                $0.status == "completed"
            }
        )
    }

    func testWholeMergeRewritesExplicitTaskDependencyOverrides() throws {
        let fixture = try makeFixture()
        fixture.firstTask.setDependencyOverrides([
            TaskTypeDependency(
                dependsOnTaskTypeId: fixture.source.id,
                overlapPercentage: 10
            )
        ])
        fixture.unrelatedTask.setDependencyOverrides([
            TaskTypeDependency(
                dependsOnTaskTypeId: fixture.source.id,
                overlapPercentage: 10
            ),
            TaskTypeDependency(
                dependsOnTaskTypeId: fixture.target.id,
                overlapPercentage: 70
            )
        ])
        try fixture.context.save()

        _ = try fixture.dataController.mergeTaskType(
            sourceTaskTypeId: fixture.source.id,
            intoTaskTypeId: fixture.target.id
        )

        XCTAssertEqual(fixture.firstTask.effectiveDependencies, [])
        XCTAssertEqual(
            fixture.unrelatedTask.effectiveDependencies,
            [
                TaskTypeDependency(
                    dependsOnTaskTypeId: fixture.target.id,
                    overlapPercentage: 70
                )
            ]
        )
        XCTAssertTrue(fixture.unrelatedTask.needsSync)
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).contains {
                $0.entityType == SyncEntityType.projectTask.rawValue
                    && $0.entityId == fixture.unrelatedTask.id
                    && $0.getChangedFields().contains(
                        "dependency_overrides"
                    )
            }
        )
    }

    func testSuccessfulMergeClearsMovedTaskTemplateSyncFlag() throws {
        let fixture = try makeFixture()
        let template = TaskTemplate(
            id: "successful-merge-template",
            companyId: fixture.source.companyId,
            taskTypeId: fixture.source.id,
            title: "Layout"
        )
        fixture.context.insert(template)
        try fixture.context.save()

        _ = try fixture.dataController.mergeTaskType(
            sourceTaskTypeId: fixture.source.id,
            intoTaskTypeId: fixture.target.id
        )
        XCTAssertTrue(template.needsSync)

        let command = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context).only
        )
        try fixture.context.transaction {
            command.status = "completed"
            command.completedAt = Date()
            try TaskTypeMutationSync.completeProtectionOperations(
                for: command,
                in: fixture.context
            )
        }

        XCTAssertFalse(template.needsSync)
    }

    func testPermanentMergeRejectionRestoresProjectionAndReleasesQueue() throws {
        let fixture = try makeFixture()
        fixture.other.dependencies = [
            TaskTypeDependency(
                dependsOnTaskTypeId: fixture.source.id,
                overlapPercentage: 25
            )
        ]
        fixture.unrelatedTask.setDependencyOverrides([
            TaskTypeDependency(
                dependsOnTaskTypeId: fixture.source.id,
                overlapPercentage: 40
            )
        ])
        let originalOverrides =
            fixture.unrelatedTask.dependencyOverridesJSON

        let product = Product(
            id: "rollback-product",
            companyId: fixture.source.companyId,
            name: "Install labor"
        )
        product.taskTypeId = fixture.source.id
        product.taskTypeRef = fixture.source.id

        let taskTemplate = TaskTemplate(
            id: "rollback-task-template",
            companyId: fixture.source.companyId,
            taskTypeId: fixture.source.id,
            title: "Layout"
        )
        let reminderTemplate = TaskTypeReminder(
            id: "rollback-reminder-template",
            taskTypeId: fixture.source.id,
            companyId: fixture.source.companyId,
            label: "Confirm layout"
        )
        reminderTemplate.taskType = fixture.source
        let reminder = TaskReminder(
            id: "rollback-reminder",
            taskId: fixture.firstTask.id,
            companyId: fixture.source.companyId,
            sourceTemplateId: reminderTemplate.id,
            label: reminderTemplate.label,
            leadTimeDays: 1,
            fireTimeLocalSeconds: 9 * 3600,
            requiresAck: false,
            recipientMode: .taskCrew,
            recipientConfig: .empty,
            firesAt: Date().addingTimeInterval(3_600)
        )
        reminder.task = fixture.firstTask

        fixture.context.insert(product)
        fixture.context.insert(taskTemplate)
        fixture.context.insert(reminderTemplate)
        fixture.context.insert(reminder)
        try fixture.context.save()

        _ = try fixture.dataController.mergeTaskType(
            sourceTaskTypeId: fixture.source.id,
            intoTaskTypeId: fixture.target.id
        )
        let rejectedCommand = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context).only
        )

        var rollbackResult =
            TaskTypeMutationSync.RejectionRollbackResult.none
        try fixture.context.transaction {
            rejectedCommand.status = "parked"
            rejectedCommand.lastError = "server rejected fixture"
            rollbackResult = try TaskTypeMutationSync
                .rollbackRejectedMutation(
                    rejectedCommand,
                    in: fixture.context
                )
        }

        XCTAssertTrue(rollbackResult.didRollback)
        XCTAssertTrue(rollbackResult.reminderStateChanged)
        XCTAssertNil(fixture.source.deletedAt)
        XCTAssertFalse(fixture.source.needsSync)
        for task in [fixture.firstTask, fixture.secondTask] {
            XCTAssertEqual(task.taskTypeId, fixture.source.id)
            XCTAssertEqual(task.taskType?.id, fixture.source.id)
            XCTAssertEqual(task.taskColor, fixture.source.color)
            XCTAssertFalse(task.needsSync)
        }
        XCTAssertEqual(product.taskTypeId, fixture.source.id)
        XCTAssertEqual(product.taskTypeRef, fixture.source.id)
        XCTAssertEqual(taskTemplate.taskTypeId, fixture.source.id)
        XCTAssertEqual(taskTemplate.taskTypeRef, fixture.source.id)
        XCTAssertFalse(taskTemplate.needsSync)
        XCTAssertEqual(
            fixture.other.dependencies.map(\.dependsOnTaskTypeId),
            [fixture.source.id]
        )
        XCTAssertFalse(fixture.other.needsSync)
        XCTAssertEqual(
            fixture.unrelatedTask.dependencyOverridesJSON,
            originalOverrides
        )
        XCTAssertFalse(fixture.unrelatedTask.needsSync)
        XCTAssertNil(reminderTemplate.deletedAt)
        XCTAssertFalse(reminderTemplate.needsSync)
        XCTAssertNil(reminder.deletedAt)
        XCTAssertFalse(reminder.needsSync)
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).allSatisfy {
                $0.status == "completed"
            }
        )

        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )
        let followUp = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context)
                .first(where: { $0.status == "pending" })
        )
        XCTAssertTrue(
            try TaskTypeMutationSync.isReadyForExecution(
                followUp,
                in: fixture.context
            )
        )
    }

    func testRejectedMutationRollsBackDependentMutationChainNewestFirst() throws {
        let fixture = try makeFixture()
        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )
        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.target.id,
            toTaskTypeId: fixture.other.id
        )
        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.other.id)

        let commands = try taskTypeMutationOperations(in: fixture.context)
        XCTAssertEqual(commands.count, 2)
        let rejectedCommand = try XCTUnwrap(
            commands.first {
                let payload = (
                    try? JSONSerialization.jsonObject(
                        with: $0.payload
                    )
                ) as? [String: Any]
                return payload?[TaskTypeMutationSync.sourceTaskTypeIdKey]
                    as? String == fixture.source.id
            }
        )
        let dependentCommand = try XCTUnwrap(
            commands.first { $0.id != rejectedCommand.id }
        )

        var rollbackResult =
            TaskTypeMutationSync.RejectionRollbackResult.none
        try fixture.context.transaction {
            rejectedCommand.status = "parked"
            rejectedCommand.lastError = "server rejected fixture"
            rollbackResult = try TaskTypeMutationSync
                .rollbackRejectedMutation(
                    rejectedCommand,
                    in: fixture.context
                )
        }

        XCTAssertEqual(rollbackResult.restoredCommandIds.count, 2)
        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.source.id)
        XCTAssertEqual(fixture.firstTask.taskType?.id, fixture.source.id)
        XCTAssertEqual(fixture.firstTask.taskColor, fixture.source.color)
        XCTAssertFalse(fixture.firstTask.needsSync)
        XCTAssertEqual(dependentCommand.status, "parked")
        XCTAssertTrue(
            dependentCommand.lastError?.contains("earlier task type")
                == true
        )
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).allSatisfy {
                $0.status == "completed"
            }
        )
    }

    func testDiscardFailedMutationRestoresProjectionAndRemovesGuards() throws {
        let fixture = try makeFixture()
        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )
        let failedCommand = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context).only
        )
        failedCommand.status = "failed"
        failedCommand.lastError = "retry budget exhausted"
        try fixture.context.save()

        fixture.dataController.syncEngine.cancelOperation(failedCommand)

        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.source.id)
        XCTAssertEqual(fixture.firstTask.taskType?.id, fixture.source.id)
        XCTAssertEqual(fixture.firstTask.taskColor, fixture.source.color)
        XCTAssertFalse(fixture.firstTask.needsSync)
        XCTAssertTrue(
            try taskTypeMutationOperations(in: fixture.context).isEmpty
        )
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).isEmpty
        )
    }

    func testRetryRolledBackMutationRearmsFreshProtectionSnapshots() throws {
        let fixture = try makeFixture()
        _ = try fixture.dataController.reassignTasks(
            taskIds: [fixture.firstTask.id],
            fromTaskTypeId: fixture.source.id,
            toTaskTypeId: fixture.target.id
        )
        let command = try XCTUnwrap(
            taskTypeMutationOperations(in: fixture.context).only
        )
        try fixture.context.transaction {
            command.status = "parked"
            _ = try TaskTypeMutationSync.rollbackRejectedMutation(
                command,
                in: fixture.context
            )
        }
        fixture.firstTask.taskColor = "#123456"
        try fixture.context.save()

        fixture.dataController.syncEngine.retryOperations([command])

        XCTAssertEqual(command.status, "pending")
        XCTAssertTrue(
            try protectionOperations(in: fixture.context).allSatisfy {
                $0.status == "pending" && $0.completedAt == nil
            }
        )

        try fixture.context.transaction {
            command.status = "parked"
            _ = try TaskTypeMutationSync.rollbackRejectedMutation(
                command,
                in: fixture.context
            )
        }
        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.source.id)
        XCTAssertEqual(fixture.firstTask.taskColor, "#123456")
    }

    func testDiscardFailedDirectDeleteRestoresTaskTypeAndRemovesOperation() throws {
        let fixture = try makeFixture()
        let deleteOperation = SyncOperation(
            entityType: SyncEntityType.taskType.rawValue,
            entityId: fixture.source.id,
            operationType: "delete",
            payload: Data("{}".utf8),
            changedFields: ["deleted_at"]
        )
        deleteOperation.status = "failed"
        let deleteOperationId = deleteOperation.id
        fixture.source.deletedAt = Date()
        fixture.source.needsSync = true
        fixture.context.insert(deleteOperation)
        try fixture.context.save()

        fixture.dataController.syncEngine.cancelOperation(deleteOperation)

        XCTAssertNil(fixture.source.deletedAt)
        XCTAssertFalse(fixture.source.needsSync)
        XCTAssertFalse(
            try fixture.context.fetch(
                FetchDescriptor<SyncOperation>()
            ).contains { $0.id == deleteOperationId }
        )
    }

    func testWholeMergeRefusesDefaultSourceBeforeMutating() throws {
        let fixture = try makeFixture()
        fixture.source.isDefault = true
        try fixture.context.save()

        XCTAssertThrowsError(
            try fixture.dataController.mergeTaskType(
                sourceTaskTypeId: fixture.source.id,
                intoTaskTypeId: fixture.target.id
            )
        ) { error in
            XCTAssertEqual(error as? TaskTypeReassignmentError, .defaultTypeProtected)
        }

        XCTAssertNil(fixture.source.deletedAt)
        XCTAssertEqual(fixture.firstTask.taskTypeId, fixture.source.id)
        XCTAssertTrue(try taskTypeMutationOperations(in: fixture.context).isEmpty)
    }

    func testDeleteTaskTypeRefusesLiveScalarReferenceEvenWhenRelationshipIsStale() async throws {
        let fixture = try makeFixture()
        fixture.firstTask.taskType = fixture.target
        fixture.firstTask.taskTypeId = fixture.source.id
        try fixture.context.save()

        await XCTAssertThrowsErrorAsync(
            try await fixture.dataController.deleteTaskType(taskTypeId: fixture.source.id)
        ) { error in
            XCTAssertEqual(
                error as? TaskTypeDeletionError,
                .stillInUse(activeTaskCount: 2)
            )
        }

        XCTAssertNil(fixture.source.deletedAt)
        XCTAssertNil(fixture.firstTask.deletedAt)
        XCTAssertNil(fixture.secondTask.deletedAt)
        let operations = try fixture.context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertFalse(operations.contains {
            $0.entityType == SyncEntityType.taskType.rawValue
                && $0.entityId == fixture.source.id
                && $0.operationType == "delete"
        })
    }

    func testDeleteTaskTypeRefusesDefaultTypeEvenWhenUnused() async throws {
        let fixture = try makeFixture()
        fixture.source.isDefault = true
        fixture.firstTask.deletedAt = Date()
        fixture.secondTask.deletedAt = Date()
        try fixture.context.save()

        await XCTAssertThrowsErrorAsync(
            try await fixture.dataController.deleteTaskType(taskTypeId: fixture.source.id)
        ) { error in
            XCTAssertEqual(error as? TaskTypeDeletionError, .defaultTypeProtected)
        }

        XCTAssertNil(fixture.source.deletedAt)
    }

    func testDeleteTaskTypeRefusesIncomingDependenciesAndReminderTemplates() async throws {
        let fixture = try makeFixture()
        fixture.firstTask.deletedAt = Date()
        fixture.secondTask.deletedAt = Date()
        fixture.other.dependencies = [
            TaskTypeDependency(
                dependsOnTaskTypeId: fixture.source.id,
                overlapPercentage: 0
            )
        ]
        let reminder = TaskTypeReminder(
            id: "delete-guard-reminder",
            taskTypeId: fixture.source.id,
            companyId: fixture.source.companyId,
            label: "Order material"
        )
        reminder.taskType = fixture.source
        fixture.context.insert(reminder)
        try fixture.context.save()

        await XCTAssertThrowsErrorAsync(
            try await fixture.dataController.deleteTaskType(
                taskTypeId: fixture.source.id
            )
        ) { error in
            XCTAssertEqual(
                error as? TaskTypeDeletionError,
                .referencedByConfiguration(referenceCount: 2)
            )
        }

        XCTAssertNil(fixture.source.deletedAt)
    }

    func testRejectedDirectDeleteRestoresVisibleTaskType() throws {
        let fixture = try makeFixture()
        let deleteOperation = SyncOperation(
            entityType: SyncEntityType.taskType.rawValue,
            entityId: fixture.source.id,
            operationType: "delete",
            payload: Data("{}".utf8),
            changedFields: ["deleted_at"]
        )
        fixture.source.deletedAt = Date()
        fixture.source.needsSync = true
        fixture.context.insert(deleteOperation)
        try fixture.context.save()

        XCTAssertTrue(
            try TaskTypeMutationSync.restoreRejectedDirectDelete(
                deleteOperation,
                in: fixture.context
            )
        )
        XCTAssertNil(fixture.source.deletedAt)
        XCTAssertFalse(fixture.source.needsSync)
    }

    func testDeleteTaskTypeRefusesExplicitTaskDependencyOverride() async throws {
        let fixture = try makeFixture()
        fixture.firstTask.taskTypeId = fixture.target.id
        fixture.firstTask.taskType = fixture.target
        fixture.secondTask.deletedAt = Date()
        fixture.firstTask.setDependencyOverrides([
            TaskTypeDependency(
                dependsOnTaskTypeId: fixture.source.id,
                overlapPercentage: 0
            )
        ])
        try fixture.context.save()

        await XCTAssertThrowsErrorAsync(
            try await fixture.dataController.deleteTaskType(
                taskTypeId: fixture.source.id
            )
        ) { error in
            XCTAssertEqual(
                error as? TaskTypeDeletionError,
                .referencedByConfiguration(referenceCount: 1)
            )
        }
        XCTAssertNil(fixture.source.deletedAt)
    }

    private func makeFixture() throws -> Fixture {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            title: "Deck rebuild",
            status: .accepted
        )
        project.companyId = "company-a"

        let source = TaskType(
            id: "source-type",
            display: "Quote",
            color: "#59779F",
            companyId: "company-a"
        )
        let target = TaskType(
            id: "target-type",
            display: "Install",
            color: "#8AA66A",
            companyId: "company-a"
        )
        let other = TaskType(
            id: "other-type",
            display: "Inspection",
            color: "#7B68A6",
            companyId: "company-a"
        )
        let firstTask = ProjectTask(
            id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            projectId: project.id,
            taskTypeId: source.id,
            companyId: "company-a",
            taskColor: source.color
        )
        let secondTask = ProjectTask(
            id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            projectId: project.id,
            taskTypeId: source.id,
            companyId: "company-a",
            taskColor: source.color
        )
        let unrelatedTask = ProjectTask(
            id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
            projectId: project.id,
            taskTypeId: other.id,
            companyId: "company-a",
            taskColor: other.color
        )
        for task in [firstTask, secondTask, unrelatedTask] {
            task.project = project
        }
        firstTask.taskType = source
        secondTask.taskType = source
        unrelatedTask.taskType = other

        context.insert(project)
        context.insert(source)
        context.insert(target)
        context.insert(other)
        context.insert(firstTask)
        context.insert(secondTask)
        context.insert(unrelatedTask)
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        return Fixture(
            context: context,
            dataController: dataController,
            source: source,
            target: target,
            other: other,
            firstTask: firstTask,
            secondTask: secondTask,
            unrelatedTask: unrelatedTask
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaV20.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func projectTaskOperations(in context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>()).filter {
            $0.entityType == SyncEntityType.projectTask.rawValue
        }
    }

    private func taskTypeMutationOperations(in context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>()).filter {
            $0.entityType == TaskTypeMutationSync.entityType
        }
    }

    private func protectionOperations(in context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>()).filter {
            $0.operationType == TaskTypeMutationSync.protectionOperationType
        }
    }
}

@MainActor
private struct Fixture {
    let context: ModelContext
    let dataController: DataController
    let source: TaskType
    let target: TaskType
    let other: TaskType
    let firstTask: ProjectTask
    let secondTask: ProjectTask
    let unrelatedTask: ProjectTask
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
