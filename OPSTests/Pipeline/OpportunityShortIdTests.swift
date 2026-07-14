//
//  OpportunityShortIdTests.swift
//  OPSTests
//
//  One lead number everywhere: hero, edit sheet, convert sheet all render
//  Opportunity.shortDisplayId ("L-" + last-6 of the un-hyphenated uuid,
//  uppercased). Guards against a surface drifting back to the old first-6
//  variant, which read as a different id than the hero's.
//

import XCTest
@testable import OPS

final class OpportunityShortIdTests: XCTestCase {

    func test_ShortDisplayId_isLastSixOfUnhyphenatedUUID_uppercased() {
        let opp = Opportunity(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "Helen Calloway"
        )

        XCTAssertEqual(opp.shortIdSuffix, "C6D7E8F9".suffix(6).uppercased()) // D7E8F9
        XCTAssertEqual(opp.shortIdSuffix, "D7E8F9")
        XCTAssertEqual(opp.shortDisplayId, "L-D7E8F9")
    }

    func test_ShortDisplayId_toleratesNonUUIDIds() {
        let opp = Opportunity(
            id: "demo-lead",
            companyId: "test-company-001",
            contactName: "Demo"
        )

        // No crash, stable output: last 6 of "demolead" uppercased.
        XCTAssertEqual(opp.shortIdSuffix, "MOLEAD")
        XCTAssertEqual(opp.shortDisplayId, "L-MOLEAD")
    }
}
