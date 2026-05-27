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
}
