//
//  PhoneNumberDedupTests.swift
//  OPSTests
//
//  Around-call lead dedup (feature 154cb8a3). Normalization + lead matching are
//  the gate that keeps a logged call from spawning a duplicate lead, so they're
//  covered exhaustively.
//

import XCTest
@testable import OPS

final class PhoneNumberDedupTests: XCTestCase {

    // MARK: - normalize

    func test_normalize_stripsFormatting() {
        XCTAssertEqual(PhoneNumber.normalize("(604) 555-0142"), "6045550142")
        XCTAssertEqual(PhoneNumber.normalize("604-555-0142"), "6045550142")
        XCTAssertEqual(PhoneNumber.normalize("604.555.0142"), "6045550142")
        XCTAssertEqual(PhoneNumber.normalize("604 555 0142"), "6045550142")
    }

    func test_normalize_dropsNANPCountryCode() {
        XCTAssertEqual(PhoneNumber.normalize("+1 (604) 555-0142"), "6045550142")
        XCTAssertEqual(PhoneNumber.normalize("16045550142"), "6045550142")
        XCTAssertEqual(PhoneNumber.normalize("1-604-555-0142"), "6045550142")
    }

    func test_normalize_tenAndElevenDigitVariantsAgree() {
        XCTAssertEqual(
            PhoneNumber.normalize("6045550142"),
            PhoneNumber.normalize("+16045550142")
        )
    }

    func test_normalize_doesNotDropLeadingNonOneOnElevenDigits() {
        // 11 digits not starting with 1 is left intact (no false country-code strip).
        XCTAssertEqual(PhoneNumber.normalize("60455501429"), "60455501429")
    }

    func test_normalize_emptyAndNilAndPunctuationOnly() {
        XCTAssertNil(PhoneNumber.normalize(nil))
        XCTAssertNil(PhoneNumber.normalize(""))
        XCTAssertNil(PhoneNumber.normalize("   "))
        XCTAssertNil(PhoneNumber.normalize("()- +"))
    }

    func test_sameNumber() {
        XCTAssertTrue(PhoneNumber.sameNumber("(604) 555-0142", "+1 604 555 0142"))
        XCTAssertFalse(PhoneNumber.sameNumber("604-555-0142", "604-555-9999"))
        XCTAssertFalse(PhoneNumber.sameNumber(nil, "604-555-0142"))
        XCTAssertFalse(PhoneNumber.sameNumber("604-555-0142", ""))
    }

    // MARK: - matchLead

    private func candidate(
        id: String = UUID().uuidString,
        phone: String?,
        name: String = "Test",
        recency: Date = Date()
    ) -> LeadPhoneMatch {
        LeadPhoneMatch(id: id, contactName: name, stageName: "new_lead", phone: phone, recency: recency)
    }

    func test_matchLead_matchesAcrossFormatting() {
        let target = candidate(id: "match", phone: "604-555-0142")
        let other = candidate(id: "other", phone: "778-555-9999")
        let found = OpportunityRepository.matchLead(phone: "+1 (604) 555-0142", candidates: [other, target])
        XCTAssertEqual(found?.id, "match")
    }

    func test_matchLead_returnsNilWhenNoMatch() {
        let candidates = [candidate(phone: "604-555-0142"), candidate(phone: nil)]
        XCTAssertNil(OpportunityRepository.matchLead(phone: "250-555-1111", candidates: candidates))
    }

    func test_matchLead_ignoresLeadsWithoutAPhone() {
        let noPhone = candidate(id: "nophone", phone: nil)
        XCTAssertNil(OpportunityRepository.matchLead(phone: "6045550142", candidates: [noPhone]))
    }

    func test_matchLead_prefersMostRecentlyActive() {
        let now = Date()
        let stale = candidate(id: "stale", phone: "604-555-0142", recency: now.addingTimeInterval(-86_400))
        let fresh = candidate(id: "fresh", phone: "16045550142", recency: now)
        let found = OpportunityRepository.matchLead(phone: "604 555 0142", candidates: [stale, fresh])
        XCTAssertEqual(found?.id, "fresh")
    }

    func test_matchLead_blankTargetReturnsNil() {
        let candidates = [candidate(phone: "604-555-0142")]
        XCTAssertNil(OpportunityRepository.matchLead(phone: "", candidates: candidates))
    }
}
