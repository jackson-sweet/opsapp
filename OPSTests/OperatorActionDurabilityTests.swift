import SwiftData
import XCTest
@testable import OPS

@MainActor
final class OperatorActionDurabilityTests: XCTestCase {
    private enum StagingProbeError: Error {
        case failed
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "feature.useDataActor")
        super.tearDown()
    }

    func testOverdueCompletionFailureKeepsTaskOpenAndQueuesNothing() async throws {
        let (dataController, context) = try makeHarness()
        let project = Project(
            id: "10101010-1010-4010-8010-101010101010",
            title: "Overdue project",
            status: .inProgress
        )
        project.companyId = "company-1"
        let task = ProjectTask(
            id: "20202020-2020-4020-8020-202020202020",
            projectId: project.id,
            taskTypeId: "task-type-1",
            companyId: project.companyId
        )
        task.project = project
        project.tasks = [task]
        context.insert(project)
        context.insert(task)
        try context.save()

        do {
            try await dataController.updateTaskStatus(
                task: task,
                to: .completed,
                stagingOperationsWith: { _, _ in
                    throw StagingProbeError.failed
                }
            )
            XCTFail("A completion without a durable outbox record must fail")
        } catch {
            XCTAssertEqual(
                error as? DataController.DurableSyncMutationError,
                .syncQueueFailed
            )
        }

        XCTAssertEqual(task.status, .active)
        XCTAssertFalse(task.needsSync)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty
        )
    }

    func testProjectContactCommitsSelectionAndOutboxTogether() async throws {
        let (dataController, context) = try makeHarness()
        let (project, client, contact) = makeContactFixture()
        context.insert(client)
        context.insert(contact)
        context.insert(project)
        try context.save()

        try await dataController.updateProjectPrimaryContact(
            project: project,
            primarySubClientId: contact.id
        )

        XCTAssertEqual(project.primarySubClientId, contact.id)
        XCTAssertTrue(project.needsSync)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ProjectPrimaryContactSelection>())
                .first?.primarySubClientId,
            contact.id
        )

        let operation = try XCTUnwrap(
            context.fetch(FetchDescriptor<SyncOperation>()).first
        )
        XCTAssertEqual(operation.entityType, SyncEntityType.project.rawValue)
        XCTAssertEqual(operation.entityId, project.id)
        XCTAssertEqual(operation.operationType, "update")
        XCTAssertEqual(operation.getChangedFields(), ["primary_sub_client_id"])

        let payload = try JSONSerialization.jsonObject(
            with: operation.payload
        ) as? [String: Any]
        XCTAssertEqual(payload?["primary_sub_client_id"] as? String, contact.id)
    }

    func testProjectContactFailureRestoresSelectionAndQueuesNothing() async throws {
        let (dataController, context) = try makeHarness()
        let (project, client, contact) = makeContactFixture()
        context.insert(client)
        context.insert(contact)
        context.insert(project)
        try context.save()

        do {
            try await dataController.updateProjectPrimaryContact(
                project: project,
                primarySubClientId: contact.id,
                stagingOperationsWith: { _, _ in
                    throw StagingProbeError.failed
                }
            )
            XCTFail("A contact assignment without an outbox record must fail")
        } catch {
            XCTAssertEqual(
                error as? DataController.DurableSyncMutationError,
                .syncQueueFailed
            )
        }

        XCTAssertNil(project.primarySubClientId)
        XCTAssertFalse(project.needsSync)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ProjectPrimaryContactSelection>()).isEmpty
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty
        )
    }

    private func makeHarness() throws -> (DataController, ModelContext) {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )
        return (dataController, context)
    }

    private func makeContactFixture() -> (Project, Client, SubClient) {
        let client = Client(
            id: "30303030-3030-4030-8030-303030303030",
            name: "Northline Builders",
            companyId: "company-1"
        )
        let contact = SubClient(
            id: "40404040-4040-4040-8040-404040404040",
            name: "Maya Stone"
        )
        contact.client = client
        client.subClients = [contact]

        let project = Project(
            id: "50505050-5050-4050-8050-505050505050",
            title: "Cedar deck",
            status: .accepted
        )
        project.companyId = "company-1"
        project.clientId = client.id
        project.client = client
        client.projects = [project]
        return (project, client, contact)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
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
            ProjectVinylOrderMarker.self,
            ProjectPrimaryContactSelection.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
