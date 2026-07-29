//
//  ConvertSheetMatchingTests.swift
//  OPSTests
//
//  Bugs 5468b3c6 (matching dead-ends) and ced5b3cb (the badge that should link
//  but navigated — or worse, destroyed local state).
//
//  Three defects are pinned here:
//
//  1. The sheet used to SYNTHESIZE `creation_blocker = project_review_required`
//     whenever its own client-side link re-check filtered every server-approved
//     candidate away. That poisoned the entire sheet — MATCH impossible (no
//     selectable chip) and CREATE disabled (blocker set) — with copy that
//     blamed an admin. The blocker is now SERVER-AUTHORED ONLY; already-linked
//     candidates degrade to review-only chips with an honest message.
//
//  2. The preflight read and the candidate link re-read shared one `do` block,
//     so a transient failure of the SECOND read reported as a preflight
//     failure ("COULD NOT CHECK PROJECTS — RETRY") and closed the sheet's only
//     committing action. They are now reported separately.
//
//  3. The idempotent already-converted branch of `convert_opportunity_to_project`
//     returns a REAL project id while hardcoding `project_accessible = false`.
//     The client read that as an access denial and NULLED the lead's project
//     link plus set a PERSISTED marker that hid MATCH PROJECT forever. That
//     shape is now recognised and recovered from, never acted on destructively.
//

import XCTest
@testable import OPS

final class ConvertSheetMatchingTests: XCTestCase {

    // MARK: - Fixtures

    private func preflight(
        candidates: [(id: String, title: String)] = [],
        others: [(id: String, title: String)] = [],
        creationBlocker: String? = nil,
        alreadyConverted: Bool = false,
        projectAccessible: Bool = false,
        existingLinkedProject: (id: String, title: String)? = nil
    ) throws -> ConversionPreflight {
        let candidateJSON = candidates.map {
            """
            {"project_id":"\($0.id)","title":"\($0.title)","address":"3998 Holland Ave",
             "confidence":"high","signals":["same_client","same_address"]}
            """
        }.joined(separator: ",")
        let otherJSON = others.map {
            """
            {"project_id":"\($0.id)","title":"\($0.title)","address":"12 Douglas St","status":"in_progress"}
            """
        }.joined(separator: ",")
        let linkedJSON = existingLinkedProject.map {
            "{\"id\":\"\($0.id)\",\"title\":\"\($0.title)\"}"
        } ?? "null"
        let blockerJSON = creationBlocker.map { "\"\($0)\"" } ?? "null"

        return try JSONDecoder().decode(
            ConversionPreflight.self,
            from: Data("""
            {
              "existing_linked_project": \(linkedJSON),
              "duplicate_candidates": [\(candidateJSON)],
              "other_client_projects": [\(otherJSON)],
              "creation_blocker": \(blockerJSON),
              "suggested_name": "3998 Holland Ave",
              "already_converted": \(alreadyConverted),
              "project_accessible": \(projectAccessible),
              "assignment_version": 4
            }
            """.utf8)
        )
    }

    // MARK: - 1. No client-side blocker synthesis

    /// The regression. Every server-approved candidate is already linked to a
    /// different lead, so nothing is matchable — but the SERVER set no blocker,
    /// so the sheet must not invent one.
    func testAllCandidatesLinkedElsewhereNeverSynthesizesACreationBlocker() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(candidates: [("project-a", "3998 Holland Ave")]),
            matchableCandidateIds: [],
            candidateLinkCheckFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertNil(
            state.creationBlocker,
            "the blocker is server-authored; the client must never synthesize one"
        )
        XCTAssertEqual(state.refs.count, 1)
        XCTAssertEqual(state.refs.first?.linkState, .linkedElsewhere)
        XCTAssertEqual(state.statusMessage, "EVERY MATCH IS LINKED TO ANOTHER LEAD")
    }

    /// A server-authored blocker still governs, verbatim.
    func testServerCreationBlockerIsPreservedWithItsOwnMessage() throws {
        let addressState = ConvertToProjectSheet.reducePreflight(
            try preflight(creationBlocker: "address_required"),
            matchableCandidateIds: [],
            candidateLinkCheckFailed: false,
            unavailableMatchProjectIds: []
        )
        XCTAssertEqual(addressState.creationBlocker, .addressRequired)
        XCTAssertEqual(addressState.statusMessage, "ADD AN ADDRESS TO CHECK EXISTING PROJECTS")

        let reviewState = ConvertToProjectSheet.reducePreflight(
            try preflight(creationBlocker: "project_review_required"),
            matchableCandidateIds: [],
            candidateLinkCheckFailed: false,
            unavailableMatchProjectIds: []
        )
        XCTAssertEqual(reviewState.creationBlocker, .projectReviewRequired)
        XCTAssertEqual(reviewState.statusMessage, "SAME ADDRESS PROJECT — ADMIN ACCESS NEEDED")
    }

    /// A matchable candidate stays matchable, and no notice is raised.
    func testMatchableCandidateStaysSelectableAndQuiet() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(candidates: [("project-a", "3998 Holland Ave")]),
            matchableCandidateIds: ["project-a"],
            candidateLinkCheckFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertEqual(state.refs.first?.linkState, .matchable)
        XCTAssertEqual(state.refs.first?.interaction, .match)
        XCTAssertEqual(state.refs.first?.actionLabel, "MATCH")
        XCTAssertNil(state.statusMessage)
    }

    /// A target this session's commit already rejected cannot come straight
    /// back as an actionable MATCH from the same preflight contract.
    func testRejectedTargetDoesNotReturnAsAnActionableMatch() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(candidates: [("project-a", "3998 Holland Ave")]),
            matchableCandidateIds: ["project-a"],
            candidateLinkCheckFailed: false,
            unavailableMatchProjectIds: ["project-a"]
        )

        XCTAssertEqual(state.refs.first?.linkState, .unavailable)
        XCTAssertEqual(state.refs.first?.interaction, .peek)
        XCTAssertEqual(state.refs.first?.actionLabel, "REVIEW")
    }

    /// Other-client projects are review-only by server contract (cross-address
    /// links are forbidden) — they carry no action label and never gate CREATE.
    func testOtherClientProjectsAreReviewOnlyAndDoNotGateCreate() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(others: [("project-b", "Douglas St porch")]),
            matchableCandidateIds: [],
            candidateLinkCheckFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertEqual(state.refs.first?.linkState, .reviewOnly)
        XCTAssertNil(state.refs.first?.actionLabel)
        XCTAssertNil(state.statusMessage)
        XCTAssertFalse(
            state.refs.contains(where: \.isLikelyDuplicate),
            "an other-client project is not a duplicate and must not block CREATE"
        )
    }

    // MARK: - 2. Split error reporting

    /// A failed candidate link re-read is a CHIP-AREA problem, not a preflight
    /// failure. The server's own answer (blocker, candidates) still stands.
    func testCandidateLinkCheckFailureIsReportedWithoutBlamingThePreflight() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(candidates: [("project-a", "3998 Holland Ave")]),
            matchableCandidateIds: [],
            candidateLinkCheckFailed: true,
            unavailableMatchProjectIds: []
        )

        XCTAssertTrue(state.candidateLinkCheckFailed)
        XCTAssertNil(state.creationBlocker)
        XCTAssertEqual(state.statusMessage, "COULD NOT CHECK PROJECT LINKS — RETRY")
        XCTAssertEqual(
            state.refs.first?.linkState, .unverified,
            "an unverified candidate is neither offered as a match nor declared taken"
        )
    }

    // MARK: - 3. The already-converted branch is not an access denial

    /// The exact prod shape of the idempotent branch: real project id, real
    /// `already_converted`, and a hardcoded `project_accessible: false`.
    func testAlreadyConvertedResultWithAProjectIdRecoversInsteadOfDenying() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": false,
              "already_converted": true,
              "won": true,
              "guard_reason": "already_converted",
              "project_id": "project-1",
              "linked_existing": true,
              "assigned_to": "user-current",
              "assignment_version": 13,
              "project_accessible": false
            }
            """.utf8)
        )

        XCTAssertEqual(
            try LeadConversionOutcomeResolver.disposition(for: result),
            .recoverConvertedProject(projectId: "project-1")
        )
    }

    /// A FRESH commit that reports an inaccessible project is a genuine access
    /// answer — that path is computed server-side and must keep its meaning.
    func testFreshCommitReportingInaccessibleProjectStillWithholdsIdentity() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": true,
              "already_converted": false,
              "won": true,
              "project_id": "project-1",
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

    /// An already-converted result with NO project id has no identity to
    /// recover — it must not fabricate one.
    func testAlreadyConvertedWithoutAProjectIdStillWithholdsIdentity() throws {
        let result = try JSONDecoder().decode(
            ConvertOpportunityResult.self,
            from: Data("""
            {
              "converted": false,
              "already_converted": true,
              "won": true,
              "guard_reason": "already_converted",
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

    // MARK: - 3b. Visibility-store self-repair

    /// Leads already damaged by the destructive path carry a PERSISTED marker
    /// that permanently hides MATCH PROJECT. Opening the lead once, with a
    /// project link present, must heal it.
    @MainActor
    func testVisibilityMarkIsRepairedWhenTheLeadStillHasAProjectLink() {
        let defaults = UserDefaults(suiteName: "ops.tests.visibility.\(UUID().uuidString)")!
        let store = LeadConversionVisibilityStore(defaults: defaults, storageKey: "k")
        store.markCommittedWithoutAccessibleProject("lead-1")
        XCTAssertTrue(store.contains("lead-1"))

        store.repairIfLinked(leadId: "lead-1", projectId: "project-1")

        XCTAssertFalse(store.contains("lead-1"))
    }

    /// A lead with no project link is genuinely in the committed-but-hidden
    /// state; the marker must survive.
    @MainActor
    func testVisibilityMarkSurvivesWhenTheLeadHasNoProjectLink() {
        let defaults = UserDefaults(suiteName: "ops.tests.visibility.\(UUID().uuidString)")!
        let store = LeadConversionVisibilityStore(defaults: defaults, storageKey: "k")
        store.markCommittedWithoutAccessibleProject("lead-1")

        store.repairIfLinked(leadId: "lead-1", projectId: nil)
        store.repairIfLinked(leadId: "lead-1", projectId: "   ")

        XCTAssertTrue(store.contains("lead-1"))
    }

    // MARK: - 4. Server link-guard reasons reach the operator distinctly

    /// Every reason suffix the RPC raises maps to its own operator copy —
    /// "PROJECT CHANGED — REVIEW MATCHES" for all four told the operator
    /// nothing about which door was closed.
    func testEachServerLinkReasonProducesItsOwnOperatorCopy() {
        let cases: [(String, String)] = [
            ("project_link_unavailable: matching_project_requires_review",
             "SAME ADDRESS ALREADY HAS A PROJECT"),
            ("project_link_unavailable: address_required_for_project_match",
             "ADD AN ADDRESS TO MATCH A PROJECT"),
            ("project_link_unavailable: matching_project_link_conflict",
             "PROJECT IS LINKED TO ANOTHER LEAD"),
            ("project_link_unavailable: dedupe_proof_unavailable",
             "COULD NOT CONFIRM DUPLICATES — RETRY"),
        ]

        for (serverMessage, expectedCopy) in cases {
            let mapped = LeadConversionService.mapRPCError(
                NSError(domain: serverMessage, code: 1)
            )
            guard let conversionError = mapped as? LeadConversionError,
                  case .projectLinkUnavailable(let reason) = conversionError else {
                return XCTFail("Expected a project-link guard for \(serverMessage)")
            }
            XCTAssertEqual(
                ConvertToProjectSheet.projectLinkFailureCopy(reason),
                expectedCopy,
                "wrong operator copy for \(serverMessage)"
            )
        }
    }

    /// A bare `project_link_unavailable` keeps the generic review copy.
    func testBareLinkFailureKeepsTheGenericReviewCopy() {
        let mapped = LeadConversionService.mapRPCError(
            NSError(domain: "project_link_unavailable", code: 1)
        )
        guard let conversionError = mapped as? LeadConversionError,
              case .projectLinkUnavailable(let reason) = conversionError else {
            return XCTFail("Expected a project-link guard")
        }
        XCTAssertNil(reason)
        XCTAssertEqual(
            ConvertToProjectSheet.projectLinkFailureCopy(reason),
            "PROJECT CHANGED — REVIEW MATCHES"
        )
    }
}
