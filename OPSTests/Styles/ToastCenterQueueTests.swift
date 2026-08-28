//
//  ToastCenterQueueTests.swift
//  OPSTests
//
//  Deterministic tests for the ToastCenter FIFO queue: coalescing, advancing,
//  cap, manual-hold errors, and transition-bound sync-indicator suppression.
//

import XCTest
@testable import OPS

@MainActor
final class ToastCenterQueueTests: XCTestCase {
    private var center: ToastCenter { ToastCenter.shared }

    override func setUp() {
        super.setUp()
        center.reset()
    }

    override func tearDown() {
        center.reset()
        super.tearDown()
    }

    func testShowsImmediatelyWhenIdle() {
        center.present(Toast(label: "// A", tone: .success))
        XCTAssertEqual(center.current?.label, "// A")
        XCTAssertTrue(center.queue.isEmpty)
    }

    func testSecondToastQueuesBehindCurrent() {
        center.present(Toast(label: "// A", tone: .success))
        center.present(Toast(label: "// B", tone: .success))
        XCTAssertEqual(center.current?.label, "// A")
        XCTAssertEqual(center.queue.count, 1)
    }

    func testCoalescesIdenticalLabels() {
        center.present(Toast(label: "// A", tone: .success))
        center.present(Toast(label: "// B", tone: .success))
        center.present(Toast(label: "// B", tone: .success)) // dup of queue.last
        XCTAssertEqual(center.queue.count, 1)
        center.present(Toast(label: "// A", tone: .success)) // dup of current
        XCTAssertEqual(center.queue.count, 1)
    }

    func testDismissAdvancesQueue() {
        center.present(Toast(label: "// A", tone: .success))
        center.present(Toast(label: "// B", tone: .success))
        center.dismiss()
        XCTAssertEqual(center.current?.label, "// B")
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testSyncIndicatorSuppressionFollowsVisibleToastThroughRemoval() async {
        center.present(Toast(label: "// FIRST", tone: .success, autoDismissAfter: 600))
        center.present(
            Toast(
                label: "// SYNC RESTORED",
                tone: .success,
                autoDismissAfter: 600,
                suppressesSyncStatusIndicator: true
            )
        )

        XCTAssertFalse(center.isSuppressingSyncStatusIndicator)
        center.dismiss()
        XCTAssertTrue(center.isSuppressingSyncStatusIndicator)
        center.dismiss()
        XCTAssertTrue(center.isSuppressingSyncStatusIndicator)

        try? await Task.sleep(
            nanoseconds: UInt64(
                (OPSStyle.Animation.durationPanel + 0.1) * 1_000_000_000
            )
        )
        XCTAssertFalse(center.isSuppressingSyncStatusIndicator)
    }

    func testSyncIndicatorSuppressionSurvivesQueuedToastReplacement() async {
        center.present(
            Toast(
                label: "// SYNC RESTORED",
                tone: .success,
                autoDismissAfter: 600,
                suppressesSyncStatusIndicator: true
            )
        )
        center.present(Toast(label: "// NEXT", tone: .success, autoDismissAfter: 600))

        center.dismiss()
        XCTAssertEqual(center.current?.label, "// NEXT")
        XCTAssertTrue(center.isSuppressingSyncStatusIndicator)

        try? await Task.sleep(
            nanoseconds: UInt64(
                (OPSStyle.Animation.durationPage + 0.1) * 1_000_000_000
            )
        )
        XCTAssertFalse(center.isSuppressingSyncStatusIndicator)
    }

    func testNewToastDuringRemovalCannotReleaseOutgoingSyncSuppression() async {
        center.present(
            Toast(
                label: "// SYNC RESTORED",
                tone: .success,
                autoDismissAfter: 600,
                suppressesSyncStatusIndicator: true
            )
        )
        // Let the dedicated toast host render the banner. Without a rendered
        // transition there is no outgoing visual lifetime to suppress.
        try? await Task.sleep(nanoseconds: 50_000_000)

        center.dismiss()
        XCTAssertTrue(center.isSuppressingSyncStatusIndicator)
        center.present(Toast(label: "// NEXT", tone: .success, autoDismissAfter: 600))
        XCTAssertEqual(center.current?.label, "// NEXT")
        XCTAssertTrue(center.isSuppressingSyncStatusIndicator)

        try? await Task.sleep(
            nanoseconds: UInt64(
                (OPSStyle.Animation.durationPanel + 0.1) * 1_000_000_000
            )
        )
        XCTAssertFalse(center.isSuppressingSyncStatusIndicator)
    }

    func testOverlappingDismissalsRetainEarlierSuppressingRemoval() async {
        center.present(
            Toast(
                label: "// SYNC RESTORED",
                tone: .success,
                autoDismissAfter: 600,
                suppressesSyncStatusIndicator: true
            )
        )
        center.present(Toast(label: "// NEXT", tone: .success, autoDismissAfter: 600))

        center.dismiss()
        XCTAssertEqual(center.current?.label, "// NEXT")
        XCTAssertTrue(center.isSuppressingSyncStatusIndicator)

        center.dismiss()
        XCTAssertNil(center.current)
        XCTAssertTrue(
            center.isSuppressingSyncStatusIndicator,
            "The earlier suppressing banner still owns the latch while its removal is visible"
        )

        try? await Task.sleep(
            nanoseconds: UInt64(
                (OPSStyle.Animation.durationPage + 0.1) * 1_000_000_000
            )
        )
        XCTAssertFalse(center.isSuppressingSyncStatusIndicator)
    }

    func testOutgoingToastReleasesInteractionAndAccessibilityOwnership() {
        XCTAssertTrue(ToastBannerOwnership.isInteractive(phase: .willAppear))
        XCTAssertTrue(ToastBannerOwnership.isInteractive(phase: .identity))
        XCTAssertFalse(ToastBannerOwnership.isInteractive(phase: .didDisappear))
    }

    func testQueueCapDropsOldestAutoDismiss() {
        center.present(Toast(label: "// 0", tone: .success)) // becomes current
        for i in 1...5 { center.present(Toast(label: "// \(i)", tone: .success)) }
        XCTAssertEqual(center.queue.count, 3)
    }

    func testManualHoldErrorDoesNotAutoSchedule() {
        center.present(Toast(label: "// ERR", tone: .error, autoDismissAfter: 0,
                             action: ToastAction(label: "RETRY", handler: {})))
        XCTAssertEqual(center.current?.label, "// ERR")
        center.dismiss()
        XCTAssertNil(center.current)
    }
}
