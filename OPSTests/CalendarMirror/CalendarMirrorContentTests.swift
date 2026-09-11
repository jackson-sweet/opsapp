import XCTest
import EventKit
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
        let visit = makeBookedVisit()
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(for: visit)
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
                presentation: makePresentation(for: visit)
            )
        )
        XCTAssertEqual(payload.title, "Call — Dana Whitfield")
        XCTAssertEqual(
            payload.body,
            "Microsoft Teams\nConfirm access with the site supervisor.\n// OPS · view in app"
        )
    }

    func test_siteVisit_windowSpansDurationFromScheduledAt() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let visit = makeBookedVisit(scheduledAt: start, duration: 90)
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(for: visit, address: nil)
            )
        )
        XCTAssertEqual(p.startDate, start)
        XCTAssertEqual(p.endDate, start.addingTimeInterval(90 * 60))
        XCTAssertFalse(p.isAllDay)
    }

    func test_siteVisit_bodyCarriesAddressDetailsAndFooter() throws {
        let visit = makeBookedVisit()
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(for: visit)
            )
        )
        XCTAssertEqual(
            p.body,
            "418 Larchmont Ave\nConfirm access with the site supervisor.\n// OPS · view in app"
        )
    }

    func test_siteVisit_urlIsLeadDeepLink() throws {
        let visit = makeBookedVisit()
        let p = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(for: visit, address: nil)
            )
        )
        XCTAssertEqual(p.url.absoluteString, "ops://leads/cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    }

    func test_siteVisit_hashChangesWhenResolvedDetailChanges() throws {
        let visit = makeBookedVisit()
        let first = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(
                    for: visit,
                    detail: "Confirm access with the site supervisor."
                )
            )
        )
        let second = try XCTUnwrap(
            CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(
                    for: visit,
                    detail: "Measure the damaged front stair rail."
                )
            )
        )

        XCTAssertNotEqual(first.canonicalHash, second.canonicalHash)
    }

    func test_siteVisit_walkUpResolvesNil() {
        let visit = makeBookedVisit()
        visit.bookedAt = nil
        XCTAssertNil(
            CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(for: visit)
            )
        )
    }

    func test_siteVisit_locationUsesCanonicalThenLeadThenVisitAddress() throws {
        let cases: [(canonical: String?, lead: String?, snapshot: String?, expected: String?)] = [
            (" Microsoft Teams \n", "418 Larchmont Ave", "903 Collinson St", "Microsoft Teams"),
            (" \n", " 418 Larchmont Ave \n", "903 Collinson St", "418 Larchmont Ave"),
            (nil, " \n", " 903 Collinson St \n", "903 Collinson St"),
            (nil, nil, nil, nil),
            (" \n", " \n", " \n", nil)
        ]

        for (index, row) in cases.enumerated() {
            let visit = makeBookedVisit()
            visit.appointmentLocation = row.canonical
            visit.address = row.snapshot
            let payload = try XCTUnwrap(CalendarMirrorContent.payload(
                for: visit,
                presentation: makePresentation(for: visit, address: row.lead)
            ))
            XCTAssertEqual(payload.location, row.expected, "Location precedence case \(index)")
        }
    }

    func test_personalEvent_locationIsNormalizedSeparatelyFromNotes() {
        let event = makeUserEvent(type: .personal, status: .none, title: "Dentist")
        event.address = " 123 Main St \n"
        event.notes = "Bring forms"
        XCTAssertEqual(CalendarMirrorContent.payload(for: event).location, "123 Main St")

        event.address = " \n"
        XCTAssertNil(CalendarMirrorContent.payload(for: event).location)
    }

    func test_task_locationUsesResolvedProjectAddress() throws {
        let task = ProjectTask(
            id: "task-1", projectId: "project-1", taskTypeId: "type-1", companyId: "company-1"
        )
        task.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        task.endDate = Date(timeIntervalSince1970: 1_800_086_400)
        let payload = try XCTUnwrap(CalendarMirrorContent.payload(
            for: task,
            projectDisplayName: "Front stairs",
            taskTypeDisplay: "Install",
            address: " 123 Main St \n"
        ))
        XCTAssertEqual(payload.location, "123 Main St")
    }

    func test_canonicalHash_tracksLocationEvenWhenNotesAreUnchanged() {
        let first = makeLocationPayload("418 Larchmont Ave")
        let repeated = makeLocationPayload("418 Larchmont Ave")
        let moved = makeLocationPayload("903 Collinson St")
        let removed = makeLocationPayload(nil)

        XCTAssertEqual(first.canonicalHash, repeated.canonicalHash)
        XCTAssertNotEqual(first.canonicalHash, moved.canonicalHash)
        XCTAssertNotEqual(first.canonicalHash, removed.canonicalHash)
    }

    @MainActor
    func test_eventMapping_writesNativeLocationWithoutDuplicatingAddressInNotes() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let visit = makeBookedVisit()
        let payload = try XCTUnwrap(CalendarMirrorContent.payload(
            for: visit,
            presentation: makePresentation(for: visit)
        ))

        CalendarMirrorEventMapping.apply(payload: payload, to: event)

        XCTAssertEqual(event.location, "418 Larchmont Ave")
        XCTAssertEqual(event.notes, "418 Larchmont Ave\nConfirm access with the site supervisor.\n// OPS · view in app")
        XCTAssertEqual(event.title, "Site visit — Dana Whitfield")
        XCTAssertEqual(event.url?.absoluteString, "ops://leads/cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        XCTAssertFalse(CalendarMirrorEventMapping.needsUpdate(
            payload: payload, event: event, contentHash: payload.canonicalHash
        ))
    }

    @MainActor
    func test_eventMapping_repairsAnOldBlankLocationWithTheSameStoredHash() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let payload = makeLocationPayload("418 Larchmont Ave")
        CalendarMirrorEventMapping.apply(payload: payload, to: event)
        // Existing app versions wrote every other field but left location empty.
        event.location = nil

        XCTAssertTrue(CalendarMirrorEventMapping.needsUpdate(
            payload: payload, event: event, contentHash: payload.canonicalHash
        ))
        CalendarMirrorEventMapping.apply(payload: payload, to: event)
        XCTAssertEqual(event.location, "418 Larchmont Ave")
        XCTAssertFalse(CalendarMirrorEventMapping.needsUpdate(
            payload: payload, event: event, contentHash: payload.canonicalHash
        ))
    }

    @MainActor
    func test_eventMapping_revertsLocationDriftWithoutChangingNotes() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let payload = makeLocationPayload("418 Larchmont Ave")
        CalendarMirrorEventMapping.apply(payload: payload, to: event)
        event.location = "Wrong address"

        XCTAssertTrue(CalendarMirrorEventMapping.needsUpdate(
            payload: payload, event: event, contentHash: payload.canonicalHash
        ))
        CalendarMirrorEventMapping.apply(payload: payload, to: event)
        XCTAssertEqual(event.location, "418 Larchmont Ave")
        XCTAssertEqual(event.notes, "Confirm access.\n// OPS · view in app")
    }

    @MainActor
    func test_eventMapping_replacesThenClearsRemovedLocation() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let first = makeLocationPayload("418 Larchmont Ave")
        CalendarMirrorEventMapping.apply(payload: first, to: event)

        let moved = makeLocationPayload("903 Collinson St")
        XCTAssertTrue(CalendarMirrorEventMapping.needsUpdate(
            payload: moved, event: event, contentHash: first.canonicalHash
        ))
        CalendarMirrorEventMapping.apply(payload: moved, to: event)
        XCTAssertEqual(event.location, "903 Collinson St")

        let removed = makeLocationPayload(nil)
        XCTAssertTrue(CalendarMirrorEventMapping.needsUpdate(
            payload: removed, event: event, contentHash: moved.canonicalHash
        ))
        CalendarMirrorEventMapping.apply(payload: removed, to: event)
        XCTAssertTrue((event.location ?? "").isEmpty)
        XCTAssertEqual(event.notes, "Confirm access.\n// OPS · view in app")
        XCTAssertFalse(CalendarMirrorEventMapping.needsUpdate(
            payload: removed, event: event, contentHash: removed.canonicalHash
        ))
    }

    @MainActor
    func test_eventMapping_refreshesTheStoredHashAfterPayloadUpgrade() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let payload = makeLocationPayload("418 Larchmont Ave")
        CalendarMirrorEventMapping.apply(payload: payload, to: event)

        XCTAssertTrue(CalendarMirrorEventMapping.needsUpdate(
            payload: payload, event: event, contentHash: "legacy-hash-without-location"
        ))
    }

    private func makeLocationPayload(_ location: String?) -> MirroredEventPayload {
        MirroredEventPayload(
            opsId: "visit-1",
            source: .siteVisit,
            title: "Site visit — Dana Whitfield",
            body: "Confirm access.\n// OPS · view in app",
            location: location,
            url: URL(string: "ops://leads/lead-1")!,
            isAllDay: false,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600)
        )
    }

    private func makePresentation(
        for visit: SiteVisit,
        address: String? = "418 Larchmont Ave",
        detail: String? = "Confirm access with the site supervisor."
    ) -> CalendarSiteVisitPresentation {
        CalendarSiteVisitPresentation(
            visit: visit,
            leadDetails: CalendarSiteVisitLeadDetails(
                opportunityId: visit.opportunityId!,
                companyId: visit.companyId,
                contactName: "Dana Whitfield",
                title: "Estimate",
                address: address,
                agentSummary: detail,
                leadDescription: nil
            )
        )
    }
}
