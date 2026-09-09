import XCTest
@testable import OPS

/// The rail's words and numbers are pure so they can be pinned (f77d38fc).
final class SiteVisitTodayRailCopyTests: XCTestCase {

    func testHeaderCountsVisitsAndSingularises() {
        XCTAssertEqual(SiteVisitTodayRailCopy.header(count: 1), "// TODAY · 1 VISIT")
        XCTAssertEqual(SiteVisitTodayRailCopy.header(count: 2), "// TODAY · 2 VISITS")
        XCTAssertEqual(SiteVisitTodayRailCopy.header(count: 3), "// TODAY · 3 VISITS")
    }

    func testTimeTokenIsShortUppercaseWithASpaceBeforeTheMeridiem() {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 8
        components.hour = 14; components.minute = 0
        let afternoon = Calendar.current.date(from: components)!
        XCTAssertEqual(SiteVisitTodayRailCopy.timeToken(afternoon), "2:00 PM")

        components.hour = 9; components.minute = 5
        let morning = Calendar.current.date(from: components)!
        XCTAssertEqual(SiteVisitTodayRailCopy.timeToken(morning), "9:05 AM")
    }

    func testVerbsStayTerse() {
        XCTAssertEqual(SiteVisitTodayRailCopy.start, "START")
        XCTAssertEqual(SiteVisitTodayRailCopy.dismissForToday, "DISMISS FOR TODAY")
    }
}
