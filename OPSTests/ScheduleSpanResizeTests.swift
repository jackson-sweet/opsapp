import XCTest
@testable import OPS

final class ScheduleSpanResizeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testInclusiveDayCountCountsCalendarDays() {
        let start = makeDate(2026, 6, 22, hour: 8, minute: 30)
        let end = makeDate(2026, 6, 24, hour: 16, minute: 45)

        let days = ScheduleSpanResize.inclusiveDayCount(start: start, end: end, calendar: calendar)

        XCTAssertEqual(days, 3)
    }

    func testDayCountFromMagnificationSnapsToWholeDays() {
        XCTAssertEqual(ScheduleSpanResize.dayCount(anchorDayCount: 1, magnification: 1.49), 1)
        XCTAssertEqual(ScheduleSpanResize.dayCount(anchorDayCount: 1, magnification: 1.50), 2)
        XCTAssertEqual(ScheduleSpanResize.dayCount(anchorDayCount: 2, magnification: 1.30), 3)
        XCTAssertEqual(ScheduleSpanResize.dayCount(anchorDayCount: 2, magnification: 0.68), 1)
    }

    func testEndDatePreservesOriginalEndTimeOfDay() {
        let start = makeDate(2026, 6, 22, hour: 8, minute: 30)
        let originalEnd = makeDate(2026, 6, 23, hour: 16, minute: 45)

        let resizedEnd = ScheduleSpanResize.endDate(
            start: start,
            preservingEndTimeFrom: originalEnd,
            dayCount: 4,
            calendar: calendar
        )

        XCTAssertEqual(resizedEnd, makeDate(2026, 6, 25, hour: 16, minute: 45))
    }

    func testEndDateClampsToAtLeastOneDay() {
        let start = makeDate(2026, 6, 22, hour: 8, minute: 30)
        let originalEnd = makeDate(2026, 6, 24, hour: 16, minute: 45)

        let resizedEnd = ScheduleSpanResize.endDate(
            start: start,
            preservingEndTimeFrom: originalEnd,
            dayCount: 0,
            calendar: calendar
        )

        XCTAssertEqual(resizedEnd, makeDate(2026, 6, 22, hour: 16, minute: 45))
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
