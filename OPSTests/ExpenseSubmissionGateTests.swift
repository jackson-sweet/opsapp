//
//  ExpenseSubmissionGateTests.swift
//  OPSTests
//
//  Regression coverage for the expense submit gate — the enforcement that was
//  missing when photo-less expenses could be submitted at companies with
//  require_receipt_photo = TRUE (bug 07b7a1b3). The same rule backs the
//  require_project_assignment gate. These lock the truth table so a future
//  refactor of ExpenseFormSheet can't silently re-open the hole.
//

import XCTest
@testable import OPS

final class ExpenseSubmissionGateTests: XCTestCase {

    // The core defect: a submit meets a live requirement with neither the
    // artifact nor a reason → BLOCKED.
    func testSubmitBlockedWhenRequiredAndNoArtifactAndNoReason() {
        XCTAssertFalse(ExpenseSubmissionGate.passes(submit: true, required: true, hasArtifact: false, hasReason: false))
    }

    // A real artifact (receipt photo / project) satisfies the requirement.
    func testSubmitAllowedWhenRequiredAndArtifactPresent() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: true, required: true, hasArtifact: true, hasReason: false))
    }

    // The escape hatch (explicit "no receipt / no project" reason) satisfies it.
    func testSubmitAllowedWhenRequiredAndReasonProvided() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: true, required: true, hasArtifact: false, hasReason: true))
    }

    // Draft saves are never gated, even when the company requires the artifact.
    func testDraftNeverBlockedEvenWhenRequired() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: false, required: true, hasArtifact: false, hasReason: false))
    }

    // Companies that don't require the artifact never block a submit.
    func testSubmitAllowedWhenNotRequired() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: true, required: false, hasArtifact: false, hasReason: false))
    }

    // Exhaustive truth table across all 16 input combinations.
    // Passes iff the save isn't a gated submit, or an artifact/reason is present.
    func testFullTruthTable() {
        for submit in [true, false] {
            for required in [true, false] {
                for hasArtifact in [true, false] {
                    for hasReason in [true, false] {
                        let expected = (!submit || !required) || hasArtifact || hasReason
                        XCTAssertEqual(
                            ExpenseSubmissionGate.passes(submit: submit, required: required, hasArtifact: hasArtifact, hasReason: hasReason),
                            expected,
                            "submit=\(submit) required=\(required) hasArtifact=\(hasArtifact) hasReason=\(hasReason)"
                        )
                    }
                }
            }
        }
    }
}
