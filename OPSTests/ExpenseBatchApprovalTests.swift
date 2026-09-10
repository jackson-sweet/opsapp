import XCTest
@testable import OPS

/// The fake stops only external I/O; the real view model owns operation state,
/// duplicate protection, canonical cache replacement, and success/failure.
@MainActor
final class ExpenseBatchApprovalTests: XCTestCase {
    private enum Failure: Error { case offline }

    private final class Repository: ExpenseBatchApprovalRepository, ExpenseConsoleRepository {
        var consoleBatchReads = 0
        var consoleLineReads = 0
        var consoleSettingsReads = 0
        var consoleLoadFails = false
        var consoleBatches: [ExpenseBatchDTO] = []
        var pauseConsole = false
        var consoleGate: CheckedContinuation<Void, Never>?
        var consoleStarted: (() -> Void)?
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

        func fetchBatches() async throws -> [ExpenseBatchDTO] {
            consoleBatchReads += 1
            let snapshot = consoleBatches
            if pauseConsole {
                await withCheckedContinuation { continuation in
                    consoleGate = continuation
                    consoleStarted?()
                }
            }
            if consoleLoadFails { throw Failure.offline }
            return snapshot
        }

        func fetchAll() async throws -> [ExpenseDTO] {
            consoleLineReads += 1
            return []
        }

        func fetchSettings() async throws -> ExpenseSettingsDTO? {
            consoleSettingsReads += 1
            return nil
        }

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
        let sharedState = ExpenseBatchApprovalState()
        let (model, repo, batch) = try fixture(sharedState: sharedState)
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
        let (reopened, reopenedRepo, reopenedBatch) = try fixture(sharedState: sharedState)
        let reopenedSaved = await reopened.approveBatch(reopenedBatch)
        XCTAssertFalse(reopenedSaved)
        XCTAssertTrue(reopenedRepo.approvalCalls.isEmpty)
        XCTAssertTrue(reopened.approvalInFlightBatchIds.contains(batch.id))
        repo.approvalGate?.resume()
        let saved = await operation.value
        XCTAssertTrue(saved)
        XCTAssertFalse(model.isApprovingBatches)
        XCTAssertEqual(reopened.reviewBatches.first?.status, "pending_review", "Simulate missed realtime")
        XCTAssertTrue(reopened.confirmedApprovedBatchIds.contains(batch.id))
        let afterCompletion = await reopened.approveBatch(reopenedBatch)
        XCTAssertFalse(afterCompletion)
        reopenedRepo.consoleLoadFails = true
        await reopened.loadConsole()
        let afterFailedRefresh = await reopened.approveBatch(reopenedBatch)
        XCTAssertFalse(afterFailedRefresh)
        XCTAssertTrue(reopenedRepo.approvalCalls.isEmpty)
        XCTAssertTrue(reopenedRepo.syncCalls.isEmpty)
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
        let sameIdentity = try makeBatch(batch.id.uppercased(), status: "pending_review")
        let count = await model.approveBatches([batch, batch, sameIdentity, second, third])
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

    func testSharedReceiptPublishesToAnotherOpenConsole() async throws {
        let sharedState = ExpenseBatchApprovalState()
        let (model, _, batch) = try fixture(sharedState: sharedState)
        let (reopened, _, _) = try fixture(sharedState: sharedState)
        var changes = 0
        let observation = reopened.objectWillChange.sink { changes += 1 }
        let saved = await model.approveBatch(batch)
        XCTAssertTrue(saved)
        XCTAssertGreaterThan(changes, 0, "Existing views must redraw when a receipt arrives elsewhere")
        XCTAssertTrue(reopened.confirmedApprovedBatchIds.contains(batch.id))
        withExtendedLifetime(observation) {}
    }

    func testFreshAuthoritativeReviewStateCanRetireAcceptedReceipt() async throws {
        let (model, repo, batch) = try fixture()
        let saved = await model.approveBatch(batch)
        XCTAssertTrue(saved)
        XCTAssertFalse(model.canApproveBatch(batch))
        // A later successful server read is the only authority to reopen it.
        repo.consoleBatches = [batch]
        await model.loadConsole()
        XCTAssertTrue(model.canApproveBatch(batch))
        XCTAssertTrue(model.confirmedApprovedBatchIds.isEmpty)
    }

    func testConsoleReadStartedBeforeAcceptanceCannotRetireReceipt() async throws {
        let state = ExpenseBatchApprovalState()
        let (model, _, batch) = try fixture(sharedState: state)
        let (reopened, repo, _) = try fixture(sharedState: state)
        repo.pauseConsole = true
        repo.consoleBatches = [batch]
        let started = expectation(description: "stale console read started")
        repo.consoleStarted = { started.fulfill() }
        let staleLoad = Task { await reopened.loadConsole() }
        await fulfillment(of: [started], timeout: 1)
        let saved = await model.approveBatch(batch)
        XCTAssertTrue(saved)
        repo.consoleGate?.resume()
        await staleLoad.value
        XCTAssertEqual(reopened.reviewBatches.first?.status, "pending_review")
        XCTAssertFalse(reopened.canApproveBatch(batch))
        XCTAssertTrue(reopened.confirmedApprovedBatchIds.contains(batch.id))
    }

    func testReceiptIsCompanyScopedAndSurvivesSwitchingBack() async throws {
        let sharedState = ExpenseBatchApprovalState()
        let (model, _, batch) = try fixture(sharedState: sharedState)
        let saved = await model.approveBatch(batch)
        XCTAssertTrue(saved)
        let otherBatch = try makeBatch(batch.id, status: "pending_review", companyId: "other-company")
        model.setup(companyId: "other-company")
        model.reviewBatches = [otherBatch]
        XCTAssertTrue(model.confirmedApprovedBatchIds.isEmpty)
        XCTAssertTrue(model.canApproveBatch(otherBatch))
        XCTAssertFalse(model.canApproveBatch(batch), "Stale rows from another company cannot be submitted")
        model.setup(companyId: batch.companyId)
        model.reviewBatches = [batch]
        XCTAssertTrue(model.confirmedApprovedBatchIds.contains(batch.id))
        XCTAssertFalse(model.canApproveBatch(batch))
    }

    func testPrequeuedRealtimeRefreshDefersAllReadsUntilApprovalFinishes() async throws {
        let (model, repo, batch) = try fixture()
        repo.pauseApproval = true
        repo.consoleBatches = [try makeBatch(batch.id, status: "approved")]
        let started = expectation(description: "approval started")
        repo.approvalStarted = { started.fulfill() }
        let refreshed = expectation(description: "one coalesced console reload completed")
        let observation = model.$settingsLoadState.filter { $0 == .loaded }.sink { _ in refreshed.fulfill() }
        // Schedule first, then enter approval before the debounce expires.
        let queued = try XCTUnwrap(model.scheduleRealtimeRefresh())
        let operation = Task { await model.approveBatch(batch) }
        await fulfillment(of: [started], timeout: 1)
        await queued.value
        XCTAssertEqual(repo.consoleBatchReads, 0)
        XCTAssertEqual(repo.consoleLineReads, 0)
        XCTAssertEqual(repo.consoleSettingsReads, 0)
        model.scheduleRealtimeRefresh()
        model.scheduleRealtimeRefresh()
        repo.approvalGate?.resume()
        let saved = await operation.value
        XCTAssertTrue(saved)
        await fulfillment(of: [refreshed], timeout: 5)
        XCTAssertEqual(repo.consoleBatchReads, 1)
        XCTAssertEqual(repo.consoleLineReads, 1)
        XCTAssertEqual(repo.consoleSettingsReads, 1)
        withExtendedLifetime(observation) {}
    }

    func testBulkKeepsSavedCountWhenReadbackAndLaterWriteBothFail() async throws {
        let (model, repo, first) = try fixture()
        let second = try makeBatch("second", status: "pending_review")
        model.reviewBatches.append(second)
        repo.batchReadFails = true
        repo.approvalFailure = second.id
        let count = await model.approveBatches([first, second])
        XCTAssertEqual(count, 1)
        let result = try XCTUnwrap(model.lastBatchApprovalResult)
        XCTAssertEqual(result.savedCount, 1)
        XCTAssertEqual(result.requestedCount, 2)
        XCTAssertTrue(result.refreshRequired)
        XCTAssertTrue(result.toastLabel.contains("1 OF 2"))
        XCTAssertTrue(result.toastLabel.contains("REFRESH NEEDED"))
        XCTAssertNil(model.error, "The counted result replaces a competing generic failure toast")
        XCTAssertFalse(model.canApproveBatch(first))
        XCTAssertTrue(model.canApproveBatch(second))
    }

    private func fixture(sharedState: ExpenseBatchApprovalState? = nil) throws -> (ExpenseViewModel, Repository, ExpenseBatchDTO) {
        let model = ExpenseViewModel(approvalState: sharedState ?? ExpenseBatchApprovalState())
        let repository = Repository()
        model.batchApprovalRepository = repository
        model.consoleRepository = repository
        let batch = try makeBatch("batch", status: "pending_review")
        model.reviewBatches = [batch]
        repository.approvedRows[batch.id] = try makeBatch(batch.id, status: "approved")
        return (model, repository, batch)
    }

    private func makeBatch(_ id: String, status: String, companyId: String = "company") throws -> ExpenseBatchDTO {
        try decode(["id": id, "company_id": companyId, "batch_number": "EXP-1", "status": status,
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
