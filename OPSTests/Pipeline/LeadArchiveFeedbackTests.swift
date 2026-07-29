//
//  LeadArchiveFeedbackTests.swift
//  OPSTests
//
//  Bug e0c8084f, archive half. Discarding a lead captures a reason and an
//  optional note (Phase C, shipped). Archiving captured nothing — one confirm
//  dialog, a bare `archived_at` PATCH, and the reason the owner parked a real
//  job was gone.
//
//  Archive is the REVERSIBLE exit, so the design stays light: one tap still
//  archives, a reason is optional, a note is optional. These tests pin that
//  contract, the RPC names, and the two degradation paths that keep the field
//  working — an archive RPC that prod has not deployed yet, and a discard flow
//  opened with no connectivity.
//

import XCTest
import Supabase
@testable import OPS

final class LeadArchiveFeedbackTests: XCTestCase {

    // MARK: - Contract

    func testRepositoryUsesTheGuardedArchiveRPCs() {
        XCTAssertEqual(
            OpportunityRepository.RPC.applyLeadArchive,
            "apply_lead_archive_feedback"
        )
        XCTAssertEqual(
            OpportunityRepository.RPC.undoLeadArchive,
            "undo_lead_archive_feedback"
        )
    }

    func testArchiveReasonsAreOptionalAndParkingShaped() {
        // Archive answers "why is this parked", never "why was this junk" —
        // that is what discard is for. Keeping the vocabularies separate is what
        // stops archive from becoming a second, softer discard.
        XCTAssertEqual(
            LeadArchiveReason.selectableReasons,
            [.notNow, .seasonal, .waitingOnClient, .other]
        )
        XCTAssertFalse(LeadArchiveReason.selectableReasons.contains(.unspecified))
    }

    func testArchiveReasonRawValuesMatchTheServerVocabulary() {
        XCTAssertEqual(LeadArchiveReason.notNow.rawValue, "not_now")
        XCTAssertEqual(LeadArchiveReason.seasonal.rawValue, "seasonal")
        XCTAssertEqual(LeadArchiveReason.waitingOnClient.rawValue, "waiting_on_client")
        XCTAssertEqual(LeadArchiveReason.other.rawValue, "other")
        XCTAssertEqual(LeadArchiveReason.unspecified.rawValue, "archive_unspecified")
    }

    func testEveryArchiveReasonCarriesLabelAndDetail() {
        for reason in LeadArchiveReason.selectableReasons {
            XCTAssertFalse(reason.label.isEmpty, "\(reason.rawValue) has no label")
            XCTAssertEqual(
                reason.label, reason.label.uppercased(),
                "reason labels carry authority — uppercase (\(reason.rawValue))"
            )
            XCTAssertFalse(reason.detail.isEmpty, "\(reason.rawValue) has no detail")
        }
    }

    func testNoReasonChosenSubmitsTheUnspecifiedCode() {
        // One tap on ARCHIVE with nothing selected is a first-class path, not
        // an error — the server records `archive_unspecified`.
        XCTAssertEqual(LeadArchiveReason.submittedCode(for: nil), "archive_unspecified")
        XCTAssertEqual(LeadArchiveReason.submittedCode(for: .seasonal), "seasonal")
    }

    func testArchiveNoteObeysTheSameCeilingAsDisposition() {
        let long = String(repeating: "x", count: 400)
        let normalized = LeadDispositionInteractionPolicy.normalizedNote(long)
        XCTAssertEqual(normalized?.count, LeadDispositionInteractionPolicy.noteLimit)
        XCTAssertNil(LeadDispositionInteractionPolicy.normalizedNote("   "))
    }

    // MARK: - Degradation: archive RPC absent in prod

    func testMissingArchiveRPCFallsBackToTheLegacyPatch() {
        // Pre-migration prod has no `apply_lead_archive_feedback`. PostgREST
        // answers PGRST202. The owner must still be able to archive.
        XCTAssertTrue(
            LeadArchiveCapability.shouldFallBackToLegacyArchive(
                forRPCError: PostgrestError(code: "PGRST202", message: "function not found")
            ),
            "an undeployed RPC must degrade to the legacy archive, never dead-end"
        )
        // The repository translates that into its own case once it has latched
        // the capability, so the flow must accept both shapes.
        XCTAssertTrue(
            LeadArchiveCapability.shouldFallBackToLegacyArchive(
                forRPCError: OpportunityRepositoryError.archiveRPCUnavailable
            )
        )
    }

    func testRealFailuresDoNotSilentlyFallBack() {
        // A permission denial is a real answer — falling back would archive a
        // lead the server just refused to archive.
        XCTAssertFalse(
            LeadArchiveCapability.shouldFallBackToLegacyArchive(
                forRPCError: PostgrestError(code: "42501", message: "opportunity_access_denied")
            )
        )
        XCTAssertFalse(
            LeadArchiveCapability.shouldFallBackToLegacyArchive(
                forRPCError: OpportunityRepositoryError.guardedCreateRejected
            )
        )
        XCTAssertFalse(
            LeadArchiveCapability.shouldFallBackToLegacyArchive(
                forRPCError: URLError(.notConnectedToInternet)
            ),
            "offline is not 'the RPC does not exist' — retry, do not half-write"
        )
    }

    // MARK: - Degradation: discard with no connectivity

    func testDiscardRoutesToLegacyConfirmWhenTheContextCheckFails() {
        // The shipped Phase C flow blocks on `get_lead_disposition_context`
        // before showing anything, so a truck with no bars could not discard at
        // all. A context failure must fall through to the legacy confirm.
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.routeWhenContextUnavailable(explainerSeen: true),
            .legacyConfirmation
        )
    }

    func testFirstTimeDiscardOfflineStillGetsItsExplainer() {
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.routeWhenContextUnavailable(explainerSeen: false),
            .legacyExplainer
        )
    }

    func testOnlineRoutingIsUnchanged() {
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.route(phaseCEnabled: true, explainerSeen: true),
            .structuredReason
        )
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.route(phaseCEnabled: false, explainerSeen: false),
            .legacyExplainer
        )
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.route(phaseCEnabled: false, explainerSeen: true),
            .legacyConfirmation
        )
    }

    // MARK: - Receipt decoding

    func testArchiveReceiptDecodesTheRPCRow() throws {
        let json = """
        [{
          "feedback_id": "3f2a5c11-2b4e-4a44-9a1e-6c7d8e9f0a1b",
          "outcome": "archived",
          "prior_archived_at": null,
          "current_archived_at": "2026-07-28T18:30:00+00:00",
          "current_opportunity_updated_at": "2026-07-28T18:30:00+00:00",
          "lifecycle_changed": true,
          "idempotent_replay": false
        }]
        """.data(using: .utf8)!

        let rows = try JSONDecoder().decode([LeadArchiveResult].self, from: json)
        let result = try XCTUnwrap(rows.first)

        XCTAssertEqual(result.feedbackId, "3f2a5c11-2b4e-4a44-9a1e-6c7d8e9f0a1b")
        XCTAssertEqual(result.outcome, "archived")
        XCTAssertNil(result.priorArchivedAt)
        XCTAssertNotNil(result.currentArchivedAt)
        XCTAssertTrue(result.lifecycleChanged)
        XCTAssertFalse(result.idempotentReplay)
    }

    @MainActor
    func testArchiveResultAppliesToTheLocalLead() {
        let lead = Opportunity.preview(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: "Roof tear-off, 28 sq",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9
        )
        XCTAssertNil(lead.archivedAt)

        let archivedAt = Date(timeIntervalSince1970: 1_785_000_000)
        LeadArchiveLocalState.apply(
            LeadArchiveResult(
                feedbackId: "3f2a5c11-2b4e-4a44-9a1e-6c7d8e9f0a1b",
                outcome: "archived",
                priorArchivedAt: nil,
                currentArchivedAt: archivedAt,
                currentOpportunityUpdatedAt: archivedAt,
                lifecycleChanged: true,
                idempotentReplay: false
            ),
            to: lead
        )

        XCTAssertEqual(lead.archivedAt, archivedAt)
        XCTAssertTrue(lead.isArchived)
    }

    @MainActor
    func testUndoRestoresTheLeadToTheBoard() {
        let lead = Opportunity.preview(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            title: "Roof tear-off, 28 sq",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 14_200,
            daysInStage: 9
        )
        lead.archivedAt = Date(timeIntervalSince1970: 1_785_000_000)

        LeadArchiveLocalState.applyUndo(
            LeadArchiveResult(
                feedbackId: "3f2a5c11-2b4e-4a44-9a1e-6c7d8e9f0a1b",
                outcome: "archived",
                priorArchivedAt: nil,
                currentArchivedAt: nil,
                currentOpportunityUpdatedAt: Date(timeIntervalSince1970: 1_785_000_100),
                lifecycleChanged: true,
                idempotentReplay: false
            ),
            to: lead
        )

        XCTAssertNil(lead.archivedAt)
        XCTAssertFalse(lead.isArchived)
    }
}
