//
//  RecurringLineSurfaceTests.swift
//  OPSTests
//
//  A recurring reimbursement line is office-filed with no receipt by design.
//  Every expense surface must read it as what it is — never as a missing
//  receipt, never as something to correct, flag, or delete — while ordinary
//  receipts keep every existing rule.
//

import XCTest
@testable import OPS

final class RecurringLineSurfaceTests: XCTestCase {

    private func expense(
        id: String = "e-1",
        status: String = "approved",
        hasReceipt: Bool = false,
        recurring: Bool = true,
        submittedBy: String = "rivera",
        approvedBy: String? = "okafor",
        batchId: String? = "b-6"
    ) -> ExpenseDTO {
        ExpenseDTO(
            id: id, companyId: "co-1", submittedBy: submittedBy, status: status, categoryId: nil,
            merchantName: recurring ? "Phone plan" : "Slegg", description: nil, amount: 275,
            taxAmount: nil, currency: "CAD", expenseDate: "2026-08-01", paymentMethod: nil,
            receiptImageUrl: hasReceipt ? "https://files.ops.test/receipt.jpg" : nil,
            receiptThumbnailUrl: nil, receiptMissingReason: recurring ? "other" : nil,
            receiptMissingNote: recurring ? "Recurring reimbursement. No receipt needed." : nil,
            projectMissingReason: nil, projectMissingNote: nil, ocrRawData: nil, ocrConfidence: nil,
            batchId: batchId, approvedBy: approvedBy, approvedAt: approvedBy == nil ? nil : "2026-09-17T02:40:00+00:00",
            rejectedBy: nil, rejectedAt: nil, rejectionReason: nil, flagComment: nil, flaggedBy: nil,
            flaggedAt: nil, accountingSyncStatus: nil, accountingSyncId: nil, accountingSyncedAt: nil,
            createdAt: "2026-09-17T02:40:00+00:00", updatedAt: "2026-09-17T02:40:00+00:00", deletedAt: nil,
            allocations: nil, category: nil,
            recurringReimbursementId: recurring ? "setup-1" : nil,
            recurringPeriod: recurring ? "2026-08-01" : nil
        )
    }

    func testLedgerPillShowsTheLinesStateInsteadOfNoReceipt() {
        XCTAssertEqual(BooksLedgerStatus.expense(expense()).text, "APPROVED")
        XCTAssertEqual(BooksLedgerStatus.expense(expense(status: "reimbursed")).text, "PAID")
    }

    func testAnOrdinaryReceiptlessExpenseStillRaisesNoReceipt() {
        XCTAssertEqual(BooksLedgerStatus.expense(expense(recurring: false)).text, "NO RECEIPT")
        XCTAssertEqual(BooksLedgerStatus.expense(expense(hasReceipt: true, recurring: false)).text, "APPROVED")
    }

    func testTheNoReceiptFilterLeavesRecurringLinesOut() {
        let lines = [expense(id: "vehicle"), expense(id: "slegg", recurring: false), expense(id: "home-depot", hasReceipt: true, recurring: false)]
        XCTAssertEqual(lines.filter(BooksExpenseFilter.noReceipt.matches).map(\.id), ["slegg"])
        XCTAssertEqual(lines.filter(BooksExpenseFilter.all.matches).count, 3)
    }

    func testReviewersCannotCorrectARecurringLine() {
        // Even shaped exactly like a correctable receipt, a recurring line is refused.
        let shaped = expense(status: "submitted", approvedBy: nil, batchId: nil)
        XCTAssertFalse(ExpenseCorrectionPolicy.canCorrect(
            expense: shaped, batch: nil, actorId: "a0000000-0000-0000-0000-000000000001",
            companyId: "co-1", canApproveAll: true, canViewAll: true
        ))
        let receipt = expense(status: "submitted", recurring: false, approvedBy: nil, batchId: nil)
        XCTAssertTrue(ExpenseCorrectionPolicy.canCorrect(
            expense: receipt, batch: nil, actorId: "a0000000-0000-0000-0000-000000000001",
            companyId: "co-1", canApproveAll: true, canViewAll: true
        ))
    }

    func testEligiblePeopleAreActiveCompanyMembersAndOnlyAdminsSeeThemselves() {
        let people: [(String, String, String?, Bool?, Date?)] = [
            ("okafor", "co-1", "Sam", true, nil),
            ("rivera", "co-1", "Priya", true, nil),
            ("casey", "co-1", "Casey", false, nil),
            ("drew", "co-1", "Drew", true, Date()),
            ("elsewhere", "co-2", "Other", true, nil),
        ]
        let users = people.map { id, company, first, active, deleted -> User in
            let user = User(id: id, firstName: first ?? "", lastName: "Crew", role: .crew, companyId: company)
            user.isActive = active
            user.deletedAt = deleted
            return user
        }

        let asManager = RecurringPerson.eligible(users: users, companyId: "co-1", currentUserId: "okafor", currentUserIsAdmin: false)
        XCTAssertEqual(asManager.map(\.id), ["rivera"])

        let asAdmin = RecurringPerson.eligible(users: users, companyId: "CO-1", currentUserId: "okafor", currentUserIsAdmin: true)
        // Sorted by display name: Priya Crew before Sam Crew.
        XCTAssertEqual(asAdmin.map(\.id), ["rivera", "okafor"])
        XCTAssertEqual(asAdmin.first?.name, "Priya Crew")
    }

    func testDisplayNameFallsBackToEmailThenDash() {
        XCTAssertEqual(RecurringPerson.displayName(first: " Priya ", last: "Rivera", email: nil), "Priya Rivera")
        XCTAssertEqual(RecurringPerson.displayName(first: "", last: "", email: "priya@example.test"), "priya@example.test")
        XCTAssertEqual(RecurringPerson.displayName(first: nil, last: nil, email: nil), "—")
    }
}
