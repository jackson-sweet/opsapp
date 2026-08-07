//
//  LeadDeckTitlePolicyTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

@MainActor
final class LeadDeckTitlePolicyTests: XCTestCase {

    func testLeadAddressBecomesTheExactDeckTitle() {
        let lead = Opportunity.preview(contactName: "Helen Calloway", stage: .quoted)
        lead.address = "  1240 Maple Ave, Vancouver BC  \n"

        XCTAssertEqual(lead.deckDesignTitle, "1240 Maple Ave, Vancouver BC")
    }

    func testMissingLeadAddressKeepsTheSafeExistingFallback() {
        let lead = Opportunity.preview(contactName: "Helen Calloway", stage: .quoted)
        lead.address = " \n "

        XCTAssertEqual(lead.deckDesignTitle, "Helen Calloway")
    }

    func testPreferredLeadTitleOverridesEveryCreationModeFallback() {
        XCTAssertEqual(
            DeckDesignTitlePolicy.resolve(
                preferred: "  1240 Maple Ave  ",
                fallback: "Copy of Recent Deck"
            ),
            "1240 Maple Ave"
        )
    }
}
