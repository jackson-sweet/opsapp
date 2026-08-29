//
//  PendingWorkRetryTrackerTests.swift
//  OPSTests
//
//  Locks retry feedback to durable queue evidence. Re-arming failed work only
//  moves it into SENDING; it is not success until the item leaves the recovery
//  inventory after that observed in-flight state.
//

import XCTest
@testable import OPS

final class PendingWorkRetryTrackerTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testRearmedItemIsRetryingUntilDurableQueueRemovesIt() {
        let failed = item(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, status: "failed")
        let sending = item(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, status: "pending")
        var tracker = PendingWorkRetryTracker()

        tracker.begin(items: [failed])
        let rearmed = tracker.reconcile(
            inventory: inventory(sending: [sending]),
            now: startedAt
        )

        XCTAssertEqual(tracker.feedbackByID[failed.id], .retrying)
        XCTAssertTrue(rearmed.succeededIDs.isEmpty)

        let completed = tracker.reconcile(
            inventory: inventory(),
            now: startedAt.addingTimeInterval(1)
        )

        XCTAssertEqual(tracker.feedbackByID[failed.id], .succeeded)
        XCTAssertEqual(completed.succeededIDs, [failed.id])
        XCTAssertEqual(tracker.successReceipts.map(\.id), [failed.id])
    }

    func testFailedRetryReturnsToAttentionAndPersists() {
        let failed = item(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, status: "failed")
        let sending = item(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, status: "pending")
        var tracker = PendingWorkRetryTracker()

        tracker.begin(items: [failed])
        _ = tracker.reconcile(inventory: inventory(sending: [sending]), now: startedAt)
        let rejected = tracker.reconcile(
            inventory: inventory(attention: [failed]),
            now: startedAt.addingTimeInterval(1)
        )

        XCTAssertEqual(tracker.feedbackByID[failed.id], .failed)
        XCTAssertEqual(rejected.failedIDs, [failed.id])
        XCTAssertTrue(tracker.successReceipts.isEmpty)
    }

    // MARK: - The failure flash (bug b8312e21)

    /// The bug: a failed retry flipped the row to the generic "Retry failed —
    /// still here" and it NEVER came back, masking the row's real cause forever.
    /// The ask was flash, then persist — so the feedback expires and the row's
    /// own status line returns.
    func testFailureFeedbackFlashesThenYieldsToTheRowsTrueStatus() {
        let failed = item(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, status: "failed")
        let sending = item(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, status: "pending")
        var tracker = PendingWorkRetryTracker()

        tracker.begin(items: [failed])
        _ = tracker.reconcile(inventory: inventory(sending: [sending]), now: startedAt)
        let flashedAt = startedAt.addingTimeInterval(1)
        _ = tracker.reconcile(inventory: inventory(attention: [failed]), now: flashedAt)
        XCTAssertEqual(tracker.feedbackByID[failed.id], .failed)

        // Still flashing a hair under the hold.
        let stillFlashing = tracker.reconcile(
            inventory: inventory(attention: [failed]),
            now: flashedAt.addingTimeInterval(PendingWorkRetryTracker.failureFlashDuration - 0.1)
        )
        XCTAssertEqual(tracker.feedbackByID[failed.id], .failed)
        XCTAssertTrue(stillFlashing.expiredFailureIDs.isEmpty)

        // At the hold it expires — feedback gone, ROW still standing.
        let expired = tracker.reconcile(
            inventory: inventory(attention: [failed]),
            now: flashedAt.addingTimeInterval(PendingWorkRetryTracker.failureFlashDuration)
        )
        XCTAssertNil(
            tracker.feedbackByID[failed.id],
            "the generic retry feedback must stop masking the row's real cause"
        )
        XCTAssertEqual(expired.expiredFailureIDs, [failed.id])
        XCTAssertTrue(expired.failedIDs.isEmpty, "expiry must not re-report a failure (no repeat haptic)")
    }

    /// Bad news is held twice as long as good news, and long enough to read at
    /// arm's length.
    func testFailureFlashOutlastsTheSuccessReceipt() {
        XCTAssertEqual(PendingWorkRetryTracker.failureFlashDuration, 4)
        XCTAssertGreaterThan(
            PendingWorkRetryTracker.failureFlashDuration,
            PendingWorkRetryTracker.successReceiptDuration
        )
    }

    /// A retry begun during the flash re-arms cleanly rather than inheriting the
    /// old attempt's expiry clock.
    func testRetryBegunDuringTheFlashReArmsNormally() {
        let failed = item(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, status: "failed")
        let sending = item(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, status: "pending")
        var tracker = PendingWorkRetryTracker()

        tracker.begin(items: [failed])
        _ = tracker.reconcile(inventory: inventory(sending: [sending]), now: startedAt)
        let flashedAt = startedAt.addingTimeInterval(1)
        _ = tracker.reconcile(inventory: inventory(attention: [failed]), now: flashedAt)
        XCTAssertEqual(tracker.feedbackByID[failed.id], .failed)

        // The operator taps RETRY mid-flash.
        tracker.begin(items: [failed])
        XCTAssertEqual(tracker.feedbackByID[failed.id], .retrying)

        let rearmed = tracker.reconcile(
            inventory: inventory(sending: [sending]),
            now: flashedAt.addingTimeInterval(PendingWorkRetryTracker.failureFlashDuration + 1)
        )
        XCTAssertEqual(
            tracker.feedbackByID[failed.id], .retrying,
            "a fresh attempt must not expire on the previous attempt's clock"
        )
        XCTAssertTrue(rearmed.expiredFailureIDs.isEmpty)
    }

    /// The success path is untouched by the failure flash.
    func testSuccessReceiptsAreUnaffectedByTheFailureFlash() {
        let failed = item(id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!, status: "failed")
        let sending = item(id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!, status: "pending")
        var tracker = PendingWorkRetryTracker()

        tracker.begin(items: [failed])
        _ = tracker.reconcile(inventory: inventory(sending: [sending]), now: startedAt)
        let done = tracker.reconcile(inventory: inventory(), now: startedAt.addingTimeInterval(1))

        XCTAssertEqual(done.succeededIDs, [failed.id])
        XCTAssertTrue(done.expiredFailureIDs.isEmpty)
        XCTAssertEqual(tracker.feedbackByID[failed.id], .succeeded)
    }

    func testSuccessReceiptExpiresOnlyAfterVisibleHold() {
        let failed = item(id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!, status: "failed")
        let sending = item(id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!, status: "pending")
        var tracker = PendingWorkRetryTracker()

        tracker.begin(items: [failed])
        _ = tracker.reconcile(inventory: inventory(sending: [sending]), now: startedAt)
        _ = tracker.reconcile(inventory: inventory(), now: startedAt.addingTimeInterval(1))
        _ = tracker.reconcile(
            inventory: inventory(),
            now: startedAt.addingTimeInterval(1 + PendingWorkRetryTracker.successReceiptDuration - 0.01)
        )
        XCTAssertEqual(tracker.successReceipts.map(\.id), [failed.id])

        let expired = tracker.reconcile(
            inventory: inventory(),
            now: startedAt.addingTimeInterval(1 + PendingWorkRetryTracker.successReceiptDuration)
        )

        XCTAssertTrue(tracker.successReceipts.isEmpty)
        XCTAssertEqual(expired.expiredSuccessIDs, [failed.id])
    }

    func testMissingItemBeforeInFlightEvidenceIsFailureNotSuccess() {
        let failed = item(id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!, status: "failed")
        var tracker = PendingWorkRetryTracker()

        tracker.begin(items: [failed])
        let missing = tracker.reconcile(inventory: inventory(), now: startedAt)

        XCTAssertEqual(tracker.feedbackByID[failed.id], .failed)
        XCTAssertTrue(missing.succeededIDs.isEmpty)
        XCTAssertEqual(missing.failedIDs, [failed.id])
    }

    private func item(id: UUID, status: String) -> RecoveryItem {
        .op(
            SyncOpSnapshot(
                id: id,
                entityType: "project",
                entityId: "project-1",
                operationType: "update",
                status: status,
                retryCount: status == "failed" ? 20 : 0,
                lastAttemptedAt: startedAt,
                lastError: status == "failed" ? "server rejected update" : nil,
                createdAt: startedAt.addingTimeInterval(-60)
            ),
            tone: status == "failed" ? .attention : .waiting,
            nextEligibleAt: nil
        )
    }

    private func inventory(
        attention: [RecoveryItem] = [],
        sending: [RecoveryItem] = []
    ) -> RecoveryInventory {
        RecoveryInventory(attention: attention, sending: sending, drafts: [], unlinked: [])
    }
}
