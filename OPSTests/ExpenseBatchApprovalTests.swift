import XCTest
@testable import OPS

/// The fake stops only external I/O; the real view model owns operation state,
/// duplicate protection, canonical cache replacement, and success/failure.
@MainActor
final class ExpenseBatchApprovalTests: XCTestCase {
    private enum Failure: Error { case offline }

    private final class Repository: ExpenseBatchApprovalRepository {
        var approvalCalls: [String] = []
        var batchReads: [String] = []
        var lineReads: [String] = []
        var syncCalls: [String] = []
        var approvalFailure: String?
        var batchReadFails = false
        var lineReadFails = false
        var approvedRows: [String: ExpenseBatchDTO] = [:]
        var lines: [String: [ExpenseDTO]] = [:]
        var approvalGate: CheckedContinuation<Void, Never>?
        var syncGate: CheckedContinuation<Void, Never>?
        var pauseApproval = false
        var pauseSync = false
        var approvalStarted: (() -> Void)?
        var syncStarted: (() -> Void)?

        func approveBatchAtomic(_ id: String) async throws {
            approvalCalls.append(id)
            if pauseApproval {
                await withCheckedContinuation { continuation in
                    approvalGate = continuation
                    approvalStarted?()
                }
            }
            if approvalFailure == id { throw Failure.offline }
        }

        func fetchBatch(_ id: String) async throws -> ExpenseBatchDTO {
            batchReads.append(id)
            if batchReadFails { throw Failure.offline }
            return try XCTUnwrap(approvedRows[id])
        }

        func fetchBatchExpenses(_ id: String) async throws -> [ExpenseDTO] {
            lineReads.append(id)
            if lineReadFails { throw Failure.offline }
            return lines[id] ?? []
        }

        func triggerAccountingSync(expenseId: String) async {
            syncCalls.append(expenseId)
            if pauseSync {
                await withCheckedContinuation { continuation in
                    syncGate = continuation
                    syncStarted?()
                }
            }
        }
    }

    func testPendingApprovalLocksDuplicateAndReopenedDetailBeforeServerResponse() async throws {
        let (model, repo, batch) = try fixture()
        repo.pauseApproval = true
        let started = expectation(description: "approval request started")
        repo.approvalStarted = { started.fulfill() }
        let operation = Task { await model.approveBatch(batch) }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(model.isApprovingBatches)
        XCTAssertFalse(model.hasSavedCurrentApproval)
        XCTAssertFalse(model.canApproveBatch(batch))
        XCTAssertEqual(model.reviewBatches.first?.status, "pending_review")
        XCTAssertTrue(model.confirmedApprovedBatchIds.isEmpty)

        // A reopened detail shares this model; even its original batch DTO
        // must not dispatch a second financial request.
        let duplicate = await model.approveBatch(batch)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(repo.approvalCalls, [batch.id])
        // Popping the entire console and reopening it creates a new model.
        let (reopened, reopenedRepo, reopenedBatch) = try fixture()
        let reopenedSaved = await reopened.approveBatch(reopenedBatch)
        XCTAssertFalse(reopenedSaved)
        XCTAssertTrue(reopenedRepo.approvalCalls.isEmpty)
        repo.approvalGate?.resume()
        let saved = await operation.value
        XCTAssertTrue(saved)
        XCTAssertFalse(model.isApprovingBatches)
    }

    func testAccountingRemainsSerialAndAwaitedWhileCanonicalApprovalIsVisible() async throws {
        let (model, repo, batch) = try fixture()
        repo.lines[batch.id] = [try line("one", batch: batch.id), try line("two", batch: batch.id)]
        repo.pauseSync = true
        let firstSync = expectation(description: "first accounting call started")
        let secondSync = expectation(description: "second accounting call started")
        repo.syncStarted = { [weak repo] in
            if repo?.syncCalls.count == 1 { firstSync.fulfill() }
            else { secondSync.fulfill() }
        }
        var completed = false
        let operation = Task {
            let result = await model.approveBatch(batch)
            completed = true
            return result
        }
        await fulfillment(of: [firstSync], timeout: 1)
        XCTAssertTrue(model.isApprovingBatches)
        XCTAssertTrue(model.hasSavedCurrentApproval)
        XCTAssertFalse(completed)
        XCTAssertEqual(model.reviewBatches.first?.status, "approved")
        XCTAssertEqual(repo.syncCalls, ["one"])
        XCTAssertEqual(repo.batchReads, [batch.id])
        XCTAssertEqual(repo.lineReads, [batch.id])
        repo.syncGate?.resume()
        await fulfillment(of: [secondSync], timeout: 1)
        XCTAssertFalse(completed)
        XCTAssertEqual(repo.syncCalls, ["one", "two"])
        repo.syncGate?.resume()
        let saved = await operation.value
        XCTAssertTrue(saved)
        XCTAssertFalse(model.isApprovingBatches)
        XCTAssertFalse(model.canApproveBatch(batch))
    }

    func testFailedApprovalKeepsReviewStateAndAllowsExplicitRetry() async throws {
        let (model, repo, batch) = try fixture()
        repo.approvalFailure = batch.id
        let saved = await model.approveBatch(batch)
        XCTAssertFalse(saved, "The detail must stay open when the write failed")
        XCTAssertFalse(model.isApprovingBatches)
        XCTAssertEqual(model.reviewBatches.first?.status, "pending_review")
        XCTAssertTrue(model.canApproveBatch(batch))
        XCTAssertNotNil(model.error)
        XCTAssertTrue(repo.batchReads.isEmpty)
        XCTAssertTrue(repo.syncCalls.isEmpty)
        repo.approvalFailure = nil
        let retrySaved = await model.approveBatch(batch)
        XCTAssertTrue(retrySaved)
    }

    func testReadbackFailureCannotTurnSavedApprovalIntoFailureOrAllowResubmission() async throws {
        let (model, repo, batch) = try fixture()
        repo.batchReadFails = true
        repo.lines[batch.id] = [try line("one", batch: batch.id)]
        let saved = await model.approveBatch(batch)
        XCTAssertTrue(saved)
        XCTAssertTrue(model.approvalRefreshRequired)
        XCTAssertNil(model.error, "Do not tell the operator the financial save failed")
        XCTAssertFalse(model.canApproveBatch(batch))
        XCTAssertEqual(repo.syncCalls, ["one"], "A failed batch read must not skip known approved lines")
        let duplicate = await model.approveBatch(batch)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(repo.approvalCalls.count, 1)
    }

    func testLineReadFailureRetainsApprovalReceiptAndCanonicalBatch() async throws {
        let (model, repo, batch) = try fixture()
        repo.lineReadFails = true
        let saved = await model.approveBatch(batch)
        XCTAssertTrue(saved)
        XCTAssertTrue(model.approvalRefreshRequired)
        XCTAssertEqual(model.reviewBatches.first?.status, "approved")
        XCTAssertFalse(model.canApproveBatch(batch))
        XCTAssertTrue(repo.syncCalls.isEmpty, "Do not guess which lines the server approved")
    }

    func testNarrowReadbackReplacesOnlyAffectedBatchAndLines() async throws {
        let (model, repo, batch) = try fixture()
        let other = try makeBatch("other", status: "pending_review")
        model.reviewBatches.append(other)
        model.expenses = [try line("one", batch: batch.id, status: "submitted"), try line("unrelated", batch: other.id)]
        repo.lines[batch.id] = [try line("one", batch: batch.id), try line("new", batch: batch.id, status: "rejected")]
        let saved = await model.approveBatch(batch)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.reviewBatches.map(\.status), ["approved", "pending_review"])
        XCTAssertEqual(Set(model.expenses.map(\.id)), ["one", "new", "unrelated"])
        XCTAssertEqual(model.expenses.first(where: { $0.id == "one" })?.status, "approved")
        XCTAssertEqual(repo.syncCalls, ["one"], "Rejected lines never go to accounting")
    }

    func testBulkDeduplicatesAndStopsAtFirstFailedWrite() async throws {
        let (model, repo, batch) = try fixture()
        let second = try makeBatch("second", status: "pending_review")
        let third = try makeBatch("third", status: "pending_review")
        model.reviewBatches += [second, third]
        repo.approvalFailure = second.id
        let count = await model.approveBatches([batch, batch, second, third])
        XCTAssertEqual(count, 1)
        XCTAssertEqual(repo.approvalCalls, [batch.id, second.id])
        XCTAssertFalse(model.canApproveBatch(batch))
        XCTAssertTrue(model.canApproveBatch(second))
        XCTAssertTrue(model.canApproveBatch(third))
    }

    func testBulkRunRejectsOverlapAndKeepsProgressAcrossBatches() async throws {
        let (model, repo, first) = try fixture()
        let second = try makeBatch("second", status: "pending_review")
        model.reviewBatches.append(second)
        repo.approvedRows[second.id] = try makeBatch(second.id, status: "approved")
        repo.pauseApproval = true
        let firstStarted = expectation(description: "first batch started")
        let secondStarted = expectation(description: "second batch started")
        repo.approvalStarted = { [weak repo] in
            if repo?.approvalCalls.count == 1 { firstStarted.fulfill() }
            else { secondStarted.fulfill() }
        }
        let operation = Task { await model.approveBatches([first, second]) }
        await fulfillment(of: [firstStarted], timeout: 1)
        XCTAssertEqual(model.approvalBatchNumber, 1)
        XCTAssertEqual(model.approvalBatchCount, 2)
        let overlappingBulk = await model.approveBatches([first, second])
        let overlappingSingle = await model.approveBatch(second)
        XCTAssertEqual(overlappingBulk, 0)
        XCTAssertFalse(overlappingSingle)
        repo.approvalGate?.resume()
        await fulfillment(of: [secondStarted], timeout: 1)
        XCTAssertTrue(model.isApprovingBatches)
        XCTAssertEqual(model.approvalBatchNumber, 2)
        XCTAssertFalse(model.hasSavedCurrentApproval)
        XCTAssertEqual(model.reviewBatches.first?.status, "approved")
        repo.approvalGate?.resume()
        let count = await operation.value
        XCTAssertEqual(count, 2)
        XCTAssertFalse(model.isApprovingBatches)
        XCTAssertEqual(repo.approvalCalls, [first.id, second.id])
    }

    func testBulkExcludesFlaggedLinesAddedAfterConfirmationSelection() async throws {
        let (model, repo, batch) = try fixture()
        let flagged: ExpenseDTO = try decode([
            "id": "flagged", "company_id": "company", "submitted_by": "submitter",
            "status": "submitted", "batch_id": batch.id, "amount": 100,
            "flagged_by": "reviewer", "created_at": "2026-09-01T12:00:00Z",
            "updated_at": "2026-09-10T12:00:00Z"
        ])
        model.expenses = [flagged]
        let count = await model.approveBatches([batch])
        XCTAssertEqual(count, 0)
        XCTAssertTrue(repo.approvalCalls.isEmpty)
        XCTAssertEqual(model.reviewBatches.first?.status, "pending_review")
    }

    private func fixture() throws -> (ExpenseViewModel, Repository, ExpenseBatchDTO) {
        let model = ExpenseViewModel()
        let repository = Repository()
        model.batchApprovalRepository = repository
        let batch = try makeBatch("batch", status: "pending_review")
        model.reviewBatches = [batch]
        repository.approvedRows[batch.id] = try makeBatch(batch.id, status: "approved")
        return (model, repository, batch)
    }

    private func makeBatch(_ id: String, status: String) throws -> ExpenseBatchDTO {
        try decode(["id": id, "company_id": "company", "batch_number": "EXP-1", "status": status,
                    "total_amount": 200, "created_at": "2026-09-01T12:00:00Z"])
    }

    private func line(_ id: String, batch: String, status: String = "approved") throws -> ExpenseDTO {
        try decode(["id": id, "company_id": "company", "submitted_by": "submitter", "status": status,
                    "batch_id": batch, "amount": 100, "created_at": "2026-09-01T12:00:00Z",
                    "updated_at": "2026-09-10T12:00:00Z"])
    }

    private func decode<T: Decodable>(_ values: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: values))
    }
}
