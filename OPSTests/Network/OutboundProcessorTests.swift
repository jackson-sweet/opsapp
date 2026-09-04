//
//  OutboundProcessorTests.swift
//  OPSTests
//
//  Regression coverage for create-then-schedule task sync coalescing.
//

import XCTest
import SwiftData
import Supabase
@testable import OPS

@MainActor
final class OutboundProcessorTests: XCTestCase {

    func testCreateFollowedByScheduleAndDisplayOrderKeepsAllFieldsInCreatePayload() throws {
        let processor = OutboundProcessor()
        let taskId = "11111111-1111-4111-8111-111111111111"

        let create = makeOperation(
            operationType: "create",
            taskId: taskId,
            payload: [
                "id": taskId,
                "company_id": "22222222-2222-4222-8222-222222222222",
                "project_id": "33333333-3333-4333-8333-333333333333",
                "status": "pending"
            ],
            changedFields: ["id", "company_id", "project_id", "status"],
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let schedule = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: [
                "start_date": "2026-05-26T15:00:00Z",
                "end_date": "2026-05-26T17:00:00Z",
                "duration": 120,
                "schedule_locked": true
            ],
            changedFields: ["start_date", "end_date", "duration", "schedule_locked"],
            createdAt: Date(timeIntervalSince1970: 2)
        )

        let displayOrder = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: [
                "display_order": 4
            ],
            changedFields: ["display_order"],
            createdAt: Date(timeIntervalSince1970: 3)
        )

        let coalesced = processor.coalesceOperations([create, schedule, displayOrder])

        XCTAssertEqual(coalesced.count, 1)
        let survivor = try XCTUnwrap(coalesced.first)
        XCTAssertEqual(survivor.operationType, "create")

        let payload = try decodedPayload(from: survivor.payload)
        XCTAssertEqual(payload["id"] as? String, taskId)
        XCTAssertEqual(payload["start_date"] as? String, "2026-05-26T15:00:00Z")
        XCTAssertEqual(payload["end_date"] as? String, "2026-05-26T17:00:00Z")
        XCTAssertEqual(payload["duration"] as? Int, 120)
        XCTAssertEqual(payload["schedule_locked"] as? Bool, true)
        XCTAssertEqual(payload["display_order"] as? Int, 4)

        XCTAssertTrue(schedule.isCompleted)
        XCTAssertTrue(displayOrder.isCompleted)
    }

    func testCompletedTaskUpdateCallsCompleteProjectTaskRPC() async throws {
        let taskId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: [
                "status": TaskStatus.completed.rawValue,
                TaskCompletionSync.idempotencyKeyPayloadKey: "complete-key-1",
                TaskCompletionSync.materialAdjustmentsPayloadKey: [:]
            ],
            changedFields: ["status", TaskCompletionSync.idempotencyKeyPayloadKey, TaskCompletionSync.materialAdjustmentsPayloadKey],
            createdAt: Date(timeIntervalSince1970: 4)
        )

        // executeOperation claims ops from the persisted store (pending → inProgress
        // linearization) — an op must be inserted and saved or the claim refuses it.
        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.completedTaskIds, [taskId])
        XCTAssertEqual(spy.completionIdempotencyKeys, ["complete-key-1"])
        XCTAssertEqual(spy.materialAdjustmentCounts, [0])
        XCTAssertTrue(spy.updatedFieldSets.isEmpty)
        XCTAssertTrue(operation.isCompleted)
    }

    func testCompletionRetryReusesStableIdempotencyKeyWhenPayloadHasNoStoredKey() async throws {
        let taskId = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        let spy = SpyProjectTaskSyncing()
        spy.remainingCompletionFailures = 1
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: ["status": TaskStatus.completed.rawValue],
            changedFields: ["status"],
            createdAt: Date(timeIntervalSince1970: 5)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        do {
            try await processor.executeOperation(operation, context: context)
            XCTFail("Expected the first RPC attempt to fail")
        } catch {
            XCTAssertEqual(operation.status, "pending")
        }

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.completionIdempotencyKeys.count, 2)
        XCTAssertEqual(spy.completionIdempotencyKeys[0], spy.completionIdempotencyKeys[1])
        XCTAssertEqual(
            spy.completionIdempotencyKeys[0],
            TaskCompletionSync.stableCompletionIdempotencyKey(taskId: taskId)
        )
        XCTAssertTrue(operation.isCompleted)
    }

    func testNonCompletionTaskStatusUpdateDoesNotCallCompletionRPC() async throws {
        let taskId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: ["status": TaskStatus.active.rawValue],
            changedFields: ["status"],
            createdAt: Date(timeIntervalSince1970: 6)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertTrue(spy.completedTaskIds.isEmpty)
        XCTAssertEqual(spy.updatedTaskIds, [taskId])
        XCTAssertEqual(spy.updatedFieldSets.first?["status"], .string(TaskStatus.active.rawValue))
    }

    func testOfflineQueuedCreateWithCompletedStatusCreatesActiveThenCompletesThroughRPC() async throws {
        let taskId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "create",
            taskId: taskId,
            payload: [
                "id": taskId,
                "company_id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
                "project_id": "ffffffff-ffff-4fff-8fff-ffffffffffff",
                "task_type_id": "11111111-1111-4111-8111-111111111111",
                "status": TaskStatus.completed.rawValue,
                TaskCompletionSync.idempotencyKeyPayloadKey: "offline-complete-key"
            ],
            changedFields: ["id", "company_id", "project_id", "task_type_id", "status", TaskCompletionSync.idempotencyKeyPayloadKey],
            createdAt: Date(timeIntervalSince1970: 7)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.createdStatuses, [TaskStatus.active.rawValue])
        XCTAssertEqual(spy.completedTaskIds, [taskId])
        XCTAssertEqual(spy.completionIdempotencyKeys, ["offline-complete-key"])
        XCTAssertTrue(spy.updatedFieldSets.isEmpty)
    }

    // MARK: - Tombstone routing (bugs db15baf2, 2a55c78f)

    func testUpdateCarryingATombstoneCallsTheSoftDeleteRPCInsteadOfPatching() async throws {
        // `deleted_at` cannot travel on a PATCH here at all: project_tasks'
        // RESTRICTIVE read policy judges that column, and Postgres attaches
        // SELECT policies as WITH CHECK options to any UPDATE whose WHERE needs
        // read access, so the write comes back 42501 for every client role.
        let taskId = "1a1a1a1a-1a1a-4a1a-8a1a-1a1a1a1a1a1a"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: ["deleted_at": "2026-09-04T17:15:45Z"],
            changedFields: ["deleted_at"],
            createdAt: Date(timeIntervalSince1970: 8)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.softDeletedTaskIds, [taskId])
        XCTAssertTrue(
            spy.updatedFieldSets.isEmpty,
            "A tombstone-only payload must send no PATCH at all."
        )
        XCTAssertTrue(operation.isCompleted)
    }

    func testRestoreUpdateCallsTheRestoreRPCInsteadOfPatchingNull() async throws {
        // Restore is staged as an `update` carrying `deleted_at: null`
        // (DataController.restoreTrash), so it never reaches the delete branch.
        // As a PATCH it matched zero rows — the tombstoned row is invisible to
        // the policy the UPDATE consults — and PostgREST answers that 200 with
        // an empty body, so every restore reported success and did nothing.
        let taskId = "2b2b2b2b-2b2b-4b2b-8b2b-2b2b2b2b2b2b"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: ["deleted_at": NSNull()],
            changedFields: ["deleted_at"],
            createdAt: Date(timeIntervalSince1970: 9)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.restoredTaskIds, [taskId])
        XCTAssertTrue(spy.softDeletedTaskIds.isEmpty, "A restore must never tombstone.")
        XCTAssertTrue(spy.updatedFieldSets.isEmpty)
        XCTAssertTrue(operation.isCompleted)
    }

    func testTombstoneUpdateSendsSiblingFieldsBeforeTheRowGoesInvisible() async throws {
        // Order is load-bearing: once the tombstone lands the row is invisible to
        // the read policy, so a PATCH issued after it would match nothing and
        // park the operation as unaddressable.
        let taskId = "3c3c3c3c-3c3c-4c3c-8c3c-3c3c3c3c3c3c"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: [
                "deleted_at": "2026-09-04T17:15:45Z",
                "custom_title": "Retired lane"
            ],
            changedFields: ["deleted_at", "custom_title"],
            createdAt: Date(timeIntervalSince1970: 10)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.callLog, ["updateFields", "softDelete"])
        XCTAssertEqual(
            spy.updatedFieldSets.first?["custom_title"],
            .string("Retired lane")
        )
        XCTAssertNil(
            spy.updatedFieldSets.first?["deleted_at"],
            "The tombstone column must be stripped out of the PATCH."
        )
    }

    func testRestoreUpdateClearsTheTombstoneBeforeSendingSiblingFields() async throws {
        let taskId = "4d4d4d4d-4d4d-4d4d-8d4d-4d4d4d4d4d4d"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: [
                "deleted_at": NSNull(),
                "custom_title": "Back in service"
            ],
            changedFields: ["deleted_at", "custom_title"],
            createdAt: Date(timeIntervalSince1970: 11)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.callLog, ["restore", "updateFields"])
        XCTAssertEqual(
            spy.updatedFieldSets.first?["custom_title"],
            .string("Back in service")
        )
    }

    func testOrdinaryUpdateStillPatchesAndNeverTouchesTheTombstoneRPCs() async throws {
        let taskId = "5e5e5e5e-5e5e-4e5e-8e5e-5e5e5e5e5e5e"
        let spy = SpyProjectTaskSyncing()
        let processor = OutboundProcessor(projectTaskSyncingFactory: { _ in spy })
        let operation = makeOperation(
            operationType: "update",
            taskId: taskId,
            payload: ["custom_title": "Renamed lane"],
            changedFields: ["custom_title"],
            createdAt: Date(timeIntervalSince1970: 12)
        )

        let context = try makeContext()
        context.insert(operation)
        try context.save()

        try await processor.executeOperation(operation, context: context)

        XCTAssertEqual(spy.callLog, ["updateFields"])
        XCTAssertEqual(spy.updatedTaskIds, [taskId])
        XCTAssertTrue(spy.softDeletedTaskIds.isEmpty)
        XCTAssertTrue(spy.restoredTaskIds.isEmpty)
    }

    func testCompleteProjectTaskResponseParsesConsumptionEvidence() throws {
        let payload = """
        {
          "ok": true,
          "task_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "company_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          "inventory_mode": "tracked",
          "consumption_performed": true,
          "demand_count": 2,
          "allocation_count": 3,
          "stock_unit_count": 2,
          "unavailable_allocation_count": 1,
          "consumed_quantity": 14.5,
          "overrun_quantity": 1.25,
          "snapshot_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
          "inventory_deduction_ids": ["dddddddd-dddd-4ddd-8ddd-dddddddddddd"],
          "stock_unit_event_ids": ["eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"],
          "request_id": "ffffffff-ffff-4fff-8fff-ffffffffffff",
          "task_status_changed": true,
          "completed_by": "11111111-1111-4111-8111-111111111111",
          "completed_at": "2026-05-29T06:25:17Z"
        }
        """

        let response = try JSONDecoder().decode(
            CompleteProjectTaskResponseDTO.self,
            from: Data(payload.utf8)
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.taskId, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(response.inventoryMode, "tracked")
        XCTAssertEqual(response.consumedQuantity, 14.5)
        XCTAssertEqual(response.overrunQuantity, 1.25)
        XCTAssertEqual(response.snapshotId, "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        XCTAssertEqual(response.inventoryDeductionIds, ["dddddddd-dddd-4ddd-8ddd-dddddddddddd"])
        XCTAssertEqual(response.stockUnitEventIds, ["eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"])
        XCTAssertEqual(response.requestId, "ffffffff-ffff-4fff-8fff-ffffffffffff")
        XCTAssertEqual(response.taskStatusChanged, true)
    }

    private func makeOperation(
        operationType: String,
        taskId: String,
        payload: [String: Any],
        changedFields: [String],
        createdAt: Date
    ) -> SyncOperation {
        let operation = SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: taskId,
            operationType: operationType,
            payload: try! JSONSerialization.data(withJSONObject: payload),
            changedFields: changedFields
        )
        operation.createdAt = createdAt
        return operation
    }

    private func decodedPayload(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Expected sync payload to decode as a JSON object."
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SyncOperation.self, configurations: configuration)
        return ModelContext(container)
    }
}

private final class SpyProjectTaskSyncing: ProjectTaskSyncing {
    var createdStatuses: [String] = []
    var updatedTaskIds: [String] = []
    var updatedFieldSets: [[String: AnyJSON]] = []
    var softDeletedTaskIds: [String] = []
    var restoredTaskIds: [String] = []
    var completedTaskIds: [String] = []
    var completionIdempotencyKeys: [String] = []
    var materialAdjustmentCounts: [Int] = []
    var remainingCompletionFailures = 0

    /// Ordered record of every call, so ordering assertions read the real
    /// sequence instead of inferring it from three separate arrays.
    var callLog: [String] = []

    func create(_ dto: SupabaseProjectTaskDTO) async throws -> SupabaseProjectTaskDTO {
        createdStatuses.append(dto.status)
        callLog.append("create")
        return dto
    }

    func updateFields(_ taskId: String, fields: [String: AnyJSON]) async throws {
        updatedTaskIds.append(taskId)
        updatedFieldSets.append(fields)
        callLog.append("updateFields")
    }

    func softDelete(_ taskId: String) async throws {
        softDeletedTaskIds.append(taskId)
        callLog.append("softDelete")
    }

    func restore(_ taskId: String) async throws {
        restoredTaskIds.append(taskId)
        callLog.append("restore")
    }

    func completeProjectTask(
        taskId: String,
        idempotencyKey: String,
        materialAdjustments: [String: AnyJSON]
    ) async throws -> CompleteProjectTaskResponseDTO {
        completedTaskIds.append(taskId)
        completionIdempotencyKeys.append(idempotencyKey)
        materialAdjustmentCounts.append(materialAdjustments.count)

        if remainingCompletionFailures > 0 {
            remainingCompletionFailures -= 1
            throw URLError(.cannotConnectToHost)
        }

        return CompleteProjectTaskResponseDTO(
            ok: true,
            taskId: taskId,
            companyId: nil,
            inventoryMode: nil,
            consumptionPerformed: false,
            demandCount: 0,
            allocationCount: 0,
            stockUnitCount: 0,
            unavailableAllocationCount: 0,
            consumedQuantity: 0,
            overrunQuantity: 0,
            snapshotId: nil,
            inventoryDeductionIds: [],
            stockUnitEventIds: [],
            requestId: "request-\(taskId)",
            taskStatusChanged: true,
            completedBy: nil,
            completedAt: nil,
            idempotentReplay: nil,
            taskConsumptionReplay: nil
        )
    }
}
