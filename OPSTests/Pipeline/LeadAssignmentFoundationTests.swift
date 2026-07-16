//
//  LeadAssignmentFoundationTests.swift
//  OPSTests
//
//  Contract tests for the iOS lead-assignment foundation. These tests stay
//  network-free: they pin the SwiftData boundary, wire encodings, permission
//  registration, and feature-flag coverage before UI assignment work exists.
//

import XCTest
@testable import OPS

final class LeadAssignmentFoundationTests: XCTestCase {

    func testCreateOpportunityEncodingCannotWriteAssignmentOrCompanyIdentity() throws {
        let dto = CreateOpportunityDTO(
            contactName: "Jason Zavarella"
        )

        let object = try jsonObject(dto)

        XCTAssertFalse(object.keys.contains("company_id"))
        XCTAssertFalse(object.keys.contains("assigned_to"))
        XCTAssertFalse(object.keys.contains("assignment_version"))
    }

    func testUpdateOpportunityEncodingCannotWriteAssignment() throws {
        let object = try jsonObject(UpdateOpportunityDTO())

        XCTAssertFalse(object.keys.contains("assigned_to"))
        XCTAssertFalse(object.keys.contains("assignment_version"))
    }

    func testGuardedCreateAlwaysRequestsSelfAssignmentAndSendsExplicitNullInitialAssignee() throws {
        let params = GuardedOpportunityCreateParams(
            opportunity: CreateOpportunityDTO(contactName: "Jason Zavarella")
        )

        let object = try jsonObject(params)
        let opportunity = try XCTUnwrap(object["p_opportunity"] as? [String: Any])

        XCTAssertEqual(object["p_assignment_mode"] as? String, "self")
        XCTAssertTrue(object["p_initial_assigned_to"] is NSNull)
        XCTAssertFalse(opportunity.keys.contains("company_id"))
        XCTAssertFalse(opportunity.keys.contains("assigned_to"))
        XCTAssertFalse(opportunity.keys.contains("assignment_version"))
        XCTAssertEqual(OpportunityRepository.RPC.createGuarded, "create_opportunity_guarded")
    }

    func testAssignmentChangeEncodingPreservesOptimisticConcurrencyAndExplicitNulls() throws {
        let params = try ChangeOpportunityAssignmentParams(
            opportunityId: "lead-1",
            expectedAssignmentVersion: 7,
            expectedAssignedTo: nil,
            newAssignedTo: nil,
            source: .manual
        )

        let object = try jsonObject(params)

        XCTAssertEqual(object["p_opportunity_id"] as? String, "lead-1")
        XCTAssertEqual(object["p_expected_assignment_version"] as? Int, 7)
        XCTAssertTrue(object["p_expected_assigned_to"] is NSNull)
        XCTAssertTrue(object["p_new_assigned_to"] is NSNull)
        XCTAssertEqual(object["p_source"] as? String, "manual")
        XCTAssertTrue(object["p_suggestion_id"] is NSNull)
        XCTAssertEqual(OpportunityRepository.RPC.changeAssignment, "change_opportunity_assignment")
    }

    func testAssignmentVersionsDefaultToZeroAndRejectNegativeServerValues() throws {
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: Data("""
        {
          "id": "lead-1",
          "company_id": "company-1",
          "stage": "new_lead",
          "stage_entered_at": "2026-07-15T12:00:00Z",
          "created_at": "2026-07-15T12:00:00Z",
          "updated_at": "2026-07-15T12:00:00Z"
        }
        """.utf8))
        XCTAssertEqual(dto.assignmentVersion, 0)
        XCTAssertEqual(dto.toModel().assignmentVersion, 0)

        XCTAssertThrowsError(try JSONDecoder().decode(
            OpportunityAssignmentChangeResult.self,
            from: Data("""
            {
              "ok": false,
              "conflict": true,
              "assigned_to": null,
              "assignment_version": -1,
              "event_id": null
            }
            """.utf8)
        ))

        XCTAssertThrowsError(try JSONDecoder().decode(
            OpportunityAssignmentChangeResult.self,
            from: Data("""
            {
              "ok": false,
              "conflict": true,
              "assigned_to": null,
              "event_id": null
            }
            """.utf8)
        ), "An assignment result without a version is not authoritative.")

        XCTAssertThrowsError(try JSONDecoder().decode(
            GuardedOpportunityCreateResult.self,
            from: Data("""
            {
              "ok": true,
              "conflict": false,
              "opportunity": {
                "id": "lead-1",
                "company_id": "company-1",
                "stage": "new_lead",
                "stage_entered_at": "2026-07-15T12:00:00Z",
                "created_at": "2026-07-15T12:00:00Z",
                "updated_at": "2026-07-15T12:00:00Z"
              },
              "assigned_to": null,
              "event_id": null
            }
            """.utf8)
        ), "A guarded create result without a version is not authoritative.")
    }

    func testAssignmentChangeResultDecodesAuthoritativeConflictSnapshot() throws {
        let result = try JSONDecoder().decode(
            OpportunityAssignmentChangeResult.self,
            from: Data("""
            {
              "ok": false,
              "conflict": true,
              "assigned_to": "user-current",
              "assignment_version": 9,
              "event_id": null
            }
            """.utf8)
        )

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.conflict)
        XCTAssertEqual(result.assignedTo, "user-current")
        XCTAssertEqual(result.assignmentVersion, 9)
        XCTAssertNil(result.eventId)
    }

    func testConversionParamsPinStageAndAssignmentSnapshot() throws {
        let params = ConvertOpportunityParams(
            companyId: "company-1",
            opportunityId: "lead-1",
            actualValue: 42_000,
            expectedStage: "quoted",
            decidedBy: "user-1",
            notes: nil,
            titleOverride: nil,
            sourcePath: "ios",
            winOpportunity: true,
            expectedAssignmentVersion: 12
        )

        let object = try jsonObject(params)

        XCTAssertEqual(object["p_expected_stage"] as? String, "quoted")
        XCTAssertEqual(object["p_expected_assignment_version"] as? Int, 12)
    }

    func testConversionResultParsesAssignmentSnapshotAndProjectAccessGuard() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": false,
              "already_converted": false,
              "guard_reason": "assignment_snapshot_mismatch",
              "assigned_to": "user-current",
              "assignment_version": 13,
              "project_accessible": false
            }
            """.utf8)
        )

        XCTAssertEqual(result.guardReason, "assignment_snapshot_mismatch")
        XCTAssertEqual(result.assignedTo, "user-current")
        XCTAssertEqual(result.assignmentVersion, 13)
        XCTAssertEqual(result.projectAccessible, false)
    }

    func testAccessibleAlreadyConvertedResultRemainsAnIdempotentSuccess() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": false,
              "already_converted": true,
              "guard_reason": "already_converted",
              "project_id": "project-1",
              "assigned_to": "user-current",
              "assignment_version": 13,
              "project_accessible": true
            }
            """.utf8)
        )

        XCTAssertEqual(result.guardDecision, .proceed)
    }

    func testLeadAccessPolicyMatchesOnlyTheCanonicalRowAssignee() {
        let policy = LeadAccessPolicy(
            currentUserId: "USER-JASON",
            permissions: [
                "pipeline.view": "assigned",
                "pipeline.edit": "assigned",
                "pipeline.assign": "assigned",
                "pipeline.convert": "assigned"
            ],
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys
        )

        XCTAssertTrue(policy.can(.view, assignedTo: "user-jason"))
        XCTAssertTrue(policy.can(.edit, assignedTo: "user-jason"))
        XCTAssertTrue(policy.can(.assign, assignedTo: "user-jason"))
        XCTAssertTrue(policy.can(.convert, assignedTo: "user-jason"))
        XCTAssertFalse(policy.can(.view, assignedTo: "someone-else"))
        XCTAssertFalse(policy.can(.view, assignedTo: nil))
    }

    func testLeadAccessPolicyNeverLetsLegacyManageWidenExplicitGranularScopeOrRevoke() {
        let explicitAssigned = LeadAccessPolicy(
            currentUserId: "user-jason",
            permissions: [
                "pipeline.manage": "all",
                "pipeline.view": "assigned"
            ],
            explicitPermissionKeys: ["pipeline.view"]
        )
        XCTAssertFalse(explicitAssigned.can(.view, assignedTo: "someone-else"))

        let explicitRevoke = LeadAccessPolicy(
            currentUserId: "user-jason",
            permissions: ["pipeline.manage": "all"],
            explicitPermissionKeys: ["pipeline.view"]
        )
        XCTAssertFalse(explicitRevoke.can(.view, assignedTo: "user-jason"))

        let legacyFallback = LeadAccessPolicy(
            currentUserId: "user-jason",
            permissions: ["pipeline.manage": "all"],
            explicitPermissionKeys: []
        )
        XCTAssertTrue(legacyFallback.can(.view, assignedTo: "someone-else"))
    }

    func testLeadAccessPolicyCapsWritesByPrerequisitesAndRequiresAllForCreate() {
        let policy = LeadAccessPolicy(
            currentUserId: "user-jason",
            permissions: [
                "pipeline.create": "assigned",
                "pipeline.view": "assigned",
                "pipeline.edit": "all",
                "pipeline.assign": "all",
                "pipeline.convert": "all"
            ],
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys
        )

        XCTAssertFalse(policy.canCreate)
        XCTAssertFalse(policy.can(.edit, assignedTo: "someone-else"))
        XCTAssertFalse(policy.can(.assign, assignedTo: "someone-else"))
        XCTAssertFalse(policy.can(.convert, assignedTo: "someone-else"))
        XCTAssertTrue(policy.can(.edit, assignedTo: "user-jason"))
    }

    func testAdminLeadAccessBypassesScopedGrants() {
        let policy = LeadAccessPolicy(
            currentUserId: nil,
            isAdmin: true,
            permissions: [:],
            explicitPermissionKeys: []
        )

        XCTAssertTrue(policy.canCreate)
        XCTAssertTrue(policy.can(.view, assignedTo: nil))
        XCTAssertTrue(policy.can(.edit, assignedTo: "anyone"))
        XCTAssertTrue(policy.can(.assign, assignedTo: "anyone"))
        XCTAssertTrue(policy.can(.convert, assignedTo: "anyone"))
    }

    func testPermissionRegistryRegistersGranularLeadActionsAndHidesLegacyManage() {
        let registered = Dictionary(
            uniqueKeysWithValues: PermissionRegistry.all.map { ($0.id, $0) }
        )

        for permission in [
            "pipeline.create",
            "pipeline.view",
            "pipeline.edit",
            "pipeline.assign",
            "pipeline.convert"
        ] {
            XCTAssertNotNil(registered[permission], "Missing \(permission)")
        }

        XCTAssertNotNil(registered["pipeline.manage"], "Legacy permission must remain registered")
        XCTAssertFalse(
            PermissionRegistry.permissions(for: "Pipeline").contains { $0.id == "pipeline.manage" },
            "Legacy pipeline.manage must not appear in new permission editing"
        )
    }

    func testPipelineFeatureFlagCoversEveryGranularLeadPermission() {
        let pipelinePermissions = Set(
            FeatureFlagService.staticFlagDefinitions["pipeline"] ?? []
        )

        XCTAssertTrue(pipelinePermissions.isSuperset(of: [
            "pipeline.create",
            "pipeline.view",
            "pipeline.edit",
            "pipeline.assign",
            "pipeline.convert"
        ]))
    }

    func testMigrationPlanDeclaresARealV16Boundary() throws {
        XCTAssertEqual(OPSMigrationPlan.schemas.count, 16)
        XCTAssertEqual(OPSMigrationPlan.stages.count, 15)
        XCTAssertEqual(
            String(describing: try XCTUnwrap(OPSMigrationPlan.schemas.last).versionIdentifier),
            "16.0.0"
        )
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
