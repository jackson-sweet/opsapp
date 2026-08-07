//
//  ExpenseBucketsTests.swift
//  OPSTests
//
//  Truth table for the expense console's pure derivation layer —
//  bucket assignment, owed amounts, person grouping, line stats,
//  auto-send foresight, and spend metrics. Mirrors the OPS-Web
//  console rules (expense-buckets.ts / expense-approval.ts /
//  expense-metrics.ts) so the two clients can never disagree.
//

import XCTest
@testable import OPS

final class ExpenseBucketsTests: XCTestCase {

    // MARK: - Fixtures

    private func batch(
        id: String = "b1",
        status: String,
        total: Double? = 100,
        approved: Double? = nil,
        paidAt: String? = nil,
        submittedBy: String? = "user-a",
        periodStart: String? = "2026-06-01",
        periodEnd: String? = "2026-06-30",
        scopeProjectId: String? = nil,
        createdAt: String = "2026-06-01"
    ) -> ExpenseBatchDTO {
        ExpenseBatchDTO(
            id: id,
            companyId: "co",
            batchNumber: "EXP-BATCH-\(id)",
            periodStart: periodStart,
            periodEnd: periodEnd,
            status: status,
            submittedBy: submittedBy,
            reviewedBy: nil,
            reviewedAt: nil,
            totalAmount: total,
            approvedAmount: approved,
            parentBatchId: nil,
            amendmentNumber: 0,
            reviewNotes: nil,
            createdAt: createdAt,
            scopeProjectId: scopeProjectId,
            paidAt: paidAt,
            paidBy: paidAt == nil ? nil : "payer"
        )
    }

    private func line(
        id: String = "e1",
        batchId: String? = "b1",
        status: String = "submitted",
        amount: Double = 50,
        flaggedBy: String? = nil,
        expenseDate: String? = "2026-07-05",
        allocated: Bool = false,
        updatedAt: String = "2026-07-05T10:00:00Z"
    ) -> ExpenseDTO {
        ExpenseDTO(
            id: id,
            companyId: "co",
            submittedBy: "user-a",
            status: status,
            categoryId: nil,
            merchantName: "MERCHANT",
            description: nil,
            amount: amount,
            taxAmount: nil,
            currency: "USD",
            expenseDate: expenseDate,
            paymentMethod: nil,
            receiptImageUrl: nil,
            receiptThumbnailUrl: nil,
            receiptMissingReason: nil,
            receiptMissingNote: nil,
            projectMissingReason: nil,
            projectMissingNote: nil,
            ocrRawData: nil,
            ocrConfidence: nil,
            batchId: batchId,
            approvedBy: nil,
            approvedAt: nil,
            rejectedBy: nil,
            rejectedAt: nil,
            rejectionReason: nil,
            flagComment: flaggedBy == nil ? nil : "fix this",
            flaggedBy: flaggedBy,
            flaggedAt: nil,
            accountingSyncStatus: nil,
            accountingSyncId: nil,
            accountingSyncedAt: nil,
            createdAt: "2026-07-05T10:00:00Z",
            updatedAt: updatedAt,
            deletedAt: nil,
            allocations: allocated
                ? [ExpenseAllocationDTO(id: "a-\(id)", expenseId: id, projectId: "proj", percentage: 100, amount: nil)]
                : nil,
            category: nil
        )
    }

    // MARK: - Spend log ordering

    func testSpendLogPutsApprovedStatesFirstThenNewestExpense() {
        let rows = [
            line(id: "new-draft", status: "draft", expenseDate: "2026-08-07"),
            line(id: "old-approved", status: "approved", expenseDate: "2026-08-01"),
            line(id: "new-approved", status: "reimbursed", expenseDate: "2026-08-06"),
            line(id: "submitted", status: "submitted", expenseDate: "2026-08-05")
        ]

        XCTAssertEqual(
            BooksExpenseOrdering.sorted(rows).map(\.id),
            ["new-approved", "old-approved", "new-draft", "submitted"]
        )
    }

    func testSpendLogUsesUpdatedTimestampWhenExpenseDateIsMissing() {
        let rows = [
            line(id: "older", status: "submitted", expenseDate: nil,
                 updatedAt: "2026-08-01T12:00:00Z"),
            line(id: "newer", status: "submitted", expenseDate: nil,
                 updatedAt: "2026-08-06T12:00:00Z")
        ]

        XCTAssertEqual(BooksExpenseOrdering.sorted(rows).map(\.id), ["newer", "older"])
    }

    /// Fixed "now": July 11, 2026 (local calendar).
    private var now: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 11; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    // MARK: - Bucket assignment truth table

    func testPaidBeatsEverything() {
        for status in ["approved", "auto_approved", "partially_approved"] {
            let b = batch(status: status, paidAt: "2026-07-10T18:00:00+00:00")
            XCTAssertEqual(ExpenseBuckets.bucket(for: b, lineCount: 3), .paid, "\(status) + paid_at should be PAID")
        }
    }

    func testNeedsReviewBucket() {
        XCTAssertEqual(ExpenseBuckets.bucket(for: batch(status: "pending_review"), lineCount: 2), .review)
        // Legacy submitted batches are cross-period review work, never hidden.
        XCTAssertEqual(ExpenseBuckets.bucket(for: batch(status: "submitted"), lineCount: 2), .review)
    }

    func testAwaitingPayoutBucket() {
        for status in ["approved", "auto_approved", "partially_approved"] {
            XCTAssertEqual(ExpenseBuckets.bucket(for: batch(status: status), lineCount: 2), .pay, "\(status) with nil paid_at owes money")
        }
    }

    func testFillingEnvelopeIsWithCrew() {
        XCTAssertEqual(ExpenseBuckets.bucket(for: batch(status: "open"), lineCount: 2), .crew)
    }

    func testRejectedHoldingLinesIsWithCrew() {
        XCTAssertEqual(ExpenseBuckets.bucket(for: batch(status: "rejected"), lineCount: 1), .crew)
    }

    func testDrainedRejectedBatchDisappears() {
        XCTAssertNil(ExpenseBuckets.bucket(for: batch(status: "rejected"), lineCount: 0))
    }

    func testRejectedWithUnknownLineCountStaysVisible() {
        XCTAssertEqual(ExpenseBuckets.bucket(for: batch(status: "rejected"), lineCount: nil), .crew)
    }

    func testUnknownStatusStaysDiscoverable() {
        XCTAssertEqual(ExpenseBuckets.bucket(for: batch(status: "some_future_status"), lineCount: 2), .crew)
    }

    // MARK: - Owed amount rule

    func testPartialApprovalUsesApprovedAmount() {
        let b = batch(status: "partially_approved", total: 500, approved: 320)
        XCTAssertEqual(ExpenseBuckets.owedAmount(b), 320)
    }

    func testPartialApprovalFallsBackToTotalWhenApprovedMissing() {
        let b = batch(status: "partially_approved", total: 500, approved: nil)
        XCTAssertEqual(ExpenseBuckets.owedAmount(b), 500)
    }

    func testFullApprovalWithZeroApprovedAmountOwesTotal() {
        // approve_expense_batch never writes approved_amount — a 0 there means
        // the whole envelope, never $0. The demo company's 39 auto-approved
        // batches all sit at approved_amount = 0 against $45.5k total.
        let b = batch(status: "approved", total: 412, approved: 0)
        XCTAssertEqual(ExpenseBuckets.owedAmount(b), 412)
        let auto = batch(status: "auto_approved", total: 240, approved: nil)
        XCTAssertEqual(ExpenseBuckets.owedAmount(auto), 240)
    }

    func testLegacyFullApprovalWithWrittenAmountUsesIt() {
        // The old iOS two-write path DID write approved_amount on full
        // approvals — a positive figure is trusted (web parity).
        let b = batch(status: "approved", total: 500, approved: 500)
        XCTAssertEqual(ExpenseBuckets.owedAmount(b), 500)
    }

    // MARK: - Line stats

    func testLineStatsCountsAndFlags() {
        let lines = [
            line(id: "e1", batchId: "b1"),
            line(id: "e2", batchId: "b1", flaggedBy: "boss"),
            line(id: "e3", batchId: "b2"),
            line(id: "e4", batchId: nil)          // unbatched drafts don't count
        ]
        let stats = ExpenseBuckets.lineStats(lines)
        XCTAssertEqual(stats["b1"]?.count, 2)
        XCTAssertEqual(stats["b1"]?.flagged, 1)
        XCTAssertEqual(stats["b2"]?.count, 1)
        XCTAssertEqual(stats["b2"]?.flagged, 0)
        XCTAssertEqual(stats.count, 2)
    }

    // MARK: - Person grouping + sorts

    func testReviewGroupsOldestOutstandingLeads() {
        let batches = [
            batch(id: "new", status: "pending_review", submittedBy: "user-b",
                  periodStart: "2026-07-01", periodEnd: "2026-07-14"),
            batch(id: "old", status: "pending_review", submittedBy: "user-a",
                  periodStart: "2026-05-01", periodEnd: "2026-05-31"),
            batch(id: "older-of-b", status: "pending_review", submittedBy: "user-b",
                  periodStart: "2026-06-01", periodEnd: "2026-06-30")
        ]
        let groups = ExpenseBuckets.reviewPersonGroups(batches)
        XCTAssertEqual(groups.map(\.userId), ["user-a", "user-b"], "user-a's May batch is the oldest outstanding")
        XCTAssertEqual(groups[1].batches.map(\.id), ["older-of-b", "new"], "batches oldest-first inside a person")
        XCTAssertEqual(groups[0].total, 100)
    }

    func testPayGroupsLargestOwedFirst() {
        let batches = [
            batch(id: "small", status: "approved", total: 100, approved: 0, submittedBy: "user-a"),
            batch(id: "big1", status: "auto_approved", total: 400, submittedBy: "user-b"),
            batch(id: "big2", status: "partially_approved", total: 500, approved: 300, submittedBy: "user-b")
        ]
        let groups = ExpenseBuckets.payPersonGroups(batches)
        XCTAssertEqual(groups.map(\.userId), ["user-b", "user-a"])
        XCTAssertEqual(groups[0].total, 700, "owed = 400 (auto, total) + 300 (partial, approved_amount)")
    }

    // MARK: - Auto-send foresight

    func testAutoSendDateIsPeriodEndPlusGrace() {
        let b = batch(status: "open", periodEnd: "2026-07-14")
        let date = ExpenseBuckets.autoSendDate(b, graceDays: 7)
        XCTAssertNotNil(date)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual([comps.year, comps.month, comps.day], [2026, 7, 21])
    }

    func testPerJobEnvelopeHasNoCalendarSendDate() {
        // per_job envelopes send `completed_at + grace` after the job wraps —
        // not knowable client-side, so no date is shown.
        let b = batch(status: "open", scopeProjectId: "proj-1")
        XCTAssertNil(ExpenseBuckets.autoSendDate(b, graceDays: 7))
    }

    // MARK: - Metrics

    func testSpendCountsSubmittedApprovedReimbursedByExpenseDate() {
        let lines = [
            line(id: "e1", status: "submitted", amount: 100, expenseDate: "2026-07-02", allocated: true),
            line(id: "e2", status: "approved", amount: 50, expenseDate: "2026-07-08"),
            line(id: "e3", status: "reimbursed", amount: 25, expenseDate: "2026-07-09", allocated: true),
            line(id: "e4", status: "draft", amount: 999, expenseDate: "2026-07-03"),      // not submitted
            line(id: "e5", status: "rejected", amount: 999, expenseDate: "2026-07-04"),   // disputed
            line(id: "e6", status: "approved", amount: 200, expenseDate: "2026-06-15")    // last month
        ]
        let m = ExpenseBuckets.computeMetrics(batches: [], expenses: lines, now: now)
        XCTAssertEqual(m.spendMTD, 175)
        XCTAssertEqual(m.spendPrevMonth, 200)
        XCTAssertEqual(m.jobSpendMTD, 125)
        XCTAssertEqual(m.overheadSpendMTD, 50)
        XCTAssertEqual(m.spendTrendPct!, -12.5, accuracy: 0.01)
        XCTAssertEqual(m.spendByMonth.count, 6)
        XCTAssertEqual(m.spendByMonth.last, 175)
        XCTAssertEqual(m.spendByMonth[4], 200)
    }

    func testTrendIsNilWhenLastMonthHadNoSpend() {
        let lines = [line(id: "e1", status: "approved", amount: 100, expenseDate: "2026-07-02")]
        let m = ExpenseBuckets.computeMetrics(batches: [], expenses: lines, now: now)
        XCTAssertNil(m.spendTrendPct)
    }

    func testBucketTotalsFeedTheTiles() {
        let batches = [
            batch(id: "r1", status: "pending_review", total: 120, submittedBy: "user-a"),
            batch(id: "r2", status: "submitted", total: 80, submittedBy: "user-b"),
            batch(id: "p1", status: "approved", total: 400, approved: 0, submittedBy: "user-a"),
            batch(id: "p2", status: "partially_approved", total: 500, approved: 300, submittedBy: "user-b"),
            batch(id: "paid1", status: "approved", total: 250, paidAt: "2026-07-10T18:00:00+00:00"),
            batch(id: "paid-old", status: "approved", total: 99, paidAt: "2026-05-10T18:00:00+00:00"),
            batch(id: "crew", status: "open", total: 42)
        ]
        let m = ExpenseBuckets.computeMetrics(batches: batches, expenses: [], now: now)
        XCTAssertEqual(m.reviewTotal, 200)
        XCTAssertEqual(m.reviewCount, 2)
        XCTAssertEqual(m.reviewPeople, 2)
        XCTAssertEqual(m.payTotal, 700)
        XCTAssertEqual(m.payCount, 2)
        XCTAssertEqual(m.paidMTDTotal, 250, "only payouts recorded this month")
        XCTAssertEqual(m.paidMTDCount, 1)
    }

    // MARK: - Paid ledger sections

    func testPaidSectionsGroupByPayoutMonthNewestFirst() {
        let batches = [
            batch(id: "june", status: "approved", paidAt: "2026-06-20T10:00:00+00:00"),
            batch(id: "july-early", status: "approved", paidAt: "2026-07-02T10:00:00+00:00"),
            batch(id: "july-late", status: "auto_approved", paidAt: "2026-07-10T10:00:00+00:00")
        ]
        let sections = ExpenseBuckets.paidSections(batches)
        XCTAssertEqual(sections.map(\.monthKey), ["2026-07", "2026-06"])
        XCTAssertEqual(sections[0].batches.map(\.id), ["july-late", "july-early"], "newest payout first")
    }
}
