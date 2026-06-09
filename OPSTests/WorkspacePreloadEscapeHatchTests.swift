//
//  WorkspacePreloadEscapeHatchTests.swift
//  OPSTests
//
//  Regression coverage for the returning-login workspace preload gate's
//  "ENTER ANYWAY" escape hatch (bug: the hatch dumped users back onto the
//  still-spinning login screen instead of entering the app).
//
//  The gate arms during the post-login initial sync, while DataController has
//  deliberately deferred the `isAuthenticated` flip to the END of that sync. So
//  when the hatch (or the watchdog) force-reveals mid-sync, `isAuthenticated` is
//  still false and the screen BEHIND the gate is the login/landing page. The fix
//  has the hatch flip authentication itself — but ONLY for users who were already
//  destined for the app, never one still mid-onboarding. `DataController.isAppBound`
//  is that decision, and it is the SAME predicate DataController's deferred flip
//  uses, so the hatch can never fast-forward a login the deferred flip wouldn't.
//

import XCTest
@testable import OPS

@MainActor
final class WorkspacePreloadEscapeHatchTests: XCTestCase {

    /// The reported scenario: a returning, fully-onboarded user whose initial
    /// sync is slow. The hatch must be able to flip auth and enter the app.
    func testReturningOnboardedUserIsAppBound() {
        let user = User(
            id: "returning-user-id",
            firstName: "Jack",
            lastName: "Ops",
            role: .owner,
            companyId: "company-id"
        )
        user.userType = .company
        user.hasCompletedAppOnboarding = true

        XCTAssertTrue(DataController.isAppBound(user))
    }

    /// A login that completed Firebase auth but has no company yet belongs in
    /// onboarding, not the app. The hatch must NOT drop them into a half-built
    /// MainTabView — it leaves auth alone. (DataController treats an empty
    /// companyId as "no company": `!(companyId ?? "").isEmpty`.)
    func testUserWithoutCompanyIsNotAppBound() {
        let user = User(
            id: "no-company-user-id",
            firstName: "Jack",
            lastName: "Ops",
            role: .owner,
            companyId: ""
        )
        user.userType = .company
        user.hasCompletedAppOnboarding = true

        XCTAssertFalse(DataController.isAppBound(user))
    }

    /// A user with a company but who has NOT cleared the server onboarding ACK
    /// (`hasCompletedAppOnboarding == false`) must resume onboarding — a partial
    /// join is not app-bound. Mirrors DataController's deferred-flip guard.
    func testUserPendingServerOnboardingIsNotAppBound() {
        let user = User(
            id: "partial-join-user-id",
            firstName: "Jack",
            lastName: "Ops",
            role: .owner,
            companyId: "company-id"
        )
        user.userType = .company
        user.hasCompletedAppOnboarding = false

        XCTAssertFalse(DataController.isAppBound(user))
    }

    /// No resolved user type → not app-bound (matches the deferred-flip guard's
    /// `userType != nil` clause).
    func testUserWithoutResolvedTypeIsNotAppBound() {
        let user = User(
            id: "no-type-user-id",
            firstName: "Jack",
            lastName: "Ops",
            role: .owner,
            companyId: "company-id"
        )
        user.userType = nil
        user.hasCompletedAppOnboarding = true

        XCTAssertFalse(DataController.isAppBound(user))
    }

    /// No fetched user at all (e.g. a failed fetch) → never app-bound. The hatch
    /// then falls back to a plain gate teardown rather than flipping auth blind.
    func testNilUserIsNotAppBound() {
        XCTAssertFalse(DataController.isAppBound(nil))
    }
}
