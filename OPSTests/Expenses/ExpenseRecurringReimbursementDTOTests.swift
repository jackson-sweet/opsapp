//
//  ExpenseRecurringReimbursementDTOTests.swift
//  OPSTests
//
//  The wire contract with the recurring reimbursement commands and tables:
//  the command payload (setup + every month's line), the bare table row, the
//  parameters PostgREST resolves each function by (explicit nulls where the
//  signature has no default), and the two new `expenses` columns.
//

import XCTest
@testable import OPS

final class ExpenseRecurringReimbursementDTOTests: XCTestCase {

    /// The shape `private.expense_recurring_reimbursement_json` returns.
    private let commandPayload = """
    {
      "id": "967e3c5b-8fbf-4eb9-aa9e-4ca1481e9a83",
      "company_id": "c0000000-0000-0000-0000-000000000001",
      "user_id": "ae10941c-f7e9-4d01-8e24-6c89b04b5634",
      "name": "Phone plan",
      "amount": 275,
      "currency": "CAD",
      "category_id": null,
      "first_period": "2026-08-01",
      "last_period": null,
      "next_period": "2026-10-01",
      "created_by": "a0000000-0000-0000-0000-000000000001",
      "updated_by": "a0000000-0000-0000-0000-000000000001",
      "created_at": "2026-09-17T02:44:17.100221+00:00",
      "updated_at": "2026-09-17T02:44:17.100221+00:00",
      "deleted_at": null,
      "deleted_by": null,
      "lines": [
        {"expense_id": "e-sep", "period": "2026-09-01", "batch_id": "b-0008", "status": "approved", "amount": 275.00, "deleted": false},
        {"expense_id": "e-aug", "period": "2026-08-01", "batch_id": "b-0006", "status": "approved", "amount": 275, "deleted": false}
      ]
    }
    """

    func testDecodesTheCommandPayloadWithMonthsOldestFirst() throws {
        let setup = try JSONDecoder().decode(ExpenseRecurringReimbursementDTO.self, from: Data(commandPayload.utf8))
        XCTAssertEqual(setup.id, "967e3c5b-8fbf-4eb9-aa9e-4ca1481e9a83")
        XCTAssertEqual(setup.name, "Phone plan")
        XCTAssertEqual(setup.amount, 275)
        XCTAssertEqual(setup.currency, "CAD")
        XCTAssertNil(setup.categoryId)
        XCTAssertNil(setup.lastPeriod)
        XCTAssertEqual(setup.nextPeriod, "2026-10-01")
        // The concurrency token survives verbatim — microseconds included.
        XCTAssertEqual(setup.updatedAt, "2026-09-17T02:44:17.100221+00:00")
        XCTAssertEqual(setup.lines.map(\.period), ["2026-08-01", "2026-09-01"])
        XCTAssertEqual(setup.lines.first?.expenseId, "e-aug")
        XCTAssertEqual(setup.lines.last?.batchId, "b-0008")
    }

    func testDecodesABareTableRowWithNoMonths() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(commandPayload.utf8)) as? [String: Any]
        )
        object.removeValue(forKey: "lines")
        let data = try JSONSerialization.data(withJSONObject: object)
        let setup = try JSONDecoder().decode(ExpenseRecurringReimbursementDTO.self, from: data)
        XCTAssertEqual(setup.lines, [])

        let joined = setup.withLines([
            RecurringLineRowDTO(
                id: "e-sep", recurringReimbursementId: setup.id, recurringPeriod: "2026-09-01",
                batchId: "b-0008", status: "approved", amount: 275, deletedAt: nil
            ).summary,
            RecurringLineRowDTO(
                id: "e-oct", recurringReimbursementId: setup.id, recurringPeriod: "2026-10-01",
                batchId: "b-0009", status: "approved", amount: 275, deletedAt: "2026-10-02T00:00:00+00:00"
            ).summary,
        ])
        XCTAssertEqual(joined.lines.map(\.period), ["2026-09-01", "2026-10-01"])
        XCTAssertEqual(joined.lines.map(\.deleted), [false, true])
    }

    func testCreateSendsAnExplicitNullCategory() throws {
        let json = try encoded(CreateRecurringReimbursementParams(
            userId: "u", name: "Phone plan", amount: 275, firstPeriod: "2026-08-01", categoryId: nil
        ))
        XCTAssertEqual(json["p_user_id"] as? String, "u")
        XCTAssertEqual(json["p_name"] as? String, "Phone plan")
        XCTAssertEqual(json["p_amount"] as? Double, 275)
        XCTAssertEqual(json["p_first_period"] as? String, "2026-08-01")
        XCTAssertTrue(json.keys.contains("p_category_id"))
        XCTAssertTrue(json["p_category_id"] is NSNull)
    }

    func testUpdateCarriesEveryParameterTheSignatureRequires() throws {
        let json = try encoded(UpdateRecurringReimbursementParams(
            id: "s", name: "Phone plan", amount: 375.5, categoryId: nil,
            expectedUpdatedAt: "2026-09-17T02:44:17.100221+00:00"
        ))
        XCTAssertEqual(Set(json.keys), ["p_id", "p_name", "p_amount", "p_category_id", "p_expected_updated_at"])
        XCTAssertTrue(json["p_category_id"] is NSNull)
        XCTAssertEqual(json["p_amount"] as? Double, 375.5)
        XCTAssertEqual(json["p_expected_updated_at"] as? String, "2026-09-17T02:44:17.100221+00:00")
    }

    func testEndSendsNullToRemoveTheEnd() throws {
        let ending = try encoded(EndRecurringReimbursementParams(id: "s", lastPeriod: "2026-12-01", expectedUpdatedAt: "t"))
        XCTAssertEqual(ending["p_last_period"] as? String, "2026-12-01")

        let resuming = try encoded(EndRecurringReimbursementParams(id: "s", lastPeriod: nil, expectedUpdatedAt: "t"))
        XCTAssertEqual(Set(resuming.keys), ["p_id", "p_last_period", "p_expected_updated_at"])
        XCTAssertTrue(resuming["p_last_period"] is NSNull)
    }

    func testDeleteAndLineCommandsNameTheirParameters() throws {
        XCTAssertEqual(
            Set(try encoded(DeleteRecurringReimbursementParams(id: "s", expectedUpdatedAt: "t")).keys),
            ["p_id", "p_expected_updated_at"]
        )
        XCTAssertEqual(try encoded(RecurringLineCommandParams(expenseId: "e")) as NSDictionary, ["p_expense_id": "e"])
    }

    func testCurrencyNormalisesToAnISOCode() {
        XCTAssertEqual(ExpenseRecurringReimbursementRepository.normalizedCurrency("cad"), "CAD")
        XCTAssertEqual(ExpenseRecurringReimbursementRepository.normalizedCurrency(" CAD "), "CAD")
        XCTAssertEqual(ExpenseRecurringReimbursementRepository.normalizedCurrency(nil), "USD")
        XCTAssertEqual(ExpenseRecurringReimbursementRepository.normalizedCurrency(""), "USD")
        XCTAssertEqual(ExpenseRecurringReimbursementRepository.normalizedCurrency("CA$"), "USD")
    }

    func testExpenseRowsCarryTheirRecurringMonth() throws {
        let json = """
        {
          "id": "e-aug", "company_id": "co", "submitted_by": "rivera", "status": "approved",
          "category_id": null, "merchant_name": "Phone plan", "description": "Monthly · August 2026",
          "amount": 275, "tax_amount": null, "currency": "CAD", "expense_date": "2026-08-01",
          "payment_method": null, "receipt_image_url": null, "receipt_thumbnail_url": null,
          "receipt_missing_reason": "other", "receipt_missing_note": "Recurring reimbursement. No receipt needed.",
          "project_missing_reason": null, "project_missing_note": null, "ocr_raw_data": null,
          "ocr_confidence": null, "batch_id": "b-0006", "approved_by": "okafor",
          "approved_at": "2026-09-17T02:40:00+00:00", "rejected_by": null, "rejected_at": null,
          "rejection_reason": null, "flag_comment": null, "flagged_by": null, "flagged_at": null,
          "accounting_sync_status": null, "accounting_sync_id": null, "accounting_synced_at": null,
          "created_at": "2026-09-17T02:40:00+00:00", "updated_at": "2026-09-17T02:40:00+00:00",
          "deleted_at": null, "expense_project_allocations": [], "expense_categories": null,
          "recurring_reimbursement_id": "967e3c5b-8fbf-4eb9-aa9e-4ca1481e9a83",
          "recurring_period": "2026-08-01"
        }
        """
        let expense = try JSONDecoder().decode(ExpenseDTO.self, from: Data(json.utf8))
        XCTAssertEqual(expense.recurringReimbursementId, "967e3c5b-8fbf-4eb9-aa9e-4ca1481e9a83")
        XCTAssertEqual(expense.recurringPeriod, "2026-08-01")
        XCTAssertTrue(expense.isRecurringReimbursement)

        // Rows from servers without the columns still decode, as receipts.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        object.removeValue(forKey: "recurring_reimbursement_id")
        object.removeValue(forKey: "recurring_period")
        let legacy = try JSONDecoder().decode(ExpenseDTO.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.recurringReimbursementId)
        XCTAssertFalse(legacy.isRecurringReimbursement)
    }

    // MARK: - Helpers

    private func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
