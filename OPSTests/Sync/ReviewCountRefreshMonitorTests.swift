//
//  ReviewCountRefreshMonitorTests.swift
//  OPSTests
//
//  The FAB is mounted on every tab, and three signals ask it to recount:
//  the menu appearing, `DataSyncCompleted`, and
//  `DataController.scheduledTasksDidChange`. A sync completion raises the last
//  two together and an inbound merge raises the third once per batch, so
//  undebounced the badge paid a full pass over the task and project tables
//  several times for one landing.
//
//  These pin the three properties the coalescing rests on: a burst costs one
//  recount, the pipeline survives its first burst, and a signal still inside the
//  window survives the SwiftUI re-render that the sync pass itself provokes.
//
//  Harness: the debounce runs on the shared `VirtualScheduler`, so these tests
//  close the window explicitly instead of waiting out a real one — a wall-clock
//  wait is outrun by parallel-build load. The window itself comes from
//  `ReviewCountRefreshMonitor.debounceMilliseconds` via the extension below,
//  so it tracks this pipeline's production constant and no other's.
//

import Combine
import XCTest
@testable import OPS

/// Exactly this pipeline's production debounce window. Kept at the call
/// site so the shared `VirtualScheduler` encodes no pipeline's timing.
private extension VirtualScheduler {
    func closeDebounceWindow() {
        advance(by: .milliseconds(ReviewCountRefreshMonitor.debounceMilliseconds))
    }
}

@MainActor
final class ReviewCountRefreshMonitorTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_aBurstOfTriggersCostsOneRecount() {
        let scheduler = VirtualScheduler()
        let monitor = ReviewCountRefreshMonitor(scheduler: scheduler)
        var recounts = 0
        monitor.output
            .sink { _ in recounts += 1 }
            .store(in: &cancellables)

        // One sync landing: the notification, the schedule flag, and a merge
        // batch's worth of flag toggles behind them.
        for _ in 0..<12 {
            monitor.signal()
        }
        XCTAssertEqual(recounts, 0, "Nothing may recount while the triggers are still arriving")

        scheduler.closeDebounceWindow()

        XCTAssertEqual(recounts, 1, "12 triggers inside one window must cost one pass over the tables")
    }

    func test_triggersAfterTheWindowKeepRecounting() {
        let scheduler = VirtualScheduler()
        let monitor = ReviewCountRefreshMonitor(scheduler: scheduler)
        var recounts = 0
        monitor.output
            .sink { _ in recounts += 1 }
            .store(in: &cancellables)

        monitor.signal()
        scheduler.closeDebounceWindow()
        XCTAssertEqual(recounts, 1)

        monitor.signal()
        scheduler.closeDebounceWindow()
        XCTAssertEqual(recounts, 2, "The badge must not freeze after its first burst")
    }

    /// The reason the monitor is a `@StateObject` rather than a pipeline stored
    /// on the view struct. `FloatingActionMenu` observes `DataController`, so it
    /// is re-evaluated throughout the sync pass — the exact moment a recount is
    /// pending.
    func test_aTriggerInFlightWhenTheViewResubscribesIsStillDelivered() {
        let scheduler = VirtualScheduler()
        let monitor = ReviewCountRefreshMonitor(scheduler: scheduler)

        var recountsBeforeResubscribe = 0
        let beforeResubscribe = monitor.output.sink { _ in recountsBeforeResubscribe += 1 }

        monitor.signal()
        beforeResubscribe.cancel()

        var recountsAfterResubscribe = 0
        monitor.output
            .sink { _ in recountsAfterResubscribe += 1 }
            .store(in: &cancellables)

        scheduler.closeDebounceWindow()

        XCTAssertEqual(
            recountsBeforeResubscribe,
            0,
            "Precondition: the trigger was still inside the window when the view re-rendered"
        )
        XCTAssertEqual(recountsAfterResubscribe, 1, "The in-flight trigger must survive the resubscribe")
    }

    /// The one test on the real scheduler. The virtual seam proves the
    /// coalescing rules; this proves production is wired to a scheduler that
    /// actually delivers, on the main thread, where the recount is allowed to
    /// read the main context. It waits on the delivery itself, not a window.
    func test_theProductionSchedulerDeliversOnTheMainThread() {
        let monitor = ReviewCountRefreshMonitor()
        let delivered = expectation(description: "recount delivered by the production scheduler")

        monitor.output
            .sink { _ in
                XCTAssertTrue(
                    Thread.isMainThread,
                    "Recounts fetch from the main context — they must land on main"
                )
                delivered.fulfill()
            }
            .store(in: &cancellables)

        monitor.signal()

        wait(for: [delivered], timeout: 5)
    }
}
