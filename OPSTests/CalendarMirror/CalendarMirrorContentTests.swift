import XCTest
@testable import OPS

final class CalendarMirrorContentTests: XCTestCase {

    func test_personalEvent_titleIsRawTitle() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "Dentist")
    }

    func test_personalEvent_emptyTitleFallsBack() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "(Untitled)")
    }

    func test_timeOff_approvedHasTimeOffPrefix() throws {
        let e = makeUserEvent(type: .timeOff, status: .approved, title: "Cottage")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "Time Off — Cottage")
    }

    func test_timeOff_pendingHasPendingPrefix() throws {
        let e = makeUserEvent(type: .timeOff, status: .pending, title: "Cottage")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "[Pending] Cottage")
    }

    func test_timeOff_deniedHasDeniedPrefix() throws {
        let e = makeUserEvent(type: .timeOff, status: .denied, title: "Cottage")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.title, "[Denied] Cottage")
    }

    func test_url_isEventDeepLink() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.url, URL(string: "ops://event/\(e.id)"))
    }

    func test_canonicalHash_isStableForSameContent() throws {
        let e1 = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let e2 = makeUserEvent(type: .personal, status: .none, title: "Dentist", id: e1.id)
        XCTAssertEqual(
            CalendarMirrorContent.payload(for: e1).canonicalHash,
            CalendarMirrorContent.payload(for: e2).canonicalHash
        )
    }

    func test_canonicalHash_changesWhenTitleChanges() throws {
        let e1 = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let e2 = makeUserEvent(type: .personal, status: .none, title: "Dentist 2", id: e1.id)
        XCTAssertNotEqual(
            CalendarMirrorContent.payload(for: e1).canonicalHash,
            CalendarMirrorContent.payload(for: e2).canonicalHash
        )
    }

    func test_body_includesAddressAndNotesAndFooter() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        e.address = "123 Main St"
        e.notes = "Bring forms"
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertTrue(p.body.contains("123 Main St"))
        XCTAssertTrue(p.body.contains("Bring forms"))
        XCTAssertTrue(p.body.contains("// OPS · view in app"))
    }

    func test_body_omitsBlankAddressAndNotes() throws {
        let e = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        let p = CalendarMirrorContent.payload(for: e)
        XCTAssertEqual(p.body, "// OPS · view in app")
    }

    // MARK: - Helpers

    private func makeUserEvent(
        type: CalendarUserEventType,
        status: CalendarUserEventStatus,
        title: String,
        id: String = UUID().uuidString
    ) -> CalendarUserEvent {
        let e = CalendarUserEvent(
            id: id,
            userId: "user-1",
            companyId: "company-1",
            type: type,
            title: title,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_086_400),
            allDay: true
        )
        e.status = status.rawValue
        return e
    }

    // MARK: - Site visits (the reserved third mirror source)

    private func makeBookedVisit(
        scheduledAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
        duration: Int = 90
    ) -> SiteVisit {
        let visit = SiteVisit(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            opportunityId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            companyId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            status: .scheduled,
            scheduledAt: scheduledAt,
            durationMinutes: duration,
            assigneeIds: ["dddddddd-dddd-4ddd-8ddd-dddddddddddd"],
            createdBy: "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        )
        visit.bookedAt = Date(timeIntervalSince1970: 1_789_900_000)
        return visit
    }

    func test_siteVisit_titleCarriesLeadName() throws {
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: makeBookedVisit(),
                leadName: "Dana Whitfield",
                address: "418 Larchmont Ave"
            )
        )
        XCTAssertEqual(p.title, "Site visit — Dana Whitfield")
        XCTAssertEqual(p.source, .siteVisit)
    }

    func test_siteVisit_phaseCMetadataOverridesLegacyTitleAndAddress() throws {
        let visit = makeBookedVisit()
        visit.appointmentTitle = "Call — Dana Whitfield"
        visit.appointmentLocation = "Microsoft Teams"
        let payload = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: visit,
                leadName: "Dana Whitfield",
                address: "418 Larchmont Ave"
            )
        )
        XCTAssertEqual(payload.title, "Call — Dana Whitfield")
        XCTAssertEqual(payload.body, "Microsoft Teams\n// OPS · view in app")
    }

    func test_siteVisit_windowSpansDurationFromScheduledAt() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: makeBookedVisit(scheduledAt: start, duration: 90),
                leadName: "Dana Whitfield",
                address: nil
            )
        )
        XCTAssertEqual(p.startDate, start)
        XCTAssertEqual(p.endDate, start.addingTimeInterval(90 * 60))
        XCTAssertFalse(p.isAllDay)
    }

    func test_siteVisit_bodyCarriesAddressAndFooter() throws {
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: makeBookedVisit(),
                leadName: "Dana Whitfield",
                address: "418 Larchmont Ave"
            )
        )
        XCTAssertEqual(p.body, "418 Larchmont Ave\n// OPS · view in app")
    }

    func test_siteVisit_urlIsLeadDeepLink() throws {
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: makeBookedVisit(),
                leadName: "Dana Whitfield",
                address: nil
            )
        )
        XCTAssertEqual(p.url.absoluteString, "ops://leads/cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    }

    func test_siteVisit_walkUpResolvesNil() {
        let visit = makeBookedVisit()
        visit.bookedAt = nil
        XCTAssertNil(
            CalendarMirrorContent.payload(for: visit, leadName: "Dana", address: nil)
        )
    }
}
