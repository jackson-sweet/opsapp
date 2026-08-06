//
//  ProjectDetailsInfoRowTests.swift
//  OPSTests
//
//  The Project Details document has one stable reading order. Status belongs
//  inside that document and is interactive only for an authorized editor.
//

import XCTest
@testable import OPS

final class ProjectDetailsInfoRowTests: XCTestCase {

    func testDetailsDocumentBeginsWithExactlyOneStatusRow() {
        let labels = ProjectInfoRow.allCases.map(\.label)

        XCTAssertEqual(labels.first, "STATUS")
        XCTAssertEqual(labels.filter { $0 == "STATUS" }.count, 1)
        XCTAssertEqual(ProjectInfoDoc.labels, labels)
    }

    func testStatusChangeActionRequiresBothEditPermissionAndAHandler() {
        XCTAssertTrue(ProjectStatusRowPolicy.canChangeStatus(canEdit: true, hasAction: true))
        XCTAssertFalse(ProjectStatusRowPolicy.canChangeStatus(canEdit: false, hasAction: true))
        XCTAssertFalse(ProjectStatusRowPolicy.canChangeStatus(canEdit: true, hasAction: false))
        XCTAssertFalse(ProjectStatusRowPolicy.canChangeStatus(canEdit: false, hasAction: false))
    }
}
