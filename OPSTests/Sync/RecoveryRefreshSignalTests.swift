//
//  RecoveryRefreshSignalTests.swift
//  OPSTests
//
//  The sync pill and the PENDING WORK screen no longer poll every 2 seconds —
//  they refresh when the store changes. That makes three things load-bearing and
//  worth locking: every source notification reaches the surfaces, a save storm
//  costs one refresh rather than one per save, and the pipeline keeps firing
//  after the first burst (a one-shot signal would freeze both surfaces).
//

import Combine
import SwiftData
import XCTest
@testable import OPS

@MainActor
final class RecoveryRefreshSignalTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// Comfortably past the 500ms debounce without being slow enough to matter.
    private let settleWindow: TimeInterval = 1.2

    func test_everySourceNotificationDrivesARefresh() {
        let sources: [Notification.Name] = [
            .dataActorDidSave,      // background sync saves
            ModelContext.didSave,   // outbound operations + local edits
            .opsLeadsDidChange,     // realtime lead rows
        ]

        for name in sources {
            let center = NotificationCenter()
            let refreshed = expectation(description: "refresh for \(name.rawValue)")
            let cancellable = RecoveryRefreshSignal.publisher(center: center).sink { _ in
                XCTAssertTrue(Thread.isMainThread, "Refreshes read the main context — they must land on main")
                refreshed.fulfill()
            }

            center.post(name: name, object: nil)

            wait(for: [refreshed], timeout: 2)
            cancellable.cancel()
        }
    }

    func test_aSaveStormCostsASingleRefresh() {
        let center = NotificationCenter()
        var refreshes = 0
        RecoveryRefreshSignal.publisher(center: center)
            .sink { _ in refreshes += 1 }
            .store(in: &cancellables)

        // A sync pass saves repeatedly; each save posts both the actor rebroadcast
        // and the context notification.
        for _ in 0..<20 {
            center.post(name: ModelContext.didSave, object: nil)
            center.post(name: .dataActorDidSave, object: nil)
        }

        settle()

        XCTAssertEqual(refreshes, 1, "40 notifications inside one window must cost one inventory load")
    }

    func test_changesAfterTheWindowKeepRefreshing() {
        let center = NotificationCenter()
        var refreshes = 0
        RecoveryRefreshSignal.publisher(center: center)
            .sink { _ in refreshes += 1 }
            .store(in: &cancellables)

        center.post(name: .opsLeadsDidChange, object: nil)
        settle()
        XCTAssertEqual(refreshes, 1)

        center.post(name: .dataActorDidSave, object: nil)
        settle()
        XCTAssertEqual(refreshes, 2, "The subscription must survive its first burst")
    }

    // MARK: - Helpers

    /// Runs the main runloop until the debounce window has certainly elapsed.
    private func settle() {
        let settled = expectation(description: "debounce window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + settleWindow) { settled.fulfill() }
        wait(for: [settled], timeout: settleWindow + 2)
    }
}

/// The monitor exists so the debounce outlives a SwiftUI re-render. Both
/// surfaces observe `DataController`, so they are re-evaluated while a sync pass
/// saves — the one moment a dropped change is most visible. These lock the
/// property that makes that safe: subscribers to `output` come and go without
/// disturbing the pipeline behind it.
@MainActor
final class RecoveryRefreshMonitorTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_aChangeInFlightWhenTheViewResubscribesIsStillDelivered() {
        let center = NotificationCenter()
        let monitor = RecoveryRefreshMonitor(center: center)

        var receiptsBeforeResubscribe = 0
        let beforeResubscribe = monitor.output.sink { _ in receiptsBeforeResubscribe += 1 }

        // A save lands, then the view re-renders before the window closes.
        center.post(name: .dataActorDidSave, object: nil)
        beforeResubscribe.cancel()

        let delivered = expectation(description: "in-flight change survives the resubscribe")
        monitor.output
            .sink { _ in delivered.fulfill() }
            .store(in: &cancellables)

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(
            receiptsBeforeResubscribe,
            0,
            "Precondition: the change was still inside the debounce window when the view resubscribed"
        )
    }

    func test_theMonitorKeepsDeliveringAfterASubscriberIsReplaced() {
        let center = NotificationCenter()
        let monitor = RecoveryRefreshMonitor(center: center)

        monitor.output.sink { _ in }.cancel()

        let delivered = expectation(description: "later change reaches the replacement subscriber")
        monitor.output
            .sink { _ in delivered.fulfill() }
            .store(in: &cancellables)

        center.post(name: ModelContext.didSave, object: nil)

        wait(for: [delivered], timeout: 2)
    }
}
