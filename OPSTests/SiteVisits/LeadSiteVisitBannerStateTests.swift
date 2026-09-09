//
//  LeadSiteVisitBannerStateTests.swift
//  OPSTests
//
//  Bug 52cc8dae — the booked-visit banner on the lead dossier.
//
//  Two rules carry the whole feature, and both are the kind that go wrong
//  quietly: the banner must be ABSENT unless the lead actually holds an open
//  booking, and START must not be offered for a visit that has not arrived.
//  A banner over a cancelled visit, or a START three days early, would be a
//  worse defect than the missing banner it replaces.
//

import XCTest
@testable import OPS

final class LeadSiteVisitBannerStateTests: XCTestCase {

    /// A Tuesday, mid-morning. Fixed so "same day" and "later today" mean the
    /// same thing on every run.
    private let now = Date(timeIntervalSince1970: 1_788_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Presence

    /// No open booking, no banner. `SiteVisitBookingLookup.openBooking` is the
    /// one definition of "open" — booked, still scheduled, not deleted — so a
    /// completed or cancelled visit reaches this as nil.
    func testNoBookingRendersNothing() {
        XCTAssertEqual(
            LeadSiteVisitBannerState.resolve(scheduledAt: nil, now: now, calendar: calendar),
            .hidden
        )
        XCTAssertNil(
            LeadSiteVisitBannerState.resolve(scheduledAt: nil, now: now, calendar: calendar).token
        )
    }

    // MARK: - START availability

    /// The day has not come. REBOOK and CANCEL still make sense; STARTING a
    /// visit you are not at does not.
    func testALaterDayOffersNoStart() {
        let state = LeadSiteVisitBannerState.resolve(
            scheduledAt: now.addingTimeInterval(4 * 86_400),
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(state.windowOpen)
        XCTAssertNotNil(state.token, "the appointment is still stated — only the verb stands down")
    }

    /// From the morning of the visit day onward — the same today-rule the
    /// appointment sheet and the calendar's branch dialog already use.
    func testTheVisitDayOpensTheWindowEvenBeforeTheHour() {
        let laterToday = now.addingTimeInterval(6 * 3_600)
        XCTAssertTrue(
            LeadSiteVisitBannerState.resolve(
                scheduledAt: laterToday,
                now: now,
                calendar: calendar
            ).windowOpen
        )
    }

    /// An appointment whose time has passed but which nobody closed is still
    /// startable — that is exactly the visit somebody is late for.
    func testAPastAppointmentIsStillStartable() {
        XCTAssertTrue(
            LeadSiteVisitBannerState.resolve(
                scheduledAt: now.addingTimeInterval(-3 * 86_400),
                now: now,
                calendar: calendar
            ).windowOpen
        )
    }

    // MARK: - Token

    /// The banner prints the app's ONE booked-visit token, never a third date
    /// grammar of its own.
    func testTheTokenIsTheSharedBookedToken() {
        let scheduledAt = now.addingTimeInterval(6 * 3_600)
        XCTAssertEqual(
            LeadSiteVisitBannerState.resolve(
                scheduledAt: scheduledAt,
                now: now,
                calendar: calendar
            ).token,
            SiteVisitBookingLookup.bookedToken(for: scheduledAt, now: now, calendar: calendar)
        )
    }

    /// And that token names the day in the operator's terms.
    func testTodayReadsAsToday() {
        let token = LeadSiteVisitBannerState.resolve(
            scheduledAt: now.addingTimeInterval(6 * 3_600),
            now: now,
            calendar: calendar
        ).token
        XCTAssertEqual(token?.hasPrefix("TODAY"), true, "got \(token ?? "nil")")
    }
}
