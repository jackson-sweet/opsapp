import XCTest
@testable import OPS

final class CalendarMirrorEligibilityTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_windowBounds_extend30DaysBack_365DaysForward() {
        let (lower, upper) = CalendarMirrorEligibility.windowBounds(now: now)
        XCTAssertLessThan(lower, now)
        XCTAssertGreaterThan(upper, now)
        XCTAssertEqual(Int(now.timeIntervalSince(lower) / 86_400), 30)
        XCTAssertEqual(Int(upper.timeIntervalSince(now) / 86_400), 365)
    }

    func test_isInWindow_eventInsideWindow_isTrue() {
        let start = now
        let end = now.addingTimeInterval(3600)
        XCTAssertTrue(CalendarMirrorEligibility.isInWindow(start: start, end: end, now: now))
    }

    func test_isInWindow_eventEntirelyTooFarPast_isFalse() {
        let start = now.addingTimeInterval(-200 * 86_400)
        let end = now.addingTimeInterval(-100 * 86_400)
        XCTAssertFalse(CalendarMirrorEligibility.isInWindow(start: start, end: end, now: now))
    }

    func test_isInWindow_eventEntirelyTooFarFuture_isFalse() {
        let start = now.addingTimeInterval(400 * 86_400)
        let end = now.addingTimeInterval(401 * 86_400)
        XCTAssertFalse(CalendarMirrorEligibility.isInWindow(start: start, end: end, now: now))
    }

    func test_userEventEligible_ownerInWindow_isTrue() {
        let e = makeEvent(userId: "u1", teamMemberIds: nil, deletedAt: nil)
        XCTAssertTrue(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    func test_userEventEligible_targetUser_isTrue() {
        let e = makeEvent(userId: "u2", teamMemberIds: ["u1", "u3"], deletedAt: nil)
        XCTAssertTrue(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    func test_userEventEligible_admin_notIn_teamMemberIds_isFalse() {
        let e = makeEvent(userId: "u2", teamMemberIds: ["u3"], deletedAt: nil)
        XCTAssertFalse(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    func test_userEventEligible_softDeleted_isFalse() {
        let e = makeEvent(userId: "u1", teamMemberIds: nil, deletedAt: Date())
        XCTAssertFalse(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    func test_userEventEligible_outOfWindow_isFalse() {
        let e = makeEvent(
            userId: "u1",
            teamMemberIds: nil,
            deletedAt: nil,
            startDate: now.addingTimeInterval(400 * 86_400),
            endDate: now.addingTimeInterval(401 * 86_400)
        )
        XCTAssertFalse(CalendarMirrorEligibility.isEligible(event: e, currentUserId: "u1", now: now))
    }

    private func makeEvent(
        userId: String,
        teamMemberIds: [String]?,
        deletedAt: Date?,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> CalendarUserEvent {
        let e = CalendarUserEvent(
            id: UUID().uuidString,
            userId: userId,
            companyId: "c1",
            type: .timeOff,
            title: "x",
            startDate: startDate ?? now,
            endDate: endDate ?? now.addingTimeInterval(3600),
            allDay: true,
            teamMemberIds: teamMemberIds
        )
        e.deletedAt = deletedAt
        return e
    }
}
