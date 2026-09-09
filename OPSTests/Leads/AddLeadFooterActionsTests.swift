//
//  AddLeadFooterActionsTests.swift
//  OPSTests
//
//  Bug 9a49bd47 — "How to book a site visit for an existing client? Or add a
//  lead under existing client".
//
//  The client profile's BOOK VISIT saves a lead and carries straight on into
//  the BOOKING sheet. That is a different follow-on from the LEADS tab's
//  save-then-capture, and the NEW LEAD footer now states which pair of verbs
//  it is offering rather than deciding it inside a view builder — so the sheet
//  cannot grow a third, silently unreachable, combination.
//

import XCTest
@testable import OPS

final class AddLeadFooterActionsTests: XCTestCase {

    /// The plain case: one CTA, SAVE LEAD.
    func testNoFollowOnLeavesOneVerb() {
        XCTAssertEqual(
            AddLeadFooterActions.resolve(offersStartVisit: false, offersBookVisit: false),
            .saveOnly
        )
    }

    /// The LEADS tab: SAVE · VISIT — save, then open the capture.
    func testAStartVisitHostGetsTheCapturePair() {
        XCTAssertEqual(
            AddLeadFooterActions.resolve(offersStartVisit: true, offersBookVisit: false),
            .saveAndVisit
        )
    }

    /// The client profile: SAVE · BOOK — save, then open the booking sheet.
    func testABookVisitHostGetsTheBookingPair() {
        XCTAssertEqual(
            AddLeadFooterActions.resolve(offersStartVisit: false, offersBookVisit: true),
            .saveAndBook
        )
    }

    /// No host offers both. If one ever did, booking wins: putting an
    /// appointment on a calendar is the deliberate act, and a footer with
    /// three CTAs is not a footer.
    func testBookingWinsIfBothAreSomehowOffered() {
        XCTAssertEqual(
            AddLeadFooterActions.resolve(offersStartVisit: true, offersBookVisit: true),
            .saveAndBook
        )
    }
}
