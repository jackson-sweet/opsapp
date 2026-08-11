//
//  VirtualScheduler.swift
//  OPSTests
//
//  Virtual clock for Combine debounce pipelines. Time only moves when a test
//  says so, so machine load cannot race a deadline.
//
//  WHY: the sync debounces (`RecoveryRefreshSignal`, `ReviewCountRefreshMonitor`)
//  take a `Scheduler` rather than a work item, so proving their coalescing rules
//  means supplying a scheduler, not capturing a block — this is a `Scheduler`
//  conformance where `InboundChangeRouterTests` uses a captured-work-item
//  harness. Wall-clock waits were the first approach and lost: a 2026-07-27
//  full-suite run under parallel-build load outran them.
//
//  Shared rather than copied per suite. Each suite closes its own window off
//  its own production constant — see the `closeDebounceWindow()` extensions at
//  the call sites — so nothing here encodes any one pipeline's timing.
//

import Combine
import Foundation

final class VirtualScheduler: Scheduler {

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
}
