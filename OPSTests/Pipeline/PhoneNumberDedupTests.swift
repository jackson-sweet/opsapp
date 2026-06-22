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

    private func opp(
        id: String = UUID().uuidString,
        phone: String?,
        lastActivityAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> Opportunity {
        let o = Opportunity(
            id: id,
            companyId: "co",
            contactName: "Test",
            stage: .newLead,
            stageEnteredAt: Date()
        )
        o.contactPhone = phone
        o.lastActivityAt = lastActivityAt
        o.deletedAt = deletedAt
        return o
    }

    func test_matchLead_matchesAcrossFormatting() {
        let target = opp(id: "match", phone: "604-555-0142")
        let other = opp(id: "other", phone: "778-555-9999")
        let found = OpportunityRepository.matchLead(phone: "+1 (604) 555-0142", candidates: [other, target])
        XCTAssertEqual(found?.id, "match")
    }

    func test_matchLead_returnsNilWhenNoMatch() {
        let candidates = [opp(phone: "604-555-0142"), opp(phone: nil)]
        XCTAssertNil(OpportunityRepository.matchLead(phone: "250-555-1111", candidates: candidates))
    }

    func test_matchLead_ignoresDeletedLeads() {
        let deleted = opp(id: "deleted", phone: "604-555-0142", deletedAt: Date())
        XCTAssertNil(OpportunityRepository.matchLead(phone: "6045550142", candidates: [deleted]))
    }

    func test_matchLead_prefersMostRecentlyActive() {
        let now = Date()
        let stale = opp(id: "stale", phone: "604-555-0142", lastActivityAt: now.addingTimeInterval(-86_400))
        let fresh = opp(id: "fresh", phone: "16045550142", lastActivityAt: now)
        let found = OpportunityRepository.matchLead(phone: "604 555 0142", candidates: [stale, fresh])
        XCTAssertEqual(found?.id, "fresh")
    }

    func test_matchLead_blankTargetReturnsNil() {
        let candidates = [opp(phone: "604-555-0142")]
        XCTAssertNil(OpportunityRepository.matchLead(phone: "", candidates: candidates))
    }
}
