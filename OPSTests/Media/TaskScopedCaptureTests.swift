//
//  TaskScopedCaptureTests.swift
//  OPSTests
//
//  Bug a290934f — a photo shot FROM a task documents that task.
//
//  The camera screen is the only place that knows which task the crew was on.
//  If the app dies between the shutter and the accept, that knowledge has to
//  survive on disk or the photo comes back as an ordinary project photo and the
//  crew has to re-tag it from memory. The durable capture receipt carries it:
//  the owner context is `project:<id>#task:<task id>`, and the accept path
//  reads the link back OFF the receipt rather than trusting whatever the caller
//  says — a caller that disagrees with the receipt is an identity fault.
//

import SwiftData
import UIKit
import XCTest
@testable import OPS

@MainActor
final class TaskScopedCaptureTests: XCTestCase {
    private var container: ModelContainer!
    private let companyID = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let userID = "283d49df-90a1-4abb-b94c-3e9f17f02c0d"
    private let taskID = "2b0004b3-4696-49c5-9c74-8bd65bc66c39"
    private let otherTaskID = "c5ec37fc-bec1-41a9-aac4-855db9feb07e"

    private func context() throws -> ModelContext {
        let schema = Schema([Project.self, ProjectTask.self, TaskType.self, TaskTypeReminder.self,
            TaskReminder.self, User.self, Client.self, SubClient.self, ProjectNote.self, ProjectPhoto.self,
            SyncOperation.self, ProjectVinylOrderMarker.self, ProjectPrimaryContactSelection.self, Opportunity.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func project(in context: ModelContext) throws -> Project {
        let project = Project(id: UUID().uuidString.lowercased(), title: "541 Prince Robert Ln", status: .inProgress)
        project.companyId = companyID
        context.insert(project)
        try context.save()
        return project
    }

    private func batch(for project: Project, kind: String = "project", taskID: String? = nil) -> StagedCaptureBatch {
        let id = UUID().uuidString.lowercased()
        return StagedCaptureBatch(
            id: UUID().uuidString.lowercased(),
            owner: StagedPhotoDestinations.owner(
                companyID: companyID, userID: userID, kind: kind, id: project.id, taskID: taskID
            ),
            items: [.init(
                id: id,
                localURL: "local://project_images/capture_\(id).jpg",
                originalLocalURL: "local://project_images/capture_\(id).original",
                capturedAt: Date(),
                pixelWidth: 80,
                pixelHeight: 40
            )]
        )
    }

    private func accept(
        _ batch: StagedCaptureBatch,
        project: Project,
        context: ModelContext,
        taskID: String? = nil
    ) async -> Bool {
        await StagedPhotoDestinations.acceptProject(
            batch, project: project, userID: userID, context: context,
            imageSyncManager: nil, taskID: taskID,
            activeUserID: { self.userID }, activeCompanyID: { self.companyID }
        )
    }

    // MARK: - The durable receipt

    func testOwnerContextCarriesTheTaskAndRoundTrips() {
        let owner = StagedPhotoDestinations.owner(
            companyID: companyID, userID: userID, kind: "project",
            id: "E3CF8105-3E83-4126-9AA1-16EBCFD096F5", taskID: "2B0004B3-4696-49C5-9C74-8BD65BC66C39"
        )
        XCTAssertEqual(
            owner.contextID,
            "project:e3cf8105-3e83-4126-9aa1-16ebcfd096f5#task:2b0004b3-4696-49c5-9c74-8bd65bc66c39"
        )

        let parsed = StagedPhotoDestinations.parseProjectContext(owner.contextID)
        XCTAssertEqual(parsed?.kind, "project")
        XCTAssertEqual(parsed?.projectID, "e3cf8105-3e83-4126-9aa1-16ebcfd096f5")
        XCTAssertEqual(parsed?.taskID, "2b0004b3-4696-49c5-9c74-8bd65bc66c39")
    }

    func testWholeProjectContextsStillParseUnchanged() {
        let plain = StagedPhotoDestinations.parseProjectContext("project:e3cf8105-3e83-4126-9aa1-16ebcfd096f5")
        XCTAssertEqual(plain?.kind, "project")
        XCTAssertEqual(plain?.projectID, "e3cf8105-3e83-4126-9aa1-16ebcfd096f5")
        XCTAssertNil(plain?.taskID)

        let draft = StagedPhotoDestinations.parseProjectContext("project-draft:e3cf8105-3e83-4126-9aa1-16ebcfd096f5")
        XCTAssertEqual(draft?.kind, "project-draft", "`project-draft` must not be read as `project` plus a stray suffix")
        XCTAssertEqual(draft?.projectID, "e3cf8105-3e83-4126-9aa1-16ebcfd096f5")
        XCTAssertNil(draft?.taskID)

        let draftWithTask = StagedPhotoDestinations.parseProjectContext(
            "project-draft:e3cf8105-3e83-4126-9aa1-16ebcfd096f5#task:2b0004b3-4696-49c5-9c74-8bd65bc66c39"
        )
        XCTAssertEqual(draftWithTask?.kind, "project-draft")
        XCTAssertEqual(draftWithTask?.taskID, "2b0004b3-4696-49c5-9c74-8bd65bc66c39")
    }

    func testForeignAndMalformedContextsAreNotProjectDestinations() {
        XCTAssertNil(StagedPhotoDestinations.parseProjectContext("lead:1234"))
        XCTAssertNil(StagedPhotoDestinations.parseProjectContext("project:"))
        XCTAssertNil(StagedPhotoDestinations.parseProjectContext("project:abc#task:"))
        XCTAssertNil(StagedPhotoDestinations.parseProjectContext("project:abc#task:x#task:y"))
        XCTAssertNil(StagedPhotoDestinations.parseProjectContext(""))
    }

    func testOwnerWithoutATaskIsUnchangedFromTheWholeProjectForm() {
        let owner = StagedPhotoDestinations.owner(companyID: companyID, userID: userID, kind: "project", id: "ABC")
        XCTAssertEqual(owner.contextID, "project:abc")

        let blank = StagedPhotoDestinations.owner(
            companyID: companyID, userID: userID, kind: "project", id: "ABC", taskID: "   "
        )
        XCTAssertEqual(blank.contextID, "project:abc", "A blank task is no task, not an empty suffix")
    }

    // MARK: - Accepting a task-scoped batch

    func testTaskScopedBatchStampsTheLinkOnTheLocalRow() async throws {
        let context = try context()
        let project = try project(in: context)
        let batch = batch(for: project, taskID: taskID.uppercased())

        let accepted = await accept(batch, project: project, context: context)
        XCTAssertTrue(accepted)

        let rows = try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.taskId, taskID, "The link is stored lowercased so it matches the task it names")
        XCTAssertEqual(rows.first?.projectId, project.id)
    }

    func testWholeProjectBatchLeavesThePhotoUnlinked() async throws {
        let context = try context()
        let project = try project(in: context)

        let accepted = await accept(batch(for: project), project: project, context: context)
        XCTAssertTrue(accepted)

        let rows = try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first?.taskId)
    }

    func testACallerThatNamesADifferentTaskThanTheReceiptIsRejected() async throws {
        let context = try context()
        let project = try project(in: context)
        let batch = batch(for: project, taskID: taskID)

        let mismatched = await accept(batch, project: project, context: context, taskID: otherTaskID)
        XCTAssertFalse(mismatched, "The receipt is the durable record; a caller may not overrule it")
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>()).isEmpty)

        let agreeing = await accept(batch, project: project, context: context, taskID: taskID.uppercased())
        XCTAssertTrue(agreeing, "Stating the same task the receipt names is fine, whatever the casing")
    }

    func testABatchForAnotherProjectIsStillRejectedWithATaskAttached() async throws {
        let context = try context()
        let project = try project(in: context)
        let foreign = StagedCaptureBatch(
            id: UUID().uuidString.lowercased(),
            owner: StagedPhotoDestinations.owner(
                companyID: companyID, userID: userID, kind: "project",
                id: "00000000-0000-0000-0000-0000000000ff", taskID: taskID
            ),
            items: batch(for: project, taskID: taskID).items
        )

        let rejected = await accept(foreign, project: project, context: context)
        XCTAssertFalse(rejected)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>()).isEmpty)
    }

    /// A replay must not undo a reassignment. Between the first accept and a
    /// recovery replay the crew may have pointed the photo at a different task
    /// in the viewer; re-stamping the receipt's task would silently revert it.
    func testReplayDoesNotRewriteALinkChangedSinceTheFirstAccept() async throws {
        let context = try context()
        let project = try project(in: context)
        let batch = batch(for: project, taskID: taskID)

        let firstAccept = await accept(batch, project: project, context: context)
        XCTAssertTrue(firstAccept)

        let reassignContext = ModelContext(container)
        let row = try XCTUnwrap(reassignContext.fetch(FetchDescriptor<ProjectPhoto>()).first)
        row.applyTaskLink(otherTaskID)
        try reassignContext.save()

        let replayed = await accept(batch, project: project, context: context)
        XCTAssertTrue(replayed, "A replay is still accepted")

        let rows = try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.taskId, otherTaskID, "The deliberate reassignment survives the replay")
    }

    // MARK: - Delivery carries the link

    func testHandoffInsertCarriesTheLinkAndOmitsItWhenThereIsNone() throws {
        let context = try context()
        let project = try project(in: context)

        let linked = ProjectPhoto(
            id: UUID().uuidString.lowercased(), projectId: project.id, companyId: companyID,
            url: "local://project_images/capture_a.jpg", source: "site_visit",
            taskId: taskID.uppercased(), uploadedBy: userID
        )
        context.insert(linked)
        let unlinked = ProjectPhoto(
            id: UUID().uuidString.lowercased(), projectId: project.id, companyId: companyID,
            url: "local://project_images/capture_b.jpg", source: "site_visit", uploadedBy: userID
        )
        context.insert(unlinked)
        try context.save()

        let remote = "https://cdn.example/a.jpg"
        let withTask = ImageSyncManager.handoffPhotoInsert(for: linked, remoteURL: remote)
        XCTAssertEqual(withTask.taskId, taskID)

        let withoutTask = ImageSyncManager.handoffPhotoInsert(for: unlinked, remoteURL: remote)
        XCTAssertNil(withoutTask.taskId, "A site-visit handoff predates the project's tasks and links to none")

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(withTask)) as? [String: Any]
        XCTAssertEqual(encoded?["task_id"] as? String, taskID, "The wire name is the column name")
    }
}
