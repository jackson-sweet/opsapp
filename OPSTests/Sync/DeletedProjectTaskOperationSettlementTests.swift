//
//  DeletedProjectTaskOperationSettlementTests.swift
//  OPSTests
//
//  A parked task update is obsolete only when the phone still holds the exact
//  same-company task as a soft-delete tombstone. Active work stays protected.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DeletedProjectTaskOperationSettlementTests: XCTestCase {
    private let companyID = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let taskID = "a8ea0ef2-05f1-4977-bd88-add9fa95dd2b"
    private var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func test_settlesOnlyParkedMissingRowUpdateForMatchingLocalTombstone() throws {
        let context = try makeContext()
        let task = makeTask()
        task.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        task.needsSync = false
        let operation = makeOperation()
        operation.status = "parked"
        operation.retryCount = 7
        operation.lastAttemptedAt = Date(timeIntervalSince1970: 1_760_000_000)
        operation.lastError = SyncError.serverRowMissingMarker
            + ": no project_tasks row \(taskID) on the server."
        context.insert(task)
        context.insert(operation)
        try context.save()

        let result = try DeletedProjectTaskOperationSettlement.sweep(
            in: context,
            activeCompanyId: companyID,
            now: Date(timeIntervalSince1970: 1_770_000_000)
        )

        XCTAssertEqual(result.settledOperationIds, [operation.id])
        XCTAssertEqual(operation.status, "completed")
        XCTAssertEqual(operation.completedAt, Date(timeIntervalSince1970: 1_770_000_000))
        XCTAssertNil(operation.serverConfirmedAt, "Obsolete is settled, not falsely server-confirmed")
        XCTAssertNil(operation.lastError)
        XCTAssertNil(operation.lastAttemptedAt)
        XCTAssertNotNil(task.deletedAt)
    }

    func test_activeTaskCreateWrongErrorAndForeignTombstoneRemainParked() throws {
        let context = try makeContext()
        let activeTask = makeTask(id: taskID)
        let foreignTombstone = makeTask(
            id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            companyId: "67ffc0b9-662c-42ea-b935-d6a78b778cc3"
        )
        foreignTombstone.deletedAt = Date()
        context.insert(activeTask)
        context.insert(foreignTombstone)

        let activeUpdate = makeOperation(entityId: activeTask.id)
        let create = makeOperation(entityId: activeTask.id, operationType: "create")
        let wrongError = makeOperation(entityId: activeTask.id)
        wrongError.lastError = "Request timed out"
        let foreignUpdate = makeOperation(entityId: foreignTombstone.id)
        for operation in [activeUpdate, create, wrongError, foreignUpdate] {
            operation.status = "parked"
            operation.lastError = operation.lastError
                ?? "\(SyncError.serverRowMissingMarker): no project_tasks row."
            context.insert(operation)
        }
        try context.save()

        let result = try DeletedProjectTaskOperationSettlement.sweep(
            in: context,
            activeCompanyId: companyID
        )

        XCTAssertTrue(result.settledOperationIds.isEmpty)
        XCTAssertTrue([activeUpdate, create, wrongError, foreignUpdate].allSatisfy {
            $0.status == "parked"
        })
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectNote.self,
            ProjectPhoto.self,
            SyncOperation.self,
            ProjectVinylOrderMarker.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return container.mainContext
    }

    private func makeTask(
        id: String? = nil,
        companyId: String? = nil
    ) -> ProjectTask {
        ProjectTask(
            id: id ?? taskID,
            projectId: "7b042615-94e5-428b-bd8d-2011a72de7e2",
            taskTypeId: "44444444-4444-4444-8444-444444444444",
            companyId: companyId ?? companyID
        )
    }

    private func makeOperation(
        entityId: String? = nil,
        operationType: String = "update"
    ) -> SyncOperation {
        SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: entityId ?? taskID,
            operationType: operationType,
            payload: Data("{}".utf8),
            changedFields: ["status"]
        )
    }
}
