//
//  SiteVisitLeadSearchAutofillTests.swift
//  OPSTests
//
//  Search-field extraction for the on-site site-visit quick-start flow.
//

import XCTest
@testable import OPS

final class SiteVisitLeadSearchAutofillTests: XCTestCase {
    func test_nameSearchAutofillsContactNameOnly() {
        let autofill = SiteVisitLeadSearchAutofill.make(from: "Helen Calloway")

        XCTAssertEqual(autofill.contactName, "Helen Calloway")
        XCTAssertNil(autofill.phone)
        XCTAssertNil(autofill.email)
        XCTAssertNil(autofill.address)
    }

    func test_emailPhoneAndAddressSearchAutofillsSeparateLeadFields() {
        let autofill = SiteVisitLeadSearchAutofill.make(
            from: "Helen Calloway helen@example.com 604-555-0142 1100 Maple Ave"
        )

        XCTAssertEqual(autofill.contactName, "Helen Calloway")
        XCTAssertEqual(autofill.email, "helen@example.com")
        XCTAssertEqual(autofill.phone, "604-555-0142")
        XCTAssertEqual(autofill.address, "1100 Maple Ave")
    }

    func test_addressOnlySearchDoesNotBecomeContactName() {
        let autofill = SiteVisitLeadSearchAutofill.make(from: "225 Dockside Rd")

        XCTAssertNil(autofill.contactName)
        XCTAssertEqual(autofill.address, "225 Dockside Rd")
    }
}
