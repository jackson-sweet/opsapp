//
//  ClientSearchActionsUITests.swift
//  OPSUITests
//
//  Native-gesture regression proof for bug 9a8bbe5e.
//

import XCTest

final class ClientSearchActionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(readOnly: Bool = false) {
        app.launchArguments = ["-OPS_CLIENT_SEARCH_ACTIONS_QA"]
        if readOnly {
            app.launchArguments.append("-OPS_CLIENT_SEARCH_ACTIONS_QA_READ_ONLY")
        }
        app.launch()
        XCTAssertTrue(
            row.waitForExistence(timeout: 20),
            "Universal Search client-row QA host did not render"
        )
    }

    private var row: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "qa_client_search_row")
            .firstMatch
    }

    private var lastAction: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "qa_client_search_last_action")
            .firstMatch
    }

    func testClientRowLongPressShowsAuthorizedActionsAndDispatchesSelection() {
        launch()

        row.press(forDuration: 1.3)

        XCTAssertTrue(app.buttons["View Client"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Project"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)

        app.buttons["Add Project"].tap()
        let actionLanded = NSPredicate(format: "label CONTAINS %@", "LAST_ACTION::add")
        expectation(for: actionLanded, evaluatedWith: lastAction)
        waitForExpectations(timeout: 5)
    }

    func testReadOnlyClientRowDoesNotExposeUnauthorizedActions() {
        launch(readOnly: true)
        row.press(forDuration: 1.3)

        XCTAssertTrue(app.buttons["View Client"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add Project"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
    }
}
