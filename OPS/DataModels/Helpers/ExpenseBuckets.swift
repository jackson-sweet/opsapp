//
//  ExpenseBuckets.swift
//  OPS
//
//  Pure derivation for the expense batch console. Every batch lands in
//  exactly one lifecycle bucket, mirroring what the operator owes attention
//  to — the same rules as the OPS-Web console (expense-buckets.ts /
//  expense-approval.ts / expense-metrics.ts) so the two clients can never
//  disagree:
//
//    review — submitted envelopes waiting on the office (pending_review +
//             legacy submitted), cross-period
//    pay    — approved money not yet settled up (approved / partially /
//             auto, paid_at IS NULL)
//    paid   — payout recorded (paid_at set), terminal reference
//    crew   — on the crew's side: filling envelopes + returned (rejected)
//             batches that still hold lines to fix; a drained returned
//             batch disappears
//
//  All functions are pure and side-effect free so they unit-test cold.
//

import Foundation

// MARK: - Bucket

enum ExpenseBucket: String, CaseIterable {
    case review, pay, paid, crew
}

// MARK: - Line stats

struct ExpenseBatchLineStats {
    var count: Int = 0
    var flagged: Int = 0
}

// MARK: - Person group

struct ExpensePersonGroup: Identifiable {
    /// users.id, or "unknown" for orphaned submitter references.
    let userId: String
    var batches: [ExpenseBatchDTO]
    var total: Double
    var id: String { userId }
}

// MARK: - Paid ledger section

struct ExpensePaidSection: Identifiable {
    /// "yyyy-MM" of the payout date.
    let monthKey: String
    var batches: [ExpenseBatchDTO]
    var id: String { monthKey }
}

// MARK: - Console metrics

struct ExpenseConsoleMetrics {
    /// Spend this calendar month (by expense date).
    var spendMTD: Double = 0
    /// Spend last calendar month — the trend base.
    var spendPrevMonth: Double = 0
    /// Month-over-month change in percent; nil when last month had no spend.
    var spendTrendPct: Double? = nil
    /// Monthly spend, oldest → newest, ending with the current month (6 entries).
    var spendByMonth: [Double] = []
    /// This month's spend that is allocated to a job.
    var jobSpendMTD: Double = 0
    /// This month's spend with no job allocation (overhead / shop).
    var overheadSpendMTD: Double = 0

    var reviewTotal: Double = 0
    var reviewCount: Int = 0
    var reviewPeople: Int = 0

    var payTotal: Double = 0
    var payCount: Int = 0
    var payPeople: Int = 0

    var paidMTDTotal: Double = 0
    var paidMTDCount: Int = 0
}

// MARK: - Bucket split (console working sets)

struct ExpenseBucketSplit {
    var review: [ExpenseBatchDTO] = []
    var pay: [ExpenseBatchDTO] = []
    var paid: [ExpenseBatchDTO] = []
    var crewFilling: [ExpenseBatchDTO] = []
    /// Returned (rejected) batches still holding ≥1 line to fix.
    var crewReturned: [ExpenseBatchDTO] = []

    var crewCount: Int { crewFilling.count + crewReturned.count }
}

// MARK: - Derivation

enum ExpenseBuckets {

    // MARK: Predicates

    /// Recorded as paid out to the submitter — terminal.
    static func isPaid(_ batch: ExpenseBatchDTO) -> Bool {
        batch.paidAt != nil
    }

    /// Approved money waiting to be settled up — the TO PAY working set.
    static func isAwaitingPayout(_ batch: ExpenseBatchDTO) -> Bool {
        let status = ExpenseBatchStatus(rawValue: batch.status)
        return (status?.isApproved ?? false) && batch.paidAt == nil
    }

    /// The amount actually owed for a batch.
    ///
    /// `approved_amount` is only authoritative for partial approvals (the
    /// send-back flow writes the clean-line total there). The atomic
    /// `approve_expense_batch` RPC approves every line but leaves
    /// approved_amount at its creation value (often 0), so for full approvals
    /// a zero/absent figure means "the whole envelope" — fall back to the
    /// recalculated total. A positive figure on a full approval (the legacy
    /// iOS two-write path wrote one) is trusted.
    static func owedAmount(_ batch: ExpenseBatchDTO) -> Double {
        if ExpenseBatchStatus(rawValue: batch.status) == .partiallyApproved {
            return batch.approvedAmount ?? batch.totalAmount ?? 0
        }
        if let approved = batch.approvedAmount, approved > 0 {
            return approved
        }
        return batch.totalAmount ?? 0
    }

    /// The one bucket a batch belongs to, or nil when it should not render at
    /// all (a returned batch whose lines have all been re-filed by the crew).
    /// `lineCount` is the batch's live line count when known; pass nil while
    /// stats are loading and the batch stays visible.
    static func bucket(for batch: ExpenseBatchDTO, lineCount: Int?) -> ExpenseBucket? {
        if isPaid(batch) { return .paid }
        let status = ExpenseBatchStatus(rawValue: batch.status)
        if status?.needsReview == true { return .review }
        if isAwaitingPayout(batch) { return .pay }
        if status == .open { return .crew }
        if status == .rejected {
            return lineCount == 0 ? nil : .crew
        }
        // Unknown/new server status — keep it discoverable rather than vanish it.
        return .crew
    }

    // MARK: Line stats

    /// Per-batch line counts + flag counts from the company-wide line list.
    /// Unbatched lines (drafts not yet placed) carry no batch and are skipped.
    /// Flagged = `flagged_by` set — the flag toggle always stamps the flagger
    /// even when the comment is still empty.
    static func lineStats(_ expenses: [ExpenseDTO]) -> [String: ExpenseBatchLineStats] {
        var stats: [String: ExpenseBatchLineStats] = [:]
        for lineItem in expenses {
            guard let batchId = lineItem.batchId else { continue }
            var entry = stats[batchId] ?? ExpenseBatchLineStats()
            entry.count += 1
            if lineItem.flaggedBy != nil { entry.flagged += 1 }
            stats[batchId] = entry
        }
        return stats
    }

    // MARK: Line ordering

    /// A line whose money is decided — approved or already reimbursed. Nothing
    /// is outstanding on it, so it reads as reference, not work.
    static func isSettled(_ expense: ExpenseDTO) -> Bool {
        ExpenseStatus(rawValue: expense.status)?.isTerminal ?? false
    }

    /// The canonical order for any list of expense LINES the operator scans:
    /// what still needs a decision leads (draft / submitted / sent back),
    /// settled money follows — newest first inside each group. Stable: equal
    /// keys keep their source order (the repositories hand lines over newest
    /// created first).
    static func attentionOrdered(_ expenses: [ExpenseDTO]) -> [ExpenseDTO] {
        expenses
            .enumerated()
            .sorted { left, right in
                let leftSettled = isSettled(left.element)
                let rightSettled = isSettled(right.element)
                if leftSettled != rightSettled { return !leftSettled }
                let leftDate = recencyDate(left.element)
                let rightDate = recencyDate(right.element)
                if leftDate != rightDate { return leftDate > rightDate }
                return left.offset < right.offset
            }
            .map { $0.element }
    }

    /// What "recent" means for a line: the day the money went out, falling
    /// back to when the line was captured.
    private static func recencyDate(_ expense: ExpenseDTO) -> Date {
        parseDate(expense.expenseDate) ?? parseDate(expense.createdAt) ?? .distantPast
    }

    // MARK: Bucket split

    /// Partition a company's batches into the console's working sets, applying
    /// each bucket's canonical order.
    static func split(_ batches: [ExpenseBatchDTO], lineStats: [String: ExpenseBatchLineStats]) -> ExpenseBucketSplit {
        var result = ExpenseBucketSplit()
        for batch in batches {
            switch bucket(for: batch, lineCount: lineStats[batch.id]?.count ?? (lineStats.isEmpty ? nil : 0)) {
            case .review: result.review.append(batch)
            case .pay:    result.pay.append(batch)
            case .paid:   result.paid.append(batch)
            case .crew:
                if ExpenseBatchStatus(rawValue: batch.status) == .open {
                    result.crewFilling.append(batch)
                } else {
                    result.crewReturned.append(batch)
                }
            case nil: break
            }
        }
        // Filling envelopes: soonest auto-send first (period end ascending,
        // per-job envelopes last).
        result.crewFilling.sort {
            (parseDate($0.periodEnd) ?? .distantFuture) < (parseDate($1.periodEnd) ?? .distantFuture)
        }
        result.crewReturned.sort { $0.createdAt > $1.createdAt }
        return result
    }

    // MARK: Person grouping

    /// TO REVIEW — the person with the oldest outstanding period leads;
    /// batches oldest-first within a person. Amount = submitted total.
    static func reviewPersonGroups(_ batches: [ExpenseBatchDTO]) -> [ExpensePersonGroup] {
        var groups = groupBySubmitter(batches) { $0.totalAmount ?? 0 }
        for index in groups.indices {
            groups[index].batches.sort {
                ($0.periodStart ?? "") == ($1.periodStart ?? "")
                    ? $0.createdAt < $1.createdAt
                    : ($0.periodStart ?? "") < ($1.periodStart ?? "")
            }
        }
        groups.sort {
            (oldestPeriodStart($0.batches) ?? "9999") < (oldestPeriodStart($1.batches) ?? "9999")
        }
        return groups
    }

    /// TO PAY — the person owed the most leads; batches largest-owed-first
    /// within a person. Amount = owed.
    static func payPersonGroups(_ batches: [ExpenseBatchDTO]) -> [ExpensePersonGroup] {
        var groups = groupBySubmitter(batches) { owedAmount($0) }
        for index in groups.indices {
            groups[index].batches.sort { owedAmount($0) > owedAmount($1) }
        }
        groups.sort { $0.total > $1.total }
        return groups
    }

    private static func groupBySubmitter(
        _ batches: [ExpenseBatchDTO],
        amount: (ExpenseBatchDTO) -> Double
    ) -> [ExpensePersonGroup] {
        var order: [String] = []
        var byUser: [String: ExpensePersonGroup] = [:]
        for batch in batches {
            let key = batch.submittedBy ?? "unknown"
            if byUser[key] == nil {
                byUser[key] = ExpensePersonGroup(userId: key, batches: [], total: 0)
                order.append(key)
            }
            byUser[key]?.batches.append(batch)
            byUser[key]?.total += amount(batch)
        }
        return order.compactMap { byUser[$0] }
    }

    private static func oldestPeriodStart(_ batches: [ExpenseBatchDTO]) -> String? {
        batches.compactMap(\.periodStart).min()
    }

    // MARK: Paid ledger

    /// PAID — month sections by payout date, newest first; newest payout
    /// first within a month.
    static func paidSections(_ batches: [ExpenseBatchDTO]) -> [ExpensePaidSection] {
        var order: [String] = []
        var byMonth: [String: [ExpenseBatchDTO]] = [:]
        for batch in batches {
            guard let paidAt = batch.paidAt else { continue }
            let key = String(paidAt.prefix(7))
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(batch)
        }
        return order
            .sorted(by: >)
            .map { key in
                ExpensePaidSection(
                    monthKey: key,
                    batches: byMonth[key, default: []].sorted { ($0.paidAt ?? "") > ($1.paidAt ?? "") }
                )
            }
    }

    // MARK: Auto-send foresight

    /// When the server sweep will auto-send a filling envelope:
    /// `period_end + auto_submit_grace_days`. Per-job envelopes send after
    /// the linked job completes — not knowable client-side, so nil.
    static func autoSendDate(_ batch: ExpenseBatchDTO, graceDays: Int) -> Date? {
        guard batch.scopeProjectId == nil,
              let periodEnd = parseDate(batch.periodEnd) else { return nil }
        return Calendar.current.date(byAdding: .day, value: graceDays, to: periodEnd)
    }

    // MARK: Metrics

    /// Everything the instrument strip shows, derived from the SAME two
    /// datasets the queue renders (batches + company lines) so the numbers
    /// can never disagree with the list underneath them.
    ///
    /// Spend counts every line the crew actually submitted (submitted /
    /// approved / reimbursed) by expense date — approval state doesn't change
    /// what was spent. Rejected lines are disputed and drafts haven't been
    /// submitted; both stay out.
    static func computeMetrics(
        batches: [ExpenseBatchDTO],
        expenses: [ExpenseDTO],
        now: Date
    ) -> ExpenseConsoleMetrics {
        var metrics = ExpenseConsoleMetrics()
        let spendStatuses: Set<String> = ["submitted", "approved", "reimbursed"]
        let currentKey = monthKey(at: now, offset: 0)
        let windowKeys = (0..<6).map { monthKey(at: now, offset: $0 - 5) }

        var spendByMonthKey: [String: Double] = [:]
        for lineItem in expenses {
            guard spendStatuses.contains(lineItem.status),
                  let expenseDate = lineItem.expenseDate else { continue }
            let key = String(expenseDate.prefix(7))
            spendByMonthKey[key, default: 0] += lineItem.amount
            if key == currentKey {
                if lineItem.allocations?.first != nil {
                    metrics.jobSpendMTD += lineItem.amount
                } else {
                    metrics.overheadSpendMTD += lineItem.amount
                }
            }
        }

        metrics.spendByMonth = windowKeys.map { spendByMonthKey[$0] ?? 0 }
        metrics.spendMTD = spendByMonthKey[currentKey] ?? 0
        metrics.spendPrevMonth = spendByMonthKey[monthKey(at: now, offset: -1)] ?? 0
        metrics.spendTrendPct = metrics.spendPrevMonth > 0
            ? ((metrics.spendMTD - metrics.spendPrevMonth) / metrics.spendPrevMonth) * 100
            : nil

        var reviewUsers = Set<String>()
        var payUsers = Set<String>()
        for batch in batches {
            let status = ExpenseBatchStatus(rawValue: batch.status)
            if isPaid(batch) {
                if String((batch.paidAt ?? "").prefix(7)) == currentKey {
                    metrics.paidMTDTotal += owedAmount(batch)
                    metrics.paidMTDCount += 1
                }
            } else if status?.needsReview == true {
                metrics.reviewTotal += batch.totalAmount ?? 0
                metrics.reviewCount += 1
                reviewUsers.insert(batch.submittedBy ?? "unknown")
            } else if isAwaitingPayout(batch) {
                metrics.payTotal += owedAmount(batch)
                metrics.payCount += 1
                payUsers.insert(batch.submittedBy ?? "unknown")
            }
        }
        metrics.reviewPeople = reviewUsers.count
        metrics.payPeople = payUsers.count
        return metrics
    }

    // MARK: Date helpers

    /// Parse the server's date shapes: plain dates ("2026-07-14") and
    /// timestamptz strings, with or without fractional seconds.
    ///
    /// Plain dates anchor to LOCAL midnight — a period ending "2026-07-14" is
    /// July 14 on the operator's calendar, not UTC's. Parsing date-only
    /// strings at UTC midnight shifts every derived day (auto-send dates,
    /// period labels) one day early for anyone west of Greenwich.
    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        dateOnly.timeZone = .current
        if let date = dateOnly.date(from: string) { return date }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }

    /// Local-time "yyyy-MM" for a month offset from `now`.
    static func monthKey(at now: Date, offset: Int) -> String {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .month, value: offset, to: now) ?? now
        let comps = calendar.dateComponents([.year, .month], from: base)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }
}
