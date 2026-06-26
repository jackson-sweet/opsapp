import XCTest
@testable import OPSDecks

final class DecksProvisioningPayloadTests: XCTestCase {
    func testProvisioningPayloadUsesDeckOnlySourceAndDoesNotContainOPSSubscriptionState() throws {
        let request = DecksCompanyProvisioningRequest(
            firebaseUID: "firebase-123",
            email: "deck@example.com",
            displayName: "Deck Operator"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"source_app\":\"ops_decks\""))
        XCTAssertFalse(json.contains("subscription_status"))
        XCTAssertFalse(json.contains("trial_end_date"))
    }

    func testProvisioningResponseDecodesDeckOnlyCompanyIdentity() throws {
        let json = """
        {
          "company_id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "role": "admin",
          "subscription_plan": "decks"
        }
        """

        let response = try JSONDecoder().decode(
            DecksCompanyProvisioningResponse.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(response.companyId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(response.userId, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(response.role, "admin")
        XCTAssertEqual(response.subscriptionPlan, "decks")
    }
}
