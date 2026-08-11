import XCTest
@testable import OPS

/// Departure math + refresh behavior with injected clock/ETA/notification
/// seams — the matrix the spec demands: book, reschedule, cancel, start,
/// permission-denied, and no-address all reduce to candidates in/out.
final class SiteVisitDepartureAlertSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Pure math

    func testFireDateSubtractsETAAndBuffer() {
        let scheduledAt = now.addingTimeInterval(3_600)          // visit in 1h
        let fire = SiteVisitDepartureMath.fireDate(
            scheduledAt: scheduledAt,
            etaSeconds: 1_200,                                    // 20 min drive
            now: now
        )
        // 60 − 20 − 5 = fire 35 minutes from now
        XCTAssertEqual(fire, now.addingTimeInterval(35 * 60))
    }

    func testFireDateInThePastResolvesNil() {
        let scheduledAt = now.addingTimeInterval(20 * 60)         // visit in 20m
        let fire = SiteVisitDepartureMath.fireDate(
            scheduledAt: scheduledAt,
            etaSeconds: 30 * 60,                                  // 30 min drive
            now: now
        )
        XCTAssertNil(fire, "a late alert is worse than none")
    }

    func testNotificationIdIsStablePerVisit() {
        XCTAssertEqual(
            SiteVisitDepartureMath.notificationId(visitId: "AAAA-1"),
            "site-visit-departure-aaaa-1"
        )
    }

    func testBodyReadsDriveMinutesAndVisitTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let scheduledAt = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 12, hour: 10, minute: 30)
        )!
        XCTAssertEqual(
            SiteVisitDepartureMath.body(etaSeconds: 25 * 60, scheduledAt: scheduledAt, calendar: calendar),
            "~25 min drive. Visit at 10:30 AM."
        )
    }

    // MARK: - Refresh behavior

    func testRefreshCancelsStaleAlertsBeforeScheduling() async {
        let notifications = SpyNotificationScheduler(pending: ["site-visit-departure-old"])
        let scheduler = SiteVisitDepartureAlertScheduler(
            etaProvider: FixedETAProvider(eta: 1_200),
            notifications: notifications,
            now: { self.now }
        )

        await scheduler.refresh(candidates: [candidate(offsetMinutes: 60)])

        XCTAssertEqual(notifications.cancelled, ["site-visit-departure-old"])
        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertEqual(notifications.scheduled.first?.id, "site-visit-departure-\(visitId)")
        XCTAssertEqual(notifications.scheduled.first?.title, "Time to leave — Dana Whitfield")
        XCTAssertEqual(notifications.scheduled.first?.fireDate, now.addingTimeInterval(35 * 60))
        XCTAssertEqual(notifications.scheduled.first?.leadId, leadId, "a tap must route into the lead")
    }

    func testNoCandidatesMeansCancelOnly() async {
        // Start/cancel/reschedule-away/unassign all reduce to "not a candidate";
        // the pending alert must die with nothing replacing it.
        let notifications = SpyNotificationScheduler(pending: ["site-visit-departure-\(visitId)"])
        let scheduler = SiteVisitDepartureAlertScheduler(
            etaProvider: FixedETAProvider(eta: 1_200),
            notifications: notifications,
            now: { self.now }
        )

        await scheduler.refresh(candidates: [])

        XCTAssertEqual(notifications.cancelled, ["site-visit-departure-\(visitId)"])
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testUnansweredETASchedulesNothing() async {
        // No location permission / no route / geocode miss → silently absent.
        let notifications = SpyNotificationScheduler(pending: [])
        let scheduler = SiteVisitDepartureAlertScheduler(
            etaProvider: FixedETAProvider(eta: nil),
            notifications: notifications,
            now: { self.now }
        )

        await scheduler.refresh(candidates: [candidate(offsetMinutes: 60)])

        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testTooLateToLeaveSchedulesNothing() async {
        let notifications = SpyNotificationScheduler(pending: [])
        let scheduler = SiteVisitDepartureAlertScheduler(
            etaProvider: FixedETAProvider(eta: 3_600),            // 60 min drive
            notifications: notifications,
            now: { self.now }
        )

        await scheduler.refresh(candidates: [candidate(offsetMinutes: 30)]) // visit in 30m

        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    // MARK: - Fixtures

    private let visitId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let leadId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    private func candidate(offsetMinutes: Int) -> DepartureAlertCandidate {
        DepartureAlertCandidate(
            visitId: visitId,
            leadId: leadId,
            leadName: "Dana Whitfield",
            address: "418 Larchmont Ave",
            scheduledAt: now.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        )
    }
}

// MARK: - Seam doubles

private struct FixedETAProvider: DrivingETAProviding {
    let eta: TimeInterval?
    func drivingETA(toAddress address: String) async -> TimeInterval? { eta }
}

private final class SpyNotificationScheduler: DepartureNotificationScheduling, @unchecked Sendable {
    struct Scheduled: Equatable {
        let id: String
        let title: String
        let body: String
        let fireDate: Date
        let leadId: String
    }

    private(set) var pending: [String]
    private(set) var cancelled: [String] = []
    private(set) var scheduled: [Scheduled] = []

    init(pending: [String]) {
        self.pending = pending
    }

    func pendingDepartureIds() async -> [String] { pending }

    func cancel(ids: [String]) async {
        cancelled.append(contentsOf: ids)
        pending.removeAll { ids.contains($0) }
    }

    func schedule(id: String, title: String, body: String, fireDate: Date, leadId: String) async {
        scheduled.append(Scheduled(id: id, title: title, body: body, fireDate: fireDate, leadId: leadId))
    }
}
