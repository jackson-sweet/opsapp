//
//  ShareCaptureOutcomeTests.swift
//  OPSTests
//
//  The share sheet may only celebrate once every selected image has been
//  durably written to the cross-process queue. A zero/partial queue is a visible
//  failure so the operator can retry without being told unsaved photos landed.
//

import XCTest
@testable import OPS

final class ShareCaptureOutcomeTests: XCTestCase {

    func testEverySelectedPhotoMustPersistBeforeSuccess() {
        XCTAssertEqual(
            ShareCaptureOutcome(
                selectedCount: 3,
                persistedCount: 3,
                recoveryResult: .committed
            ),
            .queued(count: 3)
        )
        XCTAssertEqual(
            ShareCaptureOutcome(
                selectedCount: 3,
                persistedCount: 2,
                recoveryResult: .committed
            ),
            .failed
        )
        XCTAssertEqual(
            ShareCaptureOutcome(
                selectedCount: 3,
                persistedCount: 0,
                recoveryResult: .rejected
            ),
            .failed
        )
    }

    func testAmbiguousCommitRetainsBytesAndWithholdsRetrySuccess() {
        let outcome = ShareCaptureOutcome(
            selectedCount: 3,
            persistedCount: 3,
            recoveryResult: .uncertain
        )

        XCTAssertEqual(outcome, .retainedForRecovery)
        XCTAssertFalse(
            outcome.shouldDiscardStagedFiles,
            "An ambiguous manifest commit must never delete the only staged photo bytes."
        )
    }
}
