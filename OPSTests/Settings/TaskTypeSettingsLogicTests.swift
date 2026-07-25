//
//  TaskTypeSettingsLogicTests.swift
//  OPSTests
//
//  Regression coverage for Settings.Tasks list behavior.
//

import XCTest
@testable import OPS

final class TaskTypeSettingsLogicTests: XCTestCase {

    func testVisibleTaskTypesExcludeSoftDeletedRows() {
        let active = TaskType(id: "active", display: "Install", color: "#93A17C", companyId: "company-a")
        let deleted = TaskType(id: "deleted", display: "Old", color: "#93A17C", companyId: "company-a")
        deleted.deletedAt = Date()

        let visible = TaskTypeSettingsLogic.visibleTaskTypes(
            [active, deleted],
            companyId: "company-a"
        )

        XCTAssertEqual(visible.map(\.id), ["active"])
    }

    func testSortedTaskTypesKeepCustomTypesBeforeNavigableDefaults() {
        let defaultType = TaskType(
            id: "default",
            display: "Completion",
            color: "#93A17C",
            companyId: "company-a",
            isDefault: true
        )
        let secondCustom = TaskType(
            id: "custom-b",
            display: "Quote",
            color: "#93A17C",
            companyId: "company-a"
        )
        let firstCustom = TaskType(
            id: "custom-a",
            display: "Install",
            color: "#93A17C",
            companyId: "company-a"
        )

        let sorted = TaskTypeSettingsLogic.sortedTaskTypes(
            [defaultType, secondCustom, firstCustom]
        )

        XCTAssertEqual(sorted.map(\.id), ["custom-a", "custom-b", "default"])
        XCTAssertTrue(sorted.last?.isDefault == true)
    }

    func testActiveTaskCountUsesCanonicalScalarReference() {
        let type = TaskType(
            id: "install",
            display: "Install",
            color: "#93A17C",
            companyId: "company-a"
        )
        let active = ProjectTask(
            id: "active",
            projectId: "project",
            taskTypeId: "INSTALL",
            companyId: "company-a"
        )
        let deleted = ProjectTask(
            id: "deleted",
            projectId: "project",
            taskTypeId: type.id,
            companyId: "company-a"
        )
        deleted.deletedAt = Date()
        let otherCompany = ProjectTask(
            id: "other-company",
            projectId: "project",
            taskTypeId: type.id,
            companyId: "company-b"
        )
        let otherType = ProjectTask(
            id: "other-type",
            projectId: "project",
            taskTypeId: "quote",
            companyId: "company-a"
        )

        // Deliberately leave `type.tasks` empty. The relationship can lag after
        // imports and reassignments; the scalar task_type_id is authoritative.
        XCTAssertEqual(
            TaskTypeSettingsLogic.activeTaskCount(
                for: type,
                in: [active, deleted, otherCompany, otherType]
            ),
            1
        )

        XCTAssertEqual(
            TaskTypeSettingsLogic.tasksUsing(
                type,
                in: [active, deleted, otherCompany, otherType]
            ).map(\.id),
            ["active"]
        )
    }

    func testEmptyCacheRequiresAuthoritativeRemoteOutcome() {
        XCTAssertEqual(
            TaskTypeSettingsLogic.loadState(
                hasCachedTaskTypes: false,
                remoteRefreshSucceeded: nil
            ),
            .loading
        )
        XCTAssertEqual(
            TaskTypeSettingsLogic.loadState(
                hasCachedTaskTypes: false,
                remoteRefreshSucceeded: true
            ),
            .loaded
        )
        XCTAssertEqual(
            TaskTypeSettingsLogic.loadState(
                hasCachedTaskTypes: false,
                remoteRefreshSucceeded: false
            ),
            .failed
        )
    }

    func testCachedTaskTypesRemainUsableWhenRemoteRefreshFails() {
        XCTAssertEqual(
            TaskTypeSettingsLogic.loadState(
                hasCachedTaskTypes: true,
                remoteRefreshSucceeded: false
            ),
            .loaded
        )
    }
}
