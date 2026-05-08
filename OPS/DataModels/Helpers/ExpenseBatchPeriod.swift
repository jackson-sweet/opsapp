//
//  ExpenseBatchPeriod.swift
//  OPS
//
//  Computes the (period_start, period_end) window for an expense batch
//  based on the company's review_frequency setting and the expense's date.
//
//  Used by ExpenseViewModel.submitExpense to drive the get_or_create_open_batch
//  call. Periods are calendar-date strings (yyyy-MM-dd) — matching the
//  expense_batches.period_start/period_end DATE columns.
//

import Foundation

struct ExpenseBatchPeriod {
    /// yyyy-MM-dd
    let start: String
    /// yyyy-MM-dd
    let end: String

    /// Resolve the period for an expense. The expense's own date drives
    /// the window — NOT "today" — so a late-logged April receipt batches
    /// into April even if submitted in May.
    ///
    /// Falls back to `createdAt` if `expenseDate` is missing.
    /// Falls back to `monthly` if `reviewFrequency` is unrecognized.
    static func forExpense(
        expenseDate: String?,
        createdAt: String,
        reviewFrequency: String
    ) -> ExpenseBatchPeriod {
        let date = parseExpenseDate(expenseDate) ?? parseExpenseDate(createdAt) ?? Date()
        return forDate(date, reviewFrequency: reviewFrequency)
    }

    static func forDate(_ date: Date, reviewFrequency: String) -> ExpenseBatchPeriod {
        // All period math runs in the user's local calendar — expense_date
        // is a calendar date (no time), and the user's local "today" is what
        // they typed in the form.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        // ISO week: Monday is the first day. Matches the bible spec
        // ("weekly: Batched every Monday").
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        let startDate: Date
        let endDate: Date

        switch reviewFrequency {
        case "per_job":
            // Per-job batches don't aggregate by period — the project scope
            // does the bucketing. Use the expense's date as a degenerate
            // single-day window so the row has meaningful period values.
            startDate = calendar.startOfDay(for: date)
            endDate = startDate

        case "weekly":
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date)
            startDate = weekInterval?.start ?? date
            // .end is exclusive (next Monday 00:00) — back off one day.
            endDate = calendar.date(byAdding: .day, value: -1,
                                    to: weekInterval?.end ?? date) ?? date

        case "biweekly":
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let day = comps.day ?? 1
            if day <= 14 {
                startDate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? date
                endDate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 14)) ?? date
            } else {
                startDate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 15)) ?? date
                let monthInterval = calendar.dateInterval(of: .month, for: date)
                endDate = calendar.date(byAdding: .day, value: -1,
                                        to: monthInterval?.end ?? date) ?? date
            }

        case "quarterly":
            let comps = calendar.dateComponents([.year, .month], from: date)
            let month = comps.month ?? 1
            // Quarter starts at month 1, 4, 7, or 10
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            startDate = calendar.date(from: DateComponents(year: comps.year, month: quarterStartMonth, day: 1)) ?? date
            // Quarter end = (start + 3 months) - 1 day
            let nextQuarter = calendar.date(byAdding: .month, value: 3, to: startDate) ?? date
            endDate = calendar.date(byAdding: .day, value: -1, to: nextQuarter) ?? date

        case "monthly":
            fallthrough
        default:
            let monthInterval = calendar.dateInterval(of: .month, for: date)
            startDate = monthInterval?.start ?? date
            endDate = calendar.date(byAdding: .day, value: -1,
                                    to: monthInterval?.end ?? date) ?? date
        }

        return ExpenseBatchPeriod(
            start: dateOnlyString(startDate),
            end: dateOnlyString(endDate)
        )
    }

    // MARK: - Date string helpers

    /// Parses an `expense_date` value — DTOs send these as ISO 8601 strings
    /// (full or date-only), depending on which formatter wrote them.
    private static func parseExpenseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        if let d = dateOnly.date(from: raw) { return d }
        let full = ISO8601DateFormatter()
        if let d = full.date(from: raw) { return d }
        // Last resort: pure yyyy-MM-dd
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.date(from: String(raw.prefix(10)))
    }

    /// Render a Date as `yyyy-MM-dd` for the DATE columns.
    private static func dateOnlyString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: date)
    }
}
