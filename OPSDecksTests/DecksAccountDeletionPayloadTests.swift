import XCTest
@testable import OPSDecks

final class DecksAccountDeletionPayloadTests: XCTestCase {
    func testDeletionPayloadContainsFirebaseAndCompanyOnly() throws {
        let request = DecksAccountDeletionRequest(
            firebaseUID: "firebase-123",
            companyId: "company-123"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"firebase_uid\":\"firebase-123\""))
        XCTAssertTrue(json.contains("\"company_id\":\"company-123\""))
        XCTAssertFalse(json.contains("subscription_status"))
        XCTAssertFalse(json.contains("trial_end_date"))
    }

    func testDeletionReceiptDecodesReceiptAndTimestamp() throws {
        let json = """
        {
          "receipt_id": "deletion-123",
          "deleted_at": "2026-06-26T16:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let receipt = try decoder.decode(
            DecksAccountDeletionReceipt.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )
        let expectedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-06-26T16:00:00Z")
        )

        XCTAssertEqual(receipt.receiptId, "deletion-123")
        XCTAssertEqual(receipt.deletedAt, expectedDate)
    }
}
