//
//  ExpenseSubmissionGateTests.swift
//  OPSTests
//
//  Regression coverage for the expense submit gate — the enforcement that was
//  missing when photo-less expenses could be submitted at companies with
//  require_receipt_photo = TRUE (bug 07b7a1b3). The same rule backs the
//  require_project_assignment gate. These lock the truth table so a future
//  refactor of ExpenseFormSheet can't silently re-open the hole.
//

import XCTest
@testable import OPS

final class ExpenseSubmissionGateTests: XCTestCase {

    func testSubmitBlockedWhileCompanyPolicyIsUnresolved() {
        XCTAssertFalse(
            ExpenseSubmissionGate.passes(
                submit: true,
                policyResolved: false,
                required: false,
                hasArtifact: true,
                hasReason: true
            )
        )
    }

    func testDraftAllowedWhileCompanyPolicyIsUnresolved() {
        XCTAssertTrue(
            ExpenseSubmissionGate.passes(
                submit: false,
                policyResolved: false,
                required: true,
                hasArtifact: false,
                hasReason: false
            )
        )
    }

    func testMissingSettingsUseDatabaseDefaults() {
        let requirements = ExpenseSubmissionRequirements(settings: nil)

        XCTAssertTrue(requirements.requireReceiptPhoto)
        XCTAssertFalse(requirements.requireProjectAssignment)
    }

    // The core defect: a submit meets a live requirement with neither the
    // artifact nor a reason → BLOCKED.
    func testSubmitBlockedWhenRequiredAndNoArtifactAndNoReason() {
        XCTAssertFalse(ExpenseSubmissionGate.passes(submit: true, required: true, hasArtifact: false, hasReason: false))
    }

    // A real artifact (receipt photo / project) satisfies the requirement.
    func testSubmitAllowedWhenRequiredAndArtifactPresent() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: true, required: true, hasArtifact: true, hasReason: false))
    }

    // The escape hatch (explicit "no receipt / no project" reason) satisfies it.
    func testSubmitAllowedWhenRequiredAndReasonProvided() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: true, required: true, hasArtifact: false, hasReason: true))
    }

    // Draft saves are never gated, even when the company requires the artifact.
    func testDraftNeverBlockedEvenWhenRequired() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: false, required: true, hasArtifact: false, hasReason: false))
    }

    // Companies that don't require the artifact never block a submit.
    func testSubmitAllowedWhenNotRequired() {
        XCTAssertTrue(ExpenseSubmissionGate.passes(submit: true, required: false, hasArtifact: false, hasReason: false))
    }

    // Exhaustive truth table across all 16 input combinations.
    // Passes iff the save isn't a gated submit, or an artifact/reason is present.
    func testFullTruthTable() {
        for submit in [true, false] {
            for required in [true, false] {
                for hasArtifact in [true, false] {
                    for hasReason in [true, false] {
                        let expected = (!submit || !required) || hasArtifact || hasReason
                        XCTAssertEqual(
                            ExpenseSubmissionGate.passes(submit: submit, required: required, hasArtifact: hasArtifact, hasReason: hasReason),
                            expected,
                            "submit=\(submit) required=\(required) hasArtifact=\(hasArtifact) hasReason=\(hasReason)"
                        )
                    }
                }
            }
        }
    }

    func testAllocationPercentagesRequireAnExactHundredPercent() {
        XCTAssertTrue(ExpenseAllocationPercentageTotal.isExactlyComplete(["100"]))
        XCTAssertTrue(ExpenseAllocationPercentageTotal.isExactlyComplete(["33.33", "33.33", "33.34"]))
        XCTAssertFalse(ExpenseAllocationPercentageTotal.isExactlyComplete(["99.99"]))
        XCTAssertFalse(ExpenseAllocationPercentageTotal.isExactlyComplete(["100.01"]))
        XCTAssertFalse(ExpenseAllocationPercentageTotal.isExactlyComplete(["33.333", "66.667"]))
        XCTAssertFalse(ExpenseAllocationPercentageTotal.isExactlyComplete(["not-a-number"]))
    }

    func testReceiptRetryNeverDismissesForm() {
        XCTAssertFalse(ExpenseSaveOutcome.receiptRetryRequired.shouldDismiss)
        XCTAssertFalse(ExpenseSaveOutcome.failed.shouldDismiss)
        XCTAssertTrue(ExpenseSaveOutcome.complete.shouldDismiss)
    }

    func testPermanentReceiptRejectionRotatesTheUploadIdentity() {
        let current = "11111111-1111-1111-1111-111111111111"
        let next = ExpenseReceiptRetryIdentity.rotatedUploadID(
            after: current,
            candidate: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )

        XCTAssertEqual(next, "22222222-2222-2222-2222-222222222222")
        XCTAssertNotEqual(next, current)
    }

    func testReceiptReplacementCleanupDeletesOnlySupersededUniqueObjects() {
        let urls = ExpenseReceiptCleanup.supersededURLs(
            previousImageURL: "https://files.ops.test/old.jpg",
            previousThumbnailURL: "https://files.ops.test/old.jpg",
            replacementImageURL: "https://files.ops.test/new.jpg",
            replacementThumbnailURL: "https://files.ops.test/new-thumb.jpg"
        )

        XCTAssertEqual(urls, ["https://files.ops.test/old.jpg"])
        XCTAssertTrue(
            ExpenseReceiptCleanup.supersededURLs(
                previousImageURL: "https://files.ops.test/current.jpg",
                previousThumbnailURL: "https://files.ops.test/current-thumb.jpg",
                replacementImageURL: "https://files.ops.test/current.jpg",
                replacementThumbnailURL: "https://files.ops.test/current-thumb.jpg"
            ).isEmpty
        )
    }

    func testPermanentAtomicRejectionsUnlockTheFormWithActionableCopy() throws {
        XCTAssertEqual(
            ExpenseAtomicSaveFailurePolicy.rejection(
                for: .permanent(errorCode: "PG_P0001", reason: "stale")
            ),
            ExpenseAtomicSaveRejection(
                title: "// EXPENSE CHANGED",
                message: "This expense changed after you opened it. Close and reopen it before saving.",
                requiresClose: true
            )
        )
        XCTAssertEqual(
            ExpenseAtomicSaveFailurePolicy.rejection(
                for: .permanent(errorCode: "PG_23503", reason: "foreign key")
            )?.title,
            "// UPDATE REQUIRED"
        )
        XCTAssertFalse(
            try XCTUnwrap(
                ExpenseAtomicSaveFailurePolicy.rejection(
                    for: .permanent(errorCode: "PG_23503", reason: "foreign key")
                )
            ).requiresClose
        )
        XCTAssertEqual(
            ExpenseAtomicSaveFailurePolicy.rejection(
                for: .permanent(errorCode: "PG_23514", reason: "policy")
            )?.title,
            "// REQUIREMENTS CHANGED"
        )
        XCTAssertEqual(
            ExpenseAtomicSaveFailurePolicy.rejection(
                for: .permanent(errorCode: "PG_42501", reason: "permission")
            )?.title,
            "// SAVE BLOCKED"
        )
        XCTAssertTrue(
            try XCTUnwrap(
                ExpenseAtomicSaveFailurePolicy.rejection(
                    for: .permanent(errorCode: "PG_42501", reason: "permission")
                )
            ).requiresClose
        )
    }

    func testOnlyDefinitiveAtomicRejectionsUnlockAndDiscardTheRetryCommand() {
        XCTAssertNil(
            ExpenseAtomicSaveFailurePolicy.rejection(
                for: .transient(reason: "url_timed_out")
            )
        )
        XCTAssertNil(
            ExpenseAtomicSaveFailurePolicy.rejection(
                for: .unknown(reason: "unrecognized")
            )
        )
        XCTAssertNotNil(
            ExpenseAtomicSaveFailurePolicy.rejection(
                for: .permanent(errorCode: "HTTP_400", reason: "bad request")
            )
        )
    }

    func testAtomicSaveEncodesOneCompleteReplacementCommand() throws {
        let params = ExpenseAtomicSaveParams(
            command: makeAtomicCommand()
        )
        let object = try encodedJSONObject(params)
        let command = try XCTUnwrap(object["p_command"] as? [String: Any])
        let allocations = try XCTUnwrap(command["allocations"] as? [[String: Any]])

        XCTAssertEqual(command["request_id"] as? String, "request-id")
        XCTAssertEqual(command["expense_id"] as? String, "expense-id")
        XCTAssertEqual(command["company_id"] as? String, "company-id")
        XCTAssertEqual(command["submitted_by"] as? String, "user-id")
        XCTAssertEqual(command["expected_status"] as? String, "draft")
        XCTAssertEqual(command["expected_updated_at"] as? String, "2026-07-19T18:00:01.000000+00:00")
        XCTAssertEqual(command["tax_amount"] as? Double, 5.25)
        XCTAssertEqual(command["submit"] as? Bool, true)
        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations[0]["project_id"] as? String, "project-id")
        XCTAssertEqual(allocations[0]["percentage"] as? Double, 100)
        XCTAssertTrue(command["receipt_missing_reason"] is NSNull)
        XCTAssertTrue(command["receipt_missing_note"] is NSNull)
        XCTAssertTrue(command["project_missing_reason"] is NSNull)
        XCTAssertTrue(command["project_missing_note"] is NSNull)
    }

    func testAtomicSaveEncodesNullableFieldClearsAsExplicitNull() throws {
        let params = ExpenseAtomicSaveParams(
            command: makeAtomicCommand(
                categoryId: nil,
                description: nil,
                taxAmount: nil,
                receiptImageUrl: nil,
                receiptThumbnailUrl: nil,
                receiptMissingReason: "lost",
                allocations: [],
                projectMissingReason: "overhead"
            )
        )
        let object = try encodedJSONObject(params)
        let command = try XCTUnwrap(object["p_command"] as? [String: Any])

        XCTAssertTrue(command["category_id"] is NSNull)
        XCTAssertTrue(command["description"] is NSNull)
        XCTAssertTrue(command["tax_amount"] is NSNull)
        XCTAssertTrue(command["receipt_image_url"] is NSNull)
        XCTAssertTrue(command["receipt_thumbnail_url"] is NSNull)
        XCTAssertEqual(command["receipt_missing_reason"] as? String, "lost")
        XCTAssertEqual(command["project_missing_reason"] as? String, "overhead")
        XCTAssertEqual((command["allocations"] as? [Any])?.count, 0)
    }

    func testAtomicCreateEncodesNullExpectedStatus() throws {
        let object = try encodedJSONObject(
            ExpenseAtomicSaveParams(
                command: makeAtomicCommand(expectedStatus: nil, expectedUpdatedAt: nil)
            )
        )
        let command = try XCTUnwrap(object["p_command"] as? [String: Any])

        XCTAssertTrue(command["expected_status"] is NSNull)
        XCTAssertTrue(command["expected_updated_at"] is NSNull)
        XCTAssertTrue(command["ocr_raw_data"] is NSNull)
        XCTAssertTrue(command["ocr_confidence"] is NSNull)
    }

    func testAtomicRequestIdIsReusedOnlyForTheSameIntent() {
        let original = makeAtomicCommand()
        let replay = original.replacingRequestId(with: "replay-request-id")
        let edited = makeAtomicCommand(taxAmount: 7.50)
        let staleBase = makeAtomicCommand(expectedUpdatedAt: "2026-07-19T18:00:02.000000+00:00")

        XCTAssertTrue(original.hasSameIntent(as: replay))
        XCTAssertFalse(original.hasSameIntent(as: edited))
        XCTAssertFalse(original.hasSameIntent(as: staleBase))
    }

    func testAtomicReadbackAcceptsServerSubmittedOrApprovedResult() {
        let command = makeAtomicCommand()

        XCTAssertTrue(
            ExpenseAtomicSaveReadback.matches(
                command: command,
                expense: makeExpense(status: "submitted")
            )
        )
        XCTAssertTrue(
            ExpenseAtomicSaveReadback.matches(
                command: command,
                expense: makeExpense(status: "approved")
            )
        )
    }

    func testAtomicReadbackRejectsPartialPersistence() {
        let command = makeAtomicCommand()

        XCTAssertFalse(
            ExpenseAtomicSaveReadback.matches(
                command: command,
                expense: makeExpense(status: "submitted", taxAmount: nil)
            )
        )
        XCTAssertFalse(
            ExpenseAtomicSaveReadback.matches(
                command: command,
                expense: makeExpense(status: "submitted", projectId: "different-project")
            )
        )
    }

    private func makeAtomicCommand(
        expectedStatus: String? = "draft",
        expectedUpdatedAt: String? = "2026-07-19T18:00:01.000000+00:00",
        categoryId: String? = "category-id",
        description: String? = "Fasteners",
        taxAmount: Double? = 5.25,
        receiptImageUrl: String? = "https://files.ops.test/receipt.jpg",
        receiptThumbnailUrl: String? = "https://files.ops.test/receipt-thumb.jpg",
        receiptMissingReason: String? = nil,
        allocations: [ExpenseAtomicAllocationCommand] = [
            ExpenseAtomicAllocationCommand(
                projectId: "project-id",
                percentage: 100,
                amount: nil
            )
        ],
        projectMissingReason: String? = nil
    ) -> ExpenseAtomicSaveCommand {
        ExpenseAtomicSaveCommand(
            requestId: "request-id",
            expenseId: "expense-id",
            companyId: "company-id",
            submittedBy: "user-id",
            expectedStatus: expectedStatus,
            expectedUpdatedAt: expectedUpdatedAt,
            categoryId: categoryId,
            merchantName: "Supply House",
            description: description,
            amount: 105.25,
            taxAmount: taxAmount,
            currency: "CAD",
            expenseDate: "2026-07-19T07:00:00Z",
            paymentMethod: "personal_card",
            receiptImageUrl: receiptImageUrl,
            receiptThumbnailUrl: receiptThumbnailUrl,
            receiptMissingReason: receiptMissingReason,
            receiptMissingNote: nil,
            projectMissingReason: projectMissingReason,
            projectMissingNote: nil,
            ocrRawData: nil,
            ocrConfidence: nil,
            allocations: allocations,
            submit: true
        )
    }

    private func makeExpense(
        status: String,
        taxAmount: Double? = 5.25,
        projectId: String = "project-id"
    ) -> ExpenseDTO {
        ExpenseDTO(
            id: "expense-id",
            companyId: "company-id",
            submittedBy: "user-id",
            status: status,
            categoryId: "category-id",
            merchantName: "Supply House",
            description: "Fasteners",
            amount: 105.25,
            taxAmount: taxAmount,
            currency: "CAD",
            expenseDate: "2026-07-19",
            paymentMethod: "personal_card",
            receiptImageUrl: "https://files.ops.test/receipt.jpg",
            receiptThumbnailUrl: "https://files.ops.test/receipt-thumb.jpg",
            receiptMissingReason: nil,
            receiptMissingNote: nil,
            projectMissingReason: nil,
            projectMissingNote: nil,
            ocrRawData: nil,
            ocrConfidence: nil,
            batchId: "batch-id",
            approvedBy: nil,
            approvedAt: nil,
            rejectedBy: nil,
            rejectedAt: nil,
            rejectionReason: nil,
            flagComment: nil,
            flaggedBy: nil,
            flaggedAt: nil,
            accountingSyncStatus: nil,
            accountingSyncId: nil,
            accountingSyncedAt: nil,
            createdAt: "2026-07-19T18:00:00.000000+00:00",
            updatedAt: "2026-07-19T18:00:01.000000+00:00",
            deletedAt: nil,
            allocations: [
                ExpenseAllocationDTO(
                    id: "allocation-id",
                    expenseId: "expense-id",
                    projectId: projectId,
                    percentage: 100,
                    amount: nil
                )
            ],
            category: nil
        )
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
