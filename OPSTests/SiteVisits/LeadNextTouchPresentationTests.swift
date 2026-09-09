//
//  LeadNextTouchPresentationTests.swift
//  OPSTests
//
//  The dossier's NEXT TOUCH cell.
//
//  It used to prefer a booked site visit over the follow-up date (bug
//  a218009e), because this 1/3-width cell was then the ONLY place on the
//  dossier a standing appointment appeared. Bug 52cc8dae gave the appointment
//  its own banner directly under the header — full day and time, plus
//  START · REBOOK · CANCEL — so the cell went back to the one thing it can say
//  that the banner cannot: whether a follow-up is booked behind the visit.
//  These tests pin that rule, including the case that used to be a visit.
//

import XCTest
@testable import OPS

final class LeadNextTouchPresentationTests: XCTestCase {

    private let calendar = Calendar.current

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testUnsetWhenNothingIsScheduled() {
        XCTAssertEqual(
            LeadNextTouchPresentation.resolve(nextFollowUpAt: nil, now: date(1, 8)),
            .unset
        )
    }

    func testFollowUpPrintsDayAndDate() {
        let result = LeadNextTouchPresentation.resolve(
            nextFollowUpAt: date(6, 9), now: date(1, 8)
        )
        guard case .followUp(let day, let dateToken) = result else {
            return XCTFail("Expected followUp, got \(result)")
        }
        XCTAssertEqual(day.count, 3)          // EEE
        XCTAssertEqual(dateToken, "SEP 6")
    }

    /// A lead can hold both an appointment and a later nudge. The cell states
    /// the NUDGE — the appointment is on the banner above it, in full, and
    /// repeating it here truncated to `VISIT · 6:4…` told the operator nothing
    /// they had not just read (bug 52cc8dae).
    func testTheFollowUpStandsEvenWhenAVisitIsBooked() {
        let result = LeadNextTouchPresentation.resolve(
            nextFollowUpAt: date(8, 9), now: date(1, 8)
        )
        guard case .followUp(_, let dateToken) = result else {
            return XCTFail("Expected followUp, got \(result)")
        }
        XCTAssertEqual(dateToken, "SEP 8")
    }

    /// And with no nudge on file the cell is honestly empty — an em dash,
    /// never a borrowed appointment.
    func testNoFollowUpReadsAsUnsetRatherThanBorrowingTheVisit() {
        XCTAssertEqual(
            LeadNextTouchPresentation.resolve(nextFollowUpAt: nil, now: date(1, 8)),
            .unset
        )
    }
}
