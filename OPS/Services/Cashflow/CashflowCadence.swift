//
//  CashflowCadence.swift
//  OPS
//
//  Pure cadence iteration over RecurringCadence. Calendar-injectable so test
//  suites can fix the timezone for deterministic dates. Used by the forecast
//  engine to project recurring outflows onto weekly buckets.
//

import Foundation

enum CashflowCadence {

    /// The next occurrence after `date` for the given cadence. Calendar handles
    /// month/year math (Jan 31 + 1 month → Feb 28, etc.).
    static func next(
        after date: Date,
        cadence: RecurringCadence,
        calendar: Calendar = .current
    ) -> Date {
        switch cadence {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .annually:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }

    /// All occurrence dates from `start` (inclusive) up to and including
    /// `horizon`, stopping if `endDate` is reached.
    ///
    /// Safety: capped at 520 iterations (10 years weekly) to guard against
    /// degenerate input where the cadence iterator never advances.
    static func occurrences(
        from start: Date,
        until horizon: Date,
        cadence: RecurringCadence,
        endDate: Date?,
        calendar: Calendar = .current
    ) -> [Date] {
        var result: [Date] = []
        var current = start
        while current <= horizon {
            if let endDate, current > endDate { break }
            result.append(current)
            let advanced = next(after: current, cadence: cadence, calendar: calendar)
            if advanced <= current { break }   // degenerate input guard
            current = advanced
            if result.count > 520 { break }
        }
        return result
    }
}
