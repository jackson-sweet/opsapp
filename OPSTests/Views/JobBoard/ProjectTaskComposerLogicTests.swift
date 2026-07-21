import XCTest
@testable import OPS

final class ProjectTaskComposerLogicTests: XCTestCase {
    func testTaskFromSuggestionPreservesSuggestedTypeAndCrew() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let suggestion = TaskSuggestion(
            taskTypeId: "task-type-1",
            teamMemberIds: ["crew-1", "crew-2"],
            score: 3,
            mostRecentAt: .distantPast
        )

        let task = ProjectTaskComposerLogic.task(from: suggestion, id: id)

        XCTAssertEqual(task.id, id)
        XCTAssertEqual(task.taskTypeId, "task-type-1")
        XCTAssertEqual(task.teamMemberIds, ["crew-1", "crew-2"])
        XCTAssertEqual(task.status, .active)
    }

    func testSavingEditReplacesMatchingRowWithoutReordering() {
        let firstId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let secondId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = LocalTask(id: firstId, taskTypeId: "first", status: .active)
        let second = LocalTask(id: secondId, taskTypeId: "second", status: .active)
        var editedFirst = first
        editedFirst.taskTypeId = "edited"

        let result = ProjectTaskComposerLogic.saving(editedFirst, in: [first, second])

        XCTAssertEqual(result.map(\.id), [firstId, secondId])
        XCTAssertEqual(result.first?.taskTypeId, "edited")
    }

    func testSavingNewTaskAppendsIt() {
        let existing = LocalTask(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            taskTypeId: "first",
            status: .active
        )
        let added = LocalTask(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            taskTypeId: "second",
            status: .active
        )

        let result = ProjectTaskComposerLogic.saving(added, in: [existing])

        XCTAssertEqual(result, [existing, added])
    }

    func testProjectSaveIncludesValidPendingTask() {
        let committed = LocalTask(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            taskTypeId: "committed-type",
            status: .active
        )
        let pending = LocalTask(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            taskTypeId: "pending-type",
            status: .active,
            teamMemberIds: ["crew-1"]
        )

        let result = ProjectTaskComposerLogic.tasksForParentSave(
            committedTasks: [committed],
            pendingTask: pending,
            validTaskTypeIds: ["committed-type", "pending-type"]
        )

        XCTAssertEqual(result, [committed, pending])
    }

    func testProjectSaveIgnoresPendingTaskWithoutValidType() {
        let committed = LocalTask(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            taskTypeId: "committed-type",
            status: .active
        )
        let pending = LocalTask(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            taskTypeId: "",
            status: .active
        )

        let result = ProjectTaskComposerLogic.tasksForParentSave(
            committedTasks: [committed],
            pendingTask: pending,
            validTaskTypeIds: ["committed-type"]
        )

        XCTAssertEqual(result, [committed])
    }

    func testProjectSaveIgnoresPendingTaskWhenComposerIsCollapsed() {
        let committed = LocalTask(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            taskTypeId: "committed-type",
            status: .active
        )
        let hiddenPending = LocalTask(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            taskTypeId: "pending-type",
            status: .active
        )

        let result = ProjectTaskComposerLogic.tasksForParentSave(
            committedTasks: [committed],
            pendingTask: hiddenPending,
            pendingTaskIsVisible: false,
            validTaskTypeIds: ["committed-type", "pending-type"]
        )

        XCTAssertEqual(result, [committed])
    }

    func testProjectSaveReplacesEditedTaskWithoutDuplicatingIt() {
        let taskId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let original = LocalTask(
            id: taskId,
            taskTypeId: "original-type",
            status: .active
        )
        let edited = LocalTask(
            id: taskId,
            taskTypeId: "edited-type",
            status: .completed,
            teamMemberIds: ["crew-1"]
        )

        let result = ProjectTaskComposerLogic.tasksForParentSave(
            committedTasks: [original],
            pendingTask: edited,
            validTaskTypeIds: ["original-type", "edited-type"]
        )

        XCTAssertEqual(result, [edited])
    }

    func testRemovingTaskOnlyRemovesMatchingRow() {
        let first = LocalTask(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            taskTypeId: "first",
            status: .active
        )
        let second = LocalTask(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            taskTypeId: "second",
            status: .active
        )

        let result = ProjectTaskComposerLogic.removing(taskId: first.id, from: [first, second])

        XCTAssertEqual(result, [second])
    }
}
