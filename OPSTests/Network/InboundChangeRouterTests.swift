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

import XCTest
@testable import OPS

@MainActor
final class InboundChangeRouterTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a router with fast test timings and counts callback firings.
    private func makeRouter(
        debounce: TimeInterval = 0.05,
        maxLatency: TimeInterval = 0.5,
        onCalendar: @escaping () -> Void = {},
        onUserEvents: @escaping () -> Void = {}
    ) -> InboundChangeRouter {
        InboundChangeRouter(
            debounceInterval: debounce,
            maxLatency: maxLatency,
            onCalendarTasksChanged: onCalendar,
            onUserEventsChanged: onUserEvents
        )
    }

    // MARK: - Coalescing

    func test_taskBurst_coalescesToSingleCalendarCallback() {
        let calendarFired = expectation(description: "calendar callback")
        // Coalescing is asserted via calendarCount below — an extra flush must
        // FAIL the count assertion, not crash the expectation.
        calendarFired.assertForOverFulfill = false
        var calendarCount = 0
        var userEventsCount = 0

        let router = makeRouter(
            onCalendar: {
                calendarCount += 1
                calendarFired.fulfill()
            },
            onUserEvents: { userEventsCount += 1 }
        )

        // A delta-sync style burst: several entity types in quick succession.
        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        InboundChangeSignal.post(entityNames: ["Project"])
        InboundChangeSignal.post(entityNames: ["TaskType", "ProjectTask"])

        wait(for: [calendarFired], timeout: 2.0)

        // Allow a settle window to catch an (incorrect) second flush.
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)

        XCTAssertEqual(calendarCount, 1, "burst must coalesce to exactly one calendar refresh")
        XCTAssertEqual(userEventsCount, 0, "no user-event entities were posted")
        _ = router // keep alive through the test
    }

    func test_twoSeparatedBursts_fireTwoCallbacks() {
        let firstFlush = expectation(description: "first flush")
        let secondFlush = expectation(description: "second flush")
        var calendarCount = 0

        let router = makeRouter(onCalendar: {
            calendarCount += 1
            if calendarCount == 1 { firstFlush.fulfill() }
            if calendarCount == 2 { secondFlush.fulfill() }
        })

        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        wait(for: [firstFlush], timeout: 2.0)

        InboundChangeSignal.post(entityNames: ["ProjectTask"])
        wait(for: [secondFlush], timeout: 2.0)

        XCTAssertEqual(calendarCount, 2)
        _ = router
    }

    // MARK: - Routing

    func test_irrelevantEntities_doNotFireCallbacks() {
        let noCalendar = expectation(description: "calendar must not fire")
        noCalendar.isInverted = true
        let noUserEvents = expectation(description: "user events must not fire")
        noUserEvents.isInverted = true

        let router = makeRouter(
            onCalendar: { noCalendar.fulfill() },
            onUserEvents: { noUserEvents.fulfill() }
        )

        InboundChangeSignal.post(entityNames: ["ProjectPhoto", "CatalogItem", "Client"])

        wait(for: [noCalendar, noUserEvents], timeout: 0.4)
        _ = router
    }

    func test_userEventEntity_firesUserEventsCallbackOnly() {
        let userEventsFired = expectation(description: "user events callback")
        let noCalendar = expectation(description: "calendar must not fire")
        noCalendar.isInverted = true

        userEventsFired.assertForOverFulfill = false

        let router = makeRouter(
            onCalendar: { noCalendar.fulfill() },
            onUserEvents: { userEventsFired.fulfill() }
        )

        InboundChangeSignal.post(entityNames: ["CalendarUserEvent"])

        wait(for: [userEventsFired, noCalendar], timeout: 1.0)
        _ = router
    }

    func test_photoAnnotationEntity_postsAnnotationRefreshNotificationOnly() {
        let annotationRefresh = expectation(description: "annotation refresh notification")
        annotationRefresh.assertForOverFulfill = false
        let noCalendar = expectation(description: "calendar must not fire")
        noCalendar.isInverted = true
        let noUserEvents = expectation(description: "user events must not fire")
        noUserEvents.isInverted = true

        let notificationName = Notification.Name("OPSProjectPhotoAnnotationsChanged")
        let observer = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { _ in
            annotationRefresh.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let router = makeRouter(
            onCalendar: { noCalendar.fulfill() },
            onUserEvents: { noUserEvents.fulfill() }
        )

        InboundChangeSignal.post(entityNames: ["PhotoAnnotation"])

        wait(for: [annotationRefresh, noCalendar, noUserEvents], timeout: 1.0)
        _ = router
    }

    func test_mixedNames_fireBothCallbacksOnce() {
        let calendarFired = expectation(description: "calendar callback")
        let userEventsFired = expectation(description: "user events callback")
        // Once-ness is asserted via the counters — extra flushes must fail
        // assertions, not crash the expectations.
        calendarFired.assertForOverFulfill = false
        userEventsFired.assertForOverFulfill = false
        var calendarCount = 0
        var userEventsCount = 0

        let router = makeRouter(
            onCalendar: {
                calendarCount += 1
                calendarFired.fulfill()
            },
            onUserEvents: {
                userEventsCount += 1
                userEventsFired.fulfill()
            }
        )

        InboundChangeSignal.post(entityNames: ["ProjectTask", "CalendarUserEvent"])

        wait(for: [calendarFired, userEventsFired], timeout: 2.0)
        XCTAssertEqual(calendarCount, 1)
        XCTAssertEqual(userEventsCount, 1)
        _ = router
    }

    // MARK: - Starvation Guard

    func test_continuousStream_flushesByMaxLatency() {
        let calendarFired = expectation(description: "flush during continuous stream")
        // The stream intentionally produces MULTIPLE flushes (one per
        // max-latency window) — over-fulfillment is expected behavior here.
        calendarFired.assertForOverFulfill = false

        let router = makeRouter(
            debounce: 0.06,
            maxLatency: 0.15,
            onCalendar: { calendarFired.fulfill() }
        )

        // Post faster than the debounce interval for ~0.6s. Trailing-edge
        // debounce alone would starve; the max-latency bound must flush.
        var delay: TimeInterval = 0
        for _ in 0..<20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                InboundChangeSignal.post(entityNames: ["ProjectTask"])
            }
            delay += 0.03
        }

        wait(for: [calendarFired], timeout: 1.0)

        // Drain: every scheduled post must land before this test returns,
        // otherwise stragglers leak into the next test's router (the signal
        // rides the shared default NotificationCenter).
        let drained = expectation(description: "drain scheduled posts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { drained.fulfill() }
        wait(for: [drained], timeout: 2.0)
        _ = router
    }

    // MARK: - Empty Posts

    func test_emptyEntityNames_doesNotPost() {
        let noCalendar = expectation(description: "calendar must not fire")
        noCalendar.isInverted = true

        let router = makeRouter(onCalendar: { noCalendar.fulfill() })

        InboundChangeSignal.post(entityNames: [])

        wait(for: [noCalendar], timeout: 0.3)
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
