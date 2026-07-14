//
//  LeadClientMatcherTests.swift
//  OPSTests
//
//  Bug 1d5ab9aa — leads must link to an existing client when one plausibly
//  matches (phone → email → name) and never claim soft-deleted rows or
//  match on garbage keys (short digit runs, empty names).
//

import XCTest
@testable import OPS

final class LeadClientMatcherTests: XCTestCase {

    private func client(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        email: String? = nil,
        phone: String? = nil,
        deleted: Bool = false
    ) -> Client {
        let c = Client(
            id: id,
            name: name,
            email: email,
            phoneNumber: phone,
            address: nil,
            companyId: "11111111-2222-3333-4444-555555555555",
            notes: nil
        )
        if deleted { c.deletedAt = Date() }
        return c
    }

    func test_PhoneMatch_survivesFormattingAndCountryCode() {
        let existing = client(name: "James Boss", phone: "+1 (604) 555-0142")
        let hit = LeadClientMatcher.match(
            in: [existing],
            name: "Jim Boss",
            email: nil,
            phone: "604-555-0142"
        )
        XCTAssertEqual(hit?.id, existing.id)
    }

    func test_ShortDigitRuns_neverMatch() {
        let existing = client(name: "James Boss", phone: "604-555-0142")
        let hit = LeadClientMatcher.match(
            in: [existing],
            name: "Someone Else",
            email: nil,
            phone: "0142"
        )
        XCTAssertNil(hit)
    }

    func test_EmailMatch_caseInsensitive() {
        let existing = client(name: "James Boss", email: "james@bosscontracting.ca")
        let hit = LeadClientMatcher.match(
            in: [existing],
            name: "J. Boss",
            email: "James@BossContracting.CA",
            phone: nil
        )
        XCTAssertEqual(hit?.id, existing.id)
    }

    func test_NameMatch_trimsAndIgnoresCase() {
        let existing = client(name: "James Boss")
        let hit = LeadClientMatcher.match(
            in: [existing],
            name: "  james boss ",
            email: nil,
            phone: nil
        )
        XCTAssertEqual(hit?.id, existing.id)
    }

    func test_PhoneOutranksEmailAndName() {
        let byPhone = client(name: "Different Name", phone: "604-555-0142")
        let byEmail = client(name: "Also Different", email: "james@x.com")
        let byName  = client(name: "James Boss")
        let hit = LeadClientMatcher.match(
            in: [byName, byEmail, byPhone],
            name: "James Boss",
            email: "james@x.com",
            phone: "(604) 555 0142"
        )
        XCTAssertEqual(hit?.id, byPhone.id)
    }

    func test_SoftDeletedClients_neverMatch() {
        let deleted = client(name: "James Boss", phone: "604-555-0142", deleted: true)
        let hit = LeadClientMatcher.match(
            in: [deleted],
            name: "James Boss",
            email: nil,
            phone: "604-555-0142"
        )
        XCTAssertNil(hit)
    }

    func test_NoSignals_noMatch() {
        let existing = client(name: "James Boss", email: "j@x.com", phone: "6045550142")
        let hit = LeadClientMatcher.match(in: [existing], name: "  ", email: "", phone: "12")
        XCTAssertNil(hit)
    }
}
