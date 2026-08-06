//
//  TrashRecoveryTests.swift
//  OPSTests
//
//  Regression coverage for the Settings > Trash recovery ledger. These tests
//  protect the visible contrast contract, thumbnail provenance, parent-safe
//  restore planning, and the save-before-queue durability boundary.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class TrashRecoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "feature.useDataActor")
        super.tearDown()
    }

    func testSelectedSegmentCountUsesReadableNeutralTokens() {
        let appearance = TrashSegmentAppearance.resolve(isSelected: true)

        XCTAssertEqual(appearance.segmentFill, .surfaceActive)
        XCTAssertEqual(appearance.labelInk, .text)
        XCTAssertEqual(appearance.countInk, .text)
        XCTAssertEqual(appearance.countFill, .fillNeutral)
        XCTAssertNotEqual(appearance.countInk, appearance.countFill)
    }

    func testInactiveSegmentCountRemainsNeutralInsteadOfUsingAccent() {
        let appearance = TrashSegmentAppearance.resolve(isSelected: false)

        XCTAssertEqual(appearance.segmentFill, .clear)
        XCTAssertEqual(appearance.labelInk, .text2)
        XCTAssertEqual(appearance.countInk, .text2)
        XCTAssertEqual(appearance.countFill, .fillNeutralDim)
        XCTAssertFalse(appearance.usesAccent)
    }

    func testProjectDescriptorUsesNewestRealGalleryPhotoAndTwoMetadataLines() {
        let project = makeProject(id: "project-1", title: "Cedar deck")
        project.setProjectImageURLs(["https://example.com/legacy.jpg"])
        let synced = ProjectPhoto(
            id: "photo-1",
            projectId: project.id,
            companyId: "company-1",
            url: "https://example.com/latest.jpg",
            uploadedBy: "00000000-0000-4000-8000-000000000001",
            createdAt: now.addingTimeInterval(-60)
        )

        let descriptor = TrashRecoveryRowDescriptor.project(
            project,
            syncedPhotos: [synced],
            now: now
        )

        XCTAssertEqual(descriptor.thumbnail, .projectPhoto("https://example.com/latest.jpg"))
        XCTAssertEqual(descriptor.metadataLines.count, 2)
    }

    func testClientDescriptorUsesProfilePhotoAndTwoMetadataLines() {
        let client = Client(
            id: "client-1",
            name: "Morgan Lee",
            email: "morgan@example.com",
            companyId: "company-1"
        )
        client.profileImageURL = "https://example.com/morgan.jpg"
        client.deletedAt = now.addingTimeInterval(-3_600)

        let descriptor = TrashRecoveryRowDescriptor.client(client, now: now)

        XCTAssertEqual(descriptor.thumbnail, .clientProfile("https://example.com/morgan.jpg"))
        XCTAssertEqual(descriptor.metadataLines.count, 2)
    }

    func testTaskDescriptorUsesItsProjectPhotoWhenAvailable() {
        let project = makeProject(id: "project-1", title: "Cedar deck", deleted: false)
        project.setProjectImageURLs(["https://example.com/site.jpg"])
        let task = makeTask(id: "task-1", project: project)

        let descriptor = TrashRecoveryRowDescriptor.task(
            task,
            projects: [project],
            syncedPhotos: [],
            now: now
        )

        XCTAssertEqual(descriptor.thumbnail, .projectPhoto("https://example.com/site.jpg"))
        XCTAssertEqual(descriptor.metadataLines.count, 2)
    }

    func testDeletedTaskWithActiveProjectIsReadyForInlineRestore() {
        let project = makeProject(id: "project-1", title: "Cedar deck", deleted: false)
        let task = makeTask(id: "task-1", project: project)

        let plan = TrashRecoveryPolicy.plan(for: task, projects: [project])

        XCTAssertEqual(plan.availability, .ready)
        XCTAssertEqual(plan.restoreOrder.map(\.kind), [.task])
    }

    func testDeletedTaskWithDeletedProjectRequiresOneCombinedRestore() {
        let project = makeProject(id: "project-1", title: "Cedar deck")
        let task = makeTask(id: "task-1", project: project)

        let plan = TrashRecoveryPolicy.plan(for: task, projects: [project])

        XCTAssertEqual(
            plan.availability,
            .parentRequired(
                TrashRecoveryEntityRef(kind: .project, id: project.id, title: project.title)
            )
        )
        XCTAssertEqual(plan.restoreOrder.map(\.kind), [.project, .task])
        XCTAssertEqual(plan.actionLabel, "RESTORE TASK + PROJECT")
    }

    func testDeletedTaskWithMissingProjectCannotProduceAnOrphan() {
        let task = ProjectTask(
            id: "task-1",
            projectId: "missing-project",
            taskTypeId: "task-type-1",
            companyId: "company-1"
        )
        task.customTitle = "Layout"
        task.deletedAt = now

        let plan = TrashRecoveryPolicy.plan(for: task, projects: [])

        XCTAssertEqual(plan.availability, .unsupported(.projectNotOnDevice))
        XCTAssertTrue(plan.restoreOrder.isEmpty)
    }

    func testRestoreSavesProjectBeforeQueueingExactNullTombstone() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
        let container = try makeContainer(allowsSave: true)
        let context = ModelContext(container)
        let project = makeProject(id: "project-1", title: "Cedar deck")
        context.insert(project)
        try context.save()

        let controller = configuredController(context: context)
        let result = try await controller.restoreTrash(
            TrashRecoveryPolicy.plan(for: project)
        )

        XCTAssertEqual(result.restored.map(\.kind), [.project])
        XCTAssertNil(project.deletedAt)
        XCTAssertTrue(project.needsSync)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let operation = try XCTUnwrap(operations.first)
        XCTAssertEqual(operation.entityType, SyncEntityType.project.rawValue)
        XCTAssertEqual(operation.entityId, project.id)
        XCTAssertEqual(operation.operationType, "update")
        let payload = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
        XCTAssertTrue(payload?["deleted_at"] is NSNull)
    }

    func testCombinedRestorePersistsParentAndTaskAndQueuesBoth() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
        let container = try makeContainer(allowsSave: true)
        let context = ModelContext(container)
        let project = makeProject(id: "project-1", title: "Cedar deck")
        let task = makeTask(id: "task-1", project: project)
        context.insert(project)
        context.insert(task)
        try context.save()

        let controller = configuredController(context: context)
        let result = try await controller.restoreTrash(
            TrashRecoveryPolicy.plan(for: task, projects: [project])
        )

        XCTAssertEqual(result.restored.map(\.kind), [.project, .task])
        XCTAssertNil(project.deletedAt)
        XCTAssertNil(task.deletedAt)
        XCTAssertTrue(project.needsSync)
        XCTAssertTrue(task.needsSync)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(Set(operations.map(\.entityType)), Set([
            SyncEntityType.project.rawValue,
            SyncEntityType.projectTask.rawValue,
        ]))
    }

    func testFailedLocalSaveRollsBackTombstoneAndNeverQueuesSuccess() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
        let container = try makeContainer(allowsSave: false)
        let context = ModelContext(container)
        let project = makeProject(id: "project-1", title: "Cedar deck")
        let originalDeletedAt = try XCTUnwrap(project.deletedAt)
        context.insert(project)

        let controller = configuredController(context: context)

        do {
            _ = try await controller.restoreTrash(TrashRecoveryPolicy.plan(for: project))
            XCTFail("A disabled persistent store must reject the restore")
        } catch {
            XCTAssertNotNil(error as? TrashRestoreError)
        }

        XCTAssertEqual(project.deletedAt, originalDeletedAt)
        XCTAssertFalse(project.needsSync)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertTrue(operations.isEmpty)
    }

    func testMissingRecordDuringCombinedRecoveryRollsBackEarlierMutations() async throws {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
        let container = try makeContainer(allowsSave: true)
        let context = ModelContext(container)
        let project = makeProject(id: "project-1", title: "Cedar deck")
        let originalDeletedAt = try XCTUnwrap(project.deletedAt)
        context.insert(project)
        try context.save()

        let projectRef = TrashRecoveryEntityRef(
            kind: .project,
            id: project.id,
            title: project.title
        )
        let missingClientRef = TrashRecoveryEntityRef(
            kind: .client,
            id: "missing-client",
            title: "Missing client"
        )
        let malformedPlan = TrashRecoveryPlan(
            primary: projectRef,
            availability: .ready,
            restoreOrder: [projectRef, missingClientRef]
        )

        let controller = configuredController(context: context)
        do {
            _ = try await controller.restoreTrash(malformedPlan)
            XCTFail("A partial recovery must never commit when a later record is missing")
        } catch let error as TrashRestoreError {
            guard case .entityNotOnDevice(.client) = error else {
                return XCTFail("Expected missing client error, got \(error)")
            }
        }

        XCTAssertEqual(project.deletedAt, originalDeletedAt)
        XCTAssertFalse(project.needsSync)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertTrue(operations.isEmpty)
    }

    // MARK: - Fixtures

    private func makeProject(
        id: String,
        title: String,
        deleted: Bool = true
    ) -> Project {
        let project = Project(id: id, title: title, status: .accepted)
        project.companyId = "company-1"
        project.address = "101 Cedar Street"
        project.deletedAt = deleted ? now.addingTimeInterval(-86_400) : nil
        return project
    }

    private func makeTask(id: String, project: Project) -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: project.id,
            taskTypeId: "task-type-1",
            companyId: "company-1"
        )
        task.customTitle = "Layout"
        task.project = project
        task.deletedAt = now.addingTimeInterval(-3_600)
        return task
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

    private func makeContainer(allowsSave: Bool) throws -> ModelContainer {
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
            allowsSave: allowsSave
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
