import XCTest
@testable import OPS

final class CalendarWeekRowNavigationTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testCaptionNamesThisNextPriorAndNearbyWeeks() {
        let today = makeDate(2026, 6, 26)

        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: today, relativeTo: today, calendar: calendar), "This week")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 7, 3), relativeTo: today, calendar: calendar), "Next week")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 6, 19), relativeTo: today, calendar: calendar), "Last week")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 7, 10), relativeTo: today, calendar: calendar), "2 weeks from now")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 7, 17), relativeTo: today, calendar: calendar), "3 weeks from now")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 6, 12), relativeTo: today, calendar: calendar), "2 weeks ago")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 6, 5), relativeTo: today, calendar: calendar), "3 weeks ago")
    }

    func testCaptionSwitchesToMonthScaleAfterThreeWeeks() {
        let today = makeDate(2026, 6, 26)

        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 7, 24), relativeTo: today, calendar: calendar), "1 month from now")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 8, 21), relativeTo: today, calendar: calendar), "2 months from now")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 5, 29), relativeTo: today, calendar: calendar), "1 month ago")
        XCTAssertEqual(CalendarWeekRowCaption.title(forWeekContaining: makeDate(2026, 5, 1), relativeTo: today, calendar: calendar), "2 months ago")
    }

    func testEdgePagingHitZoneScalesButStaysControlled() {
        XCTAssertEqual(CalendarWeekRowNavigation.activeEdgeWidth(forRowWidth: 0), 0)
        XCTAssertEqual(CalendarWeekRowNavigation.activeEdgeWidth(forRowWidth: 200), 28)
        XCTAssertEqual(CalendarWeekRowNavigation.activeEdgeWidth(forRowWidth: 390), 35.1, accuracy: 0.1)
        XCTAssertEqual(CalendarWeekRowNavigation.activeEdgeWidth(forRowWidth: 800), 44)
    }

    func testBookedVisitGetsFridayWeekBarAndParticipatesInOverflow() {
        let monday = makeDate(2026, 8, 24)
        let weekDays = (0..<7).map {
            calendar.date(byAdding: .day, value: $0, to: monday)!
        }
        let friday = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: weekDays[4])!
        let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        var visitsByDay = Array(repeating: [SiteVisit](), count: 7)
        visitsByDay[4] = (0..<5).map { index in
            let visit = SiteVisit(
                id: "visit-\(index)",
                opportunityId: "lead-\(index)",
                companyId: companyId,
                status: .scheduled,
                scheduledAt: friday,
                durationMinutes: 60,
                assigneeIds: [],
                createdBy: nil
            )
            visit.bookedAt = friday.addingTimeInterval(-3_600)
            return visit
        }

        let layout = CalendarWeekBarPlanner.layout(
            weekDays: weekDays,
            tasksByDay: Array(repeating: [], count: 7),
            userEventsByDay: Array(repeating: [], count: 7),
            bookedVisitsByDay: visitsByDay,
            calendar: calendar
        )

        XCTAssertEqual(
            layout.spans.map(\.id),
            ["sitevisit:visit-0", "sitevisit:visit-1", "sitevisit:visit-2", "sitevisit:visit-3"]
        )
        XCTAssertTrue(
            layout.spans.allSatisfy {
                $0.startDayIndex == 4 && $0.endDayIndex == 4
                    && $0.isFirstSegment && $0.isLastSegment
            }
        )
        XCTAssertEqual(layout.overflowPerDay, [0, 0, 0, 0, 1, 0, 0])
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }
}
