//
//  BugReportPresenterLatchTests.swift
//  OPSTests
//
//  Bug 70087050: shake-to-report sometimes stopped appearing after prolonged
//  app use. Root cause: the presenter's isPresenting latch could strand true
//  with no sheet on screen (a dismissal completion dropped by a backgrounding
//  race, or a presentation landing on a dying scene), and the shake handler's
//  guard then rejected every future shake until relaunch. present() now
//  verifies the presentation is REALLY alive and recovers when it isn't —
//  this is the truth table that decision runs on.
//

import XCTest
@testable import OPS

final class BugReportPresenterLatchTests: XCTestCase {

    /// The healthy case: window up, visible, scene attached, sheet presented.
    /// A second shake while the report is open must remain a no-op.
    func testLiveSheetIsAlive() {
        XCTAssertTrue(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: false, sceneAlive: true, sheetUp: true
        ))
    }

    /// Dismissal completion never fired: the sheet is gone but the window and
    /// latch linger. Must read dead so the next shake recovers.
    func testLingeringWindowWithoutSheetIsDead() {
        XCTAssertFalse(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: false, sceneAlive: true, sheetUp: false
        ))
    }

    /// Latch true but the window was already released (partial teardown).
    func testMissingWindowIsDead() {
        XCTAssertFalse(BugReportPresenter.isPresentationAlive(
            hasWindow: false, windowHidden: true, sceneAlive: false, sheetUp: false
        ))
    }

    /// Window hidden (teardown started but latch not cleared).
    func testHiddenWindowIsDead() {
        XCTAssertFalse(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: true, sceneAlive: true, sheetUp: true
        ))
    }

    /// The window's scene detached (backgrounding / scene destruction race).
    func testDetachedSceneIsDead() {
        XCTAssertFalse(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: false, sceneAlive: false, sheetUp: true
        ))
    }

    // MARK: - POINT AT IT (bug 14e5a792)

    /// Mid-pick the sheet is deliberately down and the pick layer is up. That
    /// is a live report holding the operator's draft — a second shake must not
    /// tear it down and start a blank one.
    func testPickLayerUpWithTheSheetDownIsAlive() {
        XCTAssertTrue(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: false, sceneAlive: true,
            sheetUp: false, pickLayerUp: true
        ))
    }

    /// The pick layer never rescues a presentation whose window or scene is
    /// gone — those are still corpses.
    func testPickLayerDoesNotRescueADeadWindow() {
        XCTAssertFalse(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: true, sceneAlive: true,
            sheetUp: false, pickLayerUp: true
        ))
        XCTAssertFalse(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: false, sceneAlive: false,
            sheetUp: false, pickLayerUp: true
        ))
    }

    /// Neither the sheet nor the pick layer: nothing on screen.
    func testNoSheetAndNoPickLayerIsDead() {
        XCTAssertFalse(BugReportPresenter.isPresentationAlive(
            hasWindow: true, windowHidden: false, sceneAlive: true,
            sheetUp: false, pickLayerUp: false
        ))
    }
}
