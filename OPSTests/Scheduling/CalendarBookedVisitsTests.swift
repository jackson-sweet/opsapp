import XCTest
@testable import OPS

/// The calendar's third source: which booked visits render, for whom, on
/// which day. Pure statics on CalendarViewModel so the rules are provable
/// without a DataController or a live store.
final class CalendarBookedVisitsTests: XCTestCase {
    private let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let me = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    private let mate = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"

    private func visit(
        id: String = UUID().uuidString.lowercased(),
        status: SiteVisitStatus = .scheduled,
        booked: Bool = true,
        assignees: [String]? = nil,
        createdBy: String? = nil,
        scheduledAt: Date = Date(timeIntervalSince1970: 1_790_000_000)
    ) -> SiteVisit {
        let visit = SiteVisit(
            id: id,
            opportunityId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            companyId: companyId,
            status: status,
            scheduledAt: scheduledAt,
            durationMinutes: 60,
            assigneeIds: assignees ?? [me],
            createdBy: createdBy ?? me
        )
        if booked {
            visit.bookedAt = Date(timeIntervalSince1970: 1_789_900_000)
        }
        return visit
    }

    // MARK: - Visibility + booking filter

    func testOnlyBookedScheduledOrInProgressVisitsSurvive() {
        let visits = [
            visit(status: .scheduled),
            visit(status: .inProgress),
            visit(status: .completed),
            visit(status: .cancelled),
            visit(status: .scheduled, booked: false),   // walk-up: junk scheduledAt
        ]

        let visible = CalendarViewModel.visibleBookedVisits(
            visits,
            currentUserId: me,
            canViewAllCalendar: true
        )

        XCTAssertEqual(visible.count, 2)
        XCTAssertTrue(visible.allSatisfy { $0.isBookedAppointment })
    }

    func testTombstonedVisitNeverRenders() {
        let dead = visit()
        dead.deletedAt = Date()

        let visible = CalendarViewModel.visibleBookedVisits(
            [dead],
            currentUserId: me,
            canViewAllCalendar: true
        )

        XCTAssertTrue(visible.isEmpty)
    }

    func testWithoutViewAllOnlyAssignedOrCreatedVisitsShow() {
        let mine = visit(assignees: [me], createdBy: mate)
        let bookedByMe = visit(assignees: [mate], createdBy: me)
        let someoneElses = visit(assignees: [mate], createdBy: mate)

        let visible = CalendarViewModel.visibleBookedVisits(
            [mine, bookedByMe, someoneElses],
            currentUserId: me,
            canViewAllCalendar: false
        )

        XCTAssertEqual(Set(visible.map(\.id)), Set([mine.id, bookedByMe.id]))
    }

    func testViewAllSeesTheCompanyCalendar() {
        let someoneElses = visit(assignees: [mate], createdBy: mate)

        let visible = CalendarViewModel.visibleBookedVisits(
            [someoneElses],
            currentUserId: me,
            canViewAllCalendar: true
        )

        XCTAssertEqual(visible.count, 1)
    }

    func testAssigneeMatchIsCaseInsensitive() {
        let mine = visit(assignees: [me])

        let visible = CalendarViewModel.visibleBookedVisits(
            [mine],
            currentUserId: me.uppercased(),
            canViewAllCalendar: false
        )

        XCTAssertEqual(visible.count, 1)
    }

    // MARK: - Per-day slotting

    func testDayAccessorPicksSameDayVisitsSortedByTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let nineAM = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9))!
        let twoPM = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 9))!

        let late = visit(scheduledAt: twoPM)
        let early = visit(scheduledAt: nineAM)
        let tomorrow = visit(scheduledAt: nextDay)

        let dayVisits = CalendarViewModel.bookedVisits(
            in: [late, early, tomorrow],
            on: day,
            calendar: calendar
        )

        XCTAssertEqual(dayVisits.map(\.id), [early.id, late.id])
    }

    // MARK: - Calendar presentation regressions

    func testVisitOnlyDayIsPopulatedAndCountsTheVisit() {
        XCTAssertTrue(
            CalendarDayContent.hasEvents(
                taskCount: 0,
                userEventCount: 0,
                bookedVisitCount: 1
            )
        )
        XCTAssertEqual(
            CalendarDayContent.eventCount(
                taskCount: 0,
                userEventCount: 0,
                bookedVisitCount: 1
            ),
            1
        )
    }

    func testLinkedLeadDetailsSurviveIntoCalendarPresentation() {
        let bookedVisit = visit(
            id: "9471b86b-965e-46a0-8104-828251780dae",
            scheduledAt: Date(timeIntervalSince1970: 1_787_936_400)
        )
        bookedVisit.opportunityId = "e9618f88-ca6b-49ee-8c35-6d260b31c131"
        let details = CalendarSiteVisitLeadDetails(
            opportunityId: "e9618f88-ca6b-49ee-8c35-6d260b31c131",
            companyId: companyId,
            contactName: "Kim Berelliee",
            title: "Estimate",
            address: "903 Collinson St, Victoria, BC, Canada",
            agentSummary: nil,
            leadDescription: "Remove and replace the damaged front stair rail."
        )

        let presentation = CalendarSiteVisitPresentation(
            visit: bookedVisit,
            leadDetails: details
        )

        XCTAssertEqual(presentation.title, "Kim Berelliee")
        XCTAssertEqual(presentation.address, "903 Collinson St, Victoria, BC, Canada")
        XCTAssertEqual(presentation.detail, "Remove and replace the damaged front stair rail.")
    }

    func testCanonicalAppointmentFieldsOverrideLeadFallbacks() {
        let bookedVisit = visit()
        bookedVisit.appointmentTitle = "Design review"
        bookedVisit.appointmentLocation = "Microsoft Teams"
        let details = CalendarSiteVisitLeadDetails(
            opportunityId: bookedVisit.opportunityId!,
            companyId: companyId,
            contactName: "Kim Berelliee",
            title: nil,
            address: "903 Collinson St",
            agentSummary: "Confirm the final rail profile.",
            leadDescription: nil
        )

        let presentation = CalendarSiteVisitPresentation(
            visit: bookedVisit,
            leadDetails: details
        )

        XCTAssertEqual(presentation.title, "Design review")
        XCTAssertEqual(presentation.address, "Microsoft Teams")
        XCTAssertEqual(presentation.detail, "Confirm the final rail profile.")
    }
}
