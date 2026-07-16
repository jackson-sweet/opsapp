//
//  PhoneContactSearchTests.swift
//  OPSTests
//
//  Bug 388663d4 — regression coverage for blending device contacts into the
//  client picker: substring/phone/email matching, and the "already in OPS"
//  dedupe that decides which contacts earn the "IN CONTACTS" badge.
//

import XCTest
@testable import OPS

final class PhoneContactSearchTests: XCTestCase {

    // MARK: - Suggestion normalization

    func testSuggestionNormalizesPhoneAndEmailKeys() {
        let suggestion = PhoneContactSuggestion(
            id: "1",
            displayName: "Maya Stone",
            firstName: "Maya",
            lastName: "Stone",
            subtitle: "(555) 123-4567",
            phones: ["(555) 123-4567"],
            emails: ["Maya.Stone@Example.com"]
        )
        XCTAssertEqual(suggestion.nameKey, "maya stone")
        XCTAssertEqual(suggestion.phoneKeys, ["5551234567"])
        XCTAssertEqual(suggestion.emailKeys, ["maya.stone@example.com"])
        XCTAssertEqual(suggestion.subtitle, "(555) 123-4567")
    }

    // MARK: - matching

    func testMatchingByNameSubstringIsCaseInsensitive() {
        let list = [sug("1", "Maya Stone"), sug("2", "Bob Vance")]
        XCTAssertEqual(PhoneContactSearch.matching(list, query: "may").map(\.id), ["1"])
        XCTAssertEqual(PhoneContactSearch.matching(list, query: "STONE").map(\.id), ["1"])
    }

    func testMatchingByPhoneIgnoresFormatting() {
        let list = [sug("1", "Maya Stone", phones: ["(555) 123-4567"])]
        XCTAssertEqual(PhoneContactSearch.matching(list, query: "5551234").map(\.id), ["1"])
        XCTAssertEqual(PhoneContactSearch.matching(list, query: "555 123").map(\.id), ["1"])
    }

    func testMatchingByEmail() {
        let list = [sug("1", "Maya Stone", emails: ["maya@example.com"])]
        XCTAssertEqual(PhoneContactSearch.matching(list, query: "example.com").map(\.id), ["1"])
    }

    func testMatchingEmptyQueryReturnsNothing() {
        let list = [sug("1", "Maya Stone")]
        XCTAssertTrue(PhoneContactSearch.matching(list, query: "   ").isEmpty)
    }

    func testMatchingNonMatchReturnsNothing() {
        let list = [sug("1", "Maya Stone"), sug("2", "Bob Vance")]
        XCTAssertTrue(PhoneContactSearch.matching(list, query: "zzz").isEmpty)
    }

    // MARK: - notInOps dedupe

    func testContactAlreadyInOpsByNameIsFiltered() {
        let identity = ClientIdentityIndex(clients: [
            Client(id: "c1", name: "Maya Stone", companyId: "co")
        ])
        let matches = [sug("1", "Maya Stone"), sug("2", "Bob Vance")]
        XCTAssertEqual(PhoneContactSearch.notInOps(matches, existing: identity).map(\.id), ["2"])
    }

    func testContactAlreadyInOpsByPhoneIsFiltered() {
        let identity = ClientIdentityIndex(clients: [
            Client(id: "c1", name: "Different Name", phoneNumber: "555-123-4567", companyId: "co")
        ])
        let matches = [sug("1", "Maya Stone", phones: ["(555) 123-4567"])]
        XCTAssertTrue(PhoneContactSearch.notInOps(matches, existing: identity).isEmpty)
    }

    func testContactAlreadyInOpsByEmailIsFiltered() {
        let identity = ClientIdentityIndex(clients: [
            Client(id: "c1", name: "Different", email: "maya@example.com", companyId: "co")
        ])
        let matches = [sug("1", "Maya Stone", emails: ["Maya@Example.com"])]
        XCTAssertTrue(PhoneContactSearch.notInOps(matches, existing: identity).isEmpty)
    }

    func testContactMatchingSubClientIsFiltered() {
        let parent = Client(id: "c1", name: "Canpro Decks", companyId: "co")
        let sub = SubClient(id: "s1", name: "Maya Stone", title: "Estimator")
        sub.phoneNumber = "555-123-4567"
        parent.subClients.append(sub)
        let identity = ClientIdentityIndex(clients: [parent])

        let matches = [sug("1", "Maya Stone", phones: ["(555) 123-4567"])]
        XCTAssertTrue(PhoneContactSearch.notInOps(matches, existing: identity).isEmpty)
    }

    func testDeletedClientDoesNotSuppressContact() {
        let client = Client(id: "c1", name: "Maya Stone", companyId: "co")
        client.deletedAt = Date()
        let identity = ClientIdentityIndex(clients: [client])

        let matches = [sug("1", "Maya Stone")]
        XCTAssertEqual(PhoneContactSearch.notInOps(matches, existing: identity).map(\.id), ["1"])
    }

    func testIntraDeviceDuplicatesCollapse() {
        let identity = ClientIdentityIndex(clients: [])
        let matches = [
            sug("1", "Maya Stone", phones: ["5551234567"]),
            sug("2", "Maya Stone", phones: ["(555) 123-4567"]) // same person, formatted differently
        ]
        XCTAssertEqual(PhoneContactSearch.notInOps(matches, existing: identity).map(\.id), ["1"])
    }

    func testNotInOpsPreservesInputOrder() {
        let identity = ClientIdentityIndex(clients: [])
        let matches = [sug("1", "Zoe Ray"), sug("2", "Amy Lee"), sug("3", "Bob Vance")]
        XCTAssertEqual(PhoneContactSearch.notInOps(matches, existing: identity).map(\.id), ["1", "2", "3"])
    }

    // MARK: - Helpers

    private func sug(_ id: String, _ name: String, phones: [String] = [], emails: [String] = []) -> PhoneContactSuggestion {
        let parts = name.split(separator: " ")
        return PhoneContactSuggestion(
            id: id,
            displayName: name,
            firstName: String(parts.first ?? ""),
            lastName: parts.count > 1 ? String(parts.last!) : "",
            subtitle: phones.first ?? emails.first,
            phones: phones,
            emails: emails
        )
    }
}
