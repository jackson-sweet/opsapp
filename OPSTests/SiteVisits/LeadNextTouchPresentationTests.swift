import XCTest
@testable import OPS

final class LeadNextTouchPresentationTests: XCTestCase {

    private let calendar = Calendar.current

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testUnsetWhenNothingIsScheduled() {
        XCTAssertEqual(
            LeadNextTouchPresentation.resolve(nextFollowUpAt: nil, bookedVisitAt: nil, now: date(1, 8)),
            .unset
        )
    }

    func testFollowUpOnlyPrintsDayAndDate() {
        let result = LeadNextTouchPresentation.resolve(
            nextFollowUpAt: date(6, 9), bookedVisitAt: nil, now: date(1, 8)
        )
        guard case .followUp(let day, let dateToken) = result else {
            return XCTFail("Expected followUp, got \(result)")
        }
        XCTAssertEqual(day.count, 3)          // EEE
        XCTAssertEqual(dateToken, "SEP 6")
    }

    func testBookedVisitOutranksFollowUp() {
        let result = LeadNextTouchPresentation.resolve(
            nextFollowUpAt: date(8, 9),        // later nudge
            bookedVisitAt: date(4, 10, 30),    // the appointment wins
            now: date(1, 8)
        )
        guard case .visit(let day, let time) = result else {
            return XCTFail("Expected visit, got \(result)")
        }
        XCTAssertEqual(time, "10:30AM")
        XCTAssertFalse(day.isEmpty)            // TODAY/TMRW/EEE/MMM d via DaySheetDateToken
    }

    func testVisitTomorrowUsesDaySheetVocabulary() {
        let result = LeadNextTouchPresentation.resolve(
            nextFollowUpAt: nil,
            bookedVisitAt: date(2, 14),
            now: date(1, 8)
        )
        XCTAssertEqual(result, .visit(day: "TMRW", time: "2:00PM"))
    }
}
