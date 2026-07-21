//
//  ReviewAccessPolicyTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class ReviewAccessPolicyTests: XCTestCase {

    func testAssignedProjectEditorCanOnlyCloseAssignedProjects() {
        let policy = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .assigned,
            canViewInvoices: true,
            canSendInvoices: true,
            canEditInvoices: true
        )

        XCTAssertTrue(policy.canClose(projectTeamMemberIDs: ["operator"]))
        XCTAssertFalse(policy.canClose(projectTeamMemberIDs: ["someone-else"]))

        let unsupportedOwnScope = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .own,
            canViewInvoices: true,
            canSendInvoices: true,
            canEditInvoices: true
        )
        XCTAssertFalse(
            unsupportedOwnScope.canClose(projectTeamMemberIDs: ["operator"])
        )
    }

    func testPaymentDirectionsRequireThePermissionAndEligibleInvoiceTheyMutate() {
        let full = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .all,
            canViewInvoices: true,
            canSendInvoices: true,
            canEditInvoices: true
        )
        let financials = PaymentReviewFinancialSummary(
            invoiceCount: 2,
            unresolvedInvoiceCount: 1,
            outstandingInvoiceCount: 1,
            overdueInvoiceCount: 1,
            unresolvedBalance: 425,
            outstandingBalance: 425,
            currencyCode: "CAD"
        )

        XCTAssertEqual(
            full.allowedDirections(
                projectTeamMemberIDs: [],
                financials: financials
            ),
            [.left, .up, .down]
        )

        let noFinancialMutation = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .all,
            canViewInvoices: true,
            canSendInvoices: false,
            canEditInvoices: false
        )
        XCTAssertEqual(
            noFinancialMutation.allowedDirections(
                projectTeamMemberIDs: [],
                financials: financials
            ),
            [.left]
        )
    }

    func testPaymentDirectionsHideReminderAndWriteOffWithoutEligibleBalances() {
        let policy = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .all,
            canViewInvoices: true,
            canSendInvoices: true,
            canEditInvoices: true
        )

        XCTAssertEqual(
            policy.allowedDirections(
                projectTeamMemberIDs: [],
                financials: .empty(currencyCode: "CAD")
            ),
            [.left, .right]
        )
    }

    func testPaymentWriteOffIsHiddenWhenAnUnresolvedDraftWouldRemain() {
        let policy = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .all,
            canViewInvoices: true,
            canSendInvoices: true,
            canEditInvoices: true
        )
        let mixed = PaymentReviewFinancialSummary(
            invoiceCount: 2,
            unresolvedInvoiceCount: 2,
            outstandingInvoiceCount: 1,
            overdueInvoiceCount: 1,
            unresolvedBalance: 700,
            outstandingBalance: 500,
            currencyCode: "CAD"
        )

        XCTAssertEqual(
            policy.allowedDirections(
                projectTeamMemberIDs: [],
                financials: mixed
            ),
            [.left, .up]
        )
    }

    func testPaymentWriteOffIsHiddenForAccountingManagedDebt() {
        let policy = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .all,
            canViewInvoices: true,
            canSendInvoices: true,
            canEditInvoices: true
        )
        let linked = PaymentReviewFinancialSummary(
            invoiceCount: 1,
            unresolvedInvoiceCount: 1,
            outstandingInvoiceCount: 1,
            externallyManagedOutstandingInvoiceCount: 1,
            overdueInvoiceCount: 1,
            unresolvedBalance: 500,
            outstandingBalance: 500,
            currencyCode: "CAD"
        )

        XCTAssertEqual(
            policy.allowedDirections(
                projectTeamMemberIDs: [],
                financials: linked
            ),
            [.left, .up]
        )
    }

    func testPaymentDirectionsFailClosedWhenFinancialStateIsUnknown() {
        let policy = PaymentReviewAccessPolicy(
            currentUserID: "operator",
            projectEditScope: .all,
            canViewInvoices: true,
            canSendInvoices: true,
            canEditInvoices: true
        )

        XCTAssertEqual(
            policy.allowedDirections(
                projectTeamMemberIDs: [],
                financials: nil
            ),
            [.left]
        )
    }

    func testPaymentDueDatesStayCurrentUntilCompanyLocalMidnight() {
        let beforeVancouverMidnight = ISO8601DateFormatter()
            .date(from: "2026-06-02T06:59:59Z")!
        let atVancouverMidnight = ISO8601DateFormatter()
            .date(from: "2026-06-02T07:00:00Z")!
        let vancouver = TimeZone(identifier: "America/Vancouver")!

        XCTAssertFalse(
            PaymentReviewRepository.isOverdue(
                dueDate: "2026-06-01",
                now: beforeVancouverMidnight,
                timeZone: vancouver
            )
        )
        XCTAssertTrue(
            PaymentReviewRepository.isOverdue(
                dueDate: "2026-06-01",
                now: atVancouverMidnight,
                timeZone: vancouver
            )
        )
    }

    func testPaymentCompanySettingsFailClosedForInvalidTimeZone() {
        XCTAssertThrowsError(
            try PaymentReviewRepository.companyTimeZone(identifier: "Not/A-Time-Zone")
        ) { error in
            guard let repositoryError = error as? PaymentReviewRepositoryError,
                  case .companySettingsUnavailable = repositoryError else {
                return XCTFail("Expected companySettingsUnavailable, got \(error)")
            }
        }
    }

    func testPaymentSummaryCarriesCanonicalCompanyCurrency() throws {
        XCTAssertEqual(
            try PaymentReviewRepository.normalizedCurrencyCode(" cad "),
            "CAD"
        )
        XCTAssertEqual(
            PaymentReviewFinancialSummary.empty(currencyCode: "CAD").currencyCode,
            "CAD"
        )
        XCTAssertThrowsError(
            try PaymentReviewRepository.normalizedCurrencyCode(" ")
        )
    }

    func testUnassignedTaskCanStillAssignWithoutCalendarPermission() {
        let policy = UnscheduledReviewAccessPolicy(
            currentUserID: "operator",
            taskEditScope: .assigned,
            canAssignTasks: true,
            taskStatusScope: .assigned,
            calendarEditScope: nil
        )
        let task = UnscheduledReviewTaskState(
            taskTeamMemberIDs: [],
            projectTeamMemberIDs: ["operator"],
            isScheduled: false
        )

        XCTAssertTrue(policy.allows(.right, task: task))
        XCTAssertTrue(policy.allows(.up, task: task))
        XCTAssertTrue(policy.allows(.down, task: task))
        XCTAssertTrue(policy.allows(.left, task: task))
    }

    func testUnassignedTaskCannotAssignCrewWithoutTaskAssignmentPermission() {
        let policy = UnscheduledReviewAccessPolicy(
            currentUserID: "operator",
            taskEditScope: .assigned,
            canAssignTasks: false,
            taskStatusScope: .assigned,
            calendarEditScope: nil
        )
        let task = UnscheduledReviewTaskState(
            taskTeamMemberIDs: [],
            projectTeamMemberIDs: ["operator"],
            isScheduled: false
        )

        XCTAssertFalse(policy.allows(.right, task: task))
        XCTAssertFalse(policy.allows(.up, task: task))
        XCTAssertTrue(policy.allows(.down, task: task))
    }

    func testAssignedTaskSeparatesStatusPermissionFromSchedulePermission() {
        let noCalendar = UnscheduledReviewAccessPolicy(
            currentUserID: "operator",
            taskEditScope: .assigned,
            canAssignTasks: false,
            taskStatusScope: .assigned,
            calendarEditScope: nil
        )
        let assigned = UnscheduledReviewTaskState(
            taskTeamMemberIDs: ["operator"],
            projectTeamMemberIDs: [],
            isScheduled: false
        )

        XCTAssertFalse(noCalendar.allows(.right, task: assigned))
        XCTAssertTrue(noCalendar.allows(.up, task: assigned))

        let ownCalendar = UnscheduledReviewAccessPolicy(
            currentUserID: "operator",
            taskEditScope: .assigned,
            canAssignTasks: false,
            taskStatusScope: .assigned,
            calendarEditScope: .own
        )
        XCTAssertTrue(ownCalendar.allows(.right, task: assigned))

        let someoneElse = UnscheduledReviewTaskState(
            taskTeamMemberIDs: ["someone-else"],
            projectTeamMemberIDs: ["operator"],
            isScheduled: false
        )
        XCTAssertFalse(ownCalendar.allows(.right, task: someoneElse))
        XCTAssertTrue(ownCalendar.allows(.up, task: someoneElse))
    }

    func testFailedOrDeniedMutationNeverCountsAsReviewed() {
        XCTAssertTrue(UnscheduledReviewCompletionPolicy.shouldFinish(.skipped))
        XCTAssertTrue(UnscheduledReviewCompletionPolicy.shouldFinish(.succeeded))
        XCTAssertFalse(UnscheduledReviewCompletionPolicy.shouldFinish(.failed))
        XCTAssertFalse(UnscheduledReviewCompletionPolicy.shouldFinish(.denied))
    }

    func testCrewAssignmentRebasePreservesConcurrentRemoteChanges() {
        let rebased = ReviewCrewAssignmentRebase.rebase(
            baseline: ["crew-a", "crew-b"],
            selected: ["crew-b", "crew-c"],
            current: ["crew-a", "crew-b", "crew-remote"]
        )

        XCTAssertEqual(rebased, ["crew-b", "crew-c", "crew-remote"])
    }

    func testVoiceOverActionsCollapseDuplicateCrewAssignmentLabels() {
        let directions = SwipeAccessibilityActionPolicy.uniqueDirections(
            SwipeDirection.allCases,
            labelForDirection: { direction in
                switch direction {
                case .right, .up: return "ASSIGN CREW"
                case .left: return "SKIP"
                case .down: return "CANCEL"
                }
            }
        )

        XCTAssertEqual(directions, [.right, .left, .down])
    }
}
