//
//  DeepLinkOccluderTests.swift
//  OPSTests
//
//  Bug 4d2e91a9 — a push-tapped lead opened UNDERNEATH whatever sheet was
//  already presented. The notifications rail (`showingNotifications`), the
//  universal search sheet (`showingUniversalSearch`) and the view-only project
//  details sheet (`isViewingDetailsOnly` + `showProjectDetails`) are all
//  passive viewers: an incoming deep link outranks them.
//
//  Project MODE is NOT passive — a crew member actively on a job keeps their
//  project. `clearNavigationOccluders()` therefore only unwinds the details
//  sheet when it is view-only, never the mode itself.
//

import XCTest
@testable import OPS

@MainActor
final class DeepLinkOccluderTests: XCTestCase {

    func testClearingOccludersDismissesRailSearchAndViewOnlyDetails() {
        let state = AppState()
        state.showingNotifications = true
        state.showingUniversalSearch = true
        state.isViewingDetailsOnly = true
        state.showProjectDetails = true
        state.activeProjectID = "p1"

        state.clearNavigationOccluders()

        XCTAssertFalse(state.showingNotifications)
        XCTAssertFalse(state.showingUniversalSearch)
        XCTAssertFalse(state.showProjectDetails)
        XCTAssertFalse(state.isViewingDetailsOnly)
        XCTAssertNil(state.activeProjectID)
    }

    func testClearingOccludersPreservesActiveProjectMode() {
        // Project MODE: a project is active and NOT merely being viewed. The
        // crew member is on the job — a deep link may cover it, never end it.
        let state = AppState()
        state.showingNotifications = true
        state.isViewingDetailsOnly = false
        state.activeProjectID = "p1"

        state.clearNavigationOccluders()

        XCTAssertFalse(state.showingNotifications)
        XCTAssertEqual(state.activeProjectID, "p1")
        XCTAssertFalse(state.isViewingDetailsOnly)
    }

    func testClearingOccludersOnAFreshStateIsANoOp() {
        let state = AppState()

        state.clearNavigationOccluders()

        XCTAssertFalse(state.showingNotifications)
        XCTAssertFalse(state.showingUniversalSearch)
        XCTAssertFalse(state.showProjectDetails)
        XCTAssertFalse(state.isViewingDetailsOnly)
        XCTAssertNil(state.activeProjectID)
    }
}
