//
//  ScheduleLongPressMenuUITests.swift
//  OPSUITests
//
//  Regression proof for bug 75318af9 — the Schedule long-press quick actions
//  (Push / Extend / Cascade / Reschedule) vanished when a second .contextMenu was
//  stacked on the day card. This drives a REAL long-press against the DEBUG QA host
//  (ScheduleLongPressQAHost) and asserts the quick-action menu actually opens.
//
//  Four cards, each long-pressed:
//    • FIXED   — shipping day composition. Quick actions MUST appear.
//    • BUGGY   — the pre-fix double-menu composition, kept as a guard. The quick
//                actions must NOT appear (the inner default menu shadows them).
//    • MONTH   — the month EventBar (single menu + .draggable). Must appear.
//    • CONTROL — a bare single-menu view. Sanity that long-press works at all.
//

import XCTest

final class ScheduleLongPressMenuUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-OPS_SCHEDULE_LONGPRESS_QA"]
        app.launch()
        XCTAssertTrue(card("qa_card_fixed").waitForExistence(timeout: 20),
                      "QA host did not render its cards")
    }

    // MARK: - Helpers

    private func card(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Long-press the card, returning once the menu has had a chance to present.
    private func longPress(_ id: String) {
        let el = card(id)
        XCTAssertTrue(el.waitForExistence(timeout: 5), "\(id) not found")
        el.press(forDuration: 1.3)
    }

    private func menuItem(_ label: String) -> XCUIElement { app.buttons[label] }

    private func dismissMenu() {
        // Tap a neutral top strip to dismiss any open context menu.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
    }

    private func attachMenuScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    // MARK: - Tests

    /// The FIX: the shipping day card shows the full quick-action menu on long-press.
    func testFixedDayCardShowsQuickActions() {
        longPress("qa_card_fixed")
        XCTAssertTrue(menuItem("+1 Day (+ crew)").waitForExistence(timeout: 5),
                      "Cascade quick action missing — the quick actions did not appear on the day card")
        XCTAssertTrue(menuItem("Reschedule...").exists, "Reschedule quick action missing")
        attachMenuScreenshot("FIXED_day_card_quick_actions")
        dismissMenu()
    }

    /// The month EventBar (single menu + .draggable) shows its quick actions —
    /// proves .draggable and .contextMenu coexist on the same view.
    func testMonthEventBarShowsQuickActions() {
        longPress("qa_card_month")
        XCTAssertTrue(menuItem("Push 1 day").waitForExistence(timeout: 5),
                      "Push quick action missing on the month EventBar")
        XCTAssertTrue(menuItem("Pick new date…").exists, "Reschedule quick action missing on month EventBar")
        attachMenuScreenshot("MONTH_eventbar_quick_actions")
        dismissMenu()
    }

    /// Sanity control: a bare single-menu view opens on long-press in this harness.
    func testControlSingleMenuOpens() {
        longPress("qa_card_control")
        XCTAssertTrue(menuItem("+1 Day (+ crew)").waitForExistence(timeout: 5),
                      "Control single-menu did not open — long-press harness itself is broken")
        dismissMenu()
    }

    /// The GUARD: the pre-fix double-menu composition reproduces the shadow — the
    /// inner default menu wins and the stacked quick actions never appear. If this
    /// ever starts passing (quick actions appear), the platform behaviour changed
    /// and the fix's rationale should be re-examined.
    func testBuggyDoubleMenuShadowsQuickActions() {
        longPress("qa_card_buggy")
        // The inner default menu ("Reschedule") is what actually opens.
        XCTAssertTrue(menuItem("Reschedule").waitForExistence(timeout: 5),
                      "Expected the inner default menu on the double-menu card")
        // The stacked outer quick actions are shadowed — they must NOT be present.
        XCTAssertFalse(menuItem("+1 Day (+ crew)").exists,
                       "Double-stacked quick actions unexpectedly appeared — the shadow bug did not reproduce")
        attachMenuScreenshot("BUGGY_double_menu_shadow")
        dismissMenu()
    }
}
