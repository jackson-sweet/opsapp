//
//  ExpenseRecurring.swift
//  OPS
//
//  Pure presentation logic for recurring reimbursements — a fixed monthly
//  amount the office pays a crew member with their expenses (vehicle
//  advertising, a phone plan). The database decides where each month's line
//  lands (ops-web migration 20260917030000_expense_recurring_reimbursements);
//  these helpers only let the app describe that decision truthfully before and
//  after it happens. Same rules as OPS-Web `expense-recurring.ts`, so the two
//  clients can never disagree.
//
//  Months are always `yyyy-MM-01` strings, which also sort chronologically as
//  plain strings. Everything here is pure.
//

import Foundation

enum ExpenseRecurring {

    /// The database accepts a first month within this many months of today.
    static let monthRange = 12
    /// The largest monthly amount the database accepts.
    static let maxAmount: Double = 10_000
    /// The longest name the database accepts, in Unicode scalars
    /// (Postgres `char_length` counts code points, not grapheme clusters).
    static let maxNameLength = 80

    private static let monthAbbreviations = [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
    ]

    // MARK: - Month arithmetic

    /// `yyyy-MM-dd` or `yyyy-MM` → (year, month). Nil for anything else.
    private static func parts(_ value: String) -> (year: Int, month: Int)? {
        let fields = value.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count >= 2,
              fields[0].count == 4, let year = Int(fields[0]),
              let month = Int(fields[1]), (1...12).contains(month) else { return nil }
        return (year, month)
    }

    private static func format(_ year: Int, _ month: Int) -> String {
        String(format: "%04d-%02d-01", year, month)
    }

    /// First day of the month containing `value`. Unparseable input is
    /// returned unchanged.
    static func monthStart(_ value: String) -> String {
        guard let p = parts(value) else { return value }
        return format(p.year, p.month)
    }

    /// `period` moved by `n` months (negative moves back). Unparseable input
    /// is returned unchanged.
    static func addMonths(_ period: String, _ n: Int) -> String {
        guard let p = parts(period) else { return period }
        let index = p.year * 12 + (p.month - 1) + n
        let year = index >= 0 ? index / 12 : (index - 11) / 12
        return format(year, index - year * 12 + 1)
    }

    /// Months from `first` through `last`, inclusive. Empty when inverted or
    /// unparseable.
    static func monthsBetween(_ first: String, _ last: String) -> [String] {
        guard parts(first) != nil, parts(last) != nil else { return [] }
        var months: [String] = []
        var cursor = monthStart(first)
        let end = monthStart(last)
        while cursor <= end {
            months.append(cursor)
            cursor = addMonths(cursor, 1)
        }
        return months
    }

    /// First-month choices the database will accept, oldest first.
    static func monthOptions(
        current: String,
        back: Int = monthRange,
        ahead: Int = monthRange
    ) -> [String] {
        monthsBetween(addMonths(current, -back), addMonths(current, ahead))
    }

    /// This month on the company's calendar, not the phone's. An unknown or
    /// missing zone falls back to UTC — the database's own fallback.
    static func currentMonth(in timeZoneIdentifier: String?, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: now)
        return format(components.year ?? 1970, components.month ?? 1)
    }

    // MARK: - Formatting

    /// `AUG 2026` — the uppercase month register used on every expense surface.
    static func formatMonth(_ period: String) -> String {
        guard let p = parts(period) else { return "—" }
        return "\(monthAbbreviations[p.month - 1]) \(p.year)"
    }

    /// Month list for preview copy: `AUG 2026, SEP 2026`.
    static func formatMonths(_ periods: [String]) -> String {
        periods.map(formatMonth).joined(separator: ", ")
    }

    // MARK: - Input

    private static let amountNoise: Set<Character> = ["$", ",", " ", "\u{00A0}"]

    /// Typed money → amount. Nil unless it is a positive amount with at most
    /// two decimals, no larger than the database allows. Tolerates `$`,
    /// grouping commas and stray spaces.
    static func parseAmount(_ raw: String) -> Double? {
        let cleaned = String(raw.filter { !amountNoise.contains($0) })
        guard cleaned.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(cleaned), value.isFinite, value > 0, value <= maxAmount else {
            return nil
        }
        return value
    }

    /// The name as the database will store it, or nil when it would be refused
    /// (empty, too long, or carrying control characters).
    static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.count <= maxNameLength,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    /// Typed name held to the database's length, counted the way it counts.
    static func clampedName(_ raw: String) -> String {
        guard raw.unicodeScalars.count > maxNameLength else { return raw }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: raw.unicodeScalars.prefix(maxNameLength))
        return String(scalars)
    }

    /// Two-decimal edit text for a stored amount (`350.00`).
    static func amountText(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }

    // MARK: - Placement preview

    struct PlacementPreview: Equatable {
        /// Months the database files the moment the reimbursement is saved.
        var filedNow: [String]
        /// Of those, months already paid out — their line lands on the next batch.
        var paidOut: [String]
        /// The first month has not arrived; nothing is filed yet.
        var startsLater: Bool
    }

    private static let approvedStatuses: Set<String> = ["approved", "auto_approved", "partially_approved"]
    private static let takingStatuses: Set<String> = ["open", "pending_review", "submitted"]

    /// What saving a new reimbursement does right now, told from the person's
    /// own batches — the same envelope rules the database applies.
    static func placementPreview(
        firstPeriod: String,
        currentMonth: String,
        userId: String,
        batches: [ExpenseBatchDTO]
    ) -> PlacementPreview {
        let first = monthStart(firstPeriod)
        let current = monthStart(currentMonth)
        if first > current {
            return PlacementPreview(filedNow: [], paidOut: [], startsLater: true)
        }

        let own = batches.filter { isPeriodEnvelope($0, of: userId) }
        let filedNow = monthsBetween(first, current)
        let paidOut = filedNow.filter { month in
            let covering = own.filter { covers($0, month: month) }
            let canTake = covering.contains(where: canTakeLine)
            let paid = covering.contains(where: isPaidOut)
            return paid && !canTake
        }

        return PlacementPreview(filedNow: filedNow, paidOut: paidOut, startsLater: false)
    }

    /// The person's own original (non-amendment) calendar envelope — the only
    /// kind a recurring line is ever filed into.
    private static func isPeriodEnvelope(_ batch: ExpenseBatchDTO, of userId: String) -> Bool {
        guard let submitter = batch.submittedBy,
              submitter.lowercased() == userId.lowercased() else { return false }
        guard (batch.amendmentNumber ?? 0) == 0, batch.scopeProjectId == nil else { return false }
        return batch.periodStart != nil && batch.periodEnd != nil
    }

    private static func covers(_ batch: ExpenseBatchDTO, month: String) -> Bool {
        guard let start = batch.periodStart, let end = batch.periodEnd else { return false }
        return start <= month && month <= end
    }

    /// Still filling, with the office, or approved and not yet paid.
    private static func canTakeLine(_ batch: ExpenseBatchDTO) -> Bool {
        if takingStatuses.contains(batch.status) { return true }
        return approvedStatuses.contains(batch.status) && batch.paidAt == nil
    }

    private static func isPaidOut(_ batch: ExpenseBatchDTO) -> Bool {
        approvedStatuses.contains(batch.status) && batch.paidAt != nil
    }

    // MARK: - Lifecycle guards

    /// Delete is for a setup made in error — refused once any month is paid.
    static func canDelete(_ lines: [RecurringLineSummary]) -> Bool {
        !lines.contains { !$0.deleted && $0.status == "reimbursed" }
    }

    /// The latest month still on a batch. Ending never removes a filed month.
    static func latestFiledPeriod(_ lines: [RecurringLineSummary]) -> String? {
        var latest: String?
        for line in lines where !line.deleted {
            if let current = latest, current >= line.period { continue }
            latest = line.period
        }
        return latest
    }

    /// Last-month choices: from the latest filed month (or the first) to a
    /// year past this month.
    static func endMonthOptions(
        firstPeriod: String,
        latestFiled: String?,
        currentMonth: String
    ) -> [String] {
        let first = monthStart(firstPeriod)
        let floor = latestFiled.map { $0 > first ? $0 : first } ?? first
        let ceiling = addMonths(monthStart(currentMonth), monthRange)
        return monthsBetween(floor, ceiling > floor ? ceiling : floor)
    }

    /// Where the last-month picker opens: this month, unless a later month is
    /// already filed.
    static func defaultEndMonth(options: [String], currentMonth: String) -> String {
        let floor = options.first ?? currentMonth
        return currentMonth >= floor ? currentMonth : floor
    }

    /// Whether a setup is paying out in `month`: started, and not yet ended.
    static func isRunning(_ setup: ExpenseRecurringReimbursementDTO, in month: String) -> Bool {
        setup.firstPeriod <= month && (setup.lastPeriod.map { $0 >= month } ?? true)
    }

    // MARK: - Server refusals

    /// Every refusal the recurring commands can return, plus transport failure.
    enum Refusal: String, CaseIterable {
        case duplicate
        case changed
        case busy
        case permission
        case selfGrant
        case paid
        case endBefore
        case removed
        case name
        case amount
        case start
        case category
        case person
        case endBeforeStart
        case afterEnd
        case offline
        case failed
    }

    private static let refusalPatterns: [(String, Refusal)] = [
        ("already has a recurring reimbursement with that name", .duplicate),
        ("changed. reload and try again", .changed),
        ("expenses are being updated", .busy),
        ("do not have permission", .permission),
        ("only an admin can set up a recurring reimbursement for themselves", .selfGrant),
        ("already been paid", .paid),
        ("is already on a batch", .endBefore),
        ("no longer available", .removed),
        ("was removed", .removed),
        ("name it in 80 characters", .name),
        ("enter an amount", .amount),
        ("start within 12 months", .start),
        ("category is unavailable", .category),
        ("not an active member", .person),
        ("end on or after the first month", .endBeforeStart),
        ("after this reimbursement ends", .afterEnd),
    ]

    /// The server's message → refusal. Unknown messages read as `.failed`.
    static func refusal(forMessage message: String?) -> Refusal {
        guard let message = message?.lowercased(), !message.isEmpty else { return .failed }
        return refusalPatterns.first { message.contains($0.0) }?.1 ?? .failed
    }
}

// MARK: - Line identity

extension ExpenseDTO {
    /// Filed by a recurring reimbursement rather than a receipt. Office-owned:
    /// no receipt to chase, nothing to flag, never edited as an expense.
    var isRecurringReimbursement: Bool {
        !(recurringReimbursementId?.isEmpty ?? true)
    }
}
