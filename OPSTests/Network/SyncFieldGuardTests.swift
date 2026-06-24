//
//  SyncFieldGuardTests.swift
//  OPSTests
//
//  Regression coverage for the silent inbound-sync revert race: a task edit
//  (complete / reschedule / assign) made from a review flow could be overwritten
//  by a stale realtime echo or pull merge during the window where the outbound
//  SyncOperation had already left "pending" (mid-push "inProgress", or
//  "completed" by the time an actor-serialized merge ran). SyncFieldGuard is the
//  single source of truth that the inbound field-guards consult, so these tests
//  pin the op-lifecycle rule directly.
//

import XCTest
@testable import OPS

final class SyncFieldGuardTests: XCTestCase {

    private let window: TimeInterval = 60

    /// Build a standalone SyncOperation (no ModelContext needed) with explicit
    /// status and lifecycle timestamps relative to `now`.
    private func makeOp(
        changed: [String],
        status: String,
        createdAgo: TimeInterval,
        attemptedAgo: TimeInterval? = nil,
        completedAgo: TimeInterval? = nil,
        now: Date
    ) -> SyncOperation {
        let op = SyncOperation(
            entityType: SyncEntityType.projectTask.rawValue,
            entityId: "11111111-1111-4111-8111-111111111111",
            operationType: "update",
            payload: Data(),
            changedFields: changed
        )
        op.status = status
        op.createdAt = now.addingTimeInterval(-createdAgo)
        op.lastAttemptedAt = attemptedAgo.map { now.addingTimeInterval(-$0) }
        op.completedAt = completedAgo.map { now.addingTimeInterval(-$0) }
        return op
    }

    // MARK: - Pending: protected regardless of age

    func testPendingOpProtectsFieldRegardlessOfAge() {
        let now = Date()
        // Offline-queued edit pending for 10 minutes must still win over an echo.
        let op = makeOp(changed: ["status"], status: "pending", createdAgo: 600, now: now)
        let protected = SyncFieldGuard.protectedFields(from: [op], now: now, window: window)
        XCTAssertTrue(protected.contains("status"))
    }

    // MARK: - In-flight (the realtime mid-push echo)

    func testInProgressOpWithinWindowProtectsField() {
        let now = Date()
        // status flipped to "inProgress" before the network await; attempted 1s ago.
        let op = makeOp(changed: ["status"], status: "inProgress", createdAgo: 2, attemptedAgo: 1, now: now)
        let protected = SyncFieldGuard.protectedFields(from: [op], now: now, window: window)
        XCTAssertTrue(protected.contains("status"))
    }

    // MARK: - Just-completed (the actor-serialized pull race — the core bug)

    func testCompletedOpWithinWindowProtectsField() {
        let now = Date()
        // Push completed 3s ago; a stale pre-edit DTO must not revert the reschedule.
        let op = makeOp(
            changed: ["start_date", "end_date", "duration"],
            status: "completed",
            createdAgo: 5, attemptedAgo: 4, completedAgo: 3,
            now: now
        )
        let protected = SyncFieldGuard.protectedFields(from: [op], now: now, window: window)
        XCTAssertTrue(protected.contains("start_date"))
        XCTAssertTrue(protected.contains("end_date"))
        XCTAssertTrue(protected.contains("duration"))
    }

    // MARK: - Self-healing: outside the window the server wins again

    func testCompletedOpOutsideWindowDoesNotProtect() {
        let now = Date()
        // Completed 2 minutes ago — safely reconciled; a later remote edit applies.
        let op = makeOp(
            changed: ["status"],
            status: "completed",
            createdAgo: 130, attemptedAgo: 125, completedAgo: 120,
            now: now
        )
        let protected = SyncFieldGuard.protectedFields(from: [op], now: now, window: window)
        XCTAssertFalse(protected.contains("status"))
        XCTAssertTrue(protected.isEmpty)
    }

    // MARK: - Field-level granularity (concurrent remote edits still merge)

    func testProtectionIsFieldLevelNotRowLevel() {
        let now = Date()
        // The operator completed the task (status); they did NOT touch the crew.
        let op = makeOp(changed: ["status"], status: "completed", createdAgo: 3, completedAgo: 2, now: now)
        let protected = SyncFieldGuard.protectedFields(from: [op], now: now, window: window)
        XCTAssertTrue(protected.contains("status"))
        // A dispatcher's concurrent reassignment must still be applied.
        XCTAssertFalse(protected.contains("team_member_ids"))
    }

    // MARK: - Recently-failed write keeps its local value briefly

    func testFailedRecentOpProtectsField() {
        let now = Date()
        let op = makeOp(changed: ["duration"], status: "failed", createdAgo: 5, attemptedAgo: 2, now: now)
        let protected = SyncFieldGuard.protectedFields(from: [op], now: now, window: window)
        XCTAssertTrue(protected.contains("duration"))
    }

    // MARK: - Union across multiple ops

    func testUnionsFieldsAcrossOps() {
        let now = Date()
        let a = makeOp(changed: ["status"], status: "completed", createdAgo: 4, completedAgo: 2, now: now)
        let b = makeOp(changed: ["start_date", "end_date"], status: "pending", createdAgo: 1, now: now)
        let stale = makeOp(changed: ["task_notes"], status: "completed", createdAgo: 200, completedAgo: 180, now: now)
        let protected = SyncFieldGuard.protectedFields(from: [a, b, stale], now: now, window: window)
        XCTAssertEqual(protected, ["status", "start_date", "end_date"])
        XCTAssertFalse(protected.contains("task_notes")) // stale op contributes nothing
    }

    // MARK: - Empty input

    func testNoOpsProtectsNothing() {
        let now = Date()
        XCTAssertTrue(SyncFieldGuard.protectedFields(from: [], now: now, window: window).isEmpty)
    }

    // MARK: - Boundary: exactly at the window edge is still protected

    func testCompletedExactlyAtCutoffIsProtected() {
        let now = Date()
        // completedAt == cutoff (>= comparison) — inclusive boundary.
        let op = makeOp(changed: ["status"], status: "completed", createdAgo: 120, attemptedAgo: 90, completedAgo: 60, now: now)
        let protected = SyncFieldGuard.protectedFields(from: [op], now: now, window: window)
        XCTAssertTrue(protected.contains("status"))
    }
}
