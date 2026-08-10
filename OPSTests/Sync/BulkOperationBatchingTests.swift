//
//  BulkOperationBatchingTests.swift
//  OPSTests
//
//  `SyncEngine.recordOperation` saves the shared main context on every call, so
//  any N-item flow that loops it costs N main-thread saves. These tests pin the
//  two worst offenders — project cascade delete and task-index reorder — to the
//  batched `recordOperations` path: same operations, same entity ids, same
//  payloads, but ONE save for the whole batch.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class BulkOperationBatchingTests: XCTestCase {

    private let projectId = "11111111-1111-4111-8111-111111111111"
    private let companyId = "22222222-2222-4222-8222-222222222222"

    // MARK: - Cascade delete

    func testDeleteProjectRecordsWholeCascadeInOneSave() async throws {
        let context = try makeContext()
        let controller = configuredController(context: context)
        let project = makeProject(in: context)
        let taskIds = (1...5).map { taskId(index: $0) }
        for id in taskIds {
            makeTask(id: id, project: project, in: context)
        }
        try context.save()

        let counter = SaveCounter(context: context)
        try assertCounterObservesSaves(counter, context: context, project: project)
        counter.reset()

        try await controller.deleteProject(project)

        counter.stop()

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let deletes = operations.filter { $0.operationType == "delete" }
        XCTAssertEqual(deletes.count, 6, "5 cascaded task deletes + the project's own delete")

        let taskDeleteIds = Set(
            deletes
                .filter { $0.entityType == SyncEntityType.projectTask.rawValue }
                .map(\.entityId)
        )
        XCTAssertEqual(taskDeleteIds, Set(taskIds))

        let projectDeletes = deletes.filter { $0.entityType == SyncEntityType.project.rawValue }
        XCTAssertEqual(projectDeletes.count, 1)
        XCTAssertEqual(projectDeletes.first?.entityId, projectId)

        for operation in deletes {
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
            )
            XCTAssertEqual(Array(payload.keys), ["deleted_at"])
            XCTAssertNotNil(payload["deleted_at"] as? String)
        }

        XCTAssertLessThanOrEqual(
            counter.count,
            2,
            "cascade delete must batch its ledger writes — observed \(counter.count) saves"
        )
    }

    func testDeleteProjectPersistsSoftDeleteOnProjectAndTasks() async throws {
        let context = try makeContext()
        let controller = configuredController(context: context)
        let project = makeProject(in: context)
        for index in 1...5 {
            makeTask(id: taskId(index: index), project: project, in: context)
        }
        try context.save()

        try await controller.deleteProject(project)

        XCTAssertFalse(context.hasChanges, "the batched save must commit the model edits too")

        let storedProject = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Project>()).first
        )
        XCTAssertNotNil(storedProject.deletedAt)
        XCTAssertTrue(storedProject.needsSync)

        let storedTasks = try context.fetch(FetchDescriptor<ProjectTask>())
        XCTAssertEqual(storedTasks.count, 5)
        for task in storedTasks {
            XCTAssertNotNil(task.deletedAt, "cascaded task \(task.id) must carry a tombstone")
            XCTAssertTrue(task.needsSync)
        }
    }

    // MARK: - Task-index reorder

    func testRecalculateTaskIndicesRecordsEveryMoveInOneSave() async throws {
        let context = try makeContext()
        let controller = configuredController(context: context)
        let project = makeProject(in: context)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let taskIds = (1...4).map { taskId(index: $0) }
        // Insert in reverse chronological order so every task's index changes.
        for (offset, id) in taskIds.enumerated() {
            let task = makeTask(id: id, project: project, in: context)
            task.startDate = start.addingTimeInterval(Double(offset) * 86_400)
            // Seed the exact reverse of the order startDate implies, so all four
            // tasks genuinely move and no assertion can pass by coincidence.
            task.taskIndex = taskIds.count - 1 - offset
            task.displayOrder = taskIds.count - 1 - offset
        }
        try context.save()

        let counter = SaveCounter(context: context)
        try assertCounterObservesSaves(counter, context: context, project: project)
        counter.reset()

        try await controller.recalculateTaskIndices(for: project, deferPush: true)

        counter.stop()

        let updates = try context
            .fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.operationType == "update" }
        XCTAssertEqual(updates.count, 4)
        XCTAssertTrue(updates.allSatisfy { $0.entityType == SyncEntityType.projectTask.rawValue })
        XCTAssertEqual(Set(updates.map(\.entityId)), Set(taskIds))

        var recordedOrder: [String: Int] = [:]
        for operation in updates {
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
            )
            XCTAssertEqual(Array(payload.keys), ["display_order"])
            recordedOrder[operation.entityId] = try XCTUnwrap(payload["display_order"] as? Int)
        }
        for (offset, id) in taskIds.enumerated() {
            XCTAssertEqual(recordedOrder[id], offset, "task \(id) must sync its new display order")
        }

        XCTAssertLessThanOrEqual(
            counter.count,
            1,
            "reorder must batch its ledger writes — observed \(counter.count) saves"
        )
    }

    func testRecalculateTaskIndicesPersistsIndicesWithTheBatch() async throws {
        let context = try makeContext()
        let controller = configuredController(context: context)
        let project = makeProject(in: context)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let taskIds = (1...4).map { taskId(index: $0) }
        for (offset, id) in taskIds.enumerated() {
            let task = makeTask(id: id, project: project, in: context)
            task.startDate = start.addingTimeInterval(Double(offset) * 86_400)
            // Seed the exact reverse of the order startDate implies, so all four
            // tasks genuinely move and no assertion can pass by coincidence.
            task.taskIndex = taskIds.count - 1 - offset
            task.displayOrder = taskIds.count - 1 - offset
        }
        try context.save()

        try await controller.recalculateTaskIndices(for: project, deferPush: true)

        XCTAssertFalse(context.hasChanges, "the batched save must commit the new indices too")

        let stored = try context.fetch(FetchDescriptor<ProjectTask>())
        for (offset, id) in taskIds.enumerated() {
            let task = try XCTUnwrap(stored.first { $0.id == id })
            XCTAssertEqual(task.taskIndex, offset)
            XCTAssertEqual(task.displayOrder, offset)
            XCTAssertTrue(task.needsSync)
        }
    }

    func testRecalculateTaskIndicesRecordsNothingWhenOrderIsAlreadyCorrect() async throws {
        let context = try makeContext()
        let controller = configuredController(context: context)
        let project = makeProject(in: context)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for offset in 0..<4 {
            let task = makeTask(id: taskId(index: offset + 1), project: project, in: context)
            task.startDate = start.addingTimeInterval(Double(offset) * 86_400)
            task.taskIndex = offset
            task.displayOrder = offset
        }
        try context.save()

        let counter = SaveCounter(context: context)
        try assertCounterObservesSaves(counter, context: context, project: project)
        counter.reset()

        try await controller.recalculateTaskIndices(for: project, deferPush: true)

        counter.stop()

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertTrue(operations.isEmpty, "an already-ordered project must not enqueue anything")
        XCTAssertEqual(counter.count, 0, "an already-ordered project must not save")
    }

    // MARK: - Fixtures

    private func taskId(index: Int) -> String {
        String(format: "33333333-3333-4333-8333-%012d", index)
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
            ProjectPhoto.self,
            SyncOperation.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func configuredController(context: ModelContext) -> DataController {
        let controller = DataController()
        controller.setModelContext(context)
        controller.syncEngine.configure(
            modelContext: context,
            connectivity: controller.connectivity
        )
        return controller
    }

    @discardableResult
    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(id: projectId, title: "Cedar deck", status: .accepted)
        project.companyId = companyId
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        id: String,
        project: Project,
        in context: ModelContext
    ) -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: project.id,
            taskTypeId: "44444444-4444-4444-8444-444444444444",
            companyId: companyId
        )
        task.project = project
        context.insert(task)
        return task
    }

    /// Proves the counter actually sees this context's saves before any test
    /// leans on a low count — a silent observer would make every save budget
    /// pass for the wrong reason.
    private func assertCounterObservesSaves(
        _ counter: SaveCounter,
        context: ModelContext,
        project: Project,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let restore = project.title
        project.title = restore + " (probe)"
        try context.save()
        project.title = restore
        try context.save()
        XCTAssertEqual(
            counter.count,
            2,
            "SaveCounter is not observing ModelContext.didSave",
            file: file,
            line: line
        )
    }
}

/// Counts `ModelContext.didSave` notifications raised by one context. SwiftData
/// posts the notification without identifying the context, so every save in the
/// process counts — the budgets these tests assert are therefore upper bounds,
/// never optimistic.
@MainActor
private final class SaveCounter {
    private(set) var count = 0
    private var observer: NSObjectProtocol?

    init(context: ModelContext) {
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }

    func reset() {
        count = 0
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
