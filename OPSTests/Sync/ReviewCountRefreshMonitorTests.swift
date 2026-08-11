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
//  Harness: the debounce runs on an injected virtual scheduler, so these tests
//  close the window explicitly instead of waiting out a real one — a wall-clock
//  wait is outrun by parallel-build load. The scheduler is a deliberate copy of
//  `RecoveryRefreshSignalTests`': that one is file-private, and neither suite
//  should be able to move the other's debounce window by editing its own.
//

import Combine
import XCTest
@testable import OPS

/// Virtual clock for the debounce. Time only moves when a test says so, so
/// machine load cannot race a deadline.
private final class VirtualScheduler: Scheduler {

    typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType
    typealias SchedulerOptions = Never

    private struct Scheduled {
        let deadline: SchedulerTimeType
        /// Non-nil for the repeating overload, which is the one Combine's
        /// `debounce` actually arms (it cancels and re-arms per element).
        let interval: SchedulerTimeType.Stride?
        let action: () -> Void
    }

    private(set) var now: SchedulerTimeType = .init(.now())
    var minimumTolerance: SchedulerTimeType.Stride { .zero }

    private var scheduled: [Int: Scheduled] = [:]
    private var nextID = 0

    func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        action()
    }

    func schedule(
        after date: SchedulerTimeType,
        tolerance: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) {
        insert(Scheduled(deadline: date, interval: nil, action: action))
    }

    func schedule(
        after date: SchedulerTimeType,
        interval: SchedulerTimeType.Stride,
        tolerance: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) -> Cancellable {
        let id = insert(Scheduled(deadline: date, interval: interval, action: action))
        return AnyCancellable { [weak self] in self?.scheduled[id] = nil }
    }

    @discardableResult
    private func insert(_ item: Scheduled) -> Int {
        defer { nextID += 1 }
        scheduled[nextID] = item
        return nextID
    }

    /// Moves virtual time forward and runs what has come due, earliest first.
    /// Never sleeps.
    ///
    /// Each entry fires at most once per call — a repeating entry re-arms one
    /// interval on, a one-shot is dropped — so no amount of advancing can spin
    /// here. Cancellation is re-checked per entry because an earlier action may
    /// cancel a later one, which is exactly what debounce does when it supersedes
    /// a pending deadline.
    func advance(by stride: SchedulerTimeType.Stride) {
        now = now.advanced(by: stride)

        let due = scheduled
            .filter { $0.value.deadline <= now }
            .sorted { $0.value.deadline < $1.value.deadline }

        for (id, item) in due {
            guard scheduled[id] != nil else { continue }

            if let interval = item.interval {
                scheduled[id] = Scheduled(
                    deadline: item.deadline.advanced(by: interval),
                    interval: interval,
                    action: item.action
                )
            } else {
                scheduled[id] = nil
            }

            item.action()
        }
    }

    /// Exactly the production debounce window.
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
