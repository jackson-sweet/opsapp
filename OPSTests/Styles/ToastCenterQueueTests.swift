//
//  ToastCenterQueueTests.swift
//  OPSTests
//
//  Deterministic tests for the ToastCenter FIFO queue: coalescing, advancing,
//  cap, and manual-hold errors. Drives the queue synchronously (no timer waits).
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
