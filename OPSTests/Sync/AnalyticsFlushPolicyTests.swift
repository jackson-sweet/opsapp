//
//  AnalyticsFlushPolicyTests.swift
//  OPSTests
//
//  The analytics flush must never dam (bug 088d82dc).
//
//  The queue is a 1,000-event ring in UserDefaults and a failed batch goes back
//  at the FRONT — so a batch that can never succeed does not merely fail, it
//  blocks every later event until the cap starts dropping the oldest. That is
//  what shipped: `analytics_events` grants the app INSERT and nothing else, the
//  client sent `.upsert(onConflict: "id")` returning a representation, and both
//  the conflict target and the representation need SELECT. Every batch 403'd on
//  a 30-second loop, forever.
//
//  The policy under test is what makes that impossible by construction:
//  a duplicate key is delivery, not failure; a permanent rejection is dropped
//  rather than re-queued; everything else retries.
//

import XCTest
@testable import OPS

final class AnalyticsFlushPolicyTests: XCTestCase {

    /// The old bug's own error. A 403 is permanent, and re-queueing it is what
    /// turned one bad batch into a stalled pipeline.
    func test_outcome_dropsThePermanentlyRejectedBatch() {
        XCTAssertEqual(
            AnalyticsFlushPolicy.outcome(for: SyncError.serverError(statusCode: 403, message: "permission denied for table analytics_events")),
            .drop,
            "a batch the server will keep refusing must never go back at the front of the queue"
        )
    }

    /// Signal loss is the ordinary case on a truck and must keep its retry.
    func test_outcome_retriesTransientFailures() {
        XCTAssertEqual(
            AnalyticsFlushPolicy.outcome(for: URLError(.notConnectedToInternet)),
            .retry
        )
        XCTAssertEqual(
            AnalyticsFlushPolicy.outcome(for: SyncError.serverError(statusCode: 503, message: "upstream unavailable")),
            .retry
        )
    }

    /// An expired token is transient here. The outbound queue owns the
    /// re-authentication escalation; throwing analytics away over it would be
    /// losing data to a condition that fixes itself.
    func test_outcome_retriesAuthFailuresRatherThanDroppingData() {
        XCTAssertEqual(
            AnalyticsFlushPolicy.outcome(for: SyncError.authExpired),
            .retry
        )
    }

    /// A duplicate key means the row is already on the server — the response
    /// was lost on the wire. That is at-least-once delivery working, not a
    /// failure, and it is what the removed upsert was reaching for.
    func test_outcome_readsADuplicateKeyAsAlreadyDelivered() {
        let byCode = SyncError.serverError(statusCode: 409, message: "23505")
        let byPhrase = SyncError.serverError(
            statusCode: 409,
            message: "duplicate key value violates unique constraint \"analytics_events_pkey\""
        )

        XCTAssertEqual(AnalyticsFlushPolicy.outcome(for: byCode), .splitBatch)
        XCTAssertEqual(AnalyticsFlushPolicy.outcome(for: byPhrase), .splitBatch)
    }

    /// The duplicate check runs BEFORE the permanent classification. A 23505
    /// classifies permanent on its own, so the wrong order would drop events
    /// that had in fact been delivered — and drop the ones beside them that had
    /// not, since a Postgres INSERT is all-or-nothing.
    func test_outcome_duplicateDetectionPrecedesThePermanentClassification() {
        let duplicate = SyncError.serverError(
            statusCode: 409,
            message: "duplicate key value violates unique constraint \"analytics_events_pkey\""
        )

        XCTAssertEqual(SyncErrorClassifier.disposition(for: duplicate), .permanent)
        XCTAssertEqual(
            AnalyticsFlushPolicy.outcome(for: duplicate), .splitBatch,
            "a duplicate must split the batch, never be dropped as a permanent rejection"
        )
    }

    /// Casing varies with how the message reached us; the match must not.
    func test_isDuplicateKey_matchesRegardlessOfCasing() {
        XCTAssertTrue(
            AnalyticsFlushPolicy.isDuplicateKey(
                SyncError.serverError(
                    statusCode: 409,
                    message: "DUPLICATE KEY VALUE VIOLATES UNIQUE CONSTRAINT"
                )
            )
        )
    }

    /// A rejection with some other cause is not a duplicate and keeps its own
    /// disposition — the split path exists for one specific verdict.
    func test_isDuplicateKey_ignoresUnrelatedRejections() {
        XCTAssertFalse(
            AnalyticsFlushPolicy.isDuplicateKey(
                SyncError.serverError(statusCode: 400, message: "invalid input syntax for type uuid")
            )
        )
        XCTAssertEqual(
            AnalyticsFlushPolicy.outcome(
                for: SyncError.serverError(statusCode: 400, message: "invalid input syntax for type uuid")
            ),
            .drop
        )
    }

    /// Nothing the policy returns re-queues a batch that cannot succeed. This
    /// is the invariant the bug violated, asserted directly.
    func test_noPermanentFailureCanEverBeRequeued() {
        let permanentErrors: [Error] = [
            SyncError.serverError(statusCode: 400, message: "bad request"),
            SyncError.serverError(statusCode: 403, message: "permission denied"),
            SyncError.serverError(statusCode: 404, message: "no such table"),
            SyncError.serverError(statusCode: 422, message: "unprocessable"),
            SyncError.encodingFailed(detail: "unencodable property")
        ]

        for error in permanentErrors {
            XCTAssertNotEqual(
                AnalyticsFlushPolicy.outcome(for: error), .retry,
                "\(error) can never become deliverable by waiting — re-queueing it dams the queue"
            )
        }
    }
}
