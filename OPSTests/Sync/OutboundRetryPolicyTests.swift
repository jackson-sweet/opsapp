//
//  OutboundRetryPolicyTests.swift
//  OPSTests
//
//  Coverage for the SYNC RECOVERY retry state machine (spec §3), exercised
//  through the REAL shared code paths:
//    * `SyncOperationFailurePolicy.apply` — the single state transition that both
//      DataActor.executeOperation and OutboundProcessor.executeOperation call, so
//      the two mirrored paths cannot drift.
//    * `SyncEngine.reenqueueRecoverableOperations` — the launch / reconnect sweep.
//  Plus the invariant that a `parked` op is never picked up by the pending push.
//

import XCTest
import SwiftData
import Supabase
@testable import OPS

@MainActor
final class OutboundRetryPolicyTests: XCTestCase {

    // MARK: - Harness

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SyncOperation.self, configurations: config)
        return ModelContext(container)
    }

    private func makeOp(
        status: String = "pending",
        retryCount: Int = 0,
        operationType: String = "update",
        lastError: String? = nil,
        lastAttemptedAt: Date? = nil,
        entityId: String = "e1"
    ) -> SyncOperation {
        let op = SyncOperation(
            entityType: SyncEntityType.client.rawValue,
            entityId: entityId,
            operationType: operationType,
            payload: Data("{}".utf8),
            changedFields: ["name"]
        )
        op.status = status
        op.retryCount = retryCount
        op.lastError = lastError
        op.lastAttemptedAt = lastAttemptedAt
        return op
    }

    // MARK: - Policy: permanent → parked immediately, no retry consumed

    func testPermanentParksImmediatelyWithoutConsumingRetry() {
        let op = makeOp(status: "inProgress", retryCount: 0)
        let outcome = SyncOperationFailurePolicy.apply(
            .permanent, to: op, errorDescription: "unsupported_opportunity_field"
        )
        XCTAssertEqual(outcome, .parked)
        XCTAssertEqual(op.status, "parked")
        XCTAssertTrue(op.isParked)
        XCTAssertEqual(op.retryCount, 0, "permanent must not burn a retry")
        XCTAssertEqual(op.lastError, "unsupported_opportunity_field")
    }

    func testPermanentDoesNotConsumeRetryEvenMidBudget() {
        let op = makeOp(status: "inProgress", retryCount: 7)
        _ = SyncOperationFailurePolicy.apply(.permanent, to: op, errorDescription: "23514 check")
        XCTAssertEqual(op.status, "parked")
        XCTAssertEqual(op.retryCount, 7, "retryCount is untouched on a park")
    }

    // MARK: - Policy: transient increments; parks at "failed" after 20

    func testTransientIncrementsAndStaysPendingUnderCap() {
        let op = makeOp(status: "inProgress", retryCount: 0)
        let outcome = SyncOperationFailurePolicy.apply(.transient, to: op, errorDescription: "timeout")
        XCTAssertEqual(outcome, .retryScheduled(retryCount: 1))
        XCTAssertEqual(op.status, "pending")
        XCTAssertEqual(op.retryCount, 1)
        XCTAssertEqual(op.lastError, "timeout")
    }

    func testTransientExhaustsToFailedAtCap() {
        let op = makeOp(status: "inProgress", retryCount: 0)
        var lastOutcome: SyncFailureOutcome = .parked
        for _ in 0..<20 {
            lastOutcome = SyncOperationFailurePolicy.apply(.transient, to: op, errorDescription: "504")
        }
        XCTAssertEqual(op.retryCount, 20)
        XCTAssertEqual(op.status, "failed")
        XCTAssertEqual(lastOutcome, .exhausted(retryCount: 20))
        XCTAssertFalse(op.isParked, "an exhausted transient op is failed (recoverable), not parked")
    }

    func testTransientJustBeforeCapStaysPending() {
        let op = makeOp(status: "inProgress", retryCount: 18)
        let outcome = SyncOperationFailurePolicy.apply(.transient, to: op, errorDescription: "x")
        XCTAssertEqual(outcome, .retryScheduled(retryCount: 19))
        XCTAssertEqual(op.status, "pending")
    }

    // MARK: - Policy: auth → failed, no retry consumed

    func testAuthMarksFailedWithoutConsumingRetry() {
        let op = makeOp(status: "inProgress", retryCount: 3)
        let outcome = SyncOperationFailurePolicy.apply(.auth, to: op, errorDescription: "JWT expired")
        XCTAssertEqual(outcome, .authExpired)
        XCTAssertEqual(op.status, "failed")
        XCTAssertEqual(op.retryCount, 3)
        XCTAssertEqual(op.lastError, "JWT expired")
    }

    // MARK: - Parked ops are NEVER returned by the pending push fetch

    func testParkedOpIsNotFetchedAsPending() throws {
        let context = try makeContext()
        context.insert(makeOp(status: "pending", entityId: "p1"))
        context.insert(makeOp(status: "parked", entityId: "p2"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "pending" }
        ))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.entityId, "p1")
    }

    func testPermanentFailureRemovesOpFromPendingQueue() throws {
        let context = try makeContext()
        let op = makeOp(status: "inProgress", entityId: "x1")
        context.insert(op)
        _ = SyncOperationFailurePolicy.apply(.permanent, to: op, errorDescription: "42501 RLS")
        try context.save()

        let pending = try context.fetch(FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "pending" }
        ))
        XCTAssertTrue(pending.isEmpty, "a parked op must not be picked up by the pending push")
    }

    // MARK: - Re-enqueue sweep (the real SyncEngine method)

    func testReenqueueSweepFlipsStaleInProgressAndFailedButLeavesParked() throws {
        let container = try ModelContainer(
            for: SyncOperation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let engine = SyncEngine(dimensionedPendingSyncer: StubDimensionedSyncer())
        engine.configure(modelContext: context, connectivity: ConnectivityManager())
        defer { engine.stopForLogoutSync() }

        // Stranded in-flight: lastAttemptedAt older than the 5-min window → pending.
        let staleInProgress = makeOp(status: "inProgress", retryCount: 4, entityId: "stale")
        staleInProgress.lastAttemptedAt = Date().addingTimeInterval(-600)
        // Genuinely in-flight now: recent lastAttemptedAt → left alone.
        let freshInProgress = makeOp(status: "inProgress", retryCount: 1, entityId: "fresh")
        freshInProgress.lastAttemptedAt = Date()
        // Never recorded an attempt → stranded → pending.
        let nilInProgress = makeOp(status: "inProgress", retryCount: 2, entityId: "nilattempt")
        nilInProgress.lastAttemptedAt = nil
        // Exhausted transient → pending, budget reset, lastError kept.
        let failed = makeOp(status: "failed", retryCount: 20, lastError: "server 500", entityId: "failed")
        // Permanent rejection → untouched.
        let parked = makeOp(status: "parked", retryCount: 0, lastError: "23514 check", entityId: "parked")

        for op in [staleInProgress, freshInProgress, nilInProgress, failed, parked] {
            context.insert(op)
        }
        try context.save()

        engine.reenqueueRecoverableOperations()

        XCTAssertEqual(staleInProgress.status, "pending")
        XCTAssertEqual(staleInProgress.retryCount, 4, "stranded in-flight revival keeps retryCount")
        XCTAssertEqual(freshInProgress.status, "inProgress", "a genuinely in-flight op is left alone")
        XCTAssertEqual(nilInProgress.status, "pending")
        XCTAssertEqual(failed.status, "pending")
        XCTAssertEqual(failed.retryCount, 0, "failed revival resets the retry budget")
        XCTAssertEqual(failed.lastError, "server 500", "failed revival preserves lastError")
        XCTAssertEqual(parked.status, "parked", "parked stays parked through the sweep")
        XCTAssertEqual(parked.lastError, "23514 check")
    }
}

/// No-op stand-in so the sweep test's in-memory container only needs
/// `SyncOperation` in its schema (SyncEngine.refreshPendingCount otherwise queries
/// PhotoAnnotation through the real dimensioned syncer).
private final class StubDimensionedSyncer: DimensionedPendingSyncing {
    func pendingDimensionedAnnotationCount(modelContext: ModelContext) -> Int { 0 }
    func syncPendingDimensions(modelContext: ModelContext) async {}
}
