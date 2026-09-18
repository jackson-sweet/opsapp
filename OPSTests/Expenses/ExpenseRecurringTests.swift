//
//  ExpenseRecurringTests.swift
//  OPSTests
//
//  Truth table for the recurring reimbursement presentation rules — month
//  arithmetic, the company-calendar month, money input, the placement preview,
//  lifecycle guards and server refusal mapping. Mirrors OPS-Web
//  `tests/unit/expenses/expense-recurring.test.ts` case for case, so the two
//  clients describe the database's decisions identically.
//

import XCTest
@testable import OPS

final class ExpenseRecurringTests: XCTestCase {

    // MARK: - Fixtures

    private var seq = 0

    private func batch(
        status: String = "open",
        submittedBy: String? = "rivera",
        periodStart: String? = "2026-08-01",
        periodEnd: String? = "2026-08-31",
        amendmentNumber: Int? = 0,
        scopeProjectId: String? = nil,
        paidAt: String? = nil
    ) -> ExpenseBatchDTO {
        seq += 1
        return ExpenseBatchDTO(
            id: "batch-\(seq)",
            companyId: "co-1",
            batchNumber: String(format: "EXP-BATCH-%04d", seq),
            periodStart: periodStart,
            periodEnd: periodEnd,
            status: status,
            submittedBy: submittedBy,
            amendmentNumber: amendmentNumber,
            createdAt: "2026-08-01T10:00:00Z",
            scopeProjectId: scopeProjectId,
            paidAt: paidAt,
            paidBy: paidAt == nil ? nil : "okafor"
        )
    }

    private func line(
        period: String = "2026-08-01",
        status: String = "approved",
        deleted: Bool = false
    ) -> RecurringLineSummary {
        RecurringLineSummary(
            expenseId: "e-\(period)-\(status)",
            period: period,
            batchId: "batch-x",
            status: status,
            amount: 275,
            deleted: deleted
        )
    }

    // MARK: - Month arithmetic

    func testMonthStartNormalisesAnyDateInTheMonth() {
        XCTAssertEqual(ExpenseRecurring.monthStart("2026-08-17"), "2026-08-01")
        XCTAssertEqual(ExpenseRecurring.monthStart("2026-12-31"), "2026-12-01")
        XCTAssertEqual(ExpenseRecurring.monthStart("2026-02"), "2026-02-01")
        XCTAssertEqual(ExpenseRecurring.monthStart("not a month"), "not a month")
    }

    func testAddMonthsCrossesYearBoundaries() {
        XCTAssertEqual(ExpenseRecurring.addMonths("2026-11-01", 2), "2027-01-01")
        XCTAssertEqual(ExpenseRecurring.addMonths("2026-01-01", -1), "2025-12-01")
        XCTAssertEqual(ExpenseRecurring.addMonths("2026-08-01", 0), "2026-08-01")
        XCTAssertEqual(ExpenseRecurring.addMonths("2026-08-01", -12), "2025-08-01")
        XCTAssertEqual(ExpenseRecurring.addMonths("2026-08-01", 25), "2028-09-01")
    }

    func testMonthsBetweenIsInclusiveAndEmptyWhenInverted() {
        XCTAssertEqual(
            ExpenseRecurring.monthsBetween("2026-11-01", "2027-02-01"),
            ["2026-11-01", "2026-12-01", "2027-01-01", "2027-02-01"]
        )
        XCTAssertEqual(ExpenseRecurring.monthsBetween("2026-09-01", "2026-09-01"), ["2026-09-01"])
        XCTAssertEqual(ExpenseRecurring.monthsBetween("2026-09-01", "2026-08-01"), [])
        XCTAssertEqual(ExpenseRecurring.monthsBetween("garbage", "2026-08-01"), [])
    }

    func testMonthOptionsOfferTwelveMonthsEitherSideOldestFirst() {
        let options = ExpenseRecurring.monthOptions(current: "2026-09-01")
        XCTAssertEqual(options.count, 25)
        XCTAssertEqual(options.first, "2025-09-01")
        XCTAssertEqual(options[12], "2026-09-01")
        XCTAssertEqual(options.last, "2027-09-01")
    }

    func testCurrentMonthFollowsTheCompanyCalendarNotThePhone() throws {
        // 2026-09-01 03:00 UTC is still August 31 in Vancouver.
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-01T03:00:00Z"))
        XCTAssertEqual(ExpenseRecurring.currentMonth(in: "America/Vancouver", now: now), "2026-08-01")
        XCTAssertEqual(ExpenseRecurring.currentMonth(in: "UTC", now: now), "2026-09-01")
        XCTAssertEqual(ExpenseRecurring.currentMonth(in: nil, now: now), "2026-09-01")
        XCTAssertEqual(ExpenseRecurring.currentMonth(in: "Not/AZone", now: now), "2026-09-01")
    }

    // MARK: - Formatting

    func testMonthsReadInTheUppercaseRegister() {
        XCTAssertEqual(ExpenseRecurring.formatMonth("2026-08-01"), "AUG 2026")
        XCTAssertEqual(ExpenseRecurring.formatMonth("2027-01-01"), "JAN 2027")
        XCTAssertEqual(ExpenseRecurring.formatMonth("nope"), "—")
        XCTAssertEqual(ExpenseRecurring.formatMonths(["2026-08-01", "2026-09-01"]), "AUG 2026, SEP 2026")
    }

    // MARK: - Input

    func testParseAmountAcceptsWhatTheDatabaseAccepts() {
        XCTAssertEqual(ExpenseRecurring.parseAmount("275"), 275)
        XCTAssertEqual(ExpenseRecurring.parseAmount("275.5"), 275.5)
        XCTAssertEqual(ExpenseRecurring.parseAmount("$1,234.56"), 1234.56)
        XCTAssertEqual(ExpenseRecurring.parseAmount(" 0.01 "), 0.01)
        XCTAssertEqual(ExpenseRecurring.parseAmount("10000"), 10000)
    }

    func testParseAmountReadsTheDecimalKeyOfAnyKeyboard() {
        // A French Canadian keypad's decimal key is a comma: 35,50 is $35.50,
        // never $3,550.
        XCTAssertEqual(ExpenseRecurring.parseAmount("35,50"), 35.5)
        XCTAssertEqual(ExpenseRecurring.parseAmount("0,5"), 0.5)
        XCTAssertEqual(ExpenseRecurring.parseAmount("1,23"), 1.23)
        XCTAssertEqual(ExpenseRecurring.parseAmount("1 234,56"), 1234.56)
        XCTAssertEqual(ExpenseRecurring.parseAmount("1\u{202F}234,56"), 1234.56)
        XCTAssertEqual(ExpenseRecurring.parseAmount("1.234,56"), 1234.56)
        // Commas between groups of three digits still group thousands.
        XCTAssertEqual(ExpenseRecurring.parseAmount("1,234"), 1234)
        XCTAssertEqual(ExpenseRecurring.parseAmount("9,999.99"), 9999.99)
    }

    func testParseAmountRefusesAmbiguousOrMalformedMarks() {
        XCTAssertNil(ExpenseRecurring.parseAmount("1,2345"))
        XCTAssertNil(ExpenseRecurring.parseAmount("275."))
        XCTAssertNil(ExpenseRecurring.parseAmount(",50"))
        XCTAssertNil(ExpenseRecurring.parseAmount("1.234"))
        XCTAssertNil(ExpenseRecurring.parseAmount("12,34,56"))
        XCTAssertNil(ExpenseRecurring.parseAmount("1,234,567"))
    }

    func testParseAmountRefusesWhatTheDatabaseRefuses() {
        XCTAssertNil(ExpenseRecurring.parseAmount(""))
        XCTAssertNil(ExpenseRecurring.parseAmount("0"))
        XCTAssertNil(ExpenseRecurring.parseAmount("0.00"))
        XCTAssertNil(ExpenseRecurring.parseAmount("10000.01"))
        XCTAssertNil(ExpenseRecurring.parseAmount("12.345"))
        XCTAssertNil(ExpenseRecurring.parseAmount("-5"))
        XCTAssertNil(ExpenseRecurring.parseAmount("12.3.4"))
        XCTAssertNil(ExpenseRecurring.parseAmount("abc"))
    }

    func testNamesAreTrimmedAndHeldToEightyCodePoints() {
        XCTAssertEqual(ExpenseRecurring.normalizedName("  Phone plan "), "Phone plan")
        XCTAssertNil(ExpenseRecurring.normalizedName("   "))
        XCTAssertNil(ExpenseRecurring.normalizedName("Phone\u{0007}plan"))
        XCTAssertNotNil(ExpenseRecurring.normalizedName(String(repeating: "a", count: 80)))
        XCTAssertNil(ExpenseRecurring.normalizedName(String(repeating: "a", count: 81)))

        let long = String(repeating: "b", count: 90)
        XCTAssertEqual(ExpenseRecurring.clampedName(long).unicodeScalars.count, 80)
        XCTAssertEqual(ExpenseRecurring.clampedName("Short"), "Short")
    }

    func testAmountTextIsTwoDecimals() {
        XCTAssertEqual(ExpenseRecurring.amountText(275), "275.00")
        XCTAssertEqual(ExpenseRecurring.amountText(12.5), "12.50")
    }

    // MARK: - Placement preview

    func testFilesEveryMonthFromTheStartThroughThisMonth() {
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-08-01", currentMonth: "2026-09-01", userId: "rivera", batches: []
        )
        XCTAssertEqual(preview, .init(filedNow: ["2026-08-01", "2026-09-01"], paidOut: [], startsLater: false))
    }

    func testAnApprovedButUnpaidMonthIsOwedNotPaidOut() {
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-08-01", currentMonth: "2026-09-01", userId: "rivera",
            batches: [batch(status: "approved")]
        )
        XCTAssertEqual(preview.paidOut, [])
    }

    func testFlagsAMonthWhoseOnlyEnvelopeWasPaidOut() {
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-07-01", currentMonth: "2026-09-01", userId: "rivera",
            batches: [
                batch(status: "approved", periodStart: "2026-07-01", periodEnd: "2026-07-31",
                      paidAt: "2026-08-05T10:00:00Z"),
                batch(status: "approved"),
            ]
        )
        XCTAssertEqual(preview.filedNow, ["2026-07-01", "2026-08-01", "2026-09-01"])
        XCTAssertEqual(preview.paidOut, ["2026-07-01"])
    }

    func testIgnoresOtherPeopleAmendmentsAndJobEnvelopes() {
        let paid = "2026-09-02T00:00:00Z"
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-08-01", currentMonth: "2026-08-01", userId: "rivera",
            batches: [
                batch(status: "approved", submittedBy: "casey", paidAt: paid),
                batch(status: "approved", amendmentNumber: 1, paidAt: paid),
                batch(status: "approved", scopeProjectId: "job-1", paidAt: paid),
            ]
        )
        XCTAssertEqual(preview.paidOut, [])
    }

    func testNotPaidOutWhileAnotherEnvelopeCanStillTakeTheLine() {
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-08-01", currentMonth: "2026-08-01", userId: "rivera",
            batches: [
                batch(status: "approved", paidAt: "2026-09-02T00:00:00Z"),
                batch(status: "pending_review"),
            ]
        )
        XCTAssertEqual(preview.paidOut, [])
    }

    func testWeeklyEnvelopesCoverTheMonthByItsFirstDay() {
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-06-01", currentMonth: "2026-06-01", userId: "rivera",
            batches: [
                batch(status: "auto_approved", periodStart: "2026-06-01", periodEnd: "2026-06-07",
                      paidAt: "2026-06-20T00:00:00Z"),
            ]
        )
        XCTAssertEqual(preview.paidOut, ["2026-06-01"])
    }

    func testSubmitterMatchIgnoresUuidCase() {
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-08-01", currentMonth: "2026-08-01", userId: "RIVERA",
            batches: [batch(status: "approved", paidAt: "2026-09-02T00:00:00Z")]
        )
        XCTAssertEqual(preview.paidOut, ["2026-08-01"])
    }

    func testFilesNothingYetWhenTheFirstMonthIsAhead() {
        let preview = ExpenseRecurring.placementPreview(
            firstPeriod: "2026-11-01", currentMonth: "2026-09-01", userId: "rivera", batches: []
        )
        XCTAssertEqual(preview, .init(filedNow: [], paidOut: [], startsLater: true))
    }

    // MARK: - Lifecycle guards

    func testDeleteOnlyWhileNoMonthIsPaid() {
        XCTAssertTrue(ExpenseRecurring.canDelete([line(), line(period: "2026-09-01")]))
        XCTAssertFalse(ExpenseRecurring.canDelete([line(status: "reimbursed")]))
        XCTAssertTrue(ExpenseRecurring.canDelete([line(status: "reimbursed", deleted: true)]))
        XCTAssertTrue(ExpenseRecurring.canDelete([]))
    }

    func testLatestFiledMonthIgnoresSkippedMonths() {
        XCTAssertEqual(
            ExpenseRecurring.latestFiledPeriod([
                line(period: "2026-08-01"),
                line(period: "2026-10-01", deleted: true),
                line(period: "2026-09-01"),
            ]),
            "2026-09-01"
        )
        XCTAssertNil(ExpenseRecurring.latestFiledPeriod([line(deleted: true)]))
        XCTAssertNil(ExpenseRecurring.latestFiledPeriod([]))
    }

    func testEndMonthsRunFromTheLatestFiledMonthToAYearOut() {
        XCTAssertEqual(
            ExpenseRecurring.endMonthOptions(firstPeriod: "2026-08-01", latestFiled: "2026-09-01", currentMonth: "2026-09-01"),
            ExpenseRecurring.monthsBetween("2026-09-01", "2027-09-01")
        )
        XCTAssertEqual(
            ExpenseRecurring.endMonthOptions(firstPeriod: "2026-11-01", latestFiled: nil, currentMonth: "2026-09-01"),
            ExpenseRecurring.monthsBetween("2026-11-01", "2027-09-01")
        )
    }

    func testTheEndPickerOpensOnThisMonthUnlessALaterMonthIsFiled() {
        let options = ExpenseRecurring.monthsBetween("2026-09-01", "2027-09-01")
        XCTAssertEqual(ExpenseRecurring.defaultEndMonth(options: options, currentMonth: "2026-09-01"), "2026-09-01")
        let later = ExpenseRecurring.monthsBetween("2026-11-01", "2027-09-01")
        XCTAssertEqual(ExpenseRecurring.defaultEndMonth(options: later, currentMonth: "2026-09-01"), "2026-11-01")
    }

    func testRunningMeansStartedAndNotEnded() {
        let setup = ExpenseRecurringReimbursementDTO(
            id: "s", companyId: "co-1", userId: "rivera", name: "Phone plan", amount: 275,
            currency: "CAD", firstPeriod: "2026-08-01", nextPeriod: "2026-10-01",
            createdBy: "okafor", updatedBy: "okafor",
            createdAt: "2026-09-17T02:44:17.100221+00:00", updatedAt: "2026-09-17T02:44:17.100221+00:00"
        )
        XCTAssertFalse(ExpenseRecurring.isRunning(setup, in: "2026-07-01"))
        XCTAssertTrue(ExpenseRecurring.isRunning(setup, in: "2026-09-01"))

        let ended = ExpenseRecurringReimbursementDTO(
            id: "s", companyId: "co-1", userId: "rivera", name: "Phone plan", amount: 275,
            currency: "CAD", firstPeriod: "2026-08-01", lastPeriod: "2026-09-01", nextPeriod: "2026-10-01",
            createdBy: "okafor", updatedBy: "okafor",
            createdAt: "2026-09-17T02:44:17.100221+00:00", updatedAt: "2026-09-17T02:44:17.100221+00:00"
        )
        XCTAssertTrue(ExpenseRecurring.isRunning(ended, in: "2026-09-01"))
        XCTAssertFalse(ExpenseRecurring.isRunning(ended, in: "2026-10-01"))
    }

    // MARK: - Server refusals

    func testEveryServerMessageMapsToItsRefusal() {
        let cases: [(String?, ExpenseRecurring.Refusal)] = [
            ("This person already has a recurring reimbursement with that name.", .duplicate),
            ("This recurring reimbursement changed. Reload and try again.", .changed),
            ("Your access changed. Reload and try again.", .changed),
            ("Expenses are being updated. Try again.", .busy),
            ("You do not have permission to manage recurring reimbursements.", .permission),
            ("You do not have permission to approve expenses.", .permission),
            ("Only an admin can set up a recurring reimbursement for themselves.", .selfGrant),
            ("That month has already been paid.", .paid),
            ("A month has already been paid. End it instead.", .paid),
            ("Sep 2026 is already on a batch. Skip that month first, or end after it.", .endBefore),
            ("This recurring reimbursement is no longer available.", .removed),
            ("This recurring reimbursement was removed.", .removed),
            ("Name it in 80 characters or fewer.", .name),
            ("Enter an amount from 0.01 to 10,000.00.", .amount),
            ("Start within 12 months of this month.", .start),
            ("That category is unavailable.", .category),
            ("That person is not an active member of your company.", .person),
            ("End on or after the first month, or delete it instead.", .endBeforeStart),
            ("That month is after this reimbursement ends.", .afterEnd),
            ("network down", .failed),
            (nil, .failed),
        ]
        for (message, expected) in cases {
            XCTAssertEqual(ExpenseRecurring.refusal(forMessage: message), expected, message ?? "nil")
        }
    }

    func testTransportFailuresReadAsOffline() {
        XCTAssertEqual(RecurringReimbursementViewModel.refusal(for: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(RecurringReimbursementViewModel.refusal(for: URLError(.timedOut)), .offline)
        XCTAssertEqual(RecurringReimbursementViewModel.refusal(for: URLError(.badServerResponse)), .failed)
    }

    func testEveryRecurringToastFollowsTheVoiceContract() {
        var toasts = ExpenseRecurring.Refusal.allCases.map(Feedback.Recurring.refused)
        toasts += [
            Feedback.Recurring.updated, Feedback.Recurring.resumed, Feedback.Recurring.deleted,
            Feedback.Recurring.loadFailed,
            Feedback.Recurring.added(amount: BooksFormat.exact(275, code: "CAD")),
            Feedback.Recurring.ended(month: ExpenseRecurring.formatMonth("2026-12-01")),
            Feedback.Recurring.skipped(month: ExpenseRecurring.formatMonth("2026-08-01"), expenseId: "e-aug", undo: {}),
            Feedback.Recurring.restored(month: ExpenseRecurring.formatMonth("2026-08-01"), expenseId: "e-aug"),
        ]
        for toast in toasts {
            XCTAssertTrue(toast.label.hasPrefix("// "), toast.label)
            let body = toast.label.replacingOccurrences(of: "//", with: "").trimmingCharacters(in: .whitespaces)
            XCTAssertEqual(body, body.uppercased(), toast.label)
        }
        XCTAssertEqual(Feedback.Recurring.added(amount: "CA$275.00").label, "// RECURRING ADDED · CA$275.00 / MO")
        XCTAssertEqual(Feedback.Recurring.skipped(month: "AUG 2026", expenseId: "e-aug", undo: {}).action?.label, "UNDO")
    }

    func testSkippingTwoLinesForTheSameMonthKeepsBothUndos() {
        let vehicle = Feedback.Recurring.skipped(month: "AUG 2026", expenseId: "e-vehicle", undo: {})
        let phone = Feedback.Recurring.skipped(month: "AUG 2026", expenseId: "e-phone", undo: {})
        XCTAssertEqual(vehicle.label, phone.label)
        XCTAssertNotEqual(vehicle.coalescingKey, phone.coalescingKey)
    }
}
