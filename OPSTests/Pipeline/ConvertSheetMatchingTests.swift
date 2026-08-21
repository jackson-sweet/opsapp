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

    /// A row exactly as `get_manual_project_link_candidates` returns it. The
    /// server has ALREADY excluded anything linked to a different lead and has
    /// ALREADY ranked what remains, so the fixture order is the server order.
    private func manual(
        _ id: String,
        _ title: String,
        address: String? = "3998 Holland Ave",
        status: String? = "in_progress",
        sameAddress: Bool = false,
        sameClient: Bool = false
    ) -> ManualProjectLinkCandidate {
        ManualProjectLinkCandidate(
            projectId: id,
            title: title,
            address: address,
            status: status,
            sameAddress: sameAddress,
            sameClient: sameClient
        )
    }

    /// SQL boolean expressions become NULL when the lead has no client. One
    /// nullable ranking hint must never make JSONDecoder discard the entire
    /// authoritative project list.
    func testNullableRankingHintsDecodeAsFalse() throws {
        let candidate = try JSONDecoder().decode(
            ManualProjectLinkCandidate.self,
            from: Data("""
            {
              "project_id": "project-no-client",
              "title": "3185 Fairview Rd",
              "address": "3185 Fairview Rd",
              "status": "accepted",
              "same_address": true,
              "same_client": null
            }
            """.utf8)
        )

        XCTAssertTrue(candidate.sameAddress)
        XCTAssertFalse(candidate.sameClient)
    }

    // MARK: - 1. ONE list, ONE source, ONE selection rule

    /// The heart of D1. The manual-link RPC is the ONLY source of selectable
    /// projects: `duplicate_candidates` and `other_client_projects` answered
    /// different questions with different rules, and merging all three is the
    /// defect. A project the server withheld from the manual list — because it
    /// belongs to another lead — must not reappear from the preflight.
    func testCandidateListComesOnlyFromTheManualLinkRPC() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(
                candidates: [("project-linked-elsewhere", "3998 Holland Ave")],
                others: [("project-other-client", "Douglas St porch")]
            ),
            manualCandidates: [manual("project-a", "3998 Holland Ave", sameAddress: true)],
            candidateLoadFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertEqual(
            state.candidates.map(\.id), ["project-a"],
            "only the manual-link RPC may contribute selectable projects"
        )
    }

    /// Every row that survives is selectable. There is no link-state to check
    /// and therefore no way to render a row the operator cannot choose.
    func testEveryListedProjectIsSelectable() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(),
            manualCandidates: [
                manual("project-a", "Same address", sameAddress: true),
                manual("project-b", "Same client", sameClient: true),
                manual("project-c", "Neither"),
            ],
            candidateLoadFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertEqual(state.candidates.count, 3)
        for candidate in state.candidates {
            XCTAssertFalse(
                candidate.displayTitle.isEmpty,
                "a selectable row must name the project it would link"
            )
        }
    }

    /// The server's ORDER IS THE RANKING (same address + client, then address,
    /// then client, then recency). The client must never re-sort it.
    func testServerRankingIsPreservedVerbatim() throws {
        let serverOrder = [
            manual("project-both", "Both", sameAddress: true, sameClient: true),
            manual("project-address", "Address", sameAddress: true),
            manual("project-client", "Client", sameClient: true),
            manual("project-recent", "Recent"),
        ]
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(),
            manualCandidates: serverOrder,
            candidateLoadFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertEqual(
            state.candidates.map(\.id),
            ["project-both", "project-address", "project-client", "project-recent"]
        )
    }

    /// `same_address` / `same_client` explain a row's rank in the operator's
    /// terms. They are evidence, never eligibility.
    func testEvidenceLabelsExplainTheRankWithoutGatingIt() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(),
            manualCandidates: [
                manual("project-both", "Both", sameAddress: true, sameClient: true),
                manual("project-address", "Address", sameAddress: true),
                manual("project-client", "Client", sameClient: true),
                manual("project-none", "Neither"),
            ],
            candidateLoadFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertEqual(
            state.candidates.map(\.evidenceLabel),
            ["SAME ADDRESS · SAME CLIENT", "SAME ADDRESS", "SAME CLIENT", nil]
        )
    }

    /// A target this session's commit already rejected is dropped from the
    /// list entirely rather than shown as an unselectable row.
    func testRejectedTargetIsDroppedRatherThanShownUnselectable() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(),
            manualCandidates: [
                manual("project-a", "Rejected", sameAddress: true),
                manual("project-b", "Fine"),
            ],
            candidateLoadFailed: false,
            unavailableMatchProjectIds: ["project-a"]
        )

        XCTAssertEqual(state.candidates.map(\.id), ["project-b"])
    }

    /// A server-authored blocker still governs, verbatim — it just describes
    /// the CREATE path now.
    func testServerCreationBlockerIsPreservedWithItsOwnMessage() throws {
        let addressState = ConvertToProjectSheet.reducePreflight(
            try preflight(creationBlocker: "address_required"),
            manualCandidates: [],
            candidateLoadFailed: false,
            unavailableMatchProjectIds: []
        )
        XCTAssertEqual(addressState.creationBlocker, .addressRequired)
        XCTAssertEqual(addressState.statusMessage, "ADD AN ADDRESS, OR PICK THE PROJECT ABOVE")

        let reviewState = ConvertToProjectSheet.reducePreflight(
            try preflight(creationBlocker: "project_review_required"),
            manualCandidates: [],
            candidateLoadFailed: false,
            unavailableMatchProjectIds: []
        )
        XCTAssertEqual(reviewState.creationBlocker, .projectReviewRequired)
        XCTAssertEqual(reviewState.statusMessage, "SAME ADDRESS PROJECT — ADMIN ACCESS NEEDED")
    }

    /// The client must never synthesize a blocker the server did not raise.
    func testClientNeverSynthesizesACreationBlocker() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(candidates: [("project-a", "3998 Holland Ave")]),
            manualCandidates: [],
            candidateLoadFailed: false,
            unavailableMatchProjectIds: []
        )

        XCTAssertNil(
            state.creationBlocker,
            "the blocker is server-authored; the client must never synthesize one"
        )
    }

    // MARK: - 2. A human's choice IS the evidence

    /// D1's core rule. The server applies `address_required` /
    /// `matching_project_requires_review` ONLY when `p_link_to_project_id IS
    /// NULL`. With a link target selected, both blockers are irrelevant and
    /// the commit must be allowed — this is exactly what stranded 39% of the
    /// founder's won leads.
    func testSelectedProjectCommitsThroughEveryCreatePathBlocker() {
        for blocker in [ConversionPreflightCreationBlocker.addressRequired,
                        .projectReviewRequired] {
            XCTAssertTrue(
                ConvertToProjectSheet.canCommitConversion(
                    hasLoadedPreflight: true,
                    preflightFailed: false,
                    isSaving: false,
                    requiresMatchReviewRefresh: false,
                    answer: .link(projectId: "project-a"),
                    requiresExplicitAnswer: true,
                    creationBlocker: blocker
                ),
                "a create-path blocker (\(blocker)) must never gate an explicit MATCH"
            )
        }
    }

    /// The same blockers stay authoritative on the CREATE path.
    func testCreatePathStillObeysTheServerBlocker() {
        XCTAssertFalse(
            ConvertToProjectSheet.canCommitConversion(
                hasLoadedPreflight: true,
                preflightFailed: false,
                isSaving: false,
                requiresMatchReviewRefresh: false,
                answer: .createNew,
                requiresExplicitAnswer: false,
                creationBlocker: .addressRequired
            )
        )
    }

    /// A same-address project makes the answer mandatory — but "create a new
    /// project" is always an available answer, so it is never a dead end.
    func testSameAddressCandidateRequiresAnAnswerButCreateNewIsAlwaysOne() {
        func canCommit(_ answer: ConvertToProjectSheet.LinkAnswer) -> Bool {
            ConvertToProjectSheet.canCommitConversion(
                hasLoadedPreflight: true,
                preflightFailed: false,
                isSaving: false,
                requiresMatchReviewRefresh: false,
                answer: answer,
                requiresExplicitAnswer: true,
                creationBlocker: nil
            )
        }

        XCTAssertFalse(canCommit(.undecided), "an unanswered duplicate risk must not create")
        XCTAssertTrue(canCommit(.createNew), "'none of these' is always an available answer")
        XCTAssertTrue(canCommit(.link(projectId: "project-a")))
    }

    /// With nothing at the same address there is nothing to disambiguate, so
    /// CREATE stays the zero-friction default.
    func testCreateIsTheDefaultAnswerWithoutADuplicateRisk() {
        XCTAssertEqual(
            ConvertToProjectSheet.initialAnswer(for: [
                ConvertToProjectSheet.ProjectLinkCandidate(
                    id: "project-a", title: "Elsewhere", address: nil,
                    status: nil, sameAddress: false, sameClient: true
                )
            ]),
            .createNew
        )

        XCTAssertEqual(
            ConvertToProjectSheet.initialAnswer(for: [
                ConvertToProjectSheet.ProjectLinkCandidate(
                    id: "project-a", title: "Same address", address: nil,
                    status: nil, sameAddress: true, sameClient: false
                )
            ]),
            .undecided
        )
    }

    // MARK: - 2b. A failed read offers a retry, never a dead list

    /// The candidate read failing is a SECTION problem, not a preflight
    /// failure — the server's own answer (blocker, existing link) still
    /// stands. It must surface a retry rather than a list nobody can use.
    func testCandidateLoadFailureIsReportedWithoutBlamingThePreflight() throws {
        let state = ConvertToProjectSheet.reducePreflight(
            try preflight(candidates: [("project-a", "3998 Holland Ave")]),
            manualCandidates: [],
            candidateLoadFailed: true,
            unavailableMatchProjectIds: []
        )

        XCTAssertTrue(state.candidateLoadFailed)
        XCTAssertNil(state.creationBlocker)
        XCTAssertTrue(
            state.candidates.isEmpty,
            "a failed read has no candidates to offer — it must not fall back to preflight rows"
        )
        XCTAssertNil(
            state.statusMessage,
            "the retry block speaks for this state; a second message would be noise"
        )
    }

    /// Search matches what the operator can actually see on the row.
    func testSearchMatchesTitleAndAddress() {
        let candidate = ConvertToProjectSheet.ProjectLinkCandidate(
            id: "project-a",
            title: "Calloway rear deck",
            address: "3998 Holland Ave, Victoria BC",
            status: nil,
            sameAddress: false,
            sameClient: false
        )

        XCTAssertTrue(candidate.matches(""), "an empty query matches everything")
        XCTAssertTrue(candidate.matches("calloway"), "title, case-insensitively")
        XCTAssertTrue(candidate.matches("holland"), "address, case-insensitively")
        XCTAssertTrue(candidate.matches("  deck  "), "a padded query still matches")
        XCTAssertFalse(candidate.matches("pergola"))
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
