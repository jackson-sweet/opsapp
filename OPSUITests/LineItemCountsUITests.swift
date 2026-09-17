//
//  LineItemCountsUITests.swift
//  OPSUITests
//
//  Drives the REAL line item sheet through `LineItemCountsQAHost`: a count
//  option starts blank, a blank count blocks the save and is named, an entered
//  0 is kept and lets the line save, and an existing line keeps the counts it
//  carries while the ones it never had read blank.
//

import XCTest

final class LineItemCountsUITests: XCTestCase {
    private var app: XCUIApplication!

    private let countIds = ["qa_opt_left", "qa_opt_right", "qa_opt_corners", "qa_opt_45", "qa_opt_wall"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(existingLine: Bool) {
        app.launchArguments = ["-OPS_LINE_ITEM_COUNTS_QA"]
        if existingLine {
            app.launchArguments.append("-OPS_LINE_ITEM_COUNTS_QA_EDIT")
        }
        app.launch()
        XCTAssertTrue(
            countValue("qa_opt_left").waitForExistence(timeout: 20),
            "line item sheet did not render its count options"
        )
    }

    // MARK: - Elements

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func countValue(_ optionId: String) -> XCUIElement {
        element("line_item_count_\(optionId)_value")
    }

    private func decrement(_ optionId: String) -> XCUIElement {
        element("line_item_count_\(optionId)_decrement")
    }

    private func increment(_ optionId: String) -> XCUIElement {
        element("line_item_count_\(optionId)_increment")
    }

    private var missingPrompt: XCUIElement {
        element("line_item_missing_options_message")
    }

    private var sheetState: XCUIElement {
        element("qa_line_item_sheet_state")
    }

    private func revealCounts() {
        app.scrollViews.firstMatch.swipeUp()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapPrimary(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(label) button missing")
        button.tap()
    }

    /// Polls the element's label directly. An `XCTNSPredicateExpectation`
    /// timed out here on a loaded machine while the label already read the
    /// expected value, so this re-reads the live element instead.
    private func waitForLabel(_ element: XCUIElement, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if element.exists, element.label == label { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        XCTFail(
            "expected \(element) to read \(label), read \(element.exists ? element.label : "<missing>")",
            file: file,
            line: line
        )
    }

    // MARK: - New line

    func testNewLineCountsStartBlankBlockTheSaveAndSaveOnceEnteredIncludingZero() {
        launch(existingLine: false)
        revealCounts()

        // 1. Every count reads "not entered" — never 0, never the catalogue default.
        for id in countIds {
            waitForLabel(countValue(id), "Not entered")
        }
        attachScreenshot(named: "01-new-line-blank-counts")

        // 2. Saving with blank counts is refused, and the refusal names them.
        tapPrimary("ADD LINE ITEM")
        XCTAssertTrue(missingPrompt.waitForExistence(timeout: 5), "blocked-save prompt did not appear")
        XCTAssertEqual(
            missingPrompt.label,
            "Left ends, Right ends, Corners, 45° corners, Wall returns. Required to save."
        )
        XCTAssertTrue(app.buttons["ADD LINE ITEM"].exists, "a blocked save must keep the sheet open")
        attachScreenshot(named: "02-new-line-blocked-save")

        // 3. Enter every count, two of them 0 — one tap each from blank.
        increment("qa_opt_left").tap()
        increment("qa_opt_right").tap()
        decrement("qa_opt_corners").tap()
        decrement("qa_opt_45").tap()
        increment("qa_opt_wall").tap()
        increment("qa_opt_wall").tap()

        waitForLabel(countValue("qa_opt_left"), "1")
        waitForLabel(countValue("qa_opt_right"), "1")
        waitForLabel(countValue("qa_opt_corners"), "0")
        waitForLabel(countValue("qa_opt_45"), "0")
        waitForLabel(countValue("qa_opt_wall"), "2")
        XCTAssertFalse(decrement("qa_opt_corners").isEnabled, "0 is the floor")
        XCTAssertFalse(missingPrompt.exists, "the prompt clears once every count is entered")
        attachScreenshot(named: "03-new-line-counts-entered-with-zero")

        // 4. The save goes through.
        tapPrimary("ADD LINE ITEM")
        XCTAssertTrue(sheetState.waitForExistence(timeout: 5), "the sheet did not close after a valid save")
        waitForLabel(sheetState, "SHEET CLOSED")
    }

    // MARK: - Existing line

    func testExistingLineKeepsItsCountsAndShowsMissingCountsBlank() {
        launch(existingLine: true)
        revealCounts()

        waitForLabel(countValue("qa_opt_left"), "2")
        waitForLabel(countValue("qa_opt_right"), "0")
        waitForLabel(countValue("qa_opt_corners"), "Not entered")
        waitForLabel(countValue("qa_opt_45"), "Not entered")
        waitForLabel(countValue("qa_opt_wall"), "Not entered")

        tapPrimary("SAVE CHANGES")
        XCTAssertTrue(missingPrompt.waitForExistence(timeout: 5), "blocked-save prompt did not appear")
        XCTAssertEqual(missingPrompt.label, "Corners, 45° corners, Wall returns. Required to save.")
        XCTAssertTrue(app.buttons["SAVE CHANGES"].exists, "a blocked save must keep the sheet open")
        attachScreenshot(named: "04-existing-line-blocked-save")
    }
}
