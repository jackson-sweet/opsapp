//
//  LeadsQueryEngineTests.swift
//  OPSTests
//
//  The LEADS console redesign (2026-08-05) moved search, sort, crew filtering,
//  roster resolution and band-state selection out of the view and into one
//  pure engine. These tests are the contract: every rule the console renders
//  is pinned here so the view can stay dumb.
//
//  Fixtures are built on the shipped `Opportunity.preview` factory and widened
//  with a local builder for the fields the factory does not expose (address,
//  email, phone, description, source, exact createdAt).
//

import XCTest
@testable import OPS

/// Ids are fixed rather than random so `shortDisplayId` (last 6 of the
/// un-hyphenated uuid) is a known quantity — several tests assert on it, and
/// the digit-token tests need a lead whose id carries no stray digits.
/// File scope: a default argument cannot reference `Self`.
private let plainLeadId = "00000000-0000-0000-0000-0000000000a1"

final class LeadsQueryEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func lead(
        id: String = plainLeadId,
        contactName: String = "Dana Whitfield",
        title: String? = nil,
        description: String? = nil,
        address: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        source: String? = nil,
        stage: PipelineStage = .quoted,
        estimatedValue: Double? = nil,
        assignedTo: String? = nil,
        createdAt: Date? = nil
    ) -> Opportunity {
        let opp = Opportunity.preview(
            id: id,
            title: title,
            contactName: contactName,
            stage: stage,
            estimatedValue: estimatedValue,
            assignedTo: assignedTo
        )
        opp.descriptionText = description
        opp.address = address
        opp.contactEmail = email
        opp.contactPhone = phone
        opp.source = source
        if let createdAt { opp.createdAt = createdAt }
        return opp
    }

    // MARK: - Controls defaults

    func testControlsDefaultToUrgencyAllCrewNoQuery() {
        let controls = LeadsListControls()
        XCTAssertEqual(controls.query, "")
        XCTAssertEqual(controls.sort, .urgency)
        XCTAssertEqual(controls.crew, .all)
        XCTAssertFalse(controls.isSearching)
    }

    func testControlsIsSearchingIgnoresWhitespaceOnlyQuery() {
        var controls = LeadsListControls()
        controls.query = "   \n "
        XCTAssertFalse(controls.isSearching, "A whitespace-only query must not suspend browse filters")
        controls.query = " dana "
        XCTAssertTrue(controls.isSearching)
    }

    // MARK: - Search matching · fields

    func testMatchesContactName() {
        let lead = lead(contactName: "Dana Whitfield")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "whitfield"))
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "WHIT"))
    }

    /// A lead with no contact name falls back to its title for display — the
    /// engine searches the same string the card shows.
    func testMatchesDisplayNameFallbackWhenContactNameBlank() {
        let lead = lead(contactName: "", title: "Website enquiry — cedar fence")
        XCTAssertEqual(lead.displayContactName, "Website enquiry — cedar fence")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "cedar"))
    }

    func testMatchesTitle() {
        let lead = lead(title: "Roof replacement")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "replacement"))
    }

    func testMatchesDescriptionText() {
        let lead = lead(description: "Needs a quote for the back deck railing")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "railing"))
    }

    func testMatchesAddress() {
        let lead = lead(address: "1440 Beacon Hill Road, Kelowna")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "kelowna"))
    }

    func testMatchesContactEmail() {
        let lead = lead(email: "dana@northgatefitness.com")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "northgate"))
    }

    func testMatchesSource() {
        let lead = lead(source: "referral")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "referral"))
    }

    func testMatchesShortDisplayId() {
        let lead = lead(id: "9f2b7c1e-4a55-4d2e-9b3c-1122ff9911")
        XCTAssertEqual(lead.shortDisplayId, "L-FF9911")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "ff9911"))
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "L-FF9911"))
    }

    func testUnrelatedQueryDoesNotMatch() {
        let lead = lead(contactName: "Dana Whitfield", title: "Roof replacement")
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "furnace"))
    }

    // MARK: - Search matching · folding

    func testMatchIsDiacriticInsensitiveInBothDirections() {
        let accented = lead(contactName: "Ana Muñoz")
        XCTAssertTrue(LeadsQueryEngine.matches(accented, query: "munoz"),
                      "An unaccented query must reach an accented name")

        let plain = lead(contactName: "Ana Munoz")
        XCTAssertTrue(LeadsQueryEngine.matches(plain, query: "Muñoz"),
                      "An accented query must reach an unaccented name")
    }

    // MARK: - Search matching · multi-token AND

    func testMultiTokenQueryRequiresEveryToken() {
        let hit = lead(contactName: "Dana Whitfield", title: "Roof replacement")
        XCTAssertTrue(LeadsQueryEngine.matches(hit, query: "dana roof"))

        let miss = lead(contactName: "Dana Whitfield", title: "Deck rebuild")
        XCTAssertFalse(LeadsQueryEngine.matches(miss, query: "dana roof"),
                       "Every token must hit a field — one match is not enough")
    }

    func testMultiTokenQueryCollapsesExtraWhitespace() {
        let hit = lead(contactName: "Dana Whitfield", title: "Roof replacement")
        XCTAssertTrue(LeadsQueryEngine.matches(hit, query: "  dana   roof \n"))
    }

    // MARK: - Search matching · phone digits

    func testPhoneMatchesThroughFormattingWhenQueryCarriesThreeOrMoreDigits() {
        let lead = lead(contactName: "Pat Donovan", phone: "(555) 123-4567")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "5551234"))
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "555-1234"),
                      "The query's own formatting must be normalised away too")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "1234567"),
                      "A digit run from the middle of the number still matches")
    }

    func testShortDigitTokenDoesNotReachThePhonePath() {
        let lead = lead(contactName: "Pat Donovan", phone: "(555) 123-4567")
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "55"),
                       "Under 3 digits the phone path stays shut — every lead would match otherwise")
    }

    func testPhonePathIsNotConsultedWhenLeadHasNoPhone() {
        let lead = lead(contactName: "Pat Donovan", phone: nil)
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "5551234"))
    }

    func testMixedTokenQueryCombinesTextAndPhone() {
        let lead = lead(contactName: "Pat Donovan", phone: "(555) 123-4567")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "donovan 5551234"))
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "donovan 9998888"))
    }

    // MARK: - Search matching · empty query

    func testEmptyQueryMatchesEveryLead() {
        let a = lead(contactName: "Dana Whitfield")
        let b = lead(id: "11111111-2222-3333-4444-5566778899aa", contactName: "Cedar Ridge HOA")
        for query in ["", "   ", "\n\t"] {
            XCTAssertTrue(LeadsQueryEngine.matches(a, query: query))
            XCTAssertTrue(LeadsQueryEngine.matches(b, query: query))
        }
    }
}
