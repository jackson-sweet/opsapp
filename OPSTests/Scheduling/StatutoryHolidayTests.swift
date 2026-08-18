//
//  StatutoryHolidayTests.swift
//  OPSTests
//
//  Bug 23ecb01a — statutory holidays on the calendar, computed on device.
//  These pin the moving dates (Easter-relative, nth-weekday, and Victoria
//  Day's "Monday before May 25" rule), because those are the ones a silent
//  arithmetic slip would get wrong without anybody noticing.
//

import XCTest
@testable import OPS

final class StatutoryHolidayTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver") ?? .current
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func date(named name: String, in year: Int) -> Date? {
        StatutoryHolidays.holidays(inYear: year, calendar: calendar)
            .first { $0.name == name }?
            .date
    }

    // MARK: - Moving dates

    func testGoodFridayTracksEaster() {
        XCTAssertEqual(date(named: "Good Friday", in: 2026), day(2026, 4, 3))
        XCTAssertEqual(date(named: "Good Friday", in: 2027), day(2027, 3, 26))
    }

    /// The Monday preceding May 25 — which is May 18 in a year where May 24
    /// falls on a Sunday, and May 24 itself when that day is a Monday.
    func testVictoriaDayIsTheMondayBeforeMay25() {
        XCTAssertEqual(date(named: "Victoria Day", in: 2026), day(2026, 5, 18))
        XCTAssertEqual(date(named: "Victoria Day", in: 2027), day(2027, 5, 24))
    }

    func testNthWeekdayHolidays() {
        // BC Family Day — third Monday of February (moved from the second in 2019).
        XCTAssertEqual(date(named: "Family Day", in: 2026), day(2026, 2, 16))
        // BC Day — first Monday of August.
        XCTAssertEqual(date(named: "BC Day", in: 2026), day(2026, 8, 3))
        // Labour Day — first Monday of September.
        XCTAssertEqual(date(named: "Labour Day", in: 2026), day(2026, 9, 7))
        // Thanksgiving — second Monday of October.
        XCTAssertEqual(date(named: "Thanksgiving", in: 2026), day(2026, 10, 12))
    }

    func testFixedDateHolidays() {
        XCTAssertEqual(date(named: "New Year's Day", in: 2026), day(2026, 1, 1))
        XCTAssertEqual(date(named: "Canada Day", in: 2026), day(2026, 7, 1))
        XCTAssertEqual(
            date(named: "National Day for Truth and Reconciliation", in: 2026),
            day(2026, 9, 30)
        )
        XCTAssertEqual(date(named: "Remembrance Day", in: 2026), day(2026, 11, 11))
        XCTAssertEqual(date(named: "Christmas Day", in: 2026), day(2026, 12, 25))
    }

    // MARK: - Jurisdiction

    func testBoxingDayIsFederalOnly() {
        let holidays = StatutoryHolidays.holidays(inYear: 2026, calendar: calendar)
        let federalOnly = holidays.filter { $0.jurisdiction == .federal }.map(\.name)
        XCTAssertEqual(
            federalOnly,
            ["Boxing Day"],
            "Boxing Day is the only day on the list BC does not make statutory."
        )
        XCTAssertEqual(StatutoryHoliday.Jurisdiction.federal.badge, "FEDERAL")
        XCTAssertEqual(StatutoryHoliday.Jurisdiction.britishColumbia.badge, "STAT")
    }

    // MARK: - Lookup

    func testHolidayLookupIsDayGranularAndOrdered() {
        XCTAssertEqual(StatutoryHolidays.holiday(on: day(2026, 7, 1), calendar: calendar)?.name, "Canada Day")
        XCTAssertNil(StatutoryHolidays.holiday(on: day(2026, 7, 2), calendar: calendar))

        let holidays = StatutoryHolidays.holidays(inYear: 2026, calendar: calendar)
        XCTAssertEqual(holidays.count, 12)
        XCTAssertEqual(holidays.map(\.date), holidays.map(\.date).sorted())
    }

    /// A range spanning a year boundary must pull from both years and clip to
    /// its own ends — the month grid asks in exactly this shape.
    func testRangeLookupSpansYearsAndClips() {
        let names = StatutoryHolidays
            .holidays(in: day(2026, 12, 24)...day(2027, 1, 1), calendar: calendar)
            .map(\.name)
        XCTAssertEqual(names, ["Christmas Day", "Boxing Day", "New Year's Day"])
    }
}
