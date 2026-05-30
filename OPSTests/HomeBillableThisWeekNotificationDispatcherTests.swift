//
//  HomeBillableThisWeekNotificationDispatcherTests.swift
//  OPSTests
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

    func testNotificationCopyAndDeepLinkAreStable() {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 3, amount: 18_250)

        XCTAssertEqual(HomeBillableThisWeekNotificationDispatcher.notificationType, "billable_this_week")
        XCTAssertEqual(HomeBillableThisWeekNotificationDispatcher.deepLinkType, "billableThisWeek")
        XCTAssertEqual(
            HomeBillableThisWeekNotificationDispatcher.notificationBody(for: rollup),
            "3 jobs / $18,250 billable"
        )
        XCTAssertEqual(
            HomeBillableThisWeekNotificationDispatcher.actionUrl(forWeekStart: "2026-05-25"),
            "ops://home/billable-this-week?weekStart=2026-05-25"
        )
    }

    @MainActor
    func testFailedRemoteCreateDoesNotSuppressRetryForWeek() async {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 1, amount: 2_400)
        let weekKey = HomeBillableThisWeekNotificationDispatcher.weekStartKey(
            for: monday,
            calendar: calendar
        )
        var storedWeek: String?
        var localNotificationCount = 0
        var createdDTOs: [NotificationRepository.CreateNotificationDTO] = []

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
            hasRemoteNotification: { _, _, _ in false },
            createRemoteNotification: { _ in throw RemoteCreateFailure() }
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
            )
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
            hasRemoteNotification: { _, _, _ in false },
            createRemoteNotification: { dto in createdDTOs.append(dto) }
        )

        XCTAssertEqual(storedWeek, weekKey)
        XCTAssertEqual(localNotificationCount, 1)
        XCTAssertEqual(createdDTOs.count, 1)
    }

    @MainActor
    func testExistingRemoteNotificationMarksWeekDispatchedWithoutDuplicatingLocalNotification() async {
        let monday = date(2026, 5, 25)
        let rollup = makeRollup(weekStart: monday, projectCount: 1, amount: 2_400)
        let weekKey = HomeBillableThisWeekNotificationDispatcher.weekStartKey(
            for: monday,
            calendar: calendar
        )
        var storedWeek: String?
        var localNotificationCount = 0
        var createAttemptCount = 0
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
            hasRemoteNotification: { _, _, _ in true },
            createRemoteNotification: { _ in createAttemptCount += 1 },
            onNotificationCreated: { callbackCount += 1 }
        )

        XCTAssertEqual(storedWeek, weekKey)
        XCTAssertEqual(localNotificationCount, 0)
        XCTAssertEqual(createAttemptCount, 0)
        XCTAssertEqual(callbackCount, 0)
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

    private struct RemoteCreateFailure: Error {}
}
