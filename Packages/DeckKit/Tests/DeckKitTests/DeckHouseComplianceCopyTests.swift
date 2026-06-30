import XCTest
@testable import DeckKit

final class DeckHouseComplianceCopyTests: XCTestCase {
    func test_disclaimerMatchesSectionSixTwoRequirement() {
        XCTAssertEqual(
            DeckHouseComplianceCopy.engineerReviewDisclaimer,
            "This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction."
        )
        XCTAssertTrue(
            DeckHouseComplianceCopy.engineerReviewNotice.contains(
                DeckHouseComplianceCopy.engineerReviewDisclaimer
            )
        )
    }

    func test_attachedLedgerDetailAvoidsPositiveComplianceClaims() {
        let lowercased = DeckHouseComplianceCopy.attachedLedgerDetail.lowercased()

        for forbidden in ["safe", "compliant", "guaranteed", "will pass", "allowed", "accepts"] {
            XCTAssertFalse(lowercased.contains(forbidden))
        }
        XCTAssertTrue(lowercased.contains("no cladding block triggered"))
        XCTAssertTrue(lowercased.contains("freestanding fallback"))
    }
}
