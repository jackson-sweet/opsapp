//
//  CashflowForecastEngineTests.swift
//  OPSTests
//
//  Unit tests for CashflowForecastEngine. Layers are added one at a time
//  across tasks 9-12 — this file accumulates tests for each.
//
//  Note: local test execution currently blocked by a pre-existing
//  MapboxConfig assertion on simulator boot (unrelated to engine).
//  Tests compile clean and are runnable once the simulator env is configured.
//

import XCTest
@testable import OPS

final class CashflowForecastEngineTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - Committed layer

    func testCommittedInflowProjectsOntoCorrectWeek() {
        let today = date(2026, 6, 1) // Monday
        let invoice = ForecastInvoiceInput(
            id: "inv-1",
            balanceDue: 5000,
            dueDate: date(2026, 6, 15), // week 2 (zero-indexed)
            status: .sent,
            clientLabel: "Smith Roof"
        )
        let inputs = ForecastInputs(
            today: today,
            horizonWeeks: 4,
            startingBalance: 10_000,
            lowWaterThreshold: 5_000,
            avgDaysToPayment: 0,
            layers: Set(ForecastLayer.allCases),
            invoices: [invoice],
            milestones: [],
            estimates: [],
            opportunities: [],
            recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)

        XCTAssertEqual(result.weeks.count, 4)
        XCTAssertEqual(result.weeks[0].balance, 10_000)
        XCTAssertEqual(result.weeks[1].balance, 10_000)
        XCTAssertEqual(result.weeks[2].balance, 15_000) // Jun 15 falls in week 2
        XCTAssertEqual(result.weeks[3].balance, 15_000)
        XCTAssertEqual(result.endingBalance, 15_000)
        XCTAssertEqual(result.weeks[2].contributors.first?.amount, 5_000)
        XCTAssertEqual(result.weeks[2].contributors.first?.layer, .committed)
    }

    func testHealthyStateWhenAllWeeksAboveThreshold() {
        let today = date(2026, 6, 1)
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 10_000, lowWaterThreshold: 5_000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [], estimates: [], opportunities: [], recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.state, .healthy)
    }
}
