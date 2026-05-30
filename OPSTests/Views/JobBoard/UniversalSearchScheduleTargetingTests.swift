//
//  UniversalSearchScheduleTargetingTests.swift
//  OPSTests
//
//  Regression coverage for Universal Search schedule quick actions.
//

import XCTest
@testable import OPS

final class UniversalSearchScheduleTargetingTests: XCTestCase {

    func testProjectQuickScheduleTargetsSingleActiveUnscheduledTask() {
        let project = Project(id: "project-1", title: "3400 Tillicum", status: .accepted)
        project.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        project.endDate = Date(timeIntervalSince1970: 1_801_000_000)

        let task = ProjectTask(
            id: "task-1",
            projectId: project.id,
            taskTypeId: "install",
            companyId: "company-1"
        )
        task.project = project
        project.tasks = [task]

        XCTAssertEqual(
            UniversalSearchScheduleTargeting.target(forProject: project),
            .task(task.id)
        )
    }

    func testProjectQuickScheduleTargetsSingleActiveScheduledTask() {
        let project = Project(id: "project-1", title: "Scheduled task", status: .accepted)
        let task = ProjectTask(
            id: "task-1",
            projectId: project.id,
            taskTypeId: "install",
            companyId: "company-1"
        )
        task.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        task.endDate = Date(timeIntervalSince1970: 1_800_086_400)
        task.project = project
        project.tasks = [task]

        XCTAssertEqual(
            UniversalSearchScheduleTargeting.target(forProject: project),
            .task(task.id)
        )
    }

    func testProjectQuickScheduleRequiresTaskChoiceWhenMultipleTaskCandidatesAreAmbiguous() {
        let project = Project(id: "project-1", title: "Multi task", status: .accepted)
        let first = ProjectTask(id: "task-1", projectId: project.id, taskTypeId: "demo", companyId: "company-1")
        let second = ProjectTask(id: "task-2", projectId: project.id, taskTypeId: "install", companyId: "company-1")
        first.project = project
        second.project = project
        project.tasks = [first, second]

        XCTAssertEqual(
            UniversalSearchScheduleTargeting.target(forProject: project),
            .chooseTask(project.id)
        )
    }

    func testProjectQuickScheduleIsUnavailableWithoutSchedulableTasks() {
        let project = Project(id: "project-1", title: "No tasks", status: .accepted)
        project.tasks = []

        XCTAssertEqual(
            UniversalSearchScheduleTargeting.target(forProject: project),
            .unavailable
        )
    }

    func testProjectQuickScheduleIgnoresDeletedAndTerminalTasks() {
        let project = Project(id: "project-1", title: "Inactive tasks", status: .accepted)
        let completed = ProjectTask(id: "task-1", projectId: project.id, taskTypeId: "demo", companyId: "company-1")
        let deleted = ProjectTask(id: "task-2", projectId: project.id, taskTypeId: "install", companyId: "company-1")
        completed.status = .completed
        deleted.deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        completed.project = project
        deleted.project = project
        project.tasks = [completed, deleted]

        XCTAssertEqual(
            UniversalSearchScheduleTargeting.target(forProject: project),
            .unavailable
        )
    }
}
