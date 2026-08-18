//
//  HomeBillableThisWeekNotificationDispatcherTests.swift
//  OPSTests
//
//  The Monday billable-week summary reaches the rail through the narrow
//  `sync_billable_week_notification` RPC (bug e302355c ADDENDUM). That one
//  call replaced a read-then-insert pair: the client used to probe for an
//  existing row and then write one itself, and the write has 42501'd for app
//  roles since the 2026-07-15 notification-creation hardening.
//
//  The server now owns the copy, the deep link, and the week's at-most-once
//  guarantee (checked against ANY read state, matching the probe it replaced).
//  What the client still owns — and what these tests pin — is the dispatch
//  gate, the local banner, and the per-week UserDefaults marker:
//
//    `created` → the summary is new: fire the local banner, record the week,
//                tell the caller.
//    `kept`    → the week is already on the rail: record it so the gate stops
//                asking, but never re-fire a banner for news already delivered.
//    throw     → nothing landed: leave the week unrecorded so the next tick
//                retries.
//

import XCTest
@testable import OPS

final class HomeBillableThisWeekNotificationDispatcherTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    // MARK: - Gate

    func testDispatchGateOnlyFiresOnceOnMondayForFinanceUsersWithBillableWork() {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 2, amount: 12_400)
        let weekKey = HomeBillableThisWeekNotificationDispatcher.weekStartKey(
            for: monday,
            calendar: calendar
        )

        XCTAssertTrue(
            HomeBillableThisWeekNotificationDispatcher.shouldDispatch(
                rollup: rollup,
                now: monday,
                lastDispatchedWeekStart: nil,
                permissionCanViewFinances: true,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            HomeBillableThisWeekNotificationDispatcher.shouldDispatch(
                rollup: rollup,
                now: monday,
                lastDispatchedWeekStart: weekKey,
                permissionCanViewFinances: true,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            HomeBillableThisWeekNotificationDispatcher.shouldDispatch(
                rollup: rollup,
                now: date(2026, 5, 26),
                lastDispatchedWeekStart: nil,
                permissionCanViewFinances: true,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            HomeBillableThisWeekNotificationDispatcher.shouldDispatch(
                rollup: rollup,
                now: monday,
                lastDispatchedWeekStart: nil,
                permissionCanViewFinances: false,
                calendar: calendar
            )
        )
    }

    func testNotificationTypeStaysTheLocalBannerContract() {
        // The rail row's type is the server's to set; this constant survives
        // because the local banner tags its userInfo with it so a tap routes
        // to the same place.
        XCTAssertEqual(HomeBillableThisWeekNotificationDispatcher.notificationType, "billable_this_week")
    }

    // MARK: - The remote seam

    @MainActor
    func testCreatedVerdictFiresTheBannerRecordsTheWeekAndForwardsTheRollupVerbatim() async {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 3, amount: 18_250)
        let weekKey = HomeBillableThisWeekNotificationDispatcher.weekStartKey(
            for: monday,
            calendar: calendar
        )
        var storedWeek: String?
        var localNotifications: [(Int, Double)] = []
        var syncCalls: [(Int, Double, String)] = []
        var callbackCount = 0

        await HomeBillableThisWeekNotificationDispatcher.dispatchIfNeeded(
            rollup: rollup,
            userId: "user-1",
            companyId: "company-1",
            now: monday,
            permissionCanViewFinances: true,
            calendar: calendar,
            lastDispatchedWeekStart: { storedWeek },
            markWeekDispatched: { storedWeek = $0 },
            scheduleLocalNotification: { localNotifications.append(($0, $1)) },
            syncRemote: { count, amount, week in
                syncCalls.append((count, amount, week))
                return "created"
            },
            onNotificationCreated: { callbackCount += 1 }
        )

        XCTAssertEqual(syncCalls.count, 1)
        XCTAssertEqual(syncCalls.first?.0, 3, "The server clamps and renders — it needs the real count")
        XCTAssertEqual(syncCalls.first?.1, 18_250)
        XCTAssertEqual(syncCalls.first?.2, weekKey, "The week key is the row's identity, not a display string")
        XCTAssertEqual(storedWeek, weekKey)
        XCTAssertEqual(localNotifications.count, 1)
        XCTAssertEqual(localNotifications.first?.0, 3)
        XCTAssertEqual(localNotifications.first?.1, 18_250)
        XCTAssertEqual(callbackCount, 1)
    }

    @MainActor
    func testKeptVerdictRecordsTheWeekWithoutRepeatingTheBanner() async {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 1, amount: 2_400)
        let weekKey = HomeBillableThisWeekNotificationDispatcher.weekStartKey(
            for: monday,
            calendar: calendar
        )
        var storedWeek: String?
        var localNotificationCount = 0
        var callbackCount = 0

        await HomeBillableThisWeekNotificationDispatcher.dispatchIfNeeded(
            rollup: rollup,
            userId: "user-1",
            companyId: "company-1",
            now: monday,
            permissionCanViewFinances: true,
            calendar: calendar,
            lastDispatchedWeekStart: { storedWeek },
            markWeekDispatched: { storedWeek = $0 },
            scheduleLocalNotification: { _, _ in localNotificationCount += 1 },
            syncRemote: { _, _, _ in "kept" },
            onNotificationCreated: { callbackCount += 1 }
        )

        XCTAssertEqual(storedWeek, weekKey, "The week is on the rail — stop asking about it")
        XCTAssertEqual(
            localNotificationCount,
            0,
            "A reinstall or a second device must not re-announce a summary the user already got"
        )
        XCTAssertEqual(callbackCount, 0)
    }

    @MainActor
    func testFailedRemoteSyncDoesNotSuppressRetryForWeek() async {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 1, amount: 2_400)
        let weekKey = HomeBillableThisWeekNotificationDispatcher.weekStartKey(
            for: monday,
            calendar: calendar
        )
        var storedWeek: String?
        var localNotificationCount = 0
        var syncCallCount = 0

        await HomeBillableThisWeekNotificationDispatcher.dispatchIfNeeded(
            rollup: rollup,
            userId: "user-1",
            companyId: "company-1",
            now: monday,
            permissionCanViewFinances: true,
            calendar: calendar,
            lastDispatchedWeekStart: { storedWeek },
            markWeekDispatched: { storedWeek = $0 },
            scheduleLocalNotification: { _, _ in localNotificationCount += 1 },
            syncRemote: { _, _, _ in
                syncCallCount += 1
                throw RemoteSyncFailure()
            }
        )

        XCTAssertNil(storedWeek)
        XCTAssertEqual(localNotificationCount, 0)
        XCTAssertTrue(
            HomeBillableThisWeekNotificationDispatcher.shouldDispatch(
                rollup: rollup,
                now: monday,
                lastDispatchedWeekStart: storedWeek,
                permissionCanViewFinances: true,
                calendar: calendar
            ),
            "Nothing reached the rail, so Monday's summary is still owed"
        )

        await HomeBillableThisWeekNotificationDispatcher.dispatchIfNeeded(
            rollup: rollup,
            userId: "user-1",
            companyId: "company-1",
            now: monday,
            permissionCanViewFinances: true,
            calendar: calendar,
            lastDispatchedWeekStart: { storedWeek },
            markWeekDispatched: { storedWeek = $0 },
            scheduleLocalNotification: { _, _ in localNotificationCount += 1 },
            syncRemote: { _, _, _ in
                syncCallCount += 1
                return "created"
            }
        )

        XCTAssertEqual(storedWeek, weekKey)
        XCTAssertEqual(localNotificationCount, 1)
        XCTAssertEqual(syncCallCount, 2)
    }

    @MainActor
    func testUnrecognizedVerdictLeavesTheWeekOwed() async {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 1, amount: 2_400)
        var storedWeek: String?
        var localNotificationCount = 0

        await HomeBillableThisWeekNotificationDispatcher.dispatchIfNeeded(
            rollup: rollup,
            userId: "user-1",
            companyId: "company-1",
            now: monday,
            permissionCanViewFinances: true,
            calendar: calendar,
            lastDispatchedWeekStart: { storedWeek },
            markWeekDispatched: { storedWeek = $0 },
            scheduleLocalNotification: { _, _ in localNotificationCount += 1 },
            syncRemote: { _, _, _ in "skipped" }
        )

        XCTAssertNil(storedWeek, "Only a verdict that means the week is on the rail may close it out")
        XCTAssertEqual(localNotificationCount, 0)
    }

    @MainActor
    func testGateFailureNeverReachesTheServer() async {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 2, amount: 9_000)
        var syncCallCount = 0

        await HomeBillableThisWeekNotificationDispatcher.dispatchIfNeeded(
            rollup: rollup,
            userId: "user-1",
            companyId: "company-1",
            now: monday,
            permissionCanViewFinances: false,
            calendar: calendar,
            lastDispatchedWeekStart: { nil },
            markWeekDispatched: { _ in },
            scheduleLocalNotification: { _, _ in },
            syncRemote: { _, _, _ in
                syncCallCount += 1
                return "created"
            }
        )

        XCTAssertEqual(
            syncCallCount,
            0,
            "The server enforces `finances.view` too, but a call it will refuse is a call not worth making"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeRollup(weekStart: Date, projectCount: Int, amount: Double) -> HomeBillableThisWeekRollup {
        let items = (0..<projectCount).map { idx in
            HomeBillableProjectCandidate(
                id: "ready-\(idx)",
                projectId: "project-\(idx)",
                title: "Project \(idx)",
                section: .readyToBill,
                taskCount: 1,
                amount: amount / Double(projectCount),
                invoiceId: nil,
                estimateId: "estimate-\(idx)",
                latestTaskEnd: weekStart
            )
        }

        return HomeBillableThisWeekRollup(
            weekStart: weekStart,
            weekEnd: calendar.date(byAdding: .day, value: 6, to: weekStart)!,
            closingThisWeek: [],
            readyToBill: items
        )
    }

    private struct RemoteSyncFailure: Error {}
}
