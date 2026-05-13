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

    // MARK: - Contracted layer (milestones + lump estimates)

    func testContractedMilestoneWithExpectedDateLandsOnRightWeek() {
        let today = date(2026, 6, 1)
        let milestone = ForecastMilestoneInput(
            id: "ms-1",
            estimateId: "est-1",
            amount: 7500,
            expectedDate: date(2026, 6, 22), // week 3
            fallbackDate: nil,
            isPaid: false,
            label: "Garcia kitchen — Framing"
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 0, lowWaterThreshold: 5000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [milestone], estimates: [], opportunities: [], recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.weeks[3].inflows, 7500)
        XCTAssertEqual(result.weeks[3].contributors.first?.layer, .contracted)
        XCTAssertEqual(result.weeks[3].contributors.first?.sourceKind, .milestone)
    }

    func testPaidMilestoneIsSkipped() {
        let today = date(2026, 6, 1)
        let milestone = ForecastMilestoneInput(
            id: "ms-1", estimateId: "est-1", amount: 7500,
            expectedDate: date(2026, 6, 22), fallbackDate: nil,
            isPaid: true, label: "x"
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 0, lowWaterThreshold: 5000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [milestone], estimates: [], opportunities: [], recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.weeks[3].inflows, 0)
    }

    func testEstimateWithoutMilestonesLumpsOnProjectEnd() {
        let today = date(2026, 6, 1)
        let est = ForecastEstimateInput(
            id: "est-1", total: 12_000, approvedAt: date(2026, 5, 15),
            projectEndDate: date(2026, 6, 12), // week 1
            clientLabel: "Jones Patio",
            hasMilestones: false
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 0, lowWaterThreshold: 5000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [], estimates: [est], opportunities: [], recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.weeks[1].inflows, 12_000)
    }

    func testEstimateWithMilestonesIsSkipped() {
        let today = date(2026, 6, 1)
        let est = ForecastEstimateInput(
            id: "est-1", total: 12_000, approvedAt: date(2026, 5, 15),
            projectEndDate: date(2026, 6, 12), clientLabel: "x", hasMilestones: true
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 0, lowWaterThreshold: 5000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [], estimates: [est], opportunities: [], recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.weeks[1].inflows, 0)
    }

    // MARK: - Pipeline layer (weighted opportunities)

    func testPipelineLayerAppliesWinProbability() {
        let today = date(2026, 6, 1)
        let opp = ForecastOpportunityInput(
            id: "opp-1",
            estimatedValue: 10_000,
            winProbability: 40,
            expectedCloseDate: date(2026, 6, 22), // week 3
            label: "Hill — qualified"
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 0, lowWaterThreshold: 5000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [], estimates: [], opportunities: [opp], recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.weeks[3].inflows, 4000)
        XCTAssertEqual(result.weeks[3].contributors.first?.probabilityHint, 40)
    }

    func testPipelineLayerExcludedWhenToggleOff() {
        let today = date(2026, 6, 1)
        let opp = ForecastOpportunityInput(
            id: "opp-1", estimatedValue: 10_000, winProbability: 40,
            expectedCloseDate: date(2026, 6, 22), label: "x"
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 0, lowWaterThreshold: 5000,
            avgDaysToPayment: 0,
            layers: [.committed, .contracted, .recurring], // no .pipeline
            invoices: [], milestones: [], estimates: [], opportunities: [opp], recurringExpenses: [],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.weeks[3].inflows, 0)
    }

    // MARK: - Recurring outflows + state transitions

    func testRecurringMonthlyHitsEachWeekItOccurs() {
        let today = date(2026, 6, 1)
        let r = ForecastRecurringInput(
            id: "r-1",
            amount: 1400,
            cadence: .monthly,
            nextDueDate: date(2026, 6, 1),
            endDate: nil,
            label: "Shop rent"
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 13,
            startingBalance: 20_000, lowWaterThreshold: 5_000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [], estimates: [], opportunities: [], recurringExpenses: [r],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        // ~3 hits across 13 weeks: Jun 1, Jul 1, Aug 1 (Sep 1 falls outside 13w from Jun 1)
        let totalOut = result.weeks.reduce(0.0) { $0 + $1.outflows }
        XCTAssertGreaterThanOrEqual(totalOut, 4200) // at least 3 × 1400
    }

    func testDangerStateWhenBalanceGoesNegative() {
        let today = date(2026, 6, 1)
        let r = ForecastRecurringInput(
            id: "r-1", amount: 15_000, cadence: .weekly,
            nextDueDate: date(2026, 6, 1), endDate: nil, label: "Payroll"
        )
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 4,
            startingBalance: 10_000, lowWaterThreshold: 5_000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [], estimates: [], opportunities: [], recurringExpenses: [r],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.state, .danger)
        XCTAssertLessThan(result.lowestBalance, 0)
    }

    func testLowWaterStateWhenBelowThresholdButPositive() {
        let today = date(2026, 6, 1)
        let r = ForecastRecurringInput(
            id: "r-1", amount: 3000, cadence: .weekly,
            nextDueDate: date(2026, 6, 1), endDate: nil, label: "Subs"
        )
        // Horizon = 3: balances trace 10k → 7k → 4k → 1k. All ≥ 0, two weeks
        // below the 5k threshold → state must be .lowWater. A 4-week horizon
        // would push wk3 to -2k and trip .danger instead.
        let inputs = ForecastInputs(
            today: today, horizonWeeks: 3,
            startingBalance: 10_000, lowWaterThreshold: 5_000,
            avgDaysToPayment: 0, layers: Set(ForecastLayer.allCases),
            invoices: [], milestones: [], estimates: [], opportunities: [], recurringExpenses: [r],
            calendar: cal
        )
        let result = CashflowForecastEngine().compute(inputs: inputs)
        XCTAssertEqual(result.state, .lowWater)
        XCTAssertGreaterThanOrEqual(result.lowestBalance, 0)
        XCTAssertLessThan(result.lowestBalance, 5_000)
    }
}
