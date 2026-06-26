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
