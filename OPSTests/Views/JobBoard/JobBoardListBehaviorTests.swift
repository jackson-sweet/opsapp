//
//  JobBoardListBehaviorTests.swift
//  OPSTests
//
//  Regression coverage for JobBoard list filtering, client/contact ordering,
//  and scroll-vs-swipe gesture classification.
//

import XCTest
@testable import OPS

final class JobBoardListBehaviorTests: XCTestCase {

    func testJobBoardVisibleTasksExcludeTasksFromArchivedClosedCompletedAndDeletedProjects() {
        let activeProject = makeProject(id: "active", status: .inProgress)
        let archivedProject = makeProject(id: "archived", status: .archived)
        let closedProject = makeProject(id: "closed", status: .closed)
        let completedProject = makeProject(id: "completed", status: .completed)
        let deletedProject = makeProject(id: "deleted", status: .inProgress, deletedAt: Date(timeIntervalSince1970: 10))

        let visible = makeTask(id: "visible", project: activeProject)
        _ = makeTask(id: "archived-hidden", project: archivedProject)
        _ = makeTask(id: "closed-hidden", project: closedProject)
        _ = makeTask(id: "completed-hidden", project: completedProject)
        _ = makeTask(id: "deleted-hidden", project: deletedProject)

        let result = JobBoardTaskFiltering.visibleTasks(from: [
            activeProject,
            archivedProject,
            closedProject,
            completedProject,
            deletedProject
        ])

        XCTAssertEqual(result.map(\.id), [visible.id])
    }

    func testJobBoardVisibleTasksDeduplicateByTaskIdKeepingFirstVisibleTask() {
        let firstProject = makeProject(id: "first", status: .accepted)
        let secondProject = makeProject(id: "second", status: .inProgress)
        _ = makeTask(id: "shared-task", project: firstProject)
        _ = makeTask(id: "shared-task", project: secondProject)

        let result = JobBoardTaskFiltering.visibleTasks(from: [firstProject, secondProject])

        XCTAssertEqual(result.map(\.projectId), [firstProject.id])
        XCTAssertEqual(result.map(\.id), ["shared-task"])
    }

    func testClientProjectOrderingKeepsActiveProjectsBeforeClosedAndArchivedProjects() {
        let oldActive = makeProject(id: "old-active", status: .rfq, start: Date(timeIntervalSince1970: 100))
        let newActive = makeProject(id: "new-active", status: .completed, start: Date(timeIntervalSince1970: 300))
        let closed = makeProject(id: "closed", status: .closed, start: Date(timeIntervalSince1970: 900))
        let archived = makeProject(id: "archived", status: .archived, start: Date(timeIntervalSince1970: 1_000))

        let result = ProjectListOrdering.activeFirst([archived, oldActive, closed, newActive])

        XCTAssertEqual(result.map(\.id), ["new-active", "old-active", "closed", "archived"])
    }

    func testClientProjectOrderingDropsSoftDeletedProjects() {
        let visible = makeProject(id: "visible", status: .accepted)
        let deleted = makeProject(id: "deleted", status: .accepted, deletedAt: Date(timeIntervalSince1970: 10))

        let result = ProjectListOrdering.activeFirst([deleted, visible])

        XCTAssertEqual(result.map(\.id), [visible.id])
    }

    func testDragClassifierRequiresHorizontalDominanceBeforeSwipe() {
        XCTAssertEqual(
            DirectionalDragClassifier.axis(forTranslation: CGSize(width: 44, height: 20)),
            .vertical
        )
        XCTAssertEqual(
            DirectionalDragClassifier.axis(forTranslation: CGSize(width: 72, height: 14)),
            .horizontal
        )
        XCTAssertEqual(
            DirectionalDragClassifier.axis(forTranslation: CGSize(width: 8, height: 2)),
            .undecided
        )
    }

    private func makeProject(
        id: String,
        status: Status,
        start: Date? = nil,
        deletedAt: Date? = nil
    ) -> Project {
        let project = Project(id: id, title: id, status: status)
        project.startDate = start
        project.deletedAt = deletedAt
        return project
    }

    @discardableResult
    private func makeTask(id: String, project: Project) -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: project.id,
            taskTypeId: "task-type",
            companyId: "company"
        )
        task.project = project
        project.tasks.append(task)
        return task
    }
}
