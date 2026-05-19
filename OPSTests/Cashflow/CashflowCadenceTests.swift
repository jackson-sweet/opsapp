//
//  CashflowCadenceTests.swift
//  OPSTests
//
//  Unit tests for CashflowCadence — pure cadence iteration over
//  RecurringCadence. Calendar-injectable so the suite is timezone-stable.
//

import XCTest
@testable import OPS

final class CashflowCadenceTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testWeeklyAddsSevenDays() {
        let start = date(2026, 6, 1)
        let next = CashflowCadence.next(after: start, cadence: .weekly, calendar: cal)
        XCTAssertEqual(next, date(2026, 6, 8))
    }

    func testBiweeklyAddsFourteenDays() {
        let start = date(2026, 6, 1)
        let next = CashflowCadence.next(after: start, cadence: .biweekly, calendar: cal)
        XCTAssertEqual(next, date(2026, 6, 15))
    }

    func testMonthlyJanuary31RollsToFebruary28() {
        let start = date(2026, 1, 31)
        let next = CashflowCadence.next(after: start, cadence: .monthly, calendar: cal)
        XCTAssertEqual(next, date(2026, 2, 28))
    }

    func testMonthlyPreservesDayOfMonth() {
        let start = date(2026, 5, 15)
        let next = CashflowCadence.next(after: start, cadence: .monthly, calendar: cal)
        XCTAssertEqual(next, date(2026, 6, 15))
    }

    func testQuarterlyAddsThreeMonths() {
        let start = date(2026, 1, 15)
        let next = CashflowCadence.next(after: start, cadence: .quarterly, calendar: cal)
        XCTAssertEqual(next, date(2026, 4, 15))
    }

    func testAnnuallyAddsOneYear() {
        let start = date(2026, 6, 1)
        let next = CashflowCadence.next(after: start, cadence: .annually, calendar: cal)
        XCTAssertEqual(next, date(2027, 6, 1))
    }

    func testOccurrencesFromStartUpToHorizon_monthly() {
        let start = date(2026, 6, 1)
        let horizon = date(2026, 9, 30)
        let occ = CashflowCadence.occurrences(
            from: start, until: horizon,
            cadence: .monthly, endDate: nil, calendar: cal
        )
        XCTAssertEqual(occ, [date(2026, 6, 1), date(2026, 7, 1), date(2026, 8, 1), date(2026, 9, 1)])
    }

    func testOccurrencesRespectEndDate() {
        let start = date(2026, 6, 1)
        let horizon = date(2026, 12, 31)
        let endDate = date(2026, 8, 15)
        let occ = CashflowCadence.occurrences(
            from: start, until: horizon,
            cadence: .monthly, endDate: endDate, calendar: cal
        )
        XCTAssertEqual(occ, [date(2026, 6, 1), date(2026, 7, 1), date(2026, 8, 1)])
    }
}
