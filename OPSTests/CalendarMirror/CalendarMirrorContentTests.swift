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
}
