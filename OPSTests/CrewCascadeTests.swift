import XCTest
@testable import OPS

/// Coverage for bug efb57ffc — the crew cascade. Pushing a job via a Cascade
/// action consolidates the pushed crew member's OTHER jobs forward (across
/// projects) to close the gap the push opens, but never pulls any job earlier
/// than its current day, and never overlaps two auto-moved jobs.
final class CrewCascadeTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Forward consolidation

    func testReporterScenario_consecutiveCrewJobsShiftForwardAcrossProjects() {
        // Charlie has back-to-back jobs on three different projects.
        let a = task("A", start: mon, project: "p1")
        let b = task("B", start: tue, project: "p2")
        let c = task("C", start: wed, project: "p3")

        // Push A +2 → Wed. Tue and Wed jobs slide to Thu and Fri.
        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: wed, pushedNewEnd: wed,
            allTasks: [a, b, c, task("X", start: tue, crew: ["other"])], skipWeekends: false
        )

        XCTAssertEqual(start(of: "B", in: changes), thu)
        XCTAssertEqual(start(of: "C", in: changes), fri)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.allSatisfy { $0.reason == .crew })
    }

    func testForwardOnly_jobBeyondTheGapIsNotPulledEarlier() {
        // A on Mon, C on Thu with a two-day gap. Push A +1 → Tue.
        let a = task("A", start: mon)
        let c = task("C", start: thu)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: tue, pushedNewEnd: tue,
            allTasks: [a, c], skipWeekends: false
        )

        // C must stay on Thu — the safe direction never pulls it back to Wed.
        XCTAssertTrue(changes.isEmpty)
    }

    func testGapAbsorbed_packedJobStaysWhenSlotReachesItsOriginalDay() {
        // A Mon, B Tue, C Thu (gap Wed). Push A +1 → Tue.
        let a = task("A", start: mon)
        let b = task("B", start: tue)
        let c = task("C", start: thu)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: tue, pushedNewEnd: tue,
            allTasks: [a, b, c], skipWeekends: false
        )

        // B fills Wed; C stays Thu (its slot caught up), Fri stays free.
        XCTAssertEqual(start(of: "B", in: changes), wed)
        XCTAssertNil(changes.first { $0.id == "C" })
        XCTAssertEqual(changes.count, 1)
    }

    func testMultiDayCrewJobPreservesDuration() {
        let a = task("A", start: mon)               // 1 day
        let b = task("B", start: tue, duration: 2)  // Tue–Wed
        let c = task("C", start: thu)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: tue, pushedNewEnd: tue,
            allTasks: [a, b, c], skipWeekends: false
        )

        // B (2-day) slides to Wed–Thu; C must clear B and land Fri.
        let bChange = changes.first { $0.id == "B" }
        XCTAssertEqual(bChange?.newStartDate, wed)
        XCTAssertEqual(bChange?.newEndDate, thu)
        XCTAssertEqual(start(of: "C", in: changes), fri)
    }

    // MARK: - Exclusions

    func testDifferentCrewJobIsNotShifted() {
        let a = task("A", start: mon, crew: ["crew-a"])
        let x = task("X", start: tue, crew: ["crew-b"])

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: wed, pushedNewEnd: wed,
            allTasks: [a, x], skipWeekends: false
        )

        XCTAssertTrue(changes.isEmpty)
    }

    func testLockedCrewJobIsNotShiftedAndActsAsObstacle() {
        // A Mon, B Tue (moveable), L Wed (locked). Push A +1 → Tue.
        let a = task("A", start: mon)
        let b = task("B", start: tue)
        let l = task("L", start: wed, locked: true)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: tue, pushedNewEnd: tue,
            allTasks: [a, b, l], skipWeekends: false
        )

        // L never moves; B must pack AROUND the locked Wed and land Thu.
        XCTAssertNil(changes.first { $0.id == "L" })
        XCTAssertEqual(start(of: "B", in: changes), thu)
    }

    func testUnlockedJobOnSameDayAsLockedJobIsPackedOff() {
        // B and the locked L both sit on Thu (a pre-existing overlap). Pushing A
        // doesn't make the pack reach Thu, so B would "stay" — but it overlaps a
        // locked crew job, so it must pack forward off the obstacle to Fri.
        let a = task("A", start: mon)
        let b = task("B", start: thu)                 // unlocked, sorts before L
        let l = task("L", start: thu, locked: true)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: tue, pushedNewEnd: tue,
            allTasks: [a, b, l], skipWeekends: false
        )

        XCTAssertEqual(start(of: "B", in: changes), fri, "B must move off the locked Thu slot")
        XCTAssertNil(changes.first { $0.id == "L" }, "locked job never moves")
    }

    func testCompletedCrewJobIsNotShifted() {
        let a = task("A", start: mon)
        let done = task("D", start: tue, active: false)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: wed, pushedNewEnd: wed,
            allTasks: [a, done], skipWeekends: false
        )

        XCTAssertTrue(changes.isEmpty)
    }

    func testPushedJobWithoutCrewYieldsNoCrewChanges() {
        let a = task("A", start: mon, crew: [])
        let b = task("B", start: tue, crew: ["crew-a"])

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: mon,
            pushedNewStart: wed, pushedNewEnd: wed,
            allTasks: [a, b], skipWeekends: false
        )

        XCTAssertTrue(changes.isEmpty)
    }

    func testJobBeforeAnchorIsNotShifted() {
        // A job earlier than the pushed job's original day is untouched.
        let a = task("A", start: wed)
        let earlier = task("E", start: mon)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: wed,
            pushedNewStart: fri, pushedNewEnd: fri,
            allTasks: [a, earlier], skipWeekends: false
        )

        XCTAssertTrue(changes.isEmpty)
    }

    // MARK: - Weekend skip

    func testSkipWeekends_packedJobLandsOnWeekday() {
        // A Thu, B Fri. Push A +1 → Fri. B is bumped off the weekend to Monday.
        let a = task("A", start: thu)
        let b = task("B", start: fri)

        let changes = SchedulingEngine.calculateCrewConsolidation(
            pushedTask: a, pushedOriginalStart: thu,
            pushedNewStart: fri, pushedNewEnd: fri,
            allTasks: [a, b], skipWeekends: true
        )

        let bStart = start(of: "B", in: changes)
        XCTAssertNotNil(bStart)
        XCTAssertFalse(calendar.isDateInWeekend(bStart!))
        XCTAssertEqual(bStart, nextMon)
    }

    // MARK: - Dependency / crew merge (calculateCascade seeding)

    func testDependencyPushesCrewSeededTaskFurtherWhenLater() {
        // V depends on P (after_end, gap 0). P pushed to Wed → V earliest Thu.
        // V was crew-seeded to Wed; the dependency must win and land it Thu.
        var v = task("V", start: tue, type: "vinyl")
        v.effectiveDependencies = [
            TaskTypeDependency(dependsOnTaskTypeId: "print", overlapPercentage: 0, overlapMode: "after_end", minGapDaysAfterEnd: 0)
        ]
        let p = task("P", start: mon, type: "print")

        let result = SchedulingEngine.calculateCascade(
            pushedTaskId: "P", newStartDate: wed, newEndDate: wed,
            allProjectTasks: [p, v], skipWeekends: false,
            seededDates: ["V": (start: wed, end: wed)]
        )

        let vChange = result.changes.first { $0.id == "V" }
        XCTAssertEqual(vChange?.newStartDate, thu)
        XCTAssertEqual(vChange?.reason, .dependency)
    }

    func testDependencyDoesNotMoveCrewSeededTaskAlreadyLaterThanRequirement() {
        // Same dependency, but V crew-seeded to Fri (after the Thu requirement):
        // the dependency is satisfied, so it must not move V.
        var v = task("V", start: tue, type: "vinyl")
        v.effectiveDependencies = [
            TaskTypeDependency(dependsOnTaskTypeId: "print", overlapPercentage: 0, overlapMode: "after_end", minGapDaysAfterEnd: 0)
        ]
        let p = task("P", start: mon, type: "print")

        let result = SchedulingEngine.calculateCascade(
            pushedTaskId: "P", newStartDate: wed, newEndDate: wed,
            allProjectTasks: [p, v], skipWeekends: false,
            seededDates: ["V": (start: fri, end: fri)]
        )

        XCTAssertNil(result.changes.first { $0.id == "V" })
    }

    // MARK: - Fixtures

    private struct CrewMock: SchedulableTask {
        var id: String
        var taskTypeId: String = "t"
        var startDate: Date?
        var endDate: Date?
        var duration: Int = 1
        var effectiveDependencies: [TaskTypeDependency] = []
        var displayOrder: Int = 0
        var schedulingTeamMemberIds: Set<String> = ["crew-a"]
        var schedulingProjectId: String = "p1"
        var schedulingLocked: Bool = false
        var schedulingIsActive: Bool = true
    }

    private func task(
        _ id: String,
        start: Date,
        duration: Int = 1,
        project: String = "p1",
        crew: Set<String> = ["crew-a"],
        locked: Bool = false,
        active: Bool = true,
        type: String = "t",
        order: Int = 0
    ) -> CrewMock {
        let end = calendar.date(byAdding: .day, value: max(duration - 1, 0), to: start)!
        return CrewMock(
            id: id, taskTypeId: type, startDate: start, endDate: end, duration: duration,
            effectiveDependencies: [], displayOrder: order,
            schedulingTeamMemberIds: crew, schedulingProjectId: project,
            schedulingLocked: locked, schedulingIsActive: active
        )
    }

    private func start(of id: String, in changes: [SchedulingEngine.CascadeResult.TaskDateChange]) -> Date? {
        changes.first { $0.id == id }?.newStartDate
    }

    private func day(_ year: Int, _ month: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = d; c.hour = 12
        return calendar.date(from: c)!
    }

    // Mon 2026-06-29 … Fri 2026-07-03, next Mon 2026-07-06.
    private var mon: Date { day(2026, 6, 29) }
    private var tue: Date { day(2026, 6, 30) }
    private var wed: Date { day(2026, 7, 1) }
    private var thu: Date { day(2026, 7, 2) }
    private var fri: Date { day(2026, 7, 3) }
    private var nextMon: Date { day(2026, 7, 6) }
}
