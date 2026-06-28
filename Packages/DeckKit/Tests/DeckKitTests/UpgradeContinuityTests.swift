import XCTest
@testable import DeckKit

final class UpgradeContinuityTests: XCTestCase {
    func testDeckOnlyCompanyRoutesOpsAppToUpgrade() {
        XCTAssertTrue(
            UpgradeContinuity.opsAppShouldRouteToUpgrade(
                for: CompanyOriginInfo(
                    id: "company-123",
                    subscriptionPlan: "decks"
                )
            )
        )
        XCTAssertFalse(
            UpgradeContinuity.opsAppShouldRouteToUpgrade(
                for: CompanyOriginInfo(
                    id: "company-123",
                    subscriptionPlan: "pro"
                )
            )
        )
    }

    func testConversionPlanPreservesCompanyAndDeckDesigns() {
        let plan = UpgradeContinuity.opsCompanyConversion(
            from: CompanyOriginInfo(
                id: "company-123",
                subscriptionPlan: "decks"
            ),
            targetSubscriptionPlan: "trial"
        )

        XCTAssertEqual(plan.companyId, "company-123")
        XCTAssertEqual(plan.currentSubscriptionPlan, "decks")
        XCTAssertEqual(plan.targetSubscriptionPlan, "trial")
        XCTAssertTrue(plan.preservesCompany)
        XCTAssertTrue(plan.preservesDeckDesigns)
        XCTAssertTrue(plan.shouldConvert)
        XCTAssertNil(plan.blockedReason)
    }

    func testConversionPlanBlocksAlreadyFullOpsCompany() {
        let plan = UpgradeContinuity.opsCompanyConversion(
            from: CompanyOriginInfo(
                id: "company-123",
                subscriptionPlan: "pro"
            ),
            targetSubscriptionPlan: "trial"
        )

        XCTAssertEqual(plan.companyId, "company-123")
        XCTAssertNil(plan.targetSubscriptionPlan)
        XCTAssertFalse(plan.shouldConvert)
        XCTAssertEqual(plan.blockedReason, .notDeckOnlyCompany)
    }

    func testConversionPlanBlocksDeckTargetPlan() {
        let plan = UpgradeContinuity.opsCompanyConversion(
            from: CompanyOriginInfo(
                id: "company-123",
                subscriptionPlan: "decks"
            ),
            targetSubscriptionPlan: "decks"
        )

        XCTAssertEqual(plan.companyId, "company-123")
        XCTAssertNil(plan.targetSubscriptionPlan)
        XCTAssertFalse(plan.shouldConvert)
        XCTAssertEqual(plan.blockedReason, .invalidTargetSubscriptionPlan)
    }
}
