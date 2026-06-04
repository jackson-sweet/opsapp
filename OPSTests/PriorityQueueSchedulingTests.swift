import XCTest
@testable import OPS

/// Regression tests for the PROJECT-level priority-queue runner
/// (`ScheduleRequest.Mode.projectPriorityQueue` → `scheduleBatch(respectOrder:)`).
///
/// The engine clamps the anchor to `max(startOfDay(anchor), today)`, so these
/// tests use FUTURE anchors and assert RELATIVE structure (ordering, spacing,
/// inclusion) rather than absolute calendar dates — which would silently clamp
/// to "today" and rot over time.
final class PriorityQueueSchedulingTests: XCTestCase {
    private let cal = Calendar.current

    /// A weekday `days` out from today (skips the "today" clamp, dodges weekends).
    private func futureWeekday(_ days: Int) -> Date {
        var d = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date()))!
        while cal.isDateInWeekend(d) { d = cal.date(byAdding: .day, value: 1, to: d)! }
        return d
    }

    /// A Friday at least a week out — for weekend-spanning duration tests.
    private func futureFriday() -> Date {
        var d = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: Date()))!
        while cal.component(.weekday, from: d) != 6 { d = cal.date(byAdding: .day, value: 1, to: d)! } // 6 = Friday
        return d
    }

    private func days(_ from: Date, _ to: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }

    // MARK: - Fixtures

    private struct PQMock: SchedulableTask {
        let id: String
        let taskTypeId: String
        var startDate: Date? = nil
        var endDate: Date? = nil
        var duration: Int = 1
        var effectiveDependencies: [TaskTypeDependency] = []
        var displayOrder: Int = 0
        var schedulingTeamMemberIds: Set<String> = ["crew-a"]
        var schedulingProjectId: String = "p1"
        var schedulingIsActive: Bool = true
    }

    private struct PQProvider: ScheduleDataProvider {
        var tasks: [any SchedulableTask]
        func tasksForProject(_ id: String) -> [any SchedulableTask] {
            tasks.filter { $0.schedulingProjectId == id }
        }
        func allScheduledTasksForMembers(_ memberIds: Set<String>, from date: Date) -> [any SchedulableTask] {
            let cal = Calendar.current
            let startDay = cal.startOfDay(for: date)
            return tasks.filter { t in
                guard let s = t.startDate else { return false }
                let e = t.endDate ?? s
                guard cal.startOfDay(for: e) >= startDay else { return false }
                return !t.schedulingTeamMemberIds.isDisjoint(with: memberIds)
            }
        }
        func coordinatesForProject(_ id: String) -> (lat: Double, lng: Double)? { nil }
        func priorityDateForProject(_ id: String) -> Date? { nil }
    }

    private func constraints(skipWeekends: Bool) -> ScheduleConstraints {
        ScheduleConstraints(skipWeekends: skipWeekends, preciseScheduling: false,
            schedulingWindow: .companyHours(open: "08:00", close: "17:00"),
            proximityRadiusKm: 15, weatherConstraints: nil)
    }

    private func run(_ orderedProjectIds: [String], tasks: [any SchedulableTask],
                     anchor: Date, skipWeekends: Bool) -> SchedulePlan {
        let req = ScheduleRequest(mode: .projectPriorityQueue(orderedProjectIds: orderedProjectIds),
                                  anchorDate: anchor, constraints: constraints(skipWeekends: skipWeekends))
        return AutoScheduleManager.schedule(request: req, provider: PQProvider(tasks: tasks))
    }

    // MARK: - Ranked order + crew sequencing

    /// Two projects, SAME crew, one task each. Ranked order is honored AND the
    /// second project's task is pushed past the first (one crew can't be two places).
    func testSameCrewProjectsSequenceInRankedOrder() {
        let base = futureWeekday(10)
        let a = PQMock(id: "a", taskTypeId: "ta", schedulingTeamMemberIds: ["crew-a"], schedulingProjectId: "p1")
        let b = PQMock(id: "b", taskTypeId: "tb", schedulingTeamMemberIds: ["crew-a"], schedulingProjectId: "p2")
        let plan = run(["p1", "p2"], tasks: [a, b], anchor: base, skipWeekends: false)

        let pa = plan.placements.first { $0.id == "a" }!
        let pb = plan.placements.first { $0.id == "b" }!
        XCTAssertEqual(days(base, pa.startDate), 0, "first ranked project starts on the anchor")
        XCTAssertEqual(days(base, pb.startDate), 1, "same-crew second project is sequenced to the next day")
    }

    /// Two projects, DIFFERENT crews. They run in parallel — both on the anchor.
    func testDifferentCrewProjectsRunInParallel() {
        let base = futureWeekday(10)
        let a = PQMock(id: "a", taskTypeId: "ta", schedulingTeamMemberIds: ["crew-a"], schedulingProjectId: "p1")
        let b = PQMock(id: "b", taskTypeId: "tb", schedulingTeamMemberIds: ["crew-b"], schedulingProjectId: "p2")
        let plan = run(["p1", "p2"], tasks: [a, b], anchor: base, skipWeekends: false)

        let pa = plan.placements.first { $0.id == "a" }!
        let pb = plan.placements.first { $0.id == "b" }!
        XCTAssertEqual(cal.startOfDay(for: pa.startDate), cal.startOfDay(for: pb.startDate),
                       "different crews are not in contention — both start on the anchor")
    }

    // MARK: - L1: weekend-aware end date

    /// A 2-day task starting Friday with skip-weekends must END Monday (the day it
    /// actually occupies), not Saturday. Regression for the calendar-day endDate bug.
    func testMultiDayTaskEndDateSkipsWeekend() {
        let friday = futureFriday()
        let t = PQMock(id: "t", taskTypeId: "tt", duration: 2,
                       schedulingTeamMemberIds: ["crew-a"], schedulingProjectId: "p1")
        let plan = run(["p1"], tasks: [t], anchor: friday, skipWeekends: true)

        let p = plan.placements.first { $0.id == "t" }!
        XCTAssertEqual(cal.component(.weekday, from: p.startDate), 6, "starts Friday")
        XCTAssertFalse(cal.isDateInWeekend(p.endDate), "end date is never a weekend day")
        XCTAssertEqual(days(p.startDate, p.endDate), 3, "Fri + 1 weekday = Mon (3 calendar days)")
    }

    // MARK: - L2: status filter

    /// A completed task with null dates is NEVER placed, even though its dates are nil.
    func testCompletedTasksAreNotScheduled() {
        let base = futureWeekday(10)
        let active = PQMock(id: "act", taskTypeId: "ta", schedulingProjectId: "p1", schedulingIsActive: true)
        let done = PQMock(id: "done", taskTypeId: "tb", schedulingProjectId: "p1", schedulingIsActive: false)
        let plan = run(["p1"], tasks: [active, done], anchor: base, skipWeekends: false)

        XCTAssertEqual(plan.placements.map(\.id), ["act"], "only the active task is placed")
    }

    // MARK: - L3: crewless tasks sequence within a project

    /// Two crewless tasks in one project must not collide on the anchor — they
    /// stack back-to-back. Each still raises a no-crew conflict.
    func testCrewlessTasksInSameProjectDoNotCollide() {
        let base = futureWeekday(10)
        let a = PQMock(id: "a", taskTypeId: "ta", displayOrder: 0, schedulingTeamMemberIds: [], schedulingProjectId: "p1")
        let b = PQMock(id: "b", taskTypeId: "tb", displayOrder: 1, schedulingTeamMemberIds: [], schedulingProjectId: "p1")
        let plan = run(["p1"], tasks: [a, b], anchor: base, skipWeekends: false)

        let starts = Set(plan.placements.map { cal.startOfDay(for: $0.startDate) })
        XCTAssertEqual(starts.count, 2, "crewless tasks are sequenced, not stacked on the same day")
        XCTAssertEqual(plan.conflicts.filter { $0.type == .noCrewAssigned }.count, 2, "both flag no crew")
    }

    // MARK: - Skips

    /// A project whose tasks are already fully scheduled contributes nothing.
    func testFullyScheduledProjectYieldsNoPlacements() {
        let base = futureWeekday(10)
        let scheduled = PQMock(id: "s", taskTypeId: "ts",
                               startDate: base, endDate: base,
                               schedulingProjectId: "p1")
        let plan = run(["p1"], tasks: [scheduled], anchor: base, skipWeekends: false)
        XCTAssertTrue(plan.placements.isEmpty, "no unscheduled work → empty plan")
    }
}
