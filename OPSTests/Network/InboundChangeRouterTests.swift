//
//  InboundChangeRouterTests.swift
//  OPSTests
//
//  Coverage for the inbound-change signal pipeline that repaints the
//  calendar when a teammate's edit lands over Realtime / delta sync.
//  The router must coalesce merge bursts into a single refresh, route
//  only calendar-relevant entity types, and never starve under a
//  continuous merge stream.
//
//  Harness: all timing here is virtual. The router's clock and its debounce
//  scheduler are injected, so these tests fire flushes explicitly and wait
//  only on observable conditions — never on a fixed wall-clock window. The
//  previous shape armed real main-queue timers and waited on 2.0s
//  expectation timeouts; a 2026-07-27 full-suite run under parallel-build
//  load outran them, so the timers landed after the waits had already
//  failed. With time under test control there is nothing left to outrun.
//
//  A second benefit: no real timers and no delayed posts remain in this
//  file, so no signal can straggle out of one test and land in the next
//  test's router through the shared default NotificationCenter.
//

import XCTest
@testable import OPS

/// Virtual time source plus captured debounce arming for deterministic
/// router tests. The router's real scheduler (main-queue asyncAfter) never
/// runs here — each test decides when the debounce deadline "elapses" by
/// firing the captured work item, so machine load cannot race a wall-clock
/// timeout.
@MainActor
private final class VirtualClock {

    /// Virtual "now" consumed by the router's max-latency check.
    private(set) var currentDate = Date(timeIntervalSinceReferenceDate: 0)

    /// Every schedule call observed, re-arms included, fired or not.
    private(set) var scheduledCount = 0

    private var pending: DispatchWorkItem?

    /// True while an un-fired, un-cancelled debounce flush is armed.
    var hasPendingFlush: Bool { pending.map { !$0.isCancelled } ?? false }

    func schedule(delay: TimeInterval, work: DispatchWorkItem) {
        pending = work
        scheduledCount += 1
    }

    /// Moves virtual time forward. Never sleeps.
    func advance(by interval: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(interval)
    }

    /// Simulates the debounce deadline elapsing. Mirrors dispatch-queue
    /// semantics: a cancelled work item never runs. Callers gate on
    /// hasPendingFlush (or scheduledCount) first, so a silent no-op here
    /// cannot mask a missed arm.
    func firePendingFlush() {
        guard let work = pending else { return }
        pending = nil
        guard !work.isCancelled else { return }
        work.perform()
    }
}

@MainActor
final class InboundChangeRouterTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a router driven by the supplied virtual clock and counts
    /// callback firings. The debounce and max-latency values are virtual
    /// thresholds only — they are measured against the clock's virtual date
    /// and gate a work item the test fires by hand, so they cost no wall
    /// time regardless of their size.
    private func makeRouter(
        clock: VirtualClock,
        debounce: TimeInterval = 0.05,
        maxLatency: TimeInterval = 0.5,
        onCalendar: @escaping () -> Void = {},
        onUserEvents: @escaping () -> Void = {},
        onTaskReminders: @escaping () -> Void = {}
    ) -> InboundChangeRouter {
        InboundChangeRouter(
            debounceInterval: debounce,
            maxLatency: maxLatency,
            now: { clock.currentDate },
            scheduleFlush: { delay, work in clock.schedule(delay: delay, work: work) },
            onCalendarTasksChanged: onCalendar,
            onUserEventsChanged: onUserEvents,
            onTaskRemindersChanged: onTaskReminders
        )
    }

    /// Condition-based wait: spins the main run loop (which drains the main
    /// queue, including the router's Combine receive(on:) delivery hop) until
    /// the condition holds. The backstop timeout exists only to fail loudly if
    /// the condition can never hold — it is not load headroom, because every
    /// wait exits the moment its condition becomes true.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for \(description)", file: file, line: line)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: - Coalescing

    func test_taskBurst_coalescesToSingleCalendarCallback() {
        let clock = VirtualClock()
        var calendarCount = 0
        var userEventsCount = 0

        let router = makeRouter(
            clock: clock,
            onCalendar: { calendarCount += 1 },
            onUserEvents: { userEventsCount += 1 }
        )

        // A delta-sync style burst: several entity types in quick succession.
        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        InboundChangeSignal.post(entityNames: ["Project"])
        InboundChangeSignal.post(entityNames: ["TaskType", "ProjectTask"])

        // Gate on all four arms rather than on "at least one". Firing the
        // flush after fewer deliveries would flush a partial burst, and the
        // coalescing assertion below would then be proving nothing.
        waitUntil("all four burst signals delivered") { clock.scheduledCount == 4 }

        clock.firePendingFlush()

        // Four arrivals armed the debounce four times; each of the first
        // three arms was cancelled by its successor, so exactly one flush
        // ran. No settle window is needed to catch a stray second flush —
        // with virtual time there is no timer and no delayed post left that
        // could produce one.
        XCTAssertEqual(calendarCount, 1, "burst must coalesce to exactly one calendar refresh")
        XCTAssertEqual(userEventsCount, 0, "no user-event entities were posted")
        XCTAssertEqual(clock.scheduledCount, 4, "the flush must not re-arm the debounce")
        XCTAssertFalse(clock.hasPendingFlush, "no flush may stay armed after the burst drains")
        _ = router // keep alive through the test
    }

    func test_twoSeparatedBursts_fireTwoCallbacks() {
        let clock = VirtualClock()
        var calendarCount = 0

        let router = makeRouter(clock: clock, onCalendar: { calendarCount += 1 })

        // The separation between these bursts is structural, not temporal.
        // The first flush runs to completion — clearing the pending name set,
        // the work item and the max-latency anchor — before the second signal
        // is posted, which is exactly what "separated" means to the router.
        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        waitUntil("first signal delivered and debounce armed") { clock.hasPendingFlush }
        clock.firePendingFlush()
        XCTAssertEqual(calendarCount, 1)

        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        waitUntil("second signal delivered and debounce armed") { clock.hasPendingFlush }
        clock.firePendingFlush()
        XCTAssertEqual(calendarCount, 2)
        _ = router
    }

    // MARK: - Routing

    func test_irrelevantEntities_doNotFireCallbacks() {
        let clock = VirtualClock()
        var calendarCount = 0
        var userEventsCount = 0
        var reminderCount = 0

        let router = makeRouter(
            clock: clock,
            onCalendar: { calendarCount += 1 },
            onUserEvents: { userEventsCount += 1 },
            onTaskReminders: { reminderCount += 1 }
        )

        InboundChangeSignal.post(entityNames: ["ProjectPhoto", "CatalogItem", "Client"])

        // Irrelevant names still accumulate and still arm the debounce —
        // routing is decided at flush time, not on arrival. So the claim
        // worth proving is that a flush actually ran and routed nowhere,
        // which means waiting for the arm and firing it rather than waiting
        // out a window and concluding from silence.
        waitUntil("signal delivered and debounce armed") { clock.hasPendingFlush }
        clock.firePendingFlush()

        XCTAssertEqual(calendarCount, 0)
        XCTAssertEqual(userEventsCount, 0)
        XCTAssertEqual(reminderCount, 0)
        _ = router
    }

    func test_userEventEntity_firesUserEventsCallbackOnly() {
        let clock = VirtualClock()
        var calendarCount = 0
        var userEventsCount = 0
        var reminderCount = 0

        let router = makeRouter(
            clock: clock,
            onCalendar: { calendarCount += 1 },
            onUserEvents: { userEventsCount += 1 },
            onTaskReminders: { reminderCount += 1 }
        )

        InboundChangeSignal.post(entityNames: ["CalendarUserEvent"])

        waitUntil("signal delivered and debounce armed") { clock.hasPendingFlush }
        clock.firePendingFlush()

        XCTAssertEqual(userEventsCount, 1)
        XCTAssertEqual(calendarCount, 0)
        XCTAssertEqual(reminderCount, 0)
        _ = router
    }

    func test_taskReminderEntity_firesReminderScheduleCallbackOnly() {
        let clock = VirtualClock()
        var calendarCount = 0
        var userEventsCount = 0
        var reminderCount = 0

        let router = makeRouter(
            clock: clock,
            onCalendar: { calendarCount += 1 },
            onUserEvents: { userEventsCount += 1 },
            onTaskReminders: { reminderCount += 1 }
        )

        InboundChangeSignal.post(entityNames: ["TaskReminder"])

        waitUntil("signal delivered and debounce armed") { clock.hasPendingFlush }
        clock.firePendingFlush()

        XCTAssertEqual(reminderCount, 1)
        XCTAssertEqual(calendarCount, 0)
        XCTAssertEqual(userEventsCount, 0)
        _ = router
    }

    func test_photoAnnotationEntity_postsAnnotationRefreshNotificationOnly() {
        let clock = VirtualClock()
        var annotationCount = 0
        var calendarCount = 0
        var userEventsCount = 0

        let notificationName = Notification.Name("OPSProjectPhotoAnnotationsChanged")
        // queue: nil, not .main. The flush posts this notification
        // synchronously on main, and a nil-queue observer runs synchronously
        // on the posting thread, so there is no extra async hop to wait for.
        // A .main-queue observer would add one and reintroduce a race.
        let observer = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: nil
        ) { _ in
            annotationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let router = makeRouter(
            clock: clock,
            onCalendar: { calendarCount += 1 },
            onUserEvents: { userEventsCount += 1 }
        )

        InboundChangeSignal.post(entityNames: ["PhotoAnnotation"])

        waitUntil("signal delivered and debounce armed") { clock.hasPendingFlush }
        clock.firePendingFlush()

        XCTAssertEqual(annotationCount, 1)
        XCTAssertEqual(calendarCount, 0)
        XCTAssertEqual(userEventsCount, 0)
        _ = router
    }

    func test_mixedNames_fireBothCallbacksOnce() {
        let clock = VirtualClock()
        var calendarCount = 0
        var userEventsCount = 0

        let router = makeRouter(
            clock: clock,
            onCalendar: { calendarCount += 1 },
            onUserEvents: { userEventsCount += 1 }
        )

        InboundChangeSignal.post(entityNames: ["ProjectTask", "CalendarUserEvent"])

        waitUntil("signal delivered and debounce armed") { clock.hasPendingFlush }
        clock.firePendingFlush()

        XCTAssertEqual(calendarCount, 1)
        XCTAssertEqual(userEventsCount, 1)
        // One delivery, one arm: the mixed name set produced a single
        // coalesced flush that fanned out to both chains.
        XCTAssertEqual(clock.scheduledCount, 1)
        XCTAssertFalse(clock.hasPendingFlush)
        _ = router
    }

    // MARK: - Starvation Guard

    func test_continuousStream_flushesByMaxLatency() {
        let clock = VirtualClock()
        var calendarCount = 0

        // 0.5 / 1.0 / 0.25 are binary-exact doubles, so the virtual
        // arithmetic below lands on no floating-point knife edges. The post
        // gap (0.25) stays below the debounce (0.5), so trailing-edge
        // debounce alone would starve forever — the max-latency bound has to
        // do all of the flushing.
        let router = makeRouter(
            clock: clock,
            debounce: 0.5,
            maxLatency: 1.0,
            onCalendar: { calendarCount += 1 }
        )

        for index in 0..<20 {
            InboundChangeSignal.post(entityNames: ["ProjectTask"])
            // Every delivery either re-arms the debounce (scheduledCount) or
            // trips the max-latency bound and flushes inline (calendarCount),
            // never both and never neither — so the sum tracks deliveries
            // exactly and is the precise signal that this post has landed.
            waitUntil("signal \(index + 1) delivered") {
                clock.scheduledCount + calendarCount == index + 1
            }
            clock.advance(by: 0.25)
        }

        // Posts land at virtual t = 0, 0.25, 0.50, … The first post of each
        // window sets the max-latency anchor, and the fifth post of that
        // window arrives exactly 1.0 later, meeting the bound and forcing an
        // inline flush that clears the anchor. Posts 5, 10, 15 and 20 flush,
        // so exactly four flushes across twenty posts.
        XCTAssertEqual(calendarCount, 4, "max-latency bound must flush once per window")
        XCTAssertEqual(clock.scheduledCount, 16, "the other sixteen posts armed the debounce")
        // Post 20 flushed inline, cancelling post 19's arm, so nothing is
        // left dangling. No drain block is needed either: this file schedules
        // no delayed posts, so no signal can straggle into the next test.
        XCTAssertFalse(clock.hasPendingFlush)
        _ = router
    }

    // MARK: - Empty Posts

    func test_emptyEntityNames_doesNotPost() {
        let clock = VirtualClock()
        var calendarCount = 0

        let router = makeRouter(clock: clock, onCalendar: { calendarCount += 1 })

        InboundChangeSignal.post(entityNames: [])
        InboundChangeSignal.post(entityNames: ["ProjectTask"])

        waitUntil("sentinel signal delivered") { clock.hasPendingFlush }

        // NotificationCenter delivery through the router's main-queue hop is
        // FIFO, so had the empty post produced a signal its arm would have
        // landed ahead of the sentinel's and this would read 2.
        XCTAssertEqual(clock.scheduledCount, 1, "an empty post must not reach the router")

        clock.firePendingFlush()
        XCTAssertEqual(calendarCount, 1, "only the sentinel signal flushed")
        _ = router
    }

    // MARK: - Table Mapping

    func test_tableMap_coversRealtimeSoftDeleteTables() {
        XCTAssertEqual(InboundChangeSignal.entityName(forTable: "project_tasks"), "ProjectTask")
        XCTAssertEqual(InboundChangeSignal.entityName(forTable: "projects"), "Project")
        XCTAssertEqual(InboundChangeSignal.entityName(forTable: "task_types"), "TaskType")
        XCTAssertEqual(InboundChangeSignal.entityName(forTable: "calendar_user_events"), "CalendarUserEvent")
        XCTAssertNil(InboundChangeSignal.entityName(forTable: "no_such_table"))
    }
}
