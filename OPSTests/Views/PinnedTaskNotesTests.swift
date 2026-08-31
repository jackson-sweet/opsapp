//
//  PinnedTaskNotesTests.swift
//  OPSTests
//
//  Bug 6854b7b8 — a cancelled task's note stayed pinned in the project
//  activity brief. The brief is standing instructions: cancelled work has
//  none, completed work keeps its (faded, last), and nothing is ever
//  deleted — a reactivated task re-pins automatically because the brief is
//  derived from the task rows, never stored.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PinnedTaskNotesTests: XCTestCase {

    /// A ModelContext does not keep its container alive — retain it for the
    /// case lifetime (see SyncCrossEntityDependencyTests.retainedContainers).
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - The rule

    func testCancelledTasksAreExcludedFromTheBrief() throws {
        let context = try makeContext()
        _ = makeTask(id: "t-active", status: .active, notes: "Glass rail along front edge", displayOrder: 0, in: context)
        _ = makeTask(id: "t-cancelled", status: .cancelled, notes: "Please drop off samples for Rose", displayOrder: 1, in: context)

        let entries = PinnedTaskNotesBuilder.entries(from: try fetchAll(context))

        XCTAssertEqual(
            entries.map(\.id), ["t-active"],
            "A cancelled task's instruction is void — it must leave the standing brief (bug 6854b7b8)."
        )
    }

    func testCompletedTasksStayPinnedLastAndCancelledStillLeaves() throws {
        let context = try makeContext()
        _ = makeTask(id: "t-completed", status: .completed, notes: "Torch down membrane first", displayOrder: 0, in: context)
        _ = makeTask(id: "t-active", status: .active, notes: "Check gate code 4411", displayOrder: 1, in: context)
        _ = makeTask(id: "t-cancelled", status: .cancelled, notes: "Old scope", displayOrder: 2, in: context)

        let entries = PinnedTaskNotesBuilder.entries(from: try fetchAll(context))

        XCTAssertEqual(
            entries.map(\.id), ["t-active", "t-completed"],
            "Completed keeps its faded, sorted-last pin; only cancelled leaves."
        )
        XCTAssertEqual(
            entries.last?.isTerminal, true,
            "The completed entry must still read as terminal so the card fades it."
        )
    }

    func testBlankNotesAndDeletedTasksNeverPin() throws {
        let context = try makeContext()
        _ = makeTask(id: "t-blank", status: .active, notes: "   \n", displayOrder: 0, in: context)
        _ = makeTask(id: "t-deleted", status: .active, notes: "Ghost", displayOrder: 1, deletedAt: Date(), in: context)

        XCTAssertTrue(PinnedTaskNotesBuilder.entries(from: try fetchAll(context)).isEmpty)
    }

    /// The note text itself is never destroyed — only the pin releases.
    func testCancelledTaskKeepsItsNoteOnTheTask() throws {
        let context = try makeContext()
        let task = makeTask(id: "t-1", status: .cancelled, notes: "Samples for Rose", displayOrder: 0, in: context)

        XCTAssertTrue(PinnedTaskNotesBuilder.entries(from: [task]).isEmpty)
        XCTAssertEqual(
            task.taskNotes, "Samples for Rose",
            "Unpinning must not touch the note the operator wrote."
        )
    }

    /// Reactivation re-pins with zero ceremony — the brief is derived state.
    func testReactivatedTaskRepins() throws {
        let context = try makeContext()
        let task = makeTask(id: "t-1", status: .cancelled, notes: "Back on", displayOrder: 0, in: context)

        XCTAssertTrue(PinnedTaskNotesBuilder.entries(from: [task]).isEmpty)
        task.status = .active
        XCTAssertEqual(PinnedTaskNotesBuilder.entries(from: [task]).map(\.id), ["t-1"])
    }

    // MARK: - Fixtures

    private func makeTask(
        id: String,
        status: TaskStatus,
        notes: String?,
        displayOrder: Int,
        deletedAt: Date? = nil,
        in context: ModelContext
    ) -> ProjectTask {
        let task = ProjectTask(
            id: id, projectId: "p-1", taskTypeId: "tt-1",
            companyId: "co", status: status
        )
        task.taskNotes = notes
        task.displayOrder = displayOrder
        task.deletedAt = deletedAt
        context.insert(task)
        return task
    }

    private func fetchAll(_ context: ModelContext) throws -> [ProjectTask] {
        try context.fetch(FetchDescriptor<ProjectTask>())
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
            SyncOperation.self,
            CalendarUserEvent.self,
            SiteVisit.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return ModelContext(container)
    }
}
