//
//  ProjectDescriptionSyncTests.swift
//  OPSTests
//
//  Regression coverage for project description edits using the synced
//  project-field writer instead of a local-only SwiftData mutation.
//

import SwiftData
import XCTest
import Supabase
@testable import OPS

@MainActor
final class ProjectDescriptionSyncTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "feature.useDataActor")
        super.tearDown()
    }

    func testUpdateProjectFieldsClearingDescriptionClearsLocalValueAndQueuesNullPayload() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let projectId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let project = Project(id: projectId, title: "Deck rebuild", status: .accepted)
        project.companyId = "company-1"
        project.projectDescription = "Remove and rebuild existing deck"
        context.insert(project)
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        try await dataController.updateProjectFields(
            projectId: projectId,
            fields: ["description": .null]
        )

        XCTAssertNil(project.projectDescription)
        XCTAssertTrue(project.needsSync)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let operation = try XCTUnwrap(operations.first)
        XCTAssertEqual(operation.entityType, SyncEntityType.project.rawValue)
        XCTAssertEqual(operation.entityId, projectId)
        XCTAssertEqual(operation.operationType, "update")
        XCTAssertEqual(operation.getChangedFields(), ["description"])

        let payload = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
        XCTAssertTrue(payload?["description"] is NSNull)
    }

    func testUpdateTaskFieldsSwitchingTaskTypeMirrorsLocalRelationshipAndSyncPayload() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", title: "Deck rebuild", status: .accepted)
        project.companyId = "company-1"

        let quote = TaskType(id: "quote-type", display: "Quote", color: "#59779F", companyId: "company-1")
        let install = TaskType(id: "install-type", display: "Install", color: "#8AA66A", companyId: "company-1")
        let task = ProjectTask(
            id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            projectId: project.id,
            taskTypeId: quote.id,
            companyId: "company-1",
            taskColor: quote.color
        )
        task.project = project
        task.taskType = quote

        context.insert(project)
        context.insert(quote)
        context.insert(install)
        context.insert(task)
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        try await dataController.updateTaskFields(
            taskId: task.id,
            fields: [
                "task_type_id": .string(install.id),
                "task_color": .string(install.color)
            ]
        )

        XCTAssertEqual(task.taskTypeId, install.id)
        XCTAssertEqual(task.taskType?.id, install.id)
        XCTAssertEqual(task.taskColor, install.color)
        XCTAssertTrue(task.needsSync)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let operation = try XCTUnwrap(operations.first { $0.entityType == SyncEntityType.projectTask.rawValue })
        XCTAssertEqual(operation.entityId, task.id)
        XCTAssertEqual(Set(operation.getChangedFields()), ["task_type_id", "task_color"])

        let payload = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
        XCTAssertEqual(payload?["task_type_id"] as? String, install.id)
        XCTAssertEqual(payload?["task_color"] as? String, install.color)
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
            ProjectVinylOrderMarker.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
