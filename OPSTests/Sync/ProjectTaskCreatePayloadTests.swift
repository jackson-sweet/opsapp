import SwiftData
import XCTest
@testable import OPS

/// Bug eed3f552 — tasks added from the NEEDS TASKS review screen never reached
/// the server. `DataController.createTask(task:)` recorded a create carrying
/// only id / project_id / status / task_type_id; the outbound push decodes a
/// create into `SupabaseProjectTaskDTO`, whose `company_id` is required, so the
/// operation failed with "The data couldn't be read because it is missing" and
/// retried forever. Five such operations sat on the founder's phone for hours
/// (twelve attempts each) while tasks from the task sheet, which records the
/// full DTO, saved normally.
@MainActor
final class ProjectTaskCreatePayloadTests: XCTestCase {

    func testCreateFieldsFromAModelDecodeIntoTheOutboundDTO() throws {
        let task = ProjectTask(
            id: "t-1", projectId: "p-1", taskTypeId: "tt-1", companyId: "c-1",
            status: .active, taskColor: "4d7ea2"
        )
        task.customTitle = "Curb details"
        task.displayOrder = 3
        task.duration = 2
        task.setTeamMemberIds(["u-1", "u-2"])
        task.startDate = Date(timeIntervalSince1970: 1_757_000_000)
        task.endDate = Date(timeIntervalSince1970: 1_757_086_400)

        let fields = try DataController.projectTaskCreateFields(for: task)
        let data = try JSONSerialization.data(withJSONObject: fields)
        let dto = try JSONDecoder().decode(SupabaseProjectTaskDTO.self, from: data)

        XCTAssertEqual(dto.id, "t-1")
        XCTAssertEqual(dto.companyId, "c-1")
        XCTAssertEqual(dto.projectId, "p-1")
        XCTAssertEqual(dto.taskTypeId, "tt-1")
        XCTAssertEqual(dto.status, "active")
        XCTAssertEqual(dto.customTitle, "Curb details")
        XCTAssertEqual(dto.taskColor, "4d7ea2")
        XCTAssertEqual(dto.displayOrder, 3)
        XCTAssertEqual(dto.duration, 2)
        XCTAssertEqual(dto.teamMemberIds, ["u-1", "u-2"])
        XCTAssertNotNil(dto.startDate)
        XCTAssertNotNil(dto.endDate)
        XCTAssertNotNil(dto.createdAt, "a create must carry created_at so the server row keeps the operator's timestamp")
    }

    func testReviewScreenCreateRecordsAPayloadTheOutboundCanDecode() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        let task = ProjectTask(
            id: "t-review", projectId: "p-1", taskTypeId: "tt-1", companyId: "c-1",
            status: .active, taskColor: "4d7ea2"
        )
        try await dataController.createTask(task: task)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let create = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.projectTask.rawValue
                && $0.entityId == "t-review"
                && $0.operationType == "create"
        })
        let dto = try JSONDecoder().decode(SupabaseProjectTaskDTO.self, from: create.payload)
        XCTAssertEqual(dto.companyId, "c-1")
        XCTAssertEqual(dto.taskTypeId, "tt-1")
        XCTAssertNotNil(dto.createdAt)
        XCTAssertNotNil(task.createdAt, "the review screen's task now carries its creation time")
        XCTAssertFalse(DataController.projectTaskCreatePayloadIsStranded(create.payload))
    }

    func testLaunchRepairRebuildsStrandedCreatesAndLeavesHealthyOnesAlone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let dataController = DataController()
        dataController.setModelContext(context)

        let stranded = ProjectTask(
            id: "t-stranded", projectId: "p-1", taskTypeId: "tt-1", companyId: "c-1",
            status: .active, taskColor: "4d7ea2"
        )
        stranded.setTeamMemberIds(["u-1"])
        context.insert(stranded)
        let strandedOperation = SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: "t-stranded",
            operationType: "create",
            payload: try JSONSerialization.data(withJSONObject: [
                "id": "t-stranded", "project_id": "p-1", "task_type_id": "tt-1", "status": "active"
            ]),
            changedFields: ["id", "project_id", "task_type_id", "status"]
        )
        strandedOperation.retryCount = 12
        strandedOperation.lastAttemptedAt = Date()
        strandedOperation.lastError = "Unexpected sync error: The data couldn’t be read because it is missing."
        context.insert(strandedOperation)

        let healthy = ProjectTask(
            id: "t-healthy", projectId: "p-1", taskTypeId: "tt-1", companyId: "c-1",
            status: .active, taskColor: "4d7ea2"
        )
        context.insert(healthy)
        let healthyPayload = try JSONSerialization.data(withJSONObject: [
            "id": "t-healthy", "company_id": "c-1", "project_id": "p-1", "task_type_id": "tt-1", "status": "active"
        ])
        let healthyOperation = SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: "t-healthy",
            operationType: "create",
            payload: healthyPayload,
            changedFields: ["id", "company_id", "project_id", "task_type_id", "status"]
        )
        healthyOperation.retryCount = 2
        context.insert(healthyOperation)
        try context.save()

        XCTAssertEqual(dataController.repairStrandedProjectTaskCreates(), 1)

        let rebuilt = try JSONDecoder().decode(SupabaseProjectTaskDTO.self, from: strandedOperation.payload)
        XCTAssertEqual(rebuilt.companyId, "c-1")
        XCTAssertEqual(rebuilt.teamMemberIds, ["u-1"])
        XCTAssertEqual(strandedOperation.retryCount, 0)
        XCTAssertNil(strandedOperation.lastError)
        XCTAssertNil(strandedOperation.lastAttemptedAt)
        XCTAssertEqual(strandedOperation.status, "pending")
        XCTAssertTrue(strandedOperation.getChangedFields().contains("company_id"))

        XCTAssertEqual(healthyOperation.payload, healthyPayload)
        XCTAssertEqual(healthyOperation.retryCount, 2)

        XCTAssertEqual(dataController.repairStrandedProjectTaskCreates(), 0, "the repair is idempotent")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            SyncOperation.self,
            ProjectVinylOrderMarker.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
