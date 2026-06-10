import XCTest
@testable import OPS

/// Regression coverage for bug 6aad9984 — "Push 1 week" must be exactly +7
/// calendar days on the same weekday, identical on every surface, and must
/// never weekend-normalize a weekend-anchored task into a +9 over-advance.
///
/// Every push surface (CalendarSchedulerSheet, TaskRescheduleSheet,
/// MonthGridView, DayCanvasView, DataController) routes its week affordance
/// through `SchedulingEngine.pushByCalendarWeeks`, so these engine-level
/// assertions guard the behavior all of them share.
final class SchedulingPushTests: XCTestCase {

    // Use the same calendar the engine uses so day/weekday math matches exactly.
    private let calendar = Calendar.current

    // MARK: - Week push: exactly +7, weekday-preserving

    func testWeekPushOnSaturdayOriginIsExactlySevenDaysSameWeekday() {
        // The reported task: anchored on Saturday 2026-06-27 in a skip-weekends
        // company. A week push must land Saturday 2026-07-04 — exactly +7.
        let saturday = makeDate(2026, 6, 27)
        XCTAssertTrue(calendar.isDateInWeekend(saturday), "fixture must be a weekend day")

        let task = PushMock(startDate: saturday, endDate: saturday, duration: 1)
        let result = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: 1)

        XCTAssertEqual(daysBetween(saturday, result.newStart), 7, "week push must move exactly 7 days")
        XCTAssertEqual(weekday(result.newStart), weekday(saturday), "weekday must be preserved")
    }

    func testWeekPushOnWeekdayOriginIsExactlySevenDaysSameWeekday() {
        let monday = makeDate(2026, 6, 29)
        let task = PushMock(startDate: monday, endDate: monday, duration: 1)
        let result = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: 1)

        XCTAssertEqual(daysBetween(monday, result.newStart), 7)
        XCTAssertEqual(weekday(result.newStart), weekday(monday))
    }

    func testWeekPushPreservesDurationOfMultiDayTask() {
        // The reported task is duration-2 (spans Sat–Sun). The whole block must
        // translate by 7 days, keeping its length.
        let saturday = makeDate(2026, 6, 27)
        let sunday = makeDate(2026, 6, 28)
        let task = PushMock(startDate: saturday, endDate: sunday, duration: 2)

        let result = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: 1)

        XCTAssertEqual(daysBetween(saturday, result.newStart), 7)
        XCTAssertEqual(daysBetween(result.newStart, result.newEnd), 1, "duration-2 span must be preserved")
        XCTAssertEqual(weekday(result.newStart), weekday(saturday))
        XCTAssertEqual(weekday(result.newEnd), weekday(sunday))
    }

    func testWeekPushAcrossMonthBoundaryStaysSevenDays() {
        let jun30 = makeDate(2026, 6, 30) // Tuesday near month end
        let task = PushMock(startDate: jun30, endDate: jun30, duration: 1)

        let result = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: 1)

        XCTAssertEqual(daysBetween(jun30, result.newStart), 7)
        XCTAssertEqual(weekday(result.newStart), weekday(jun30))
        XCTAssertEqual(calendar.component(.month, from: result.newStart), 7, "must roll into July")
    }

    func testTwoWeekPushIsExactlyFourteenDaysSameWeekday() {
        // Future-proofs the weeks parameter the DataController derives via days/7.
        let saturday = makeDate(2026, 6, 27)
        let task = PushMock(startDate: saturday, endDate: saturday, duration: 1)

        let result = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: 2)

        XCTAssertEqual(daysBetween(saturday, result.newStart), 14)
        XCTAssertEqual(weekday(result.newStart), weekday(saturday))
    }

    func testNegativeWeekPushMovesBackwardExactlySevenDays() {
        // Every surface derives the week count as `days / 7`, which preserves
        // sign — a backward week push must move exactly −7 on the same weekday,
        // never collapse to a forward push.
        let saturday = makeDate(2026, 6, 27)
        let task = PushMock(startDate: saturday, endDate: saturday, duration: 1)

        let result = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: -1)

        XCTAssertEqual(daysBetween(saturday, result.newStart), -7)
        XCTAssertEqual(weekday(result.newStart), weekday(saturday))
    }

    // MARK: - The bug: the legacy day path over-advances a weekend-anchored task

    func testSkipWeekendDayPushOverAdvancesWeekendTask_whichWeekPathAvoids() {
        // Documents the exact defect: a +7 DAY push with skip-weekends on a
        // Saturday-origin task lands Sat → skip → Mon = +9. The week path,
        // which every "+1 week" affordance now uses, stays at exactly +7.
        let saturday = makeDate(2026, 6, 27)
        let task = PushMock(startDate: saturday, endDate: saturday, duration: 1)

        let dayPath = SchedulingEngine.pushByDays(task: task, days: 7, skipWeekends: true)
        let weekPath = SchedulingEngine.pushByCalendarWeeks(task: task, weeks: 1)

        XCTAssertGreaterThan(
            daysBetween(saturday, dayPath.newStart), 7,
            "the legacy skip-weekend day path over-advances a weekend-anchored task past +7"
        )
        XCTAssertEqual(
            daysBetween(saturday, weekPath.newStart), 7,
            "the week path used by every '+1 week' affordance must stay exactly +7"
        )
        XCTAssertEqual(weekday(weekPath.newStart), weekday(saturday))
    }

    // MARK: - Regression guard: intended day-nudge weekend skip is preserved

    func testDayNudgeStillSkipsWeekendForWeekdayOrigin() {
        // A +1 day nudge off a Friday in a skip-weekends company must still skip
        // the weekend and land Monday (+3 calendar days). The week-push fix must
        // not disturb the intended sub-week day-nudge behavior.
        let friday = makeDate(2026, 6, 26)
        let task = PushMock(startDate: friday, endDate: friday, duration: 1)

        let result = SchedulingEngine.pushByDays(task: task, days: 1, skipWeekends: true)

        XCTAssertFalse(calendar.isDateInWeekend(result.newStart), "a +1 day nudge into the weekend must skip to a weekday")
        XCTAssertEqual(daysBetween(friday, result.newStart), 3, "Fri +1 → Sat → skip → Mon = +3")
    }

    // MARK: - Fixtures

    private struct PushMock: SchedulableTask {
        var id: String = "task"
        var taskTypeId: String = "install"
        var startDate: Date?
        var endDate: Date?
        var duration: Int
        var effectiveDependencies: [TaskTypeDependency] = []
        var displayOrder: Int = 0
        var schedulingTeamMemberIds: Set<String> = []
        var schedulingProjectId: String = "project"
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12 // noon — safe from midnight/DST rollover
        return calendar.date(from: components)!
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }

    private func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }
}
