//
//  DaySheetViewTests.swift
//  OPSTests
//
//  Which LEADS surface an operator gets (spec §2). The branch is a permission
//  scope, never a role name, and it is a pure static function precisely so it
//  can be proven without a view, a fetch, or a permission store.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DaySheetViewTests
//

import XCTest
@testable import OPS

@MainActor
final class DaySheetViewTests: XCTestCase {

    /// Granular keys marked explicit: a real delegate role carries the
    /// `pipeline.*` rows, so the legacy `pipeline.manage` widening never
    /// applies to it.
    private func policy(_ permissions: [String: String]) -> LeadAccessPolicy {
        LeadAccessPolicy(
            currentUserId: "u1",
            permissions: permissions,
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys
        )
    }

    /// The owner keeps the triage console — the day sheet is not an upgrade
    /// everybody gets, it is what `assigned` scope means.
    func testAllViewScopeRendersConsole() {
        XCTAssertFalse(LeadsTabView.showsDaySheet(policy: policy(["pipeline.view": "all"])))
    }

    func testAssignedViewScopeRendersDaySheet() {
        XCTAssertTrue(LeadsTabView.showsDaySheet(policy: policy(["pipeline.view": "assigned"])))
    }

    /// No view grant at all — `MainTabView` hides the tab, and if it is somehow
    /// reached the console (not the day sheet) is the surface, empty.
    func testNoViewGrantRendersConsole() {
        XCTAssertFalse(LeadsTabView.showsDaySheet(policy: policy([:])))
    }

    /// Edit scoped to `assigned` does NOT by itself pick the sheet: the view
    /// scope is the one that decides what an operator is looking at.
    func testAssignedEditWithAllViewRendersConsole() {
        let mixed = policy(["pipeline.view": "all", "pipeline.edit": "assigned"])
        XCTAssertFalse(LeadsTabView.showsDaySheet(policy: mixed))
    }

    /// Legacy all-scope `pipeline.manage` (a role predating the granular rows,
    /// so nothing is explicit) widens to `.all` — console.
    func testLegacyManageRendersConsole() {
        let legacy = LeadAccessPolicy(
            currentUserId: "u1",
            permissions: ["pipeline.manage": "all"],
            explicitPermissionKeys: []
        )
        XCTAssertFalse(LeadsTabView.showsDaySheet(policy: legacy))
    }

    /// A pipeline grant blocked by a feature flag reaches the policy as an
    /// explicit revoke — no scope, so no day sheet.
    func testFlagBlockedViewRendersConsole() {
        let blocked = LeadAccessPolicy(
            currentUserId: "u1",
            permissions: [:],
            explicitPermissionKeys: ["pipeline.view"]
        )
        XCTAssertFalse(LeadsTabView.showsDaySheet(policy: blocked))
    }
}
