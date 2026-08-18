//
//  AdminAuthorityTests.swift
//  OPSTests
//
//  Bug bb4775c1 — five company account holders had no `user_roles` row, so
//  `PermissionService.fetchPermissions` threw `.noRoleAssigned` before it ever
//  reached overrides, `PermissionStore` fell back to an empty cache, and EVERY
//  permission gate in the app returned false. Four of them were real paying
//  customers who signed up, found the app inert, and left with zero projects
//  and zero photos.
//
//  Admin status in OPS is an account fact, not a role name. The server decides
//  it in exactly one place — `private.current_user_is_admin()` — and these pin
//  the client to that same boolean:
//
//      deleted_at IS NULL
//      AND ( COALESCE(is_company_admin, false)
//            OR users.id::text = companies.account_holder_id
//            OR users.id::text = ANY(COALESCE(companies.admin_ids, '{}')) )
//
//  They also pin the four behaviours the fix must hold simultaneously:
//    1. an admin with no role row gets full access,
//    2. a non-admin with no role row still gets nothing,
//    3. a crew member's assigned-scope reads are completely unchanged,
//    4. an unresolvable admin probe is "unknown", not a silent demotion.
//

import XCTest
@testable import OPS

final class AdminAuthorityTests: XCTestCase {

    // Canonical shapes, matching the live rows for the affected accounts:
    // sole owner of their own company, so all three admin conditions hold.
    private let operatorId = "288501bc-0126-438c-8715-f805aeceefa7"
    private let otherId = "d6408c02-6de9-477f-afd7-816bcd50d1bf"

    private func identity(
        userId: String? = nil,
        isDeleted: Bool = false,
        isCompanyAdmin: Bool? = nil,
        accountHolderId: String? = nil,
        adminIds: [String]? = nil
    ) -> AdminAuthorityIdentity {
        AdminAuthorityIdentity(
            userId: userId ?? operatorId,
            isDeleted: isDeleted,
            isCompanyAdmin: isCompanyAdmin,
            accountHolderId: accountHolderId,
            adminIds: adminIds
        )
    }

    // MARK: - The server's boolean, transliterated

    func testAccountHolderIsAdmin() {
        XCTAssertTrue(
            AdminAuthority.isAdmin(identity(accountHolderId: operatorId))
        )
    }

    func testMembershipOfAdminIdsIsAdmin() {
        XCTAssertTrue(
            AdminAuthority.isAdmin(
                identity(accountHolderId: otherId, adminIds: [otherId, operatorId])
            )
        )
    }

    func testCompanyAdminFlagIsAdmin() {
        XCTAssertTrue(
            AdminAuthority.isAdmin(
                identity(isCompanyAdmin: true, accountHolderId: otherId, adminIds: [otherId])
            )
        )
    }

    /// The flag alone settles it — the server never needs the company row to
    /// widen a `true`, which is why the probe may skip that read.
    func testCompanyAdminFlagIsAdminWithNoCompanyRowAtAll() {
        XCTAssertTrue(AdminAuthority.isAdmin(identity(isCompanyAdmin: true)))
    }

    func testNoneOfTheThreeConditionsIsNotAdmin() {
        XCTAssertFalse(
            AdminAuthority.isAdmin(
                identity(
                    isCompanyAdmin: false,
                    accountHolderId: otherId,
                    adminIds: [otherId]
                )
            )
        )
    }

    /// `COALESCE(is_company_admin, false)` — a NULL flag is not a grant.
    func testNullCompanyAdminFlagIsNotAdmin() {
        XCTAssertFalse(AdminAuthority.isAdmin(identity(isCompanyAdmin: nil)))
    }

    /// `COALESCE(admin_ids, ARRAY[]::text[])` — a NULL roster is not a grant.
    func testNullAdminIdsIsNotAdmin() {
        XCTAssertFalse(AdminAuthority.isAdmin(identity(adminIds: nil)))
    }

    /// A user with no company row matches neither company disjunct — the
    /// server's LEFT JOIN leaves both NULL, and NULL is not a match.
    func testNoCompanyAndNoFlagIsNotAdmin() {
        XCTAssertFalse(AdminAuthority.isAdmin(identity()))
    }

    /// `u.deleted_at IS NULL` gates the whole predicate — a soft-deleted
    /// account holder is not an admin, flag or no flag.
    func testSoftDeletedUserIsNeverAdmin() {
        XCTAssertFalse(
            AdminAuthority.isAdmin(
                identity(
                    isDeleted: true,
                    isCompanyAdmin: true,
                    accountHolderId: operatorId,
                    adminIds: [operatorId]
                )
            )
        )
    }

    /// The server compares `u.id::text` against plain `text` columns, so the
    /// match is exact. Matching case-insensitively here would let the client
    /// call someone an admin whose writes the server's RLS would then refuse.
    func testIdComparisonIsExactLikeTheServers() {
        XCTAssertFalse(
            AdminAuthority.isAdmin(
                identity(
                    userId: operatorId.uppercased(),
                    accountHolderId: operatorId,
                    adminIds: [operatorId]
                )
            )
        )
    }

    // MARK: - The admin payload

    func testAdminPayloadGrantsEveryRegisteredPermissionAtScopeAll() {
        let payload = PermissionService.adminPayload()

        XCTAssertTrue(payload.isAdmin == true)
        XCTAssertEqual(payload.roleId, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(payload.roleName, "Admin")
        XCTAssertFalse(PermissionRegistry.all.isEmpty)

        for definition in PermissionRegistry.all {
            XCTAssertEqual(
                payload.permissions[definition.id],
                "all",
                "\(definition.id) must be granted at scope all for a company admin"
            )
            XCTAssertTrue(payload.explicitPermissionKeys.contains(definition.id))
        }
    }

    /// `spec.admin` is the internal SPEC-operator bit. The server refuses to let
    /// anyone write it (`guard_user_overrides_final_state`), and a company admin
    /// is not a platform operator — the client must never fabricate it.
    func testAdminPayloadNeverFabricatesTheProtectedSpecAdminPermission() {
        XCTAssertFalse(PermissionService.adminPayload().permissions.keys.contains("spec.admin"))
    }

    // MARK: - Store: an admin with no role row gets full access

    func testAdminWithNoRoleRowGetsEveryGate() {
        let store = PermissionStore()
        store.apply(PermissionService.adminPayload(), userId: operatorId)
        store.setPreviewOperatorId(operatorId)

        XCTAssertTrue(store.isAdmin)
        XCTAssertTrue(store.initialized)

        for definition in PermissionRegistry.all {
            XCTAssertTrue(store.can(definition.id), "\(definition.id) must be granted")
            XCTAssertTrue(store.can(definition.id, requiredScope: "all"))
            XCTAssertTrue(store.hasFullAccess(definition.id))
            XCTAssertEqual(store.scope(for: definition.id), "all")
        }
    }

    func testAdminReachesEveryScopeAwareGateRegardlessOfAssignment() {
        let store = PermissionStore()
        store.apply(PermissionService.adminPayload(), userId: operatorId)
        store.setPreviewOperatorId(operatorId)

        XCTAssertTrue(store.canEditAnySchedule)
        XCTAssertTrue(store.canEditSchedule(assigneeIds: []))
        XCTAssertTrue(store.canEditSchedule(assigneeIds: [otherId]))
        XCTAssertTrue(store.canEditTaskFields(assigneeIds: [otherId]))
        XCTAssertTrue(store.canChangeTaskStatus(assigneeIds: [otherId]))
        XCTAssertTrue(store.canAssignTaskCrew)

        let leads = store.leadAccessPolicy
        XCTAssertTrue(leads.canCreate)
        XCTAssertTrue(leads.canViewAny)
        XCTAssertTrue(leads.canEditAny)
        XCTAssertTrue(leads.canConvertAny)
        for action in LeadAction.allCases {
            XCTAssertTrue(
                leads.can(action, assignedTo: otherId),
                "\(action.permissionKey) must reach a lead assigned to someone else"
            )
        }
    }

    /// The registry is a client-side list and the server's permission universe
    /// moves independently. An admin's authority must not depend on that list
    /// staying in sync, so the gates short-circuit on admin authority itself.
    func testAdminIsGrantedAPermissionMissingFromTheClientRegistry() {
        let store = PermissionStore()
        store.apply(
            PermissionPayload(
                roleId: PermissionService.adminPresetRoleId,
                roleName: "Admin",
                roleHierarchy: 1,
                permissions: [:],
                explicitPermissionKeys: [],
                isAdmin: true
            ),
            userId: operatorId
        )

        XCTAssertTrue(store.can("a.permission.the.registry.has.never.heard.of"))
        XCTAssertTrue(store.hasFullAccess("a.permission.the.registry.has.never.heard.of"))
        XCTAssertEqual(store.scope(for: "a.permission.the.registry.has.never.heard.of"), "all")
        XCTAssertTrue(store.leadAccessPolicy.canCreate)
    }

    /// Feature flags are a company-wide rollout/entitlement gate, not a
    /// permission. They sit ABOVE admin authority — an admin of a company
    /// without the DECK entitlement still must not see DECK.
    func testFeatureFlagsStillOutrankAdminAuthority() {
        let store = PermissionStore()
        store.apply(PermissionService.adminPayload(), userId: operatorId)
        store.blockedByFlags = ["deck_builder.view", "pipeline.view"]
        store.disabledFlags = ["deck_builder", "pipeline"]

        XCTAssertFalse(store.can("deck_builder.view"))
        XCTAssertFalse(store.hasFullAccess("deck_builder.view"))
        XCTAssertNil(store.scope(for: "deck_builder.view"))
        XCTAssertTrue(store.isBlockedByFlag("deck_builder.view"))
        XCTAssertFalse(store.isFeatureEnabled("deck_builder"))
        XCTAssertFalse(store.leadAccessPolicy.canViewAny)

        // Everything the flags did not touch is still open.
        XCTAssertTrue(store.can("projects.view"))
    }

    // MARK: - Store: a non-admin with no role row still gets nothing

    func testNonAdminWithNoRoleRowGetsNothing() {
        let store = PermissionStore()
        store.apply(
            PermissionPayload(
                roleId: "00000000-0000-0000-0000-000000000006",
                roleName: "Unassigned",
                roleHierarchy: 99,
                permissions: [:],
                explicitPermissionKeys: [],
                isAdmin: false
            ),
            userId: operatorId
        )
        store.setPreviewOperatorId(operatorId)

        XCTAssertFalse(store.isAdmin)
        for definition in PermissionRegistry.all {
            XCTAssertFalse(store.can(definition.id), "\(definition.id) must stay denied")
            XCTAssertFalse(store.hasFullAccess(definition.id))
            XCTAssertNil(store.scope(for: definition.id))
        }
        XCTAssertFalse(store.canEditAnySchedule)
        XCTAssertFalse(store.canAssignTaskCrew)
        XCTAssertFalse(store.leadAccessPolicy.canViewAny)
    }

    /// A store that has never resolved anything grants nothing — the posture a
    /// fresh install holds until the first successful fetch.
    func testFreshStoreGrantsNothing() {
        let store = PermissionStore()
        XCTAssertFalse(store.isAdmin)
        XCTAssertFalse(store.can("projects.view"))
        XCTAssertNil(store.scope(for: "projects.view"))
    }

    // MARK: - Store: crew scoping is untouched

    func testCrewAssignedScopeIsUnchanged() {
        let store = PermissionStore()
        store.apply(
            PermissionPayload(
                roleId: "00000000-0000-0000-0000-000000000005",
                roleName: "Crew",
                roleHierarchy: 5,
                permissions: [
                    "projects.view": "assigned",
                    "tasks.edit": "assigned",
                    "tasks.change_status": "assigned",
                    "calendar.view": "assigned"
                ],
                explicitPermissionKeys: ["projects.view", "tasks.edit", "tasks.change_status", "calendar.view"],
                isAdmin: false
            ),
            userId: operatorId
        )
        store.setPreviewOperatorId(operatorId)

        XCTAssertEqual(store.scope(for: "projects.view"), "assigned")
        XCTAssertFalse(store.hasFullAccess("projects.view"))
        XCTAssertTrue(store.can("projects.view", requiredScope: "assigned"))
        XCTAssertFalse(store.can("projects.view", requiredScope: "all"))

        XCTAssertTrue(store.canEditTaskFields(assigneeIds: [operatorId]))
        XCTAssertFalse(store.canEditTaskFields(assigneeIds: [otherId]))
        XCTAssertTrue(store.canChangeTaskStatus(assigneeIds: [operatorId]))
        XCTAssertFalse(store.canChangeTaskStatus(assigneeIds: []))

        // No calendar.edit grant — Crew changes status, never the schedule.
        XCTAssertFalse(store.canEditAnySchedule)
        XCTAssertFalse(store.canEditSchedule(assigneeIds: [operatorId]))
        XCTAssertFalse(store.canAssignTaskCrew)
    }

    // MARK: - Store: unknown vs. negative admin status

    /// A probe that could not complete reports nil. That is "unknown", and it
    /// must not silently strip a live admin mid-session on a network blip —
    /// the same posture the feature-flag fetch already takes.
    func testUnknownAdminStatusPreservesTheLastKnownAnswer() {
        let store = PermissionStore()
        store.apply(PermissionService.adminPayload(), userId: operatorId)
        XCTAssertTrue(store.isAdmin)

        store.apply(
            PermissionPayload(
                roleId: "00000000-0000-0000-0000-000000000002",
                roleName: "Owner",
                roleHierarchy: 2,
                permissions: ["projects.view": "all"],
                explicitPermissionKeys: ["projects.view"],
                isAdmin: nil
            ),
            userId: operatorId
        )

        XCTAssertTrue(store.isAdmin, "An unresolvable probe must not demote a known admin")
        XCTAssertTrue(store.can("photos.delete"))
    }

    /// An explicit `false` IS authoritative — a demoted admin loses the bypass
    /// on the next successful resolution.
    func testExplicitlyResolvedNonAdminDemotesAKnownAdmin() {
        let store = PermissionStore()
        store.apply(PermissionService.adminPayload(), userId: operatorId)
        XCTAssertTrue(store.isAdmin)

        store.apply(
            PermissionPayload(
                roleId: "00000000-0000-0000-0000-000000000005",
                roleName: "Crew",
                roleHierarchy: 5,
                permissions: ["projects.view": "assigned"],
                explicitPermissionKeys: ["projects.view"],
                isAdmin: false
            ),
            userId: operatorId
        )

        XCTAssertFalse(store.isAdmin)
        XCTAssertFalse(store.can("photos.delete"))
        XCTAssertEqual(store.scope(for: "projects.view"), "assigned")
    }

    /// An unknown probe on a store that never knew anything stays closed.
    func testUnknownAdminStatusWithNoPriorAnswerFailsClosed() {
        let store = PermissionStore()
        store.apply(
            PermissionPayload(
                roleId: "00000000-0000-0000-0000-000000000005",
                roleName: "Crew",
                roleHierarchy: 5,
                permissions: ["projects.view": "assigned"],
                explicitPermissionKeys: ["projects.view"],
                isAdmin: nil
            ),
            userId: operatorId
        )

        XCTAssertFalse(store.isAdmin)
        XCTAssertFalse(store.can("photos.delete"))
    }

    func testLogoutDropsAdminAuthority() {
        let store = PermissionStore()
        store.apply(PermissionService.adminPayload(), userId: operatorId)
        XCTAssertTrue(store.isAdmin)

        store.clearPermissions()

        XCTAssertFalse(store.isAdmin)
        XCTAssertFalse(store.can("projects.view"))
        XCTAssertFalse(store.initialized)
    }

    // MARK: - Cache

    /// The cached blob carries admin authority so an offline admin keeps it.
    func testCachedBlobRoundTripsAdminAuthority() throws {
        let cached = CachedPermissions(
            permissions: ["projects.view": "all"],
            roleName: "Admin",
            roleHierarchy: 1,
            roleId: PermissionService.adminPresetRoleId,
            userId: operatorId,
            fetchedAt: Date(timeIntervalSinceReferenceDate: 0),
            blockedByFlags: [],
            disabledFlags: [],
            explicitPermissionKeys: ["projects.view"],
            isAdmin: true
        )

        let encoded = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedPermissions.self, from: encoded)
        XCTAssertTrue(decoded.isAdmin == true)
    }

    /// A cache blob written before admin authority existed has no such key. It
    /// must still decode, and it must read as "not an admin" — fail closed
    /// until the next successful fetch says otherwise.
    func testLegacyCachedBlobWithoutAdminAuthorityDecodesAsUnknownAndFailsClosed() throws {
        let legacy = """
        {
          "permissions": {"projects.view": "assigned"},
          "roleName": "Crew",
          "roleHierarchy": 5,
          "roleId": "00000000-0000-0000-0000-000000000005",
          "userId": "\(operatorId)",
          "fetchedAt": 0,
          "blockedByFlags": [],
          "disabledFlags": [],
          "explicitPermissionKeys": ["projects.view"]
        }
        """

        let decoded = try JSONDecoder().decode(
            CachedPermissions.self,
            from: Data(legacy.utf8)
        )

        XCTAssertNil(decoded.isAdmin)

        let store = PermissionStore()
        store.setPreviewAdminAuthority(decoded.isAdmin ?? false)
        XCTAssertFalse(store.isAdmin)
        XCTAssertFalse(store.can("photos.delete"))
    }
}
