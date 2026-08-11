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
//  Harness: the debounce runs on an injected virtual scheduler, so these tests
//  close the window explicitly instead of waiting out a real one. This mirrors
//  `InboundChangeRouterTests`, which moved to virtual time after a 2026-07-27
//  full-suite run under parallel-build load outran its wall-clock waits. One
//  test deliberately stays on the production scheduler — see below.
//

import Combine
import SwiftData
import XCTest
@testable import OPS

/// Exactly this pipeline's production debounce window. Kept at the call
/// site so the shared `VirtualScheduler` encodes no pipeline's timing.
private extension VirtualScheduler {
    func closeDebounceWindow() {
        advance(by: .milliseconds(RecoveryRefreshSignal.debounceMilliseconds))
    }
}

@MainActor
final class RecoveryRefreshSignalTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_everySourceNotificationDrivesARefresh() {
        let sources: [Notification.Name] = [
            .dataActorDidSave,      // background sync saves
            ModelContext.didSave,   // outbound operations + local edits
            .opsLeadsDidChange,     // realtime lead rows
        ]

        for name in sources {
            let center = NotificationCenter()
            let scheduler = VirtualScheduler()
            var refreshes = 0
            let cancellable = RecoveryRefreshSignal.publisher(center: center, scheduler: scheduler)
                .sink { _ in refreshes += 1 }

            center.post(name: name, object: nil)
            XCTAssertEqual(refreshes, 0, "\(name.rawValue) must wait out the debounce window")

            scheduler.closeDebounceWindow()
            XCTAssertEqual(refreshes, 1, "\(name.rawValue) must reach the surfaces")

            cancellable.cancel()
        }
    }

    func test_aSaveStormCostsASingleRefresh() {
        let center = NotificationCenter()
        let scheduler = VirtualScheduler()
        var refreshes = 0
        RecoveryRefreshSignal.publisher(center: center, scheduler: scheduler)
            .sink { _ in refreshes += 1 }
            .store(in: &cancellables)

        // A sync pass saves repeatedly; each save posts both the actor rebroadcast
        // and the context notification.
        for _ in 0..<20 {
            center.post(name: ModelContext.didSave, object: nil)
            center.post(name: .dataActorDidSave, object: nil)
        }

        scheduler.closeDebounceWindow()

        XCTAssertEqual(refreshes, 1, "40 notifications inside one window must cost one inventory load")
    }

    func test_changesAfterTheWindowKeepRefreshing() {
        let center = NotificationCenter()
        let scheduler = VirtualScheduler()
        var refreshes = 0
        RecoveryRefreshSignal.publisher(center: center, scheduler: scheduler)
            .sink { _ in refreshes += 1 }
            .store(in: &cancellables)

        center.post(name: .opsLeadsDidChange, object: nil)
        scheduler.closeDebounceWindow()
        XCTAssertEqual(refreshes, 1)

        center.post(name: .dataActorDidSave, object: nil)
        scheduler.closeDebounceWindow()
        XCTAssertEqual(refreshes, 2, "The subscription must survive its first burst")
    }

    /// The one test on the real scheduler. The virtual seam proves the
    /// coalescing rules; this proves the production pipeline is wired to a
    /// scheduler that actually delivers, on the main thread, where the refresh
    /// is allowed to touch the main context. It waits on the delivery itself,
    /// not on a fixed window.
    func test_theProductionSchedulerDeliversOnTheMainThread() {
        let center = NotificationCenter()
        let delivered = expectation(description: "refresh delivered by the production scheduler")

        RecoveryRefreshSignal.publisher(center: center)
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread, "Refreshes read the main context — they must land on main")
                delivered.fulfill()
            }
            .store(in: &cancellables)

        center.post(name: .dataActorDidSave, object: nil)

        wait(for: [delivered], timeout: 5)
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
        let scheduler = VirtualScheduler()
        let monitor = RecoveryRefreshMonitor(center: center, scheduler: scheduler)

        var receiptsBeforeResubscribe = 0
        let beforeResubscribe = monitor.output.sink { _ in receiptsBeforeResubscribe += 1 }

        // A save lands, then the view re-renders before the window closes.
        center.post(name: .dataActorDidSave, object: nil)
        beforeResubscribe.cancel()

        var receiptsAfterResubscribe = 0
        monitor.output
            .sink { _ in receiptsAfterResubscribe += 1 }
            .store(in: &cancellables)

        scheduler.closeDebounceWindow()

        XCTAssertEqual(
            receiptsBeforeResubscribe,
            0,
            "Precondition: the change was still inside the debounce window when the view resubscribed"
        )
        XCTAssertEqual(receiptsAfterResubscribe, 1, "The in-flight change must survive the resubscribe")
    }

    func test_theMonitorKeepsDeliveringAfterASubscriberIsReplaced() {
        let center = NotificationCenter()
        let scheduler = VirtualScheduler()
        let monitor = RecoveryRefreshMonitor(center: center, scheduler: scheduler)

        monitor.output.sink { _ in }.cancel()

        var refreshes = 0
        monitor.output
            .sink { _ in refreshes += 1 }
            .store(in: &cancellables)

        center.post(name: ModelContext.didSave, object: nil)
        scheduler.closeDebounceWindow()

        XCTAssertEqual(refreshes, 1, "A later change must reach the replacement subscriber")
    }
}
