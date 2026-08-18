//
//  ExpenseDecisionNotificationTests.swift
//  OPSTests
//
//  The submitter's expense-decision rail row must cross the narrow server RPC
//  (`notify_expense_batch_decision`), never a direct `notifications` insert —
//  the 2026-07-15 notification-creation hardening revoked app-role INSERT, so
//  the legacy client-side insert 42501'd on every approve / send-back / payout
//  and the crew member's rail went silently dead while their push still landed.
//
//  What these tests pin:
//    1. Each decision maps to exactly the vocabulary the server validates —
//       `approved` / `sent_back` / `paid` — carrying the batch ID, not the
//       batch number: copy, recipient, and deep link are server-rendered now.
//    2. The sent-back line count is the ONLY payload the client still supplies,
//       and only for `sent_back`.
//    3. Every self / missing-submitter / missing-company guard still short
//       circuits before the RPC — an approver must not notify themselves, and
//       a batch with no submitter has nobody to notify.
//    4. A transport failure stays contained: the decision itself is already
//       persisted, so the rail's failure must never surface to the approver.
//

import XCTest
@testable import OPS

@MainActor
final class ExpenseDecisionNotificationTests: XCTestCase {

    // MARK: - Spy

    /// Records every (batchId, decision, count) the view model reports. One
    /// decision dispatches one call, so plain storage is race-free.
    private final class ExpenseDecisionSpy: ExpenseDecisionNotifying {
        struct Call: Equatable {
            let batchId: String
            let decision: String
            let count: Int?
        }

        private(set) var calls: [Call] = []
        var shouldFail = false

        func notifyExpenseBatchDecision(batchId: String, decision: String, count: Int?) async throws -> String {
            calls.append(Call(batchId: batchId, decision: decision, count: count))
            if shouldFail {
                throw URLError(.notConnectedToInternet)
            }
            return "created"
        }
    }

    // MARK: - Identities

    private enum ID {
        /// The office user taking the decision — the view model's stored operator.
        static let approver  = "user-approver-1"
        /// The crew member who submitted the envelope — the notification's target.
        static let submitter = "user-submitter-1"
        static let company   = "co-expenses"
        /// Deliberately unlike `number`: the RPC takes the ID and derives its
        /// own copy, so a regression that forwards the human-facing batch
        /// number instead fails every mapping assertion below.
        static let batch     = "batch-7f3"
        static let number    = "EXP-2026-07"
    }

    // MARK: - Push-lane bookkeeping

    /// `notifySubmitter` dispatches two lanes in one task: the rail RPC (under
    /// test) and the OneSignal push (untouched by this rewire). The push lane
    /// early-returns when its recipient is the device's own user, which it
    /// reads from the `UserDefaults` "currentUserId" key — pointing that key at
    /// the SUBMITTER makes the push lane inert, so awaiting the task never
    /// reaches Firebase or the network. The view model's own self-guard reads
    /// its separately stored operator, so the rail lane still runs.
    private var savedCurrentUserId: String?

    override func setUp() {
        super.setUp()
        savedCurrentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        UserDefaults.standard.set(ID.submitter, forKey: "currentUserId")
    }

    override func tearDown() {
        if let savedCurrentUserId {
            UserDefaults.standard.set(savedCurrentUserId, forKey: "currentUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUserId")
        }
        super.tearDown()
    }

    // MARK: - 1. Approved

    func test_approvedReportsApprovedDecisionWithNoCount() async {
        let (viewModel, spy) = makeViewModel()

        let dispatch = viewModel.notifySubmitter(of: makeBatch(), notice: .approved)
        await dispatch?.value

        XCTAssertNotNil(dispatch, "An approval on somebody else's envelope must dispatch")
        XCTAssertEqual(
            spy.calls,
            [.init(batchId: ID.batch, decision: "approved", count: nil)],
            "An approval reports the batch ID and the `approved` decision — the server renders the copy"
        )
    }

    // MARK: - 2. Sent back

    func test_sentBackReportsSentBackDecisionWithFlaggedCount() async {
        let (viewModel, spy) = makeViewModel()

        let dispatch = viewModel.notifySubmitter(of: makeBatch(), notice: .sentBack(count: 3))
        await dispatch?.value

        XCTAssertEqual(
            spy.calls,
            [.init(batchId: ID.batch, decision: "sent_back", count: 3)],
            "The flagged line count is the only payload the client still supplies"
        )
    }

    // MARK: - 3. Paid

    func test_paidReportsPaidDecisionWithNoCount() async {
        let (viewModel, spy) = makeViewModel()

        let dispatch = viewModel.notifySubmitter(of: makeBatch(), notice: .paid)
        await dispatch?.value

        XCTAssertEqual(
            spy.calls,
            [.init(batchId: ID.batch, decision: "paid", count: nil)],
            "A payout reports `paid` with no count — the count is a send-back concept only"
        )
    }

    // MARK: - 4. Self-decision short circuits

    func test_decidingOnYourOwnBatchReportsNothing() async {
        let (viewModel, spy) = makeViewModel(currentUserId: ID.submitter)

        let dispatch = viewModel.notifySubmitter(of: makeBatch(), notice: .approved)
        await dispatch?.value

        XCTAssertNil(dispatch, "Approving your own envelope dispatches nothing — the toast is the feedback")
        XCTAssertTrue(spy.calls.isEmpty, "No self-notification may reach the server")
    }

    // MARK: - 5. Missing submitter short circuits

    func test_batchWithoutSubmitterReportsNothing() async {
        let (viewModel, spy) = makeViewModel()

        let dispatch = viewModel.notifySubmitter(of: makeBatch(submittedBy: nil), notice: .approved)
        await dispatch?.value

        XCTAssertNil(dispatch, "A batch with no submitter has nobody to notify")
        XCTAssertTrue(spy.calls.isEmpty, "No recipient -> nothing reported")
    }

    func test_batchWithEmptySubmitterReportsNothing() async {
        let (viewModel, spy) = makeViewModel()

        let dispatch = viewModel.notifySubmitter(of: makeBatch(submittedBy: ""), notice: .paid)
        await dispatch?.value

        XCTAssertNil(dispatch, "An empty submitter is as absent as a missing one")
        XCTAssertTrue(spy.calls.isEmpty, "No recipient -> nothing reported")
    }

    // MARK: - 6. Missing company short circuits

    func test_viewModelWithoutCompanyReportsNothing() async {
        // No `setup(companyId:)` — the operator is known, the company is not.
        let viewModel = ExpenseViewModel()
        let spy = ExpenseDecisionSpy()
        viewModel.decisionNotifier = spy
        viewModel.setCurrentUser(id: ID.approver, name: "Dana Reyes")

        let dispatch = viewModel.notifySubmitter(of: makeBatch(), notice: .approved)
        await dispatch?.value

        XCTAssertNil(dispatch, "An unconfigured view model dispatches nothing")
        XCTAssertTrue(spy.calls.isEmpty, "No company context -> nothing reported")
    }

    // MARK: - 7. Transport failure stays contained

    func test_transportFailureIsContained() async {
        let (viewModel, spy) = makeViewModel()
        spy.shouldFail = true

        let dispatch = viewModel.notifySubmitter(of: makeBatch(), notice: .approved)
        await dispatch?.value

        XCTAssertEqual(
            spy.calls,
            [.init(batchId: ID.batch, decision: "approved", count: nil)],
            "The call is still attempted"
        )
        XCTAssertNil(
            viewModel.error,
            "The approval is already persisted — a failed rail row must never surface to the approver"
        )
    }

    // MARK: - Fixtures

    /// A view model with a company and an operator, wired to the spy. Defaults
    /// to the approver deciding on somebody else's envelope.
    private func makeViewModel(currentUserId: String = ID.approver) -> (ExpenseViewModel, ExpenseDecisionSpy) {
        let viewModel = ExpenseViewModel()
        let spy = ExpenseDecisionSpy()
        viewModel.decisionNotifier = spy
        viewModel.setup(
            companyId: ID.company,
            currentUserId: currentUserId,
            currentUserName: "Dana Reyes"
        )
        return (viewModel, spy)
    }

    private func makeBatch(submittedBy: String? = ID.submitter) -> ExpenseBatchDTO {
        ExpenseBatchDTO(
            id: ID.batch,
            companyId: ID.company,
            batchNumber: ID.number,
            periodStart: "2026-07-01",
            periodEnd: "2026-07-31",
            status: ExpenseBatchStatus.submitted.rawValue,
            submittedBy: submittedBy,
            reviewedBy: nil,
            reviewedAt: nil,
            totalAmount: 480,
            approvedAmount: nil,
            parentBatchId: nil,
            amendmentNumber: 0,
            reviewNotes: nil,
            createdAt: "2026-07-01T09:00:00Z",
            scopeProjectId: nil,
            paidAt: nil,
            paidBy: nil
        )
    }
}
