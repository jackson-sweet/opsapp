import XCTest
@testable import OPSDecks

final class DecksEntitlementProviderTests: XCTestCase {
    func testRevenueCatDeckProEntitlementUnlocksPro() {
        let entitlement = DecksEntitlementResolver.entitlement(
            activeRevenueCatEntitlementIds: ["deck_pro"]
        )

        XCTAssertEqual(entitlement, .pro)
    }

    func testMissingRevenueCatDeckProEntitlementUsesFreeLimit() {
        let entitlement = DecksEntitlementResolver.entitlement(
            activeRevenueCatEntitlementIds: ["ops_full"]
        )

        XCTAssertEqual(entitlement, .free(savedDeckLimit: 1))
    }

    func testProviderRetainsCachedEntitlementWhenRevenueCatRefreshFails() async {
        let reader = FailingDecksRevenueCatCustomerInfoReader()
        let provider = DecksRevenueCatEntitlementProvider(
            customerInfoReader: reader,
            cachedEntitlement: .pro
        )

        let entitlement = await provider.refreshEntitlement()

        XCTAssertEqual(entitlement, .pro)
    }

    func testSubscriptionMirrorRowDecodesDedicatedDeckSubscriptionContract() throws {
        let json = """
        {
          "company_id": "company-123",
          "revenuecat_customer_id": "firebase-123",
          "entitlement": "deck_pro",
          "product_id": "ops_decks_pro_monthly",
          "status": "active",
          "store": "app_store",
          "expires_at": "2026-07-26T16:00:00Z",
          "last_event_at": "2026-06-26T16:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let row = try decoder.decode(
            DeckSubscriptionMirrorRow.self,
            from: try XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertEqual(row.companyId, "company-123")
        XCTAssertEqual(row.revenueCatCustomerId, "firebase-123")
        XCTAssertEqual(row.entitlement, "deck_pro")
        XCTAssertEqual(row.productId, "ops_decks_pro_monthly")
        XCTAssertEqual(row.status, .active)
        XCTAssertEqual(row.store, "app_store")
    }

    func testActiveMirrorUnlocksProAndExpiredMirrorFallsBackToFree() {
        let activeRow = DeckSubscriptionMirrorRow(
            companyId: "company-123",
            revenueCatCustomerId: "firebase-123",
            entitlement: "deck_pro",
            productId: "ops_decks_pro_monthly",
            status: .active,
            store: "app_store",
            expiresAt: nil,
            lastEventAt: Date(timeIntervalSince1970: 0)
        )
        let expiredRow = DeckSubscriptionMirrorRow(
            companyId: "company-123",
            revenueCatCustomerId: "firebase-123",
            entitlement: "deck_pro",
            productId: "ops_decks_pro_monthly",
            status: .expired,
            store: "app_store",
            expiresAt: nil,
            lastEventAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            DecksEntitlementResolver.entitlement(subscriptionMirror: activeRow),
            .pro
        )
        XCTAssertEqual(
            DecksEntitlementResolver.entitlement(subscriptionMirror: expiredRow),
            .free(savedDeckLimit: 1)
        )
    }
}

private final class FailingDecksRevenueCatCustomerInfoReader: DecksRevenueCatCustomerInfoReading {
    func activeEntitlementIdentifiers() async throws -> Set<String> {
        throw TestError.offline
    }
}

private enum TestError: Error {
    case offline
}
