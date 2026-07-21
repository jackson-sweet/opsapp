//
//  ScheduleLongPressMenuUITests.swift
//  OPSUITests
//
//  Regression proof for bug 75318af9 — the Schedule long-press quick actions
//  (Push / Extend / Cascade / Reschedule) vanished when a second .contextMenu was
//  stacked on the day card. This drives a REAL long-press against the DEBUG QA host
//  (ScheduleLongPressQAHost) and asserts the quick-action menu actually opens.
//
//  Calendar surfaces, each long-pressed:
//    • FIXED   — shipping day composition. Quick actions MUST appear.
//    • ONGOING — a continuation-day card. Same actions MUST appear.
//    • MONTH DETAIL — a card in the month day-detail sheet. Same actions MUST appear.
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
        if name.contains("testFixedDayCardStillLiftsIntoRescheduleDrag") {
            app.launchArguments.append("-OPS_SCHEDULE_QA_KEEP_ANIMATIONS")
        }
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
        var scrollAttempts = 0
        while !el.isHittable && scrollAttempts < 5 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(el.isHittable, "\(id) could not be scrolled on screen")
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
        XCTAssertTrue(menuItem("Push").waitForExistence(timeout: 5), "Push submenu missing")
        XCTAssertTrue(menuItem("Extend").exists, "Extend submenu missing")
        XCTAssertTrue(menuItem("Cascade").exists, "Cascade submenu missing")
        XCTAssertTrue(menuItem("Pick new date…").waitForExistence(timeout: 5),
                      "Quick-action menu missing on the day card")
        XCTAssertTrue(menuItem("Select").exists, "Select quick action missing")
        attachMenuScreenshot("FIXED_day_card_quick_actions")
        dismissMenu()
    }

    /// Continuation days are the same scheduled task, so they must expose the
    /// same quick actions as the task's first day.
    func testOngoingDayCardShowsQuickActions() {
        longPress("qa_card_ongoing")
        XCTAssertTrue(menuItem("Cascade").waitForExistence(timeout: 5),
                      "Cascade submenu missing on an ongoing day card")
        XCTAssertTrue(menuItem("Pick new date…").waitForExistence(timeout: 5),
                      "Reschedule quick action missing on an ongoing day card")
        attachMenuScreenshot("ONGOING_day_card_quick_actions")
        dismissMenu()
    }

    /// Month day details reuse CalendarEventCard and must not silently fall back
    /// to its one-item default menu.
    func testMonthDayDetailCardShowsQuickActions() {
        longPress("qa_card_month_detail")
        XCTAssertTrue(menuItem("Cascade").waitForExistence(timeout: 5),
                      "Cascade submenu missing in the month day-detail card")
        XCTAssertTrue(menuItem("Pick new date…").waitForExistence(timeout: 5),
                      "Reschedule quick action missing in the month day-detail card")
        attachMenuScreenshot("MONTH_day_detail_quick_actions")
        dismissMenu()
    }

    /// The month EventBar (single menu + .draggable) shows its quick actions —
    /// proves .draggable and .contextMenu coexist on the same view.
    func testMonthEventBarShowsQuickActions() {
        let monthBar = card("qa_card_month")
        XCTAssertTrue(monthBar.waitForExistence(timeout: 5), "month EventBar not found")
        XCTAssertGreaterThanOrEqual(
            monthBar.frame.height,
            44,
            "Month EventBar interaction target is smaller than the mobile minimum"
        )
        longPress("qa_card_month")
        XCTAssertTrue(menuItem("Push").waitForExistence(timeout: 5),
                      "Push submenu missing on the month EventBar")
        XCTAssertTrue(menuItem("Extend").exists,
                      "Extend submenu missing on the month EventBar")
        XCTAssertTrue(menuItem("Cascade").exists,
                      "Cascade submenu missing on the month EventBar")
        XCTAssertTrue(menuItem("Pick new date…").waitForExistence(timeout: 5),
                      "Quick-action menu missing on month EventBar")
        attachMenuScreenshot("MONTH_eventbar_quick_actions")
        dismissMenu()
    }

    /// Visibility alone is not enough: selecting a menu item must invoke the
    /// scheduling callback supplied by the host surface.
    func testQuickActionSelectionReachesSchedulingCallback() {
        longPress("qa_card_fixed")
        let cascadeMenu = menuItem("Cascade")
        XCTAssertTrue(cascadeMenu.waitForExistence(timeout: 5), "Cascade submenu missing")
        cascadeMenu.tap()
        let cascade = menuItem("Cascade 2 days")
        XCTAssertTrue(cascade.waitForExistence(timeout: 5), "Cascade action missing")
        cascade.tap()

        let lastAction = card("qa_last_action")
        let callbackLanded = NSPredicate(format: "label CONTAINS %@", "cascade 2")
        expectation(for: callbackLanded, evaluatedWith: lastAction)
        waitForExpectations(timeout: 5)
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

    /// Drag/menu COEXISTENCE: the same long-press that owns the single quick-action
    /// menu must still lift into a native reschedule drag when the finger MOVES
    /// (hold → menu; hold + MOVE → drag). Drags the fixed card onto the harness
    /// drop zone and asserts the RescheduleDragPayload actually lands — if the
    /// single-owner menu had eaten the drag gesture, the drop label never changes.
    ///
    /// Gesture shape matters: the synthesized hold commits the context menu with
    /// its lifted PREVIEW, and the element-based drag then pulls that preview out
    /// of the menu — iOS's native "drag from a context menu" path. The menu items
    /// dissolve as the preview moves and the payload rides to the drop zone.
    /// (A shorter hold + coordinate drag instead slides ACROSS the open menu's
    /// items and never lifts anything — proven by screen recording.)
    func testFixedDayCardStillLiftsIntoRescheduleDrag() {
        // The drop zone flattens into ONE accessibility element (shape + overlay
        // text), so the payload text surfaces as the zone's LABEL — there is no
        // separate "qa_drop_result" StaticText in the tree.
        let landedPredicate = NSPredicate(
            format: "label CONTAINS %@", "DROPPED::qa_longpress_task")

        // The APP contract is deterministic; the SYNTHESIZED preview-grab is
        // timing-sensitive against the menu's bloom animation, so allow the
        // synthetic finger a few attempts. Each retry relaunches and reacquires
        // both elements: dismissing a context menu invalidates XCTest's cached
        // accessibility element. The landing requirement itself never relaxes.
        var landed = false
        for attempt in 1...3 {
            let source = card("qa_card_fixed")
            let target = card("qa_drop_zone")
            XCTAssertTrue(source.waitForExistence(timeout: 5), "fixed card not found")
            XCTAssertTrue(target.waitForExistence(timeout: 5), "drop zone not found")
            XCTAssertTrue(source.isHittable, "fixed card is not hittable on attempt \(attempt)")
            XCTAssertTrue(target.isHittable, "drop zone is not hittable on attempt \(attempt)")

            source.press(forDuration: 1.5, thenDragTo: target)
            let wait = XCTNSPredicateExpectation(predicate: landedPredicate, object: target)
            if XCTWaiter().wait(for: [wait], timeout: 6) == .completed {
                landed = true
                break
            }
            print("drag attempt \(attempt) did not land — relaunching before retry")
            if attempt < 3 {
                app.terminate()
                app.launch()
                XCTAssertTrue(card("qa_card_fixed").waitForExistence(timeout: 20),
                              "QA host did not relaunch for drag retry")
            }
        }
        XCTAssertTrue(
            landed,
            "The drag never lifted or the payload never dropped across 3 attempts — drag-to-reschedule is broken on the single-menu card"
        )
        attachMenuScreenshot("FIXED_day_card_drag_dropped")
        dismissMenu()
    }
}
