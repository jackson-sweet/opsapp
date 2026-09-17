//
//  RecurringReimbursementViewModelTests.swift
//  OPSTests
//
//  The fake stops only the network; the real view model owns the snapshot,
//  one-command-at-a-time, the toast for every outcome, the settle-on-refusal
//  reload, the expense broadcast, and skip's UNDO.
//

import XCTest
import Supabase
@testable import OPS

@MainActor
final class RecurringReimbursementViewModelTests: XCTestCase {

    private enum Refused: Error { case offline }

    private final class Repository: RecurringReimbursementRepository {
        var snapshot = RecurringReimbursementsSnapshot(setups: [], currency: "CAD", timeZone: "America/Vancouver")
        var snapshotReads = 0
        var failRead = false
        var reply: ExpenseRecurringReimbursementDTO?
        var failure: Error?
        var created: [CreateRecurringReimbursementParams] = []
        var updated: [UpdateRecurringReimbursementParams] = []
        var ended: [EndRecurringReimbursementParams] = []
        var deleted: [DeleteRecurringReimbursementParams] = []
        var skipped: [String] = []
        var restored: [String] = []
        var gate: CheckedContinuation<Void, Never>?
        var pause = false

        func fetchSnapshot() async throws -> RecurringReimbursementsSnapshot {
            snapshotReads += 1
            if failRead { throw Refused.offline }
            return snapshot
        }

        private func answer() async throws -> ExpenseRecurringReimbursementDTO {
            if pause { await withCheckedContinuation { gate = $0 } }
            if let failure { throw failure }
            return try XCTUnwrap(reply)
        }

        func create(_ params: CreateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
            created.append(params)
            return try await answer()
        }

        func update(_ params: UpdateRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
            updated.append(params)
            return try await answer()
        }

        func end(_ params: EndRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
            ended.append(params)
            return try await answer()
        }

        func delete(_ params: DeleteRecurringReimbursementParams) async throws -> ExpenseRecurringReimbursementDTO {
            deleted.append(params)
            return try await answer()
        }

        func skipLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO {
            skipped.append(expenseId)
            return try await answer()
        }

        func restoreLine(expenseId: String) async throws -> ExpenseRecurringReimbursementDTO {
            restored.append(expenseId)
            return try await answer()
        }
    }

    private var repository: Repository!
    private var toasts: [Toast] = []
    private var viewModel: RecurringReimbursementViewModel!

    override func setUp() async throws {
        repository = Repository()
        toasts = []
        let repo = repository!
        viewModel = RecurringReimbursementViewModel(
            makeRepository: { _ in repo },
            toasts: { [weak self] in self?.toasts.append($0) }
        )
        viewModel.setup(companyId: "co-1")
    }

    private func setup(
        id: String = "setup-1",
        amount: Double = 275,
        lastPeriod: String? = nil,
        updatedAt: String = "2026-09-17T02:44:17.100221+00:00",
        deletedAt: String? = nil
    ) -> ExpenseRecurringReimbursementDTO {
        ExpenseRecurringReimbursementDTO(
            id: id, companyId: "co-1", userId: "rivera", name: "Phone plan", amount: amount,
            currency: "CAD", firstPeriod: "2026-08-01", lastPeriod: lastPeriod, nextPeriod: "2026-10-01",
            createdBy: "okafor", updatedBy: "okafor", createdAt: "2026-09-17T02:44:17.100221+00:00",
            updatedAt: updatedAt, deletedAt: deletedAt, deletedBy: deletedAt == nil ? nil : "okafor",
            lines: [RecurringLineSummary(expenseId: "e-aug", period: "2026-08-01", batchId: "b-6", status: "approved", amount: amount, deleted: false)]
        )
    }

    private func recurringLine() -> ExpenseDTO {
        ExpenseDTO(
            id: "e-aug", companyId: "co-1", submittedBy: "rivera", status: "approved", categoryId: nil,
            merchantName: "Phone plan", description: "Monthly · August 2026", amount: 275,
            taxAmount: nil, currency: "CAD", expenseDate: "2026-08-01", paymentMethod: nil,
            receiptImageUrl: nil, receiptThumbnailUrl: nil, receiptMissingReason: "other",
            receiptMissingNote: "Recurring reimbursement. No receipt needed.", projectMissingReason: nil,
            projectMissingNote: nil, ocrRawData: nil, ocrConfidence: nil, batchId: "b-6",
            approvedBy: "okafor", approvedAt: "2026-09-17T02:40:00+00:00", rejectedBy: nil, rejectedAt: nil,
            rejectionReason: nil, flagComment: nil, flaggedBy: nil, flaggedAt: nil, accountingSyncStatus: nil,
            accountingSyncId: nil, accountingSyncedAt: nil, createdAt: "2026-09-17T02:40:00+00:00",
            updatedAt: "2026-09-17T02:40:00+00:00", deletedAt: nil, allocations: nil, category: nil,
            recurringReimbursementId: "setup-1", recurringPeriod: "2026-08-01"
        )
    }

    // MARK: - Reads

    func testLoadPublishesTheCompanyCalendarAndSetups() async {
        repository.snapshot.setups = [setup()]
        await viewModel.load()
        XCTAssertEqual(viewModel.setups.map(\.id), ["setup-1"])
        XCTAssertEqual(viewModel.currency, "CAD")
        XCTAssertEqual(viewModel.setup(for: recurringLine())?.id, "setup-1")
        XCTAssertFalse(viewModel.loadFailed)
    }

    func testAFailedReadIsReported() async {
        repository.failRead = true
        await viewModel.load()
        XCTAssertNil(viewModel.snapshot)
        XCTAssertTrue(viewModel.loadFailed)
    }

    // MARK: - Commands

    func testCreateSendsTheCommandMergesTheAnswerAndSaysSo() async {
        await viewModel.load()
        repository.reply = setup()
        let expensesChanged = expectation(forNotification: .opsExpensesDidChange, object: nil)

        let outcome = await viewModel.create(userId: "rivera", name: "Phone plan", amount: 275, firstPeriod: "2026-08-01")

        await fulfillment(of: [expensesChanged], timeout: 1)
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(repository.created, [CreateRecurringReimbursementParams(
            userId: "rivera", name: "Phone plan", amount: 275, firstPeriod: "2026-08-01", categoryId: nil
        )])
        XCTAssertEqual(viewModel.setups.map(\.id), ["setup-1"])
        XCTAssertEqual(toasts.map(\.label), ["// RECURRING ADDED · CA$275.00 / MO"])
        XCTAssertNil(viewModel.inFlight)
    }

    func testUpdateCarriesTheTokenTheFormOpenedWith() async {
        let opened = setup()
        repository.snapshot.setups = [opened]
        await viewModel.load()
        repository.reply = setup(amount: 375, updatedAt: "2026-09-18T00:00:00.000001+00:00")

        let outcome = await viewModel.update(opened, name: "Phone plan", amount: 375)

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(repository.updated.first?.expectedUpdatedAt, "2026-09-17T02:44:17.100221+00:00")
        XCTAssertEqual(viewModel.setups.first?.amount, 375)
        XCTAssertEqual(toasts.map(\.label), ["// RECURRING UPDATED"])
    }

    func testARefusalIsToldAndTheListSettlesOnTheCurrentTruth() async {
        let opened = setup()
        repository.snapshot.setups = [opened]
        await viewModel.load()
        let readsBefore = repository.snapshotReads
        repository.failure = PostgrestError(code: "P0001", message: "This recurring reimbursement changed. Reload and try again.")

        let outcome = await viewModel.update(opened, name: "Phone plan", amount: 400)

        XCTAssertEqual(outcome, .refused(.changed))
        XCTAssertTrue(outcome.invalidatesForm)
        XCTAssertEqual(toasts.map(\.label), ["// CHANGED ELSEWHERE · OPEN IT AGAIN"])
        XCTAssertEqual(repository.snapshotReads, readsBefore + 1)
    }

    func testOfflineIsAWarningThatKeepsTheForm() async {
        await viewModel.load()
        repository.failure = URLError(.notConnectedToInternet)

        let outcome = await viewModel.end(setup(), lastPeriod: "2026-12-01")

        XCTAssertEqual(outcome, .refused(.offline))
        XCTAssertFalse(outcome.invalidatesForm)
        XCTAssertEqual(toasts.map(\.tone), [.warning])
    }

    func testEndAndRemoveEndSayWhatHappened() async {
        await viewModel.load()
        repository.reply = setup(lastPeriod: "2026-12-01")
        _ = await viewModel.end(setup(), lastPeriod: "2026-12-01")
        repository.reply = setup()
        _ = await viewModel.end(setup(lastPeriod: "2026-12-01"), lastPeriod: nil)

        XCTAssertEqual(repository.ended.map(\.lastPeriod), ["2026-12-01", nil])
        XCTAssertEqual(toasts.map(\.label), ["// ENDS AFTER DEC 2026", "// END REMOVED · RUNS MONTHLY"])
    }

    func testADeletedSetupLeavesTheList() async {
        repository.snapshot.setups = [setup()]
        await viewModel.load()
        repository.reply = setup(deletedAt: "2026-09-18T00:00:00+00:00")

        let outcome = await viewModel.delete(setup())

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(viewModel.setups, [])
        XCTAssertEqual(toasts.map(\.label), ["// RECURRING DELETED"])
    }

    func testOnlyOneCommandRunsAtATime() async {
        await viewModel.load()
        repository.reply = setup()
        repository.pause = true

        let first = Task { await self.viewModel.create(userId: "rivera", name: "A", amount: 1, firstPeriod: "2026-09-01") }
        while repository.gate == nil { await Task.yield() }
        XCTAssertEqual(viewModel.inFlight, .create)

        let second = await viewModel.update(setup(), name: "B", amount: 2)
        XCTAssertEqual(second, .ignored)
        XCTAssertEqual(repository.updated.count, 0)

        repository.gate?.resume()
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .done)
        XCTAssertNil(viewModel.inFlight)
    }

    // MARK: - Skip / UNDO

    func testSkipOffersUndoThatRestoresTheMonth() async throws {
        repository.snapshot.setups = [setup()]
        await viewModel.load()
        repository.reply = setup()
        var changes = 0

        let outcome = await viewModel.skip(recurringLine()) { changes += 1 }

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(repository.skipped, ["e-aug"])
        XCTAssertEqual(changes, 1)
        let toast = try XCTUnwrap(toasts.first)
        XCTAssertEqual(toast.label, "// AUG 2026 SKIPPED")
        let undo = try XCTUnwrap(toast.action)
        XCTAssertEqual(undo.label, "UNDO")

        undo.handler()
        while repository.restored.isEmpty || changes < 2 { await Task.yield() }

        XCTAssertEqual(repository.restored, ["e-aug"])
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(toasts.last?.label, "// AUG 2026 RESTORED")
    }

    func testAStaleReadNeverOverwritesACommandsAnswer() async {
        repository.snapshot.setups = [setup(amount: 275)]
        await viewModel.load()
        // A command lands while the list still holds the old amount; its answer wins.
        repository.reply = setup(amount: 400)
        _ = await viewModel.update(setup(), name: "Phone plan", amount: 400)
        XCTAssertEqual(viewModel.setups.first?.amount, 400)
    }
}
