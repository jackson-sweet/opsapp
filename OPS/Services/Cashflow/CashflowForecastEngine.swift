//
//  CashflowForecastEngine.swift
//  OPS
//
//  Pure forecast logic. Consumes value-type inputs (decoupled from SwiftData /
//  Supabase DTOs); produces a ForecastResult. Testable in isolation.
//
//  Spec: docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md §5.
//

import Foundation

// MARK: - Input value types

enum ForecastInvoiceStatus: String, Codable {
    case sent
    case viewed
    case partiallyPaid = "partially_paid"
    case pastDue       = "past_due"
}

struct ForecastInvoiceInput {
    let id: String
    let balanceDue: Double
    let dueDate: Date
    let status: ForecastInvoiceStatus
    let clientLabel: String
}

struct ForecastMilestoneInput {
    let id: String
    let estimateId: String
    let amount: Double
    let expectedDate: Date?      // from payment_milestones.expected_date
    let fallbackDate: Date?      // derived from project span when expected_date is nil
    let isPaid: Bool
    let label: String            // e.g. "Garcia kitchen — Framing"
}

struct ForecastEstimateInput {
    let id: String
    let total: Double
    let approvedAt: Date?
    let projectEndDate: Date?
    let clientLabel: String
    let hasMilestones: Bool      // if true, skip (milestones handle it)
}

struct ForecastOpportunityInput {
    let id: String
    let estimatedValue: Double
    let winProbability: Int      // 0..100
    let expectedCloseDate: Date
    let label: String
}

struct ForecastRecurringInput {
    let id: String
    let amount: Double
    let cadence: RecurringCadence
    let nextDueDate: Date
    let endDate: Date?
    let label: String
}

struct ForecastInputs {
    let today: Date
    let horizonWeeks: Int
    let startingBalance: Double
    let lowWaterThreshold: Double
    let avgDaysToPayment: Double
    let layers: Set<ForecastLayer>
    let invoices: [ForecastInvoiceInput]
    let milestones: [ForecastMilestoneInput]
    let estimates: [ForecastEstimateInput]
    let opportunities: [ForecastOpportunityInput]
    let recurringExpenses: [ForecastRecurringInput]
    let calendar: Calendar
    let startingBalanceAsOf: Date?

    init(
        today: Date,
        horizonWeeks: Int,
        startingBalance: Double,
        lowWaterThreshold: Double,
        avgDaysToPayment: Double,
        layers: Set<ForecastLayer>,
        invoices: [ForecastInvoiceInput],
        milestones: [ForecastMilestoneInput],
        estimates: [ForecastEstimateInput],
        opportunities: [ForecastOpportunityInput],
        recurringExpenses: [ForecastRecurringInput],
        calendar: Calendar,
        startingBalanceAsOf: Date? = nil
    ) {
        self.today = today
        self.horizonWeeks = horizonWeeks
        self.startingBalance = startingBalance
        self.lowWaterThreshold = lowWaterThreshold
        self.avgDaysToPayment = avgDaysToPayment
        self.layers = layers
        self.invoices = invoices
        self.milestones = milestones
        self.estimates = estimates
        self.opportunities = opportunities
        self.recurringExpenses = recurringExpenses
        self.calendar = calendar
        self.startingBalanceAsOf = startingBalanceAsOf
    }
}

// MARK: - Engine

struct CashflowForecastEngine {

    func compute(inputs: ForecastInputs) -> ForecastResult {
        let weekRanges = makeWeekRanges(
            today: inputs.today,
            count: inputs.horizonWeeks,
            calendar: inputs.calendar
        )
        var weeklyInflows  = Array(repeating: 0.0, count: inputs.horizonWeeks)
        var weeklyOutflows = Array(repeating: 0.0, count: inputs.horizonWeeks)
        var weeklyContrib  = Array(repeating: [ProjectionContributor](), count: inputs.horizonWeeks)

        // Layer: committed (sent / partially-paid invoices)
        if inputs.layers.contains(.committed) {
            for inv in inputs.invoices {
                let projected = offsetByPaymentDays(inv.dueDate, days: inputs.avgDaysToPayment, calendar: inputs.calendar)
                if let w = weekIndex(for: projected, in: weekRanges) {
                    weeklyInflows[w] += inv.balanceDue
                    weeklyContrib[w].append(.init(
                        id: inv.id,
                        layer: .committed,
                        label: inv.clientLabel,
                        amount: inv.balanceDue,
                        sourceKind: .invoice,
                        probabilityHint: nil
                    ))
                }
            }
        }

        // Additional layers wired up in Tasks 10–12.

        return buildResult(
            inputs: inputs,
            weekRanges: weekRanges,
            inflows: weeklyInflows,
            outflows: weeklyOutflows,
            contributors: weeklyContrib
        )
    }

    // MARK: - Helpers

    private func makeWeekRanges(today: Date, count: Int, calendar: Calendar) -> [(start: Date, end: Date)] {
        var result: [(Date, Date)] = []
        var cursor = startOfWeek(for: today, calendar: calendar)
        for _ in 0..<count {
            let end = calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor
            result.append((cursor, end))
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cursor
        }
        return result
    }

    private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }

    private func weekIndex(for date: Date, in ranges: [(start: Date, end: Date)]) -> Int? {
        for (i, r) in ranges.enumerated() where date >= r.start && date <= r.end {
            return i
        }
        return nil
    }

    private func offsetByPaymentDays(_ date: Date, days: Double, calendar: Calendar) -> Date {
        let intDays = Int(ceil(days))
        return calendar.date(byAdding: .day, value: intDays, to: date) ?? date
    }

    private func buildResult(
        inputs: ForecastInputs,
        weekRanges: [(start: Date, end: Date)],
        inflows: [Double],
        outflows: [Double],
        contributors: [[ProjectionContributor]]
    ) -> ForecastResult {
        var running = inputs.startingBalance
        var weeks: [WeeklyProjection] = []

        for i in 0..<inputs.horizonWeeks {
            let net = inflows[i] - outflows[i]
            running += net
            weeks.append(.init(
                id: i,
                weekStart: weekRanges[i].start,
                weekEnd: weekRanges[i].end,
                inflows: inflows[i],
                outflows: outflows[i],
                net: net,
                balance: running,
                contributors: contributors[i]
            ))
        }

        let lowest = weeks.min(by: { $0.balance < $1.balance }) ?? weeks[0]
        let state: ForecastState
        if weeks.contains(where: { $0.balance < 0 }) {
            state = .danger
        } else if weeks.contains(where: { $0.balance < inputs.lowWaterThreshold }) {
            state = .lowWater
        } else {
            state = .healthy
        }

        return ForecastResult(
            weeks: weeks,
            state: state,
            startingBalance: inputs.startingBalance,
            startingBalanceAsOf: inputs.startingBalanceAsOf,
            lowestWeekIndex: lowest.id,
            lowestBalance: lowest.balance,
            endingBalance: weeks.last?.balance ?? inputs.startingBalance,
            lowWaterThreshold: inputs.lowWaterThreshold,
            layersIncluded: inputs.layers,
            computedAt: Date()
        )
    }
}
