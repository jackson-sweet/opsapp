//
//  AnnotationRetryPolicyTests.swift
//  OPSTests
//
//  Locks the park/cap behavior for the pending-annotation sweep: permanent
//  server rejections park a row after the threshold, parked rows get exactly
//  one retry per launch (so a landed server-side fix self-heals the fleet),
//  and un-parked rows always retry. Bugs 452bab04/0415504f — the sweep used
//  to hammer the same RLS-rejected soft-delete forever.
//

import XCTest
@testable import OPS

final class AnnotationRetryPolicyTests: XCTestCase {

    // MARK: - Sweep decision

    func testUnparkedRowAlwaysAttempts() {
        XCTAssertEqual(
            AnnotationRetryPolicy.sweepDecision(parkedAt: nil, alreadyRetriedThisLaunch: false),
            .attempt
        )
        // The launch flag is irrelevant while un-parked.
        XCTAssertEqual(
            AnnotationRetryPolicy.sweepDecision(parkedAt: nil, alreadyRetriedThisLaunch: true),
            .attempt
        )
    }

    func testParkedRowGetsExactlyOneAttemptPerLaunch() {
        let parkedAt = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertEqual(
            AnnotationRetryPolicy.sweepDecision(parkedAt: parkedAt, alreadyRetriedThisLaunch: false),
            .attempt
        )
        XCTAssertEqual(
            AnnotationRetryPolicy.sweepDecision(parkedAt: parkedAt, alreadyRetriedThisLaunch: true),
            .skip
        )
    }

    // MARK: - Park threshold

    func testParksAtThresholdNotBefore() {
        XCTAssertFalse(AnnotationRetryPolicy.shouldPark(failureCount: 0))
        XCTAssertFalse(AnnotationRetryPolicy.shouldPark(failureCount: AnnotationRetryPolicy.parkThreshold - 1))
        XCTAssertTrue(AnnotationRetryPolicy.shouldPark(failureCount: AnnotationRetryPolicy.parkThreshold))
        XCTAssertTrue(AnnotationRetryPolicy.shouldPark(failureCount: AnnotationRetryPolicy.parkThreshold + 1))
    }

    func testFailureCountIncrementsByOne() {
        XCTAssertEqual(AnnotationRetryPolicy.nextFailureCount(after: 0), 1)
        XCTAssertEqual(AnnotationRetryPolicy.nextFailureCount(after: 2), 3)
    }

    // MARK: - Classifier integration

    /// The park counter must only move on PERMANENT classifications, and the
    /// repository's zero-rows sentinel is exactly that: an RLS-filtered
    /// no-op can never masquerade as transient noise (or as success).
    func testWriteNotAppliedClassifiesPermanent() {
        let kind = UploadErrorClassifier.classify(
            AnnotationSyncError.writeNotApplied(annotationId: "abc")
        )
        guard case .permanent(let code, _) = kind else {
            return XCTFail("writeNotApplied must classify permanent, got \(kind)")
        }
        XCTAssertEqual(code, "PG_0ROWS")
    }
}
