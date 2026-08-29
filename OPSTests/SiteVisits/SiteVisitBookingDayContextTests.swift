import XCTest
@testable import OPS

final class SiteVisitBookingDayContextTests: XCTestCase {

    private let calendar = Calendar.current
    private let me = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    private func makeVisit(
        id: String = UUID().uuidString.lowercased(),
        opportunityId: String? = UUID().uuidString.lowercased(),
        scheduledAt: Date?,
        durationMinutes: Int = 60,
        status: SiteVisitStatus = .scheduled,
        booked: Bool = true,
        assigneeIds: [String]? = nil,
        deleted: Bool = false
    ) -> SiteVisit {
        let visit = SiteVisit(
            id: id,
            opportunityId: opportunityId,
            companyId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            status: status,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            assigneeIds: assigneeIds ?? [me]
        )
        if booked { visit.bookedAt = Date(timeIntervalSince1970: 1_000) }
        if deleted { visit.deletedAt = Date(timeIntervalSince1970: 2_000) }
        return visit
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    // MARK: contextVisits

    func testContextExcludesWalkUpsCancelledDeletedAndSelf() {
        let keep = makeVisit(id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1", scheduledAt: date(3, 10))
        let walkUp = makeVisit(scheduledAt: date(3, 11), booked: false)
        let cancelled = makeVisit(scheduledAt: date(3, 12), status: .cancelled)
        let deleted = makeVisit(scheduledAt: date(3, 13), deleted: true)
        let moving = makeVisit(id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2", scheduledAt: date(3, 14))

        let result = SiteVisitBookingDayContext.contextVisits(
            in: [keep, walkUp, cancelled, deleted, moving],
            currentUserId: me,
            canViewAllCalendar: true,
            excluding: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2" // case-insensitive
        )
        XCTAssertEqual(result.map(\.id), ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1"])
    }

    func testContextWithoutViewAllShowsOnlyMine() {
        let mine = makeVisit(scheduledAt: date(4, 9))
        let theirs = makeVisit(scheduledAt: date(4, 10), assigneeIds: ["eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"])
        let result = SiteVisitBookingDayContext.contextVisits(
            in: [theirs, mine],
            currentUserId: me,
            canViewAllCalendar: false,
            excluding: nil
        )
        XCTAssertEqual(result.map(\.id), [mine.id])
    }

    func testContextSortsByStart() {
        let late = makeVisit(scheduledAt: date(5, 15))
        let early = makeVisit(scheduledAt: date(5, 8))
        let result = SiteVisitBookingDayContext.contextVisits(
            in: [late, early], currentUserId: me, canViewAllCalendar: true, excluding: nil
        )
        XCTAssertEqual(result.map(\.start), [date(5, 8), date(5, 15)])
    }

    // MARK: countsByDay / visits(on:)

    func testCountsGroupByStartOfDay() {
        let visits = [
            BookingDayVisit(id: "a", opportunityId: nil, start: date(3, 9), durationMinutes: 60),
            BookingDayVisit(id: "b", opportunityId: nil, start: date(3, 16), durationMinutes: 30),
            BookingDayVisit(id: "c", opportunityId: nil, start: date(4, 9), durationMinutes: 60),
        ]
        let counts = SiteVisitBookingDayContext.countsByDay(visits, calendar: calendar)
        XCTAssertEqual(counts[calendar.startOfDay(for: date(3, 0, 1))], 2)
        XCTAssertEqual(counts[calendar.startOfDay(for: date(4, 0, 1))], 1)
        XCTAssertEqual(
            SiteVisitBookingDayContext.visits(visits, on: date(3, 12), calendar: calendar).map(\.id),
            ["a", "b"]
        )
    }

    // MARK: overlap

    func testTouchingWindowsDoNotOverlap() {
        let existing = [BookingDayVisit(id: "a", opportunityId: nil, start: date(3, 10), durationMinutes: 60)]
        XCTAssertNil(SiteVisitBookingDayContext.overlap(
            chosenStart: date(3, 11), durationMinutes: 60, against: existing, calendar: calendar
        ))
        XCTAssertNil(SiteVisitBookingDayContext.overlap(
            chosenStart: date(3, 9), durationMinutes: 60, against: existing, calendar: calendar
        ))
    }

    func testIntersectingWindowOverlaps() {
        let existing = [BookingDayVisit(id: "a", opportunityId: nil, start: date(3, 10), durationMinutes: 60)]
        XCTAssertEqual(SiteVisitBookingDayContext.overlap(
            chosenStart: date(3, 10, 30), durationMinutes: 60, against: existing, calendar: calendar
        )?.id, "a")
    }

    func testOverlapIgnoresOtherDays() {
        let existing = [BookingDayVisit(id: "a", opportunityId: nil, start: date(4, 10), durationMinutes: 480)]
        XCTAssertNil(SiteVisitBookingDayContext.overlap(
            chosenStart: date(3, 10), durationMinutes: 60, against: existing, calendar: calendar
        ))
    }

    // MARK: merging

    func testMergePreservesWallClockTime() {
        let merged = SiteVisitBookingDayContext.merging(
            day: date(12, 0, 1), timeOfDayFrom: date(3, 14, 30), calendar: calendar
        )
        let parts = calendar.dateComponents([.day, .hour, .minute], from: merged)
        XCTAssertEqual(parts.day, 12)
        XCTAssertEqual(parts.hour, 14)
        XCTAssertEqual(parts.minute, 30)
    }

    // MARK: countdown

    func testCountdownGrammar() {
        let start = date(3, 10)
        XCTAssertEqual(SiteVisitCountdown.token(until: start, now: date(1, 6)), "2D 4H")
        XCTAssertEqual(SiteVisitCountdown.token(until: start, now: date(3, 6, 48)), "3H 12M")
        XCTAssertEqual(SiteVisitCountdown.token(until: start, now: date(3, 9, 42)), "18M")
        XCTAssertEqual(SiteVisitCountdown.token(until: start, now: date(1, 10)), "2D")
        XCTAssertEqual(SiteVisitCountdown.token(until: start, now: date(3, 7)), "3H")
        XCTAssertEqual(SiteVisitCountdown.token(until: start, now: start.addingTimeInterval(-30)), "1M")
        XCTAssertNil(SiteVisitCountdown.token(until: start, now: start))
        XCTAssertNil(SiteVisitCountdown.token(until: start, now: start.addingTimeInterval(90)))
    }
}
