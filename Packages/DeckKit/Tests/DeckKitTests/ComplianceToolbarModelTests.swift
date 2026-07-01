import XCTest
@testable import DeckKit

final class ComplianceToolbarModelTests: XCTestCase {
    func testLightCapabilitiesShowSingleComplianceUpsellEntry() {
        let entries = DeckComplianceToolbarModel.entries(for: .light)

        XCTAssertEqual(entries.map(\.kind), [.opsDecksProUpsell])
        XCTAssertEqual(entries.first?.title, "Available in OPS Decks Pro")
        XCTAssertEqual(entries.first?.subtitle, "Open the standalone app for permit tools")
        XCTAssertEqual(entries.filter(\.isUpsell).count, 1)
    }

    func testFullCapabilitiesShowCompliancePermitAndReviewEntries() {
        let entries = DeckComplianceToolbarModel.entries(for: .full)

        XCTAssertEqual(entries.map(\.kind), [
            .complianceReport,
            .asBuiltAudit,
            .permitPlanSet,
            .peStamp,
        ])
        XCTAssertFalse(entries.contains { $0.isUpsell })
    }
}
