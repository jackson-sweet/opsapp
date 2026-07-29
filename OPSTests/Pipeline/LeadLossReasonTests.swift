//
//  LeadLossReasonTests.swift
//  OPSTests
//
//  Bug f5c67513 — the lost-reason chips only let an owner blame the market
//  (price, timing, competition, scope) or the customer (no response). There was
//  no way to say "that one was on me", so self-inflicted losses were logged as
//  something else and the pipeline lied back to the owner.
//
//  Also pins the adjacent latent bug the same sheet carries: `lost_reason` is
//  unconstrained text server-side and already holds values this enum has never
//  known (`operator_no_response`, `not_a_lead`, `Other`). Parsing those to nil
//  left the sheet with no chip selected and could overwrite a real reason with
//  whatever the operator happened to tap.
//

import XCTest
@testable import OPS

final class LeadLossReasonTests: XCTestCase {

    // MARK: - Self-attributed reasons

    func testSelfAttributedReasonsExist() {
        XCTAssertEqual(LossReason.droppedBall.rawValue, "dropped_ball")
        XCTAssertEqual(LossReason.forgot.rawValue, "forgot")
    }

    func testSelfAttributedReasonsSitBetweenNoResponseAndOther() {
        // Chips render straight off `allCases` (LostReasonSheet.options), so
        // case order IS the on-screen order. The two self-attributed reasons
        // belong next to NO RESPONSE — same "nobody talked" family — and ahead
        // of the OTHER catch-all, which always closes the row.
        XCTAssertEqual(
            LossReason.allCases,
            [.price, .timing, .competition, .scope, .noResponse, .droppedBall, .forgot, .other]
        )
    }

    func testSelfAttributedLabelsAreOwnedNotHedged() {
        XCTAssertEqual(LossReason.droppedBall.displayName, "DROPPED THE BALL")
        XCTAssertEqual(LossReason.forgot.displayName, "NEVER FOLLOWED UP")
    }

    func testEveryReasonHasANonEmptyLabel() {
        for reason in LossReason.allCases {
            XCTAssertFalse(
                reason.displayName.isEmpty,
                "\(reason.rawValue) renders as an empty chip"
            )
            XCTAssertEqual(
                reason.displayName,
                reason.displayName.uppercased(),
                "chip labels carry authority — uppercase (\(reason.rawValue))"
            )
        }
    }

    // MARK: - Server-authored values (latent bug)

    func testKnownServerValueResolvesToItsCase() {
        XCTAssertEqual(LossReason(storedValue: "no_response"), .noResponse)
        XCTAssertEqual(LossReason(storedValue: "price"), .price)
    }

    func testServerValueMatchingIsCaseAndWhitespaceInsensitive() {
        // Production data contains a capitalised "Other".
        XCTAssertEqual(LossReason(storedValue: "Other"), .other)
        XCTAssertEqual(LossReason(storedValue: "  PRICE "), .price)
    }

    func testUnknownServerValueDoesNotResolveToACase() {
        // `operator_no_response` and `not_a_lead` are live in prod and are not
        // members of this enum. Silently mapping them to a chip would rewrite
        // history on the next save.
        XCTAssertNil(LossReason(storedValue: "operator_no_response"))
        XCTAssertNil(LossReason(storedValue: "not_a_lead"))
        XCTAssertNil(LossReason(storedValue: ""))
        XCTAssertNil(LossReason(storedValue: nil))
    }

    // MARK: - Selection state preserves unknown values

    func testSelectionStartsUnselectedForAnUnknownStoredReason() {
        let state = LostReasonSelection(storedReason: "operator_no_response")
        XCTAssertNil(state.reason, "an unknown value must not masquerade as a chip")
        // Saving stays AVAILABLE even with no chip lit: the lead already has a
        // reason on the record, so the operator can add notes without being
        // forced to pick a chip — and forcing a pick is exactly what would
        // overwrite the server's reason. Requiring a selection here would turn
        // the bug this fix removes back on.
        XCTAssertTrue(
            state.canSave,
            "an existing reason is savable — the operator should not have to overwrite it to add notes"
        )
    }

    func testUnknownStoredReasonSurvivesWhenTheOperatorSavesNothingNew() {
        // The operator opens the sheet on a server-authored reason and dismisses
        // without touching a chip: the original value must be handed back
        // untouched, never nil-ed out.
        let state = LostReasonSelection(storedReason: "operator_no_response")
        XCTAssertEqual(state.resolvedReasonForSave, "operator_no_response")
    }

    func testChoosingAChipReplacesTheUnknownStoredReason() {
        var state = LostReasonSelection(storedReason: "operator_no_response")
        state.reason = .droppedBall
        XCTAssertTrue(state.canSave)
        XCTAssertEqual(state.resolvedReasonForSave, "dropped_ball")
    }

    func testKnownStoredReasonPreselectsItsChip() {
        let state = LostReasonSelection(storedReason: "no_response")
        XCTAssertEqual(state.reason, .noResponse)
        XCTAssertTrue(state.canSave)
        XCTAssertEqual(state.resolvedReasonForSave, "no_response")
    }

    func testFreshSheetHasNothingToSaveUntilAChipIsChosen() {
        var state = LostReasonSelection(storedReason: nil)
        XCTAssertNil(state.resolvedReasonForSave)
        XCTAssertFalse(state.canSave)
        state.reason = .price
        XCTAssertTrue(state.canSave)
        XCTAssertEqual(state.resolvedReasonForSave, "price")
    }
}
