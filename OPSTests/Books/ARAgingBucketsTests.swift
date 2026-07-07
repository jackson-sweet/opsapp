//
//  ARAgingBucketsTests.swift
//  OPSTests
//
//  Locks the single A/R-aging semantic shared by the Money command-grid
//  receivables tile (BooksCommandGrid.agingBuckets) and its drill-down sheet
//  (BooksARSheet.buckets). Bug 3911ed80: the two views split aging two ways —
//  the tile put undated invoices in `current` (`?? 0`), the sheet dropped them
//  (`guard let due else continue`) — so the drill-down failed to reconcile to
//  the hero it opened from whenever an outstanding invoice had no due date.
//
//  The invariant these tests enforce: EVERY outstanding item lands in exactly
//  one bucket, so the four buckets always sum to the outstanding total. That
//  makes drill-down↔hero reconciliation structural and the
//  all-empty-buckets-but-positive-total state impossible.
//

import XCTest
@testable import OPS

final class ARAgingBucketsTests: XCTestCase {

    // Fixed reference instant so day math is deterministic (no wall-clock).
    private let asOf = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(amount: Double, dueDaysOverdue days: Int?) -> MoneyDashboardViewModel.BreakdownItem {
        // +3600s pushes the due date just past the day boundary so
        // Int(timeInterval / 86_400) == days unambiguously (no float edge).
        let due: Date? = days.map { asOf.addingTimeInterval(-(Double($0) * 86_400 + 3_600)) }
        return MoneyDashboardViewModel.BreakdownItem(
            label: "INV", amount: amount, date: due, entityId: UUID().uuidString, type: .invoice
        )
    }

    private func futureItem(amount: Double, dueInDays days: Int) -> MoneyDashboardViewModel.BreakdownItem {
        MoneyDashboardViewModel.BreakdownItem(
            label: "INV", amount: amount,
            date: asOf.addingTimeInterval(Double(days) * 86_400),
            entityId: UUID().uuidString, type: .invoice
        )
    }

    // MARK: - Empty

    func testEmptyBreakdownIsAllZero() {
        let b = MoneyDashboardViewModel.agingBuckets(from: [], asOf: asOf)
        XCTAssertEqual(b, MoneyDashboardViewModel.ARAgingBuckets())
        XCTAssertEqual(b.total, 0, accuracy: 0.0001)
    }

    // MARK: - Youngest bucket absorbs not-yet-due and undated (the fix)

    func testUndatedInvoiceLandsInCurrent() {
        let b = MoneyDashboardViewModel.agingBuckets(from: [item(amount: 500, dueDaysOverdue: nil)], asOf: asOf)
        XCTAssertEqual(b.current, 500, accuracy: 0.0001)
        XCTAssertEqual(b.d30, 0, accuracy: 0.0001)
        XCTAssertEqual(b.d60, 0, accuracy: 0.0001)
        XCTAssertEqual(b.d90, 0, accuracy: 0.0001)
    }

    func testNotYetDueInvoiceLandsInCurrent() {
        // Due 10 days in the FUTURE — negative "days overdue" → youngest bucket.
        let b = MoneyDashboardViewModel.agingBuckets(from: [futureItem(amount: 800, dueInDays: 10)], asOf: asOf)
        XCTAssertEqual(b.current, 800, accuracy: 0.0001)
        XCTAssertEqual(b.total, 800, accuracy: 0.0001)
    }

    // MARK: - Threshold boundaries (31 / 61 / 91)

    func testBucketBoundaries() {
        func bucketIndex(forDaysOverdue days: Int) -> Int {
            let b = MoneyDashboardViewModel.agingBuckets(from: [item(amount: 1, dueDaysOverdue: days)], asOf: asOf)
            if b.current > 0 { return 0 }
            if b.d30 > 0 { return 1 }
            if b.d60 > 0 { return 2 }
            return 3
        }
        XCTAssertEqual(bucketIndex(forDaysOverdue: 0),  0, "0d → current")
        XCTAssertEqual(bucketIndex(forDaysOverdue: 30), 0, "30d → current")
        XCTAssertEqual(bucketIndex(forDaysOverdue: 31), 1, "31d → 31–60")
        XCTAssertEqual(bucketIndex(forDaysOverdue: 60), 1, "60d → 31–60")
        XCTAssertEqual(bucketIndex(forDaysOverdue: 61), 2, "61d → 61–90")
        XCTAssertEqual(bucketIndex(forDaysOverdue: 90), 2, "90d → 61–90")
        XCTAssertEqual(bucketIndex(forDaysOverdue: 91), 3, "91d → 90+")
        XCTAssertEqual(bucketIndex(forDaysOverdue: 365), 3, "365d → 90+")
    }

    // MARK: - Reconciliation invariant (the whole point)

    func testBucketsAlwaysSumToTotal_mixedIncludingUndated() {
        let breakdown = [
            item(amount: 100, dueDaysOverdue: nil),   // undated → current (regression case)
            futureItem(amount: 200, dueInDays: 20),   // not yet due → current
            item(amount: 300, dueDaysOverdue: 15),    // current
            item(amount: 400, dueDaysOverdue: 45),    // 31–60
            item(amount: 500, dueDaysOverdue: 75),    // 61–90
            item(amount: 600, dueDaysOverdue: 200),   // 90+
        ]
        let expectedTotal = breakdown.reduce(0) { $0 + $1.amount } // 2100
        let b = MoneyDashboardViewModel.agingBuckets(from: breakdown, asOf: asOf)

        // The hero (totalOutstanding) reduces over the SAME array; the buckets
        // must reconcile to it to the cent.
        XCTAssertEqual(b.total, expectedTotal, accuracy: 0.0001)
        XCTAssertEqual(b.current, 100 + 200 + 300, accuracy: 0.0001)
        XCTAssertEqual(b.d30, 400, accuracy: 0.0001)
        XCTAssertEqual(b.d60, 500, accuracy: 0.0001)
        XCTAssertEqual(b.d90, 600, accuracy: 0.0001)
    }

    // The exact defect: a positive outstanding total that produced empty buckets.
    func testUndatedOnlyIsNotSilentlyDropped() {
        let breakdown = [
            item(amount: 250, dueDaysOverdue: nil),
            item(amount: 750, dueDaysOverdue: nil),
        ]
        let b = MoneyDashboardViewModel.agingBuckets(from: breakdown, asOf: asOf)
        XCTAssertEqual(b.total, 1000, accuracy: 0.0001, "undated invoices must still populate a bucket")
        XCTAssertGreaterThan(b.current, 0, "positive total can never yield all-empty buckets")
    }
}
