import XCTest
@testable import OPS

final class ScheduleDragSessionHoverTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor
    func testRefreshHoverUpdatesDateTargetAndReportsChange() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let source = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        let changed = session.refreshHover(day: monday, source: source, calendar: calendar)

        XCTAssertTrue(changed)
        XCTAssertEqual(session.hoverSource, source)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: monday))
    }

    @MainActor
    func testRefreshHoverDoesNotReportChangeForSameDate() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let source = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        _ = session.refreshHover(day: monday, source: source, calendar: calendar)
        let changed = session.refreshHover(day: monday, source: source, calendar: calendar)

        XCTAssertFalse(changed)
    }

    @MainActor
    func testOldDayExitDoesNotClearNewDayHover() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let tuesday = makeDate(2026, 6, 23)
        let mondaySource = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)
        let tuesdaySource = ScheduleDragHoverSource.dayCell(for: tuesday, calendar: calendar)

        session.begin(payload)
        session.updateHover(day: monday, source: mondaySource)
        session.updateHover(day: tuesday, source: tuesdaySource)
        session.clearHover(source: mondaySource)

        XCTAssertEqual(session.hoverSource, tuesdaySource)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: tuesday))
    }

    @MainActor
    func testDayExitDoesNotClearWeekEdgeHoverForSameDate() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let daySource = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)
        let edgeSource = ScheduleDragHoverSource.weekRowEdge(.previous)

        session.begin(payload)
        session.updateHover(day: monday, source: daySource)
        session.updateHover(day: monday, source: edgeSource)
        session.clearHover(source: daySource)

        XCTAssertEqual(session.hoverSource, edgeSource)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: monday))
    }

    @MainActor
    func testDeferredPreviewEndDoesNotClearWhileHoveringTarget() async {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let source = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        session.updateHover(day: monday, source: source)
        session.endWhenOffGrid(after: .milliseconds(10))
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(session.active?.id, payload.id)
        XCTAssertEqual(session.hoverSource, source)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: monday))
    }

    @MainActor
    func testDeferredPreviewEndClearsWhenNoTargetOwnsHover() async {
        let session = ScheduleDragSession()

        session.begin(makePayload())
        session.endWhenOffGrid(after: .milliseconds(10))
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertNil(session.active)
        XCTAssertNil(session.hoveredDate)
        XCTAssertNil(session.hoverSource)
    }

    private func makePayload() -> RescheduleDragPayload {
        RescheduleDragPayload(
            id: "task-1",
            kind: .task,
            title: "Install rail",
            durationDays: 1,
            startEpoch: makeDate(2026, 6, 22).timeIntervalSince1970
        )
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
