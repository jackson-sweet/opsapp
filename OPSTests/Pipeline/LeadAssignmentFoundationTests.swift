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
            linkToProjectId: "project-existing",
            sourcePath: "ios",
            winOpportunity: true,
            projectStatus: "accepted",
            evidence: ["surface": "convert_sheet"],
            expectedAssignmentVersion: 12
        )

        let object = try jsonObject(params)

        XCTAssertEqual(object["p_expected_stage"] as? String, "quoted")
        XCTAssertEqual(object["p_expected_assignment_version"] as? Int, 12)
        XCTAssertEqual(object["p_link_to_project_id"] as? String, "project-existing")
        XCTAssertEqual(object["p_project_status"] as? String, "accepted")
        XCTAssertEqual(
            (object["p_evidence"] as? [String: String])?["surface"],
            "convert_sheet"
        )
    }

    func testConversionPreflightRoutesOnlyEligibleDuplicateCandidatesToMatch() {
        let matchCandidate = ConvertToProjectSheet.RelatedProjectRef(
            id: "project-match",
            title: "3998 Holland Ave",
            address: "3998 Holland Ave, Victoria bc",
            status: nil,
            isLikelyDuplicate: true
        )
        let reviewOnlyProject = ConvertToProjectSheet.RelatedProjectRef(
            id: "project-review",
            title: "Other client project",
            address: "12 Douglas St",
            status: .accepted,
            isLikelyDuplicate: false
        )
        let rejectedStaleCandidate = ConvertToProjectSheet.RelatedProjectRef(
            id: "project-stale",
            title: "Already linked project",
            address: "3998 Holland Ave, Victoria bc",
            status: .accepted,
            isLikelyDuplicate: true,
            isMatchAvailable: false
        )

        XCTAssertEqual(matchCandidate.interaction, .match)
        XCTAssertEqual(matchCandidate.actionLabel, "MATCH")
        XCTAssertEqual(reviewOnlyProject.interaction, .open)
        XCTAssertNil(reviewOnlyProject.actionLabel)
        XCTAssertEqual(rejectedStaleCandidate.interaction, .open)
        XCTAssertEqual(rejectedStaleCandidate.actionLabel, "REVIEW")
    }

    func testCandidateProjectMustBeUnlinkedOrAlreadyBelongToThisLead() {
        XCTAssertTrue(LeadConversionService.projectLinkIsAvailable(
            opportunityId: nil,
            opportunityRef: nil,
            leadId: "lead-current"
        ))
        XCTAssertTrue(LeadConversionService.projectLinkIsAvailable(
            opportunityId: "lead-current",
            opportunityRef: "lead-current",
            leadId: "lead-current"
        ))
        XCTAssertFalse(LeadConversionService.projectLinkIsAvailable(
            opportunityId: "lead-other",
            opportunityRef: "lead-other",
            leadId: "lead-current"
        ))
        XCTAssertFalse(LeadConversionService.projectLinkIsAvailable(
            opportunityId: "lead-current",
            opportunityRef: "lead-other",
            leadId: "lead-current"
        ))
    }

    func testSelectedExistingProjectBecomesTheGuardedConversionTarget() {
        let create = ConvertToProjectSheet.SubmissionTarget(selectedProjectId: nil)
        let match = ConvertToProjectSheet.SubmissionTarget(
            selectedProjectId: "project-existing"
        )
        let emptySelection = ConvertToProjectSheet.SubmissionTarget(
            selectedProjectId: "   "
        )

        XCTAssertNil(create.linkToProjectId)
        XCTAssertEqual(create.primaryLabel, "CREATE PROJECT")
        XCTAssertTrue(create.showsProjectIdentityFields)
        XCTAssertEqual(match.linkToProjectId, "project-existing")
        XCTAssertEqual(match.primaryLabel, "MATCH PROJECT")
        XCTAssertFalse(match.showsProjectIdentityFields)
        XCTAssertNil(emptySelection.linkToProjectId)
        XCTAssertEqual(emptySelection.primaryLabel, "CREATE PROJECT")
        XCTAssertTrue(emptySelection.showsProjectIdentityFields)
    }

    func testConversionCannotCommitBeforeAHealthyAuthoritativePreflight() {
        XCTAssertFalse(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: false,
            preflightFailed: false,
            isSaving: false,
            requiresMatchReviewRefresh: false,
            hasLikelyDuplicate: false,
            hasSelectedMatch: false
        ))
        XCTAssertFalse(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: true,
            preflightFailed: true,
            isSaving: false,
            requiresMatchReviewRefresh: false,
            hasLikelyDuplicate: false,
            hasSelectedMatch: false
        ))
        XCTAssertFalse(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: true,
            preflightFailed: false,
            isSaving: false,
            requiresMatchReviewRefresh: true,
            hasLikelyDuplicate: false,
            hasSelectedMatch: false
        ))
        XCTAssertFalse(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: true,
            preflightFailed: false,
            isSaving: false,
            requiresMatchReviewRefresh: false,
            hasLikelyDuplicate: true,
            hasSelectedMatch: false
        ))
        XCTAssertTrue(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: true,
            preflightFailed: false,
            isSaving: false,
            requiresMatchReviewRefresh: false,
            hasLikelyDuplicate: true,
            hasSelectedMatch: true
        ))
        XCTAssertTrue(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: true,
            preflightFailed: false,
            isSaving: false,
            requiresMatchReviewRefresh: false,
            hasLikelyDuplicate: false,
            hasSelectedMatch: false
        ))
    }

    func testPreflightCreationBlockerStopsUnsafeCreateWithAnActionableReason() throws {
        let addressPreflight = try JSONDecoder().decode(
            ConversionPreflight.self,
            from: Data("""
            {
              "existing_linked_project": null,
              "duplicate_candidates": [],
              "other_client_projects": [],
              "creation_blocker": "address_required",
              "suggested_name": "New project",
              "already_converted": false,
              "project_accessible": false,
              "assignment_version": 4
            }
            """.utf8)
        )

        let reviewPreflight = try JSONDecoder().decode(
            ConversionPreflight.self,
            from: Data("""
            {
              "existing_linked_project": null,
              "duplicate_candidates": [],
              "other_client_projects": [],
              "creation_blocker": "project_review_required",
              "suggested_name": "New project",
              "already_converted": false,
              "project_accessible": false,
              "assignment_version": 4
            }
            """.utf8)
        )

        XCTAssertEqual(addressPreflight.creationBlocker, .addressRequired)
        XCTAssertEqual(reviewPreflight.creationBlocker, .projectReviewRequired)
        XCTAssertFalse(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: true,
            preflightFailed: false,
            isSaving: false,
            requiresMatchReviewRefresh: false,
            hasLikelyDuplicate: false,
            hasSelectedMatch: false,
            creationBlocker: addressPreflight.creationBlocker
        ))
        XCTAssertFalse(ConvertToProjectSheet.canCommitConversion(
            hasLoadedPreflight: true,
            preflightFailed: false,
            isSaving: false,
            requiresMatchReviewRefresh: false,
            hasLikelyDuplicate: false,
            hasSelectedMatch: false,
            creationBlocker: reviewPreflight.creationBlocker
        ))
        XCTAssertTrue(ConvertToProjectSheet.shouldStopCreateAfterAddressRecheck(
            creationBlocker: reviewPreflight.creationBlocker
        ))
        XCTAssertFalse(ConvertToProjectSheet.shouldStopCreateAfterAddressRecheck(
            creationBlocker: nil
        ))
    }

    func testEditedCreateAddressInvalidatesTheAuthoritativePreflight() {
        XCTAssertTrue(ConvertToProjectSheet.createAddressNeedsRecheck(
            address: "3998 Holland Ave, Victoria bc",
            verifiedFingerprint: nil
        ))

        let verified = ConvertToProjectSheet.createAddressFingerprint(
            "3998 Holland Ave, Victoria bc"
        )
        XCTAssertFalse(ConvertToProjectSheet.createAddressNeedsRecheck(
            address: "3998 Holland Ave, Victoria bc",
            verifiedFingerprint: verified
        ))
        XCTAssertTrue(ConvertToProjectSheet.createAddressNeedsRecheck(
            address: "4000 Holland Ave, Victoria bc",
            verifiedFingerprint: verified
        ))
    }

    func testProjectLinkGuardFailuresBecomeARefreshableMatchError() {
        let serverErrors = [
            "project_link_unavailable",
            "project_link_unavailable: matching_project_link_conflict",
            "project_link_ambiguous",
            "linked project belongs to another opportunity",
            "link target project already belongs to another opportunity",
            "link target project legacy mirror belongs to another opportunity",
            "opportunity is already linked to another project",
            "opportunity project mirrors disagree",
        ]

        for message in serverErrors {
            let rawError = NSError(domain: message, code: 1)
            guard let mapped = LeadConversionService.mapRPCError(rawError) as? LeadConversionError,
                  case .projectLinkUnavailable = mapped else {
                return XCTFail("Expected project-link guard mapping for \(message)")
            }
        }

        XCTAssertEqual(
            LeadConversionError.projectLinkUnavailable.errorDescription,
            "The project changed and must be reviewed before matching."
        )
    }

    func testLinkedProjectRowSurvivesBeforeTheProjectTitleHydrates() {
        XCTAssertEqual(
            LeadDetailsDocument.projectRowPresentation(
                projectId: "project-linked",
                projectName: nil,
                stage: .won,
                canMatchProject: true
            ),
            .linked(label: "LINKED PROJECT")
        )
        XCTAssertEqual(
            LeadDetailsDocument.projectRowPresentation(
                projectId: nil,
                projectName: nil,
                stage: .won,
                canMatchProject: true
            ),
            .match
        )
        XCTAssertEqual(
            LeadDetailsDocument.projectRowPresentation(
                projectId: nil,
                projectName: nil,
                stage: .won,
                canMatchProject: false
            ),
            .empty
        )
        XCTAssertEqual(
            LeadDetailsDocument.projectActionMinimumHeight,
            OPSStyle.Layout.touchTargetMin
        )
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
              "won": true,
              "guard_reason": "already_converted",
              "project_id": "project-1",
              "assigned_to": "user-current",
              "assignment_version": 13,
              "project_accessible": true
            }
            """.utf8)
        )

        XCTAssertEqual(result.guardDecision, .proceed)
        XCTAssertEqual(
            try LeadConversionOutcomeResolver.disposition(for: result),
            .fetchProject(projectId: "project-1")
        )
    }

    func testWonStageCannotUseTheDirectStageMutationBoundary() {
        XCTAssertThrowsError(
            try OpportunityRepository.validateDirectStageMutation(.won)
        ) { error in
            XCTAssertEqual(
                error as? OpportunityRepositoryError,
                .guardedConversionRequired
            )
        }

        for stage in PipelineStage.allCases where stage != .won {
            XCTAssertNoThrow(
                try OpportunityRepository.validateDirectStageMutation(stage),
                "\(stage.rawValue) should remain a direct stage transition"
            )
        }
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

    func testLegacyNullScopeOverrideStillInheritsPipelineManageCompatibility() {
        let inherited = PermissionService.foldOverrides(
            [
                PermissionOverrideFoldRow(
                    permission: "pipeline.view",
                    scope: nil,
                    granted: true
                )
            ],
            into: ["pipeline.manage": "all"],
            explicitPermissionKeys: []
        )

        XCTAssertFalse(inherited.explicitPermissionKeys.contains("pipeline.view"))
        XCTAssertTrue(
            LeadAccessPolicy(
                currentUserId: "user-jason",
                permissions: inherited.permissions,
                explicitPermissionKeys: inherited.explicitPermissionKeys
            ).can(.view, assignedTo: "someone-else")
        )

        let revoked = PermissionService.foldOverrides(
            [
                PermissionOverrideFoldRow(
                    permission: "pipeline.view",
                    scope: nil,
                    granted: false
                )
            ],
            into: ["pipeline.manage": "all"],
            explicitPermissionKeys: []
        )
        XCTAssertTrue(revoked.explicitPermissionKeys.contains("pipeline.view"))
        XCTAssertFalse(
            LeadAccessPolicy(
                currentUserId: "user-jason",
                permissions: revoked.permissions,
                explicitPermissionKeys: revoked.explicitPermissionKeys
            ).can(.view, assignedTo: "user-jason")
        )
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

    func testRawRoleNameCannotBypassAnExplicitGranularRevoke() {
        let policy = LeadAccessPolicy(
            currentUserId: nil,
            permissions: [:],
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys
        )

        XCTAssertFalse(policy.canCreate)
        XCTAssertFalse(policy.canViewAny)
        XCTAssertFalse(policy.can(.view, assignedTo: nil))
        XCTAssertFalse(policy.can(.edit, assignedTo: "anyone"))
        XCTAssertFalse(policy.can(.assign, assignedTo: "anyone"))
        XCTAssertFalse(policy.can(.convert, assignedTo: "anyone"))
    }

    func testAssignedLeadViewScopeMakesTheLeadsSurfaceAvailable() {
        let policy = LeadAccessPolicy(
            currentUserId: "user-jason",
            permissions: ["pipeline.view": "assigned"],
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys
        )

        XCTAssertTrue(policy.canViewAny)
        XCTAssertTrue(policy.can(.view, assignedTo: "user-jason"))
        XCTAssertFalse(policy.can(.view, assignedTo: "someone-else"))
    }

    func testPermissionRegistryUsesCanonicalScopesAndHidesCompatibilityBits() {
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

        XCTAssertEqual(registered["pipeline.create"]?.allowedLevels, [.off, .all])
        XCTAssertEqual(registered["pipeline.view"]?.allowedLevels, [.off, .assigned, .all])
        XCTAssertEqual(registered["calendar.edit"]?.allowedLevels, [.off, .own, .all])
        XCTAssertEqual(registered["profile.edit"]?.allowedLevels, [.off, .own])

        XCTAssertNotNil(registered["pipeline.manage"], "Legacy permission must remain readable")
        XCTAssertNotNil(registered["inbox.view_company"], "Legacy permission must remain readable")
        XCTAssertFalse(
            PermissionRegistry.editable.contains { $0.id == "pipeline.manage" },
            "Legacy pipeline.manage must not appear in canonical mutations"
        )
        XCTAssertFalse(
            PermissionRegistry.editable.contains { $0.id == "inbox.view_company" },
            "Legacy inbox.view_company must not appear in canonical mutations"
        )
        XCTAssertEqual(PermissionRegistry.editable.count, 100)
    }

    func testPipelinePermissionNormalizationOnlyNarrowsDependentActions() {
        let initial: [String: PermissionLevel] = [
            "pipeline.create": .all,
            "pipeline.view": .assigned,
            "pipeline.edit": .all,
            "pipeline.assign": .all,
            "pipeline.convert": .all,
        ]

        let normalized = PermissionEditorPolicy.normalized(initial)

        XCTAssertEqual(normalized["pipeline.create"], .all)
        XCTAssertEqual(normalized["pipeline.view"], .assigned)
        XCTAssertEqual(normalized["pipeline.edit"], .assigned)
        XCTAssertEqual(normalized["pipeline.assign"], .assigned)
        XCTAssertEqual(normalized["pipeline.convert"], .assigned)

        let revoked = PermissionEditorPolicy.normalized([
            "pipeline.create": .all,
            "pipeline.view": .off,
            "pipeline.edit": .assigned,
            "pipeline.assign": .assigned,
            "pipeline.convert": .assigned,
        ])
        XCTAssertEqual(revoked["pipeline.create"], .off)
        XCTAssertEqual(revoked["pipeline.edit"], .off)
        XCTAssertEqual(revoked["pipeline.assign"], .off)
        XCTAssertEqual(revoked["pipeline.convert"], .off)
    }

    func testRolePermissionMutationIsCompleteCanonicalAndExplicit() throws {
        let expected = [
            CanonicalRolePermission(permission: "pipeline.view", scope: "assigned"),
            CanonicalRolePermission(permission: "pipeline.manage", scope: "all"),
        ]
        let request = try RolePermissionMutationRequest(
            expectedPermissions: expected,
            desiredLevels: ["pipeline.view": .assigned],
            assignmentResolutions: []
        )

        XCTAssertEqual(
            request.expectedPermissions.map(\.permission),
            ["pipeline.manage", "pipeline.view"]
        )
        XCTAssertEqual(request.newPermissions.count, PermissionRegistry.editable.count)
        XCTAssertEqual(
            request.newPermissions.map(\.permission),
            request.newPermissions.map(\.permission).sorted()
        )
        XCTAssertEqual(
            request.newPermissions.first { $0.permission == "pipeline.view" }?.scope,
            "assigned"
        )
        XCTAssertNil(
            try XCTUnwrap(
                request.newPermissions.first { $0.permission == "pipeline.edit" }
            ).scope
        )
        XCTAssertFalse(request.newPermissions.contains { $0.permission == "pipeline.manage" })
        XCTAssertFalse(request.newPermissions.contains { $0.permission == "inbox.view_company" })

        let object = try jsonObject(request)
        XCTAssertNotNil(object["expectedPermissions"])
        XCTAssertNotNil(object["newPermissions"])
        XCTAssertNotNil(object["assignmentResolutions"])
        let encodedDesired = try XCTUnwrap(object["newPermissions"] as? [[String: Any]])
        XCTAssertTrue(
            try XCTUnwrap(encodedDesired.first { $0["permission"] as? String == "pipeline.edit" })["scope"] is NSNull
        )

        let explicitUnassign = RolePermissionAssignmentResolution(
            opportunityId: "lead-1",
            expectedAssignedTo: "user-jason",
            expectedAssignmentVersion: 4,
            newAssignedTo: nil
        )
        let encodedResolution = try jsonObject(explicitUnassign)
        XCTAssertEqual(encodedResolution["expected_assigned_to"] as? String, "user-jason")
        XCTAssertTrue(encodedResolution["new_assigned_to"] is NSNull)
    }

    func testRolePermissionSuccessRequiresTheFullAuthoritativeResponse() throws {
        let valid = try JSONDecoder().decode(
            RolePermissionMutationSuccess.self,
            from: Data("""
            {
              "ok": true,
              "roleId": "role-1",
              "permissions": [{"permission":"pipeline.view","scope":"assigned"}],
              "resolvedAssignments": 0
            }
            """.utf8)
        )
        XCTAssertEqual(valid.roleId, "role-1")
        XCTAssertTrue(valid.ok)

        for invalid in [
            #"{"ok":true,"permissions":[],"resolvedAssignments":0}"#,
            #"{"ok":true,"roleId":"role-1","resolvedAssignments":0}"#,
            #"{"ok":true,"roleId":"role-1","permissions":[]}"#,
            #"{"ok":false,"roleId":"role-1","permissions":[],"resolvedAssignments":0}"#,
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    RolePermissionMutationSuccess.self,
                    from: Data(invalid.utf8)
                )
            )
        }
    }

    func testUserOverrideMutationIsAtomicSortedAndPreservesHiddenSnapshotRows() throws {
        let request = try UserPermissionOverrideMutationRequest(
            expectedOverrides: [
                CanonicalUserPermissionOverride(
                    permission: "pipeline.view",
                    scope: "assigned",
                    granted: true
                ),
                CanonicalUserPermissionOverride(
                    permission: "pipeline.manage",
                    scope: "all",
                    granted: true
                ),
                CanonicalUserPermissionOverride(
                    permission: "pipeline.edit",
                    scope: "assigned",
                    granted: true
                ),
                CanonicalUserPermissionOverride(
                    permission: "pipeline.convert",
                    scope: nil,
                    granted: false
                ),
            ],
            roleBaseline: [
                "pipeline.view": .assigned,
                "pipeline.edit": .assigned,
            ],
            desiredLevels: [
                "pipeline.view": .all,
                "pipeline.edit": .off,
            ],
            assignmentResolutions: []
        )

        XCTAssertEqual(
            request.expectedOverrides.map(\.permission),
            ["pipeline.convert", "pipeline.edit", "pipeline.manage", "pipeline.view"]
        )
        XCTAssertEqual(request.set.map(\.permission), ["pipeline.edit", "pipeline.view"])
        XCTAssertEqual(request.clear, ["pipeline.convert"])
        XCTAssertFalse(request.set.contains { $0.permission == "pipeline.manage" })

        let object = try jsonObject(request)
        XCTAssertNotNil(object["expectedOverrides"])
        XCTAssertNotNil(object["set"])
        XCTAssertNotNil(object["clear"])
        XCTAssertNotNil(object["assignmentResolutions"])
        let rows = try XCTUnwrap(object["set"] as? [[String: Any]])
        let revoke = try XCTUnwrap(
            rows.first { $0["permission"] as? String == "pipeline.edit" }
        )
        XCTAssertEqual(revoke["granted"] as? Bool, false)
        XCTAssertTrue(revoke["scope"] is NSNull)
    }

    func testUserRoleMutationEncodesNullableSnapshotsAndRequiresAuthoritativeResponse() throws {
        let request = try UserRoleMutationRequest(
            expectedRoleId: nil,
            newRoleId: nil,
            assignmentResolutions: []
        )
        let object = try jsonObject(request)
        XCTAssertTrue(object["expectedRoleId"] is NSNull)
        XCTAssertTrue(object["newRoleId"] is NSNull)
        XCTAssertNotNil(object["assignmentResolutions"])

        let valid = try JSONDecoder().decode(
            UserRoleMutationSuccess.self,
            from: Data("""
            {
              "ok": true,
              "userId": "user-jason",
              "roleId": null,
              "legacyRole": "unassigned",
              "resolvedAssignments": 0
            }
            """.utf8)
        )
        XCTAssertNil(valid.roleId)

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UserRoleMutationSuccess.self,
                from: Data("""
                {
                  "ok": true,
                  "userId": "user-jason",
                  "legacyRole": "unassigned",
                  "resolvedAssignments": 0
                }
                """.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UserRoleSnapshotConflict.self,
                from: Data(#"{"code":"permission_snapshot_mismatch"}"#.utf8)
            )
        )
    }

    func testPresetRoleIdentityComesFromCanonicalDatabaseFlag() throws {
        let role = try JSONDecoder().decode(
            AdminRoleRow.self,
            from: Data("""
            {
              "id": "custom-operator",
              "name": "Operator",
              "hierarchy": 8,
              "is_preset": false
            }
            """.utf8)
        )
        XCTAssertFalse(role.isPreset)
    }

    func testAssignmentResolutionConflictRequiresSnapshotsAndEligibleTargets() throws {
        let conflict = try JSONDecoder().decode(
            RolePermissionMutationConflict.self,
            from: Data("""
            {
              "code": "assignment_resolution_required",
              "strandedCount": 1,
              "stranded": [{
                "opportunity_id": "lead-1",
              "title": null,
                "assigned_to": "user-jason",
                "assignment_version": 9
              }],
              "eligibleAssignees": [{
                "id": "user-amy",
                "first_name": null,
                "last_name": null,
                "profile_image_url": null,
                "user_color": null,
                "role": null
              }]
            }
            """.utf8)
        )

        XCTAssertEqual(conflict.strandedCount, 1)
        XCTAssertEqual(conflict.stranded.first?.assignmentVersion, 9)
        XCTAssertEqual(conflict.stranded.first?.title, "")
        XCTAssertEqual(conflict.eligibleAssignees.first?.id, "user-amy")
        XCTAssertEqual(conflict.eligibleAssignees.first?.displayName, "")

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RolePermissionMutationConflict.self,
                from: Data(#"{"code":"assignment_resolution_required","strandedCount":1,"stranded":[]}"#.utf8)
            )
        )
    }

    func testInaccessibleConvertedProjectIsACommittedSuccessWithoutIdentity() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": false,
              "already_converted": true,
              "won": true,
              "guard_reason": "already_converted",
              "project_id": "secret-project",
              "assigned_to": "user-jason",
              "assignment_version": 13,
              "project_accessible": false
            }
            """.utf8)
        )

        XCTAssertEqual(
            try LeadConversionOutcomeResolver.disposition(for: result),
            .committedWithoutAccessibleProject
        )
    }

    func testHiddenConversionPreflightCarriesAssignmentSnapshotWithoutProjectIdentity() throws {
        let preflight = try JSONDecoder().decode(
            ConversionPreflight.self,
            from: Data("""
            {
              "existing_linked_project": null,
              "duplicate_candidates": [],
              "other_client_projects": [],
              "suggested_name": null,
              "already_converted": true,
              "project_accessible": false,
              "assignment_version": 14
            }
            """.utf8)
        )

        XCTAssertTrue(preflight.isCommittedWithoutAccessibleProject)
        XCTAssertEqual(preflight.assignmentVersion, 14)
        XCTAssertNil(preflight.existingLinkedProject)
        XCTAssertTrue(preflight.duplicateCandidates.isEmpty)
        XCTAssertTrue(preflight.otherClientProjects.isEmpty)
    }

    @MainActor
    func testHiddenConversionPresentationMarkerPersistsOnlyLeadIdentity() throws {
        let suiteName = "LeadAssignmentFoundationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "hidden-conversion-test"

        let first = LeadConversionVisibilityStore(
            defaults: defaults,
            storageKey: storageKey
        )
        first.markCommittedWithoutAccessibleProject("lead-1")

        let restored = LeadConversionVisibilityStore(
            defaults: defaults,
            storageKey: storageKey
        )
        XCTAssertTrue(restored.contains("lead-1"))
        XCTAssertEqual(defaults.stringArray(forKey: storageKey), ["lead-1"])

        restored.clear("lead-1")
        XCTAssertFalse(
            LeadConversionVisibilityStore(
                defaults: defaults,
                storageKey: storageKey
            ).contains("lead-1")
        )
    }

    func testUncommittedConversionResultFailsClosed() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": false,
              "already_converted": false,
              "project_accessible": false
            }
            """.utf8)
        )

        XCTAssertThrowsError(try LeadConversionOutcomeResolver.disposition(for: result))
    }

    func testConversionMustProveTheWonTransitionCommitted() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": true,
              "already_converted": false,
              "won": false,
              "project_id": "project-1",
              "project_accessible": true
            }
            """.utf8)
        )

        XCTAssertThrowsError(try LeadConversionOutcomeResolver.disposition(for: result))
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

    func testMigrationPlanDeclaresARealAssignmentBoundary() throws {
        // The assignment + chase boundary lives at V18 after the main-line
        // reconciliation (V16 = opportunity media, V17 = vinyl color/PO).
        // V19 is a later additive lead-ownership boundary and must not move it.
        XCTAssertEqual(OPSMigrationPlan.schemas.count, 20)
        XCTAssertEqual(OPSMigrationPlan.stages.count, 19)
        let versions = OPSMigrationPlan.schemas.map {
            String(describing: $0.versionIdentifier)
        }
        XCTAssertEqual(versions.firstIndex(of: "18.0.0"), 17)
        XCTAssertEqual(
            String(describing: try XCTUnwrap(OPSMigrationPlan.schemas.last).versionIdentifier),
            "20.0.0"
        )
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
