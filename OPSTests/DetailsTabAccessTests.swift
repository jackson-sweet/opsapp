import XCTest
@testable import OPS

/// Bug 71213e3b — "for crew there's just way too much stuff on the details tab...
/// Jake doesn't even need to see the details tab." The Details tab is now
/// permission-scoped (never role-gated): `DetailsTabAccess` decides section
/// visibility from granular permissions alone. These tests pin the crew vs
/// office vs unassigned difference to the exact preset-role grants in Supabase
/// `role_permissions` (verified 2026-07-04).
final class DetailsTabAccessTests: XCTestCase {

    private func store(_ perms: [String: String], disabledFlags: Set<String> = []) -> PermissionStore {
        let s = PermissionStore()
        s.permissions = perms
        s.disabledFlags = disabledFlags
        s.blockedByFlags = []
        return s
    }

    /// Exact preset Crew grants: clients.view=assigned, deck_builder.view=assigned,
    /// projects.view=assigned, tasks.view=assigned — and NO team.view, NO
    /// catalog.orders.view. Result: a focused where/what/when view.
    func testCrewSeesFocusedOnSiteView() {
        let crew = store([
            "projects.view": "assigned",
            "tasks.view": "assigned",
            "clients.view": "assigned",
            "deck_builder.view": "assigned"
        ])
        let access = DetailsTabAccess(permissions: crew)

        XCTAssertTrue(access.showsClient, "crew keep client contact for site coordination")
        XCTAssertFalse(access.showsTeam, "crew: team roster hidden (no team.view)")
        XCTAssertFalse(access.showsVinylOrder, "crew: vinyl ordering hidden (no catalog.orders.view)")
    }

    /// Exact preset Office grants — full depth, every section visible.
    func testOfficeSeesFullDepth() {
        let office = store([
            "projects.view": "all",
            "clients.view": "all",
            "team.view": "all",
            "catalog.orders.view": "all",
            "deck_builder.view": "all"
        ])
        let access = DetailsTabAccess(permissions: office)

        XCTAssertTrue(access.showsClient)
        XCTAssertTrue(access.showsTeam)
        XCTAssertTrue(access.showsVinylOrder)
    }

    /// Operator holds team.view + catalog.orders.view too — also full depth,
    /// proving the scope is driven by the permission, not the role tier.
    func testOperatorSeesFullDepth() {
        let op = store([
            "projects.view": "all",
            "clients.view": "all",
            "team.view": "all",
            "catalog.orders.view": "all",
            "deck_builder.view": "assigned"
        ])
        let access = DetailsTabAccess(permissions: op)

        XCTAssertTrue(access.showsClient)
        XCTAssertTrue(access.showsTeam)
        XCTAssertTrue(access.showsVinylOrder)
    }

    /// Unassigned (projects.view only) — the most restricted preset loses client
    /// contact and team too.
    func testUnassignedLosesClientTeamAndVinyl() {
        let unassigned = store(["projects.view": "assigned"])
        let access = DetailsTabAccess(permissions: unassigned)

        XCTAssertFalse(access.showsClient, "no clients.view → no client contact")
        XCTAssertFalse(access.showsTeam)
        XCTAssertFalse(access.showsVinylOrder)
    }

    /// The deck feature flag being OFF hides vinyl even for office — the flag gate
    /// sits above the permission gate.
    func testVinylHiddenWhenDeckFeatureDisabled() {
        let office = store([
            "clients.view": "all", "team.view": "all",
            "catalog.orders.view": "all", "deck_builder.view": "all"
        ], disabledFlags: ["deck_builder"])
        let access = DetailsTabAccess(permissions: office)

        XCTAssertFalse(access.showsVinylOrder, "deck feature off → vinyl marker hidden regardless of role")
        XCTAssertTrue(access.showsTeam, "other sections unaffected by the deck flag")
    }
}
