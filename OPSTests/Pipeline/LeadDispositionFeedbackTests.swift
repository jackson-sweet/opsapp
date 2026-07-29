//
//  LeadDispositionFeedbackTests.swift
//  OPSTests
//
//  Phase C lead correction contract: reason vocabulary, canonical outcomes,
//  disabled-mode routing, one-tap semantics, DTO decoding, and guarded Undo
//  state application.
//

import XCTest
@testable import OPS

final class LeadDispositionFeedbackTests: XCTestCase {

    func testRepositoryUsesTheGuardedFeedbackRPCs() {
        XCTAssertEqual(
            OpportunityRepository.RPC.leadDispositionContext,
            "get_lead_disposition_context"
        )
        XCTAssertEqual(
            OpportunityRepository.RPC.applyLeadDisposition,
            "apply_lead_disposition_feedback"
        )
        XCTAssertEqual(
            OpportunityRepository.RPC.undoLeadDisposition,
            "undo_lead_disposition_feedback"
        )
    }

    func testStandardReasonVocabularyExcludesLegacyFallback() {
        XCTAssertEqual(
            LeadDispositionReason.standardReasons,
            [
                .spam,
                .jobApplicant,
                .vendorSales,
                .internalMessage,
                .platformNotification,
                .testTraffic,
                .duplicate,
                .notAFit,
                .other,
            ]
        )
        XCTAssertFalse(LeadDispositionReason.standardReasons.contains(.legacyUnspecified))
    }

    func testEveryReasonMapsToCanonicalOutcome() {
        let expected: [LeadDispositionReason: LeadDispositionOutcome] = [
            .spam: .discarded,
            .jobApplicant: .discarded,
            .vendorSales: .discarded,
            .internalMessage: .discarded,
            .platformNotification: .discarded,
            .testTraffic: .discarded,
            .duplicate: .duplicateReview,
            .notAFit: .lost,
            .other: .reviewDeferred,
            .legacyUnspecified: .discarded,
        ]

        for (reason, outcome) in expected {
            XCTAssertEqual(reason.expectedOutcome, outcome, "\(reason.rawValue) mapped incorrectly")
        }
    }

    func testDuplicateAndOtherNeverChangeLifecycle() {
        XCTAssertFalse(LeadDispositionReason.duplicate.changesLifecycle)
        XCTAssertFalse(LeadDispositionReason.other.changesLifecycle)
        XCTAssertTrue(LeadDispositionReason.spam.changesLifecycle)
        XCTAssertTrue(LeadDispositionReason.notAFit.changesLifecycle)
    }

    func testPhaseCRouteIsStructuredAndStandardReasonsSubmitImmediately() {
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.route(
                phaseCEnabled: true,
                explainerSeen: false
            ),
            .structuredReason
        )
        for reason in LeadDispositionReason.standardReasons {
            XCTAssertEqual(reason.selectionBehavior, .submitImmediately)
            XCTAssertFalse(reason.requiresSecondConfirmation)
        }
    }

    func testDisabledRoutePreservesExistingEducationAndConfirmation() {
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.route(
                phaseCEnabled: false,
                explainerSeen: false
            ),
            .legacyExplainer
        )
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.route(
                phaseCEnabled: false,
                explainerSeen: true
            ),
            .legacyConfirmation
        )
    }

    func testOptionalContextIsTrimmedAndBoundedWithoutBecomingRequired() {
        XCTAssertNil(LeadDispositionInteractionPolicy.normalizedNote("   "))
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.normalizedNote("  Wrong mailbox  "),
            "Wrong mailbox"
        )
        XCTAssertEqual(
            LeadDispositionInteractionPolicy.normalizedNote(String(repeating: "a", count: 400))?.count,
            LeadDispositionInteractionPolicy.noteLimit
        )
    }

    func testApplyAndUndoReuseStableIdempotencyKeysUntilCompletion() {
        var keys = LeadDispositionIdempotencyKeys()

        XCTAssertEqual(
            keys.applyKey(for: "lead-1", make: { "apply-1" }),
            "apply-1"
        )
        XCTAssertEqual(
            keys.applyKey(for: "lead-1", make: { "apply-2" }),
            "apply-1"
        )
        keys.completeApply(for: "lead-1")
        XCTAssertEqual(
            keys.applyKey(for: "lead-1", make: { "apply-2" }),
            "apply-2"
        )

        XCTAssertEqual(
            keys.undoKey(for: "feedback-1", make: { "undo-1" }),
            "undo-1"
        )
        XCTAssertEqual(
            keys.undoKey(for: "feedback-1", make: { "undo-2" }),
            "undo-1"
        )
        keys.completeUndo(for: "feedback-1")
        XCTAssertEqual(
            keys.undoKey(for: "feedback-1", make: { "undo-2" }),
            "undo-2"
        )
    }

    func testApplyResultDecodesAuthoritativeOutcomeAndPriorStage() throws {
        let payload = """
        {
          "feedback_id": "11111111-1111-1111-1111-111111111111",
          "outcome": "lost",
          "prior_stage": "quoted",
          "current_stage": "lost",
          "current_stage_entered_at": "2026-07-27T20:00:00.000Z",
          "current_stage_manually_set": true,
          "current_lost_reason": "other",
          "current_lost_notes": null,
          "current_actual_close_date": "2026-07-27",
          "lifecycle_changed": true,
          "idempotent_replay": false
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(LeadDispositionResult.self, from: payload)

        XCTAssertEqual(result.feedbackId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(result.outcome, .lost)
        XCTAssertEqual(result.priorStage, .quoted)
        XCTAssertEqual(result.currentStage, .lost)
        XCTAssertTrue(result.lifecycleChanged)
        XCTAssertFalse(result.idempotentReplay)
    }

    @MainActor
    func testAuthoritativeResultAndUndoRestoreLocalLifecycle() {
        let lead = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Jordan Blake",
            stage: .quoted,
            stageEnteredAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let applied = LeadDispositionResult(
            feedbackId: "feedback-1",
            outcome: .discarded,
            priorStage: .quoted,
            currentStage: .discarded,
            currentStageEnteredAt: "2026-07-27T20:00:00.000Z",
            currentStageManuallySet: true,
            currentLostReason: nil,
            currentLostNotes: nil,
            currentActualCloseDate: nil,
            lifecycleChanged: true,
            idempotentReplay: false
        )
        LeadDispositionLocalState.apply(applied, to: lead)
        XCTAssertEqual(lead.stage, .discarded)
        XCTAssertTrue(lead.stageManuallySet)

        let undone = LeadDispositionResult(
            feedbackId: "feedback-1",
            outcome: .discarded,
            priorStage: .quoted,
            currentStage: .quoted,
            currentStageEnteredAt: "2026-07-27T19:00:00.000Z",
            currentStageManuallySet: false,
            currentLostReason: nil,
            currentLostNotes: nil,
            currentActualCloseDate: nil,
            lifecycleChanged: true,
            idempotentReplay: false
        )
        LeadDispositionLocalState.applyUndo(undone, to: lead)
        XCTAssertEqual(lead.stage, .quoted)
    }
}
