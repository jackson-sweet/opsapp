import XCTest
@testable import OPS

enum ExpenseCorrectionFixtures {
    static let company = "11111111-1111-4111-8111-111111111111"
    static let actor = "22222222-2222-4222-8222-222222222222"
    static let crew = "33333333-3333-4333-8333-333333333333"
    static let expense = "44444444-4444-4444-8444-444444444444"
    static let request = "55555555-5555-4555-8555-555555555555"
    static let batch = "66666666-6666-4666-8666-666666666666"
    static let revision = "2026-09-14T12:01:02.123456+00:00"

    static func decode<T: Decodable>(_ value: [String: Any], as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }

    static func row(_ overrides: [String: Any] = [:]) throws -> ExpenseDTO {
        var values: [String: Any] = [
            "id": expense, "company_id": company, "submitted_by": crew,
            "status": "submitted", "merchant_name": "Lumber yard", "amount": 40,
            "currency": "CAD", "expense_date": "2026-09-13", "payment_method": "personal_card",
            "created_at": revision, "updated_at": revision,
            "expense_project_allocations": []
        ]
        values.merge(overrides) { _, new in new }
        return try decode(values)
    }

    static func envelope(status: String = "pending_review", paidAt: String? = nil) -> ExpenseBatchDTO {
        ExpenseBatchDTO(id: batch, companyId: company, batchNumber: "EXP-204", status: status,
                        submittedBy: crew, totalAmount: 40, createdAt: revision, paidAt: paidAt)
    }

    static func command(note: String = "Use the subtotal before tax.") -> ExpenseCorrectionCommand {
        ExpenseCorrectionCommand(content: ExpenseAtomicSaveCommand(
            requestId: request, expenseId: expense, companyId: company, submittedBy: crew,
            expectedStatus: "submitted", expectedUpdatedAt: revision, categoryId: nil,
            merchantName: "Lumber yard", description: nil, amount: 38, taxAmount: nil,
            currency: "CAD", expenseDate: "2026-09-13", paymentMethod: "personal_card",
            receiptImageUrl: "private-receipt", receiptThumbnailUrl: "private-thumb",
            receiptMissingReason: nil, receiptMissingNote: nil, projectMissingReason: nil,
            projectMissingNote: nil, ocrRawData: ["secret": "receipt content"], ocrConfidence: 0.9,
            allocations: [], submit: false), actorId: actor, correctionNote: note)
    }

    static func snapshot(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = [
            "status": "submitted", "updated_at": revision, "merchant_name": "Lumber yard",
            "amount": 40, "currency": "CAD", "expense_date": "2026-09-13",
            "payment_method": "personal_card", "allocations": []
        ]
        value.merge(overrides) { _, new in new }
        return value
    }

    static func record(note: String = "Use the subtotal before tax.", before: [String: Any]? = nil, after: [String: Any]? = nil) -> [String: Any] {
        ["id": request, "request_id": request,
         "expense_id": expense, "company_id": company, "actor_id": actor, "submitted_by": crew,
         "corrected_at": "2026-09-14T12:02:00.654321+00:00", "correction_note": note,
         "before": before ?? snapshot(), "after": after ?? snapshot(["status": "rejected", "amount": 38, "updated_at": "2026-09-14T12:02:00.654321Z"])]
    }

    static func receipt(replayed: Bool = false, overrides: [String: Any] = [:]) throws -> ExpenseCorrectionReceipt {
        var value: [String: Any] = ["request_id": request, "expense_id": expense,
            "company_id": company, "actor_id": actor, "submitted_by": crew,
            "replayed": replayed, "correction": record()]
        value.merge(overrides) { _, new in new }
        return try decode(value)
    }
}

final class ExpenseCorrectionContractTests: XCTestCase {
    private typealias F = ExpenseCorrectionFixtures

    func testInvalidNumbersFailBeforeCommandFreezesOrNullableTaxCanBeCleared() {
        for amount in ["NaN", "Infinity", "-inf", "1e309", "no", ""] {
            XCTAssertFalse(ExpenseFormNumericValidation.errors(amount: amount, tax: "", percentages: []).isEmpty)
        }
        for tax in ["NaN", "Infinity", "no", " "] {
            XCTAssertFalse(ExpenseFormNumericValidation.errors(amount: "40", tax: tax, percentages: []).isEmpty)
        }
        for percentage in ["NaN", "Infinity", "no", "", "0", "-1", "101"] {
            XCTAssertFalse(ExpenseFormNumericValidation.errors(amount: "40", tax: "", percentages: [percentage]).isEmpty)
        }
        XCTAssertTrue(ExpenseFormNumericValidation.errors(amount: "40.00", tax: "", percentages: ["33.33", "66.67"]).isEmpty)
    }

    func testCorrectionWireOmitsReceiptOCRApprovalAndSubmitFields() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(F.command())) as? [String: Any])
        XCTAssertEqual(object["expected_updated_at"] as? String, F.revision)
        XCTAssertEqual(object["actor_id"] as? String, F.actor)
        XCTAssertEqual(object["submitted_by"] as? String, F.crew)
        XCTAssertTrue(object["tax_amount"] is NSNull)
        XCTAssertTrue(object["description"] is NSNull)
        XCTAssertTrue(object["category_id"] is NSNull)
        XCTAssertTrue(object["project_missing_reason"] is NSNull)
        for key in ["receipt_image_url", "receipt_thumbnail_url", "receipt_missing_reason", "receipt_missing_note", "ocr_raw_data", "ocr_confidence", "submit", "approved_at", "paid_at", "status"] {
            XCTAssertNil(object[key], "Correction must not encode \(key)")
        }
    }

    func testEmptyNoteIsAnExplicitString() throws {
        let command = F.command(note: "")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        XCTAssertEqual(object["correction_note"] as? String, "")
        let receipt: ExpenseCorrectionReceipt = try F.receipt(overrides: ["correction": F.record(note: "")])
        XCTAssertTrue(receipt.matches(command))
    }

    func testReceiptRequiresBothEnvelopeAndNestedExactIdentity() throws {
        let command = F.command()
        XCTAssertTrue(try F.receipt().matches(command))
        for key in ["request_id", "expense_id", "company_id", "actor_id", "submitted_by"] {
            XCTAssertFalse(try F.receipt(overrides: [key: "88888888-8888-4888-8888-888888888888"]).matches(command))
            var record = F.record()
            record[key] = "88888888-8888-4888-8888-888888888888"
            XCTAssertFalse(try F.receipt(overrides: ["correction": record]).matches(command))
        }
    }

    func testTimestampComparisonPreservesEveryMicrosecondAcrossTimezoneSpelling() {
        XCTAssertEqual(ExpenseCorrectionTimestamp.microseconds(F.revision), ExpenseCorrectionTimestamp.microseconds("2026-09-14T12:01:02.123456Z"))
        XCTAssertEqual(ExpenseCorrectionTimestamp.microseconds(F.revision), ExpenseCorrectionTimestamp.microseconds("2026-09-14T05:01:02.123456-07:00"))
        XCTAssertNotEqual(ExpenseCorrectionTimestamp.microseconds(F.revision), ExpenseCorrectionTimestamp.microseconds("2026-09-14T12:01:02.123457Z"))
        XCTAssertNil(ExpenseCorrectionTimestamp.microseconds("not a timestamp"))
    }

    func testReceiptRejectsWrongRevisionAuditIdAndAppliedBusinessValues() throws {
        var wrongId = F.record()
        wrongId["id"] = F.crew
        XCTAssertFalse(try F.receipt(overrides: ["correction": wrongId]).matches(F.command()))
        var wrongRevision = F.record()
        wrongRevision["before"] = F.snapshot(["updated_at": "2026-09-14T12:01:02.123457Z"])
        XCTAssertFalse(try F.receipt(overrides: ["correction": wrongRevision]).matches(F.command()))
        for (key, value) in [("amount", 39 as Any), ("tax_amount", 1), ("currency", "USD"), ("description", "Different note"), ("merchant_name", "Other merchant"), ("payment_method", "company_card"), ("expense_date", "2026-09-12"), ("category_id", F.crew)] {
            var after = F.snapshot(["status": "rejected", "amount": 38, "updated_at": "2026-09-14T12:02:00.654321Z"])
            after[key] = value
            XCTAssertFalse(try F.receipt(overrides: ["correction": F.record(after: after)]).matches(F.command()), key)
        }
        let wrongAllocations = F.snapshot(["status": "rejected", "amount": 38, "updated_at": "2026-09-14T12:02:00.654321Z",
            "allocations": [["project_id": F.request, "project_title": "Deck", "percentage": 100]]])
        XCTAssertFalse(try F.receipt(overrides: ["correction": F.record(after: wrongAllocations)]).matches(F.command()))
    }

    func testReplayConfirmsHistoricalCorrectionWithoutClaimingCurrentStatus() throws {
        let receipt = try F.receipt(replayed: true)
        XCTAssertTrue(receipt.matches(F.command()))
        XCTAssertEqual(receipt.correction.after.status, "rejected")
        XCTAssertTrue(receipt.replayed)
    }

    func testChangedFieldsUseFrozenNamesAndPreserveClears() throws {
        let before = F.snapshot(["category_id": F.actor, "category_name": "Materials", "description": "Original note",
            "allocations": [["project_id": F.company, "project_title": "Old deck", "percentage": 100, "amount": NSNull()]]])
        let after = F.snapshot(["status": "rejected", "category_id": F.crew, "category_name": "Tools", "description": NSNull(),
            "allocations": [["project_id": F.request, "project_title": "New deck", "percentage": 100, "amount": NSNull()]]])
        let record: ExpenseCorrectionDTO = try F.decode(F.record(before: before, after: after))
        let changes = ExpenseCorrectionChange.changes(in: record)
        XCTAssertEqual(changes.map(\.id), ["description", "category_id", "allocations"])
        XCTAssertEqual(changes[0].after, "—")
        XCTAssertEqual(changes[1].before, "Materials")
        XCTAssertEqual(changes[1].after, "Tools")
        XCTAssertTrue(changes[2].before.contains("Old deck"))
        XCTAssertTrue(changes[2].after.contains("New deck"))
        XCTAssertFalse(changes[2].after.contains(F.request))
    }

    func testStatusTimestampAndProjectRenameAloneAreNotBusinessChanges() throws {
        let before = F.snapshot(["allocations": [["project_id": F.company, "project_title": "Old name", "percentage": 100]]])
        let after = F.snapshot(["status": "rejected", "updated_at": "2026-09-15T00:00:00Z",
            "allocations": [["project_id": F.company, "project_title": "New name", "percentage": 100]]])
        let record: ExpenseCorrectionDTO = try F.decode(F.record(before: before, after: after))
        XCTAssertTrue(ExpenseCorrectionChange.changes(in: record).isEmpty)
    }

    func testCurrencyChangeIsVisibleEvenWhenNumericAmountIsUnchanged() throws {
        let record: ExpenseCorrectionDTO = try F.decode(F.record(after: F.snapshot(["status": "rejected", "currency": "USD"])))
        let changes = ExpenseCorrectionChange.changes(in: record)
        XCTAssertEqual(changes.map(\.id), ["amount"])
        XCTAssertNotEqual(changes.first?.before, changes.first?.after)
    }

    func testEligibilityRejectsSelfForeignAccountMissingScopeAndSettledEvidence() throws {
        func allowed(_ row: ExpenseDTO, actor: String = F.actor, company: String = F.company, approve: Bool = true, view: Bool = true) -> Bool {
            ExpenseCorrectionPolicy.canCorrect(expense: row, batch: nil, actorId: actor, companyId: company, canApproveAll: approve, canViewAll: view)
        }
        XCTAssertTrue(allowed(try F.row()))
        XCTAssertTrue(allowed(try F.row(["status": "rejected"])))
        XCTAssertFalse(allowed(try F.row(), actor: F.crew))
        XCTAssertFalse(allowed(try F.row(), company: F.crew))
        XCTAssertFalse(allowed(try F.row(), approve: false))
        XCTAssertFalse(allowed(try F.row(), view: false))
        for status in ["draft", "approved", "reimbursed", "unknown"] {
            XCTAssertFalse(allowed(try F.row(["status": status])))
        }
        for key in ["approved_at", "approved_by", "deleted_at", "accounting_sync_id", "accounting_synced_at"] {
            XCTAssertFalse(allowed(try F.row([key: "recorded"])))
        }
        for status in ["synced", "error", "processing", "unknown"] {
            XCTAssertFalse(allowed(try F.row(["accounting_sync_status": status])))
        }
        XCTAssertTrue(allowed(try F.row(["accounting_sync_status": "pending"])))
    }

    func testBatchEligibilityRequiresKnownExactUnpaidUnapprovedEnvelope() throws {
        let row = try F.row(["batch_id": F.batch])
        func allowed(_ batch: ExpenseBatchDTO?) -> Bool {
            ExpenseCorrectionPolicy.canCorrect(expense: row, batch: batch, actorId: F.actor, companyId: F.company, canApproveAll: true, canViewAll: true)
        }
        XCTAssertFalse(allowed(nil))
        for status in ["open", "pending_review", "submitted", "rejected"] { XCTAssertTrue(allowed(F.envelope(status: status))) }
        for status in ["approved", "auto_approved", "partially_approved"] { XCTAssertFalse(allowed(F.envelope(status: status))) }
        XCTAssertFalse(allowed(F.envelope(paidAt: F.revision)))
    }

    func testStaleReloadPreservesEditedFieldsAndAdoptsUntouchedCrewChanges() throws {
        let previous = ExpenseCorrectionDraft(expense: try F.row())
        var entered = previous
        entered.amount = "38.00"
        let latest = ExpenseCorrectionDraft(expense: try F.row(["description": "Crew added the missing explanation"]))
        let result = entered.rebased(from: previous, onto: latest)
        XCTAssertEqual(result.draft.amount, "38.00")
        XCTAssertEqual(result.draft.description, "Crew added the missing explanation")
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testStaleReloadCallsOutCompetingAmountEditWithoutLosingReviewerValue() throws {
        let previous = ExpenseCorrectionDraft(expense: try F.row())
        var entered = previous
        entered.amount = "38.00"
        let latest = ExpenseCorrectionDraft(expense: try F.row(["amount": 42]))
        let result = entered.rebased(from: previous, onto: latest)
        XCTAssertEqual(result.draft.amount, "38.00")
        XCTAssertEqual(result.conflicts, ["amount"])
    }

    func testProjectRebaseTreatsSplitAndExceptionAsOneIntent() throws {
        let previous = ExpenseCorrectionDraft(expense: try F.row())
        var entered = previous
        entered.projectReason = "overhead"
        var latest = previous
        latest.allocations = [ExpenseAtomicAllocationCommand(projectId: F.request, percentage: 100, amount: nil)]
        let result = entered.rebased(from: previous, onto: latest)
        XCTAssertTrue(result.draft.allocations.isEmpty)
        XCTAssertEqual(result.draft.projectReason, "overhead")
        XCTAssertEqual(result.conflicts, ["project split"])
    }
}

@MainActor
final class ExpenseCorrectionViewModelTests: XCTestCase {
    private typealias F = ExpenseCorrectionFixtures
    private enum Failure: Error { case offline }
    private final class Repository: ExpenseCorrectionRepository, ExpenseConsoleRepository {
        var calls: [ExpenseCorrectionCommand] = []
        var receipt = try! F.receipt()
        var row = try! F.row(["status": "rejected", "amount": 38])
        var writeFails = false
        var readFails = false
        var readCount = 0
        var onWrite: (() -> Void)?
        var onRead: (() -> Void)?
        var pauseRead = false
        var readStarted: (() -> Void)?
        var readGate: CheckedContinuation<Void, Never>?
        var consoleRow = try! F.row(["status": "submitted", "amount": 75])
        func fetchBatches() async throws -> [ExpenseBatchDTO] { [] }
        func fetchAll() async throws -> [ExpenseDTO] { [consoleRow] }
        func fetchSettings() async throws -> ExpenseSettingsDTO? { nil }
        func correctForReview(_ command: ExpenseCorrectionCommand) async throws -> ExpenseCorrectionReceipt {
            calls.append(command)
            if writeFails { throw Failure.offline }
            onWrite?()
            return receipt
        }
        func fetchOne(_ expenseId: String) async throws -> ExpenseDTO {
            readCount += 1
            if readFails { throw Failure.offline }
            let snapshot = row
            if pauseRead {
                readStarted?()
                await withCheckedContinuation { readGate = $0 }
            }
            onRead?()
            return snapshot
        }
        func fetchBatch(_ batchId: String) async throws -> ExpenseBatchDTO { F.envelope() }
        func fetchCorrections(expenseId: String) async throws -> [ExpenseCorrectionDTO] {
            onRead?()
            return [receipt.correction]
        }
    }
    private func model(_ repo: Repository) -> ExpenseViewModel {
        let model = ExpenseViewModel()
        model.setup(companyId: F.company, currentUserId: F.actor)
        model.correctionRepository = repo
        return model
    }

    func testWriteFailureDoesNotPublishSuccessOrReplaceCachedExpense() async throws {
        let repo = Repository(), model = model(Repository())
        model.correctionRepository = repo
        model.expenses = [try F.row()]
        repo.writeFails = true
        do { _ = try await model.correctExpenseForReview(F.command()); XCTFail("Expected write failure") } catch { }
        XCTAssertEqual(model.expenses.first?.amount, 40)
        XCTAssertEqual(repo.readCount, 0)
    }

    func testInvalidReceiptDoesNotTriggerCurrentStateRead() async throws {
        let repo = Repository(), model = model(Repository())
        model.correctionRepository = repo
        repo.receipt = try F.receipt(overrides: ["company_id": F.crew])
        do { _ = try await model.correctExpenseForReview(F.command()); XCTFail("Expected identity failure") } catch { }
        XCTAssertEqual(repo.readCount, 0)
    }

    func testReplayPublishesCurrentCrewEditInsteadOfHistoricalAfterSnapshot() async throws {
        let repo = Repository()
        let model = model(repo)
        model.expenses = [try F.row()]
        repo.receipt = try F.receipt(replayed: true)
        repo.row = try F.row(["status": "submitted", "amount": 45])
        let result = try await model.correctExpenseForReview(F.command())
        XCTAssertTrue(result.refreshed)
        XCTAssertTrue(result.receipt.replayed)
        XCTAssertEqual(model.expenses.first?.amount, 45)
        XCTAssertEqual(model.expenses.first?.status, "submitted")
    }

    func testConfirmedReceiptSurvivesIndependentRefreshFailure() async throws {
        let repo = Repository()
        let model = model(repo)
        repo.readFails = true
        let result = try await model.correctExpenseForReview(F.command())
        XCTAssertFalse(result.refreshed)
        XCTAssertEqual(result.receipt.requestId, F.request)
        XCTAssertEqual(repo.calls.count, 1)
    }

    func testCompanySwitchDuringWritePreventsReadAndPublication() async throws {
        let repo = Repository()
        let model = model(repo)
        model.expenses = [try F.row()]
        repo.onWrite = { model.setup(companyId: F.crew, currentUserId: F.actor) }
        do { _ = try await model.correctExpenseForReview(F.command()); XCTFail("Expected scope failure") } catch { }
        XCTAssertEqual(repo.readCount, 0)
        XCTAssertEqual(model.expenses.first?.amount, 40)
    }

    func testUserSwitchDuringReadPreventsPublication() async throws {
        let repo = Repository()
        let model = model(repo)
        model.expenses = [try F.row()]
        repo.onRead = { model.setCurrentUser(id: F.crew, name: nil) }
        do { _ = try await model.correctExpenseForReview(F.command()); XCTFail("Expected scope failure") } catch { }
        XCTAssertEqual(model.expenses.first?.amount, 40)
    }

    func testWrongActorCannotDispatchCorrection() async throws {
        let repo = Repository()
        let model = model(repo)
        model.setCurrentUser(id: F.crew, name: nil)
        do { _ = try await model.correctExpenseForReview(F.command()); XCTFail("Expected scope failure") } catch { }
        XCTAssertTrue(repo.calls.isEmpty)
    }

    func testHistoryReadCannotLeakAcrossAnAccountSwitch() async throws {
        let repo = Repository()
        let model = model(repo)
        repo.onRead = { model.setCurrentUser(id: F.crew, name: nil) }
        do {
            _ = try await model.loadExpenseCorrections(expenseId: F.expense, companyId: F.company, actorId: F.actor)
            XCTFail("Expected scope failure")
        } catch { }
    }

    func testNewerConsoleReadSupersedesDelayedCorrectionRefresh() async throws {
        let repo = Repository()
        let model = model(repo)
        model.consoleRepository = repo
        model.expenses = [try F.row()]
        repo.pauseRead = true
        let started = expectation(description: "Correction read suspended")
        repo.readStarted = { started.fulfill() }
        let correction = Task { try await model.correctExpenseForReview(F.command()) }
        await fulfillment(of: [started], timeout: 2)
        await model.loadConsole()
        XCTAssertEqual(model.expenses.first?.amount, 75)
        repo.readGate?.resume()
        let result = try await correction.value
        XCTAssertFalse(result.refreshed)
        XCTAssertEqual(model.expenses.first?.amount, 75)
    }

    func testBaselineReadDoesNotOverwriteEnteredOrCachedValues() async throws {
        let repo = Repository()
        let model = model(repo)
        model.expenses = [try F.row()]
        let baseline = try await model.reloadExpenseCorrectionBaseline(expenseId: F.expense, companyId: F.company, actorId: F.actor)
        XCTAssertEqual(baseline.0.amount, 38)
        XCTAssertEqual(model.expenses.first?.amount, 40)
    }
}
