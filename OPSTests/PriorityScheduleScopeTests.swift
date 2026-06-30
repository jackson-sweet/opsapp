//
//  PriorityScheduleScopeTests.swift
//  OPSTests
//
//  Targeting rules behind the Prioritize screen's run buttons.
//
//  These cover the regression that made the buttons feel broken: with nothing
//  ranked, SCHEDULE ALL only considered the (empty) ranked list and sat
//  disabled, so the common "just schedule everything" path was dead. `.all`
//  must consider every active project; `.ranked` must consider only the
//  prioritized ones and leave the rest alone.
//

import XCTest
@testable import OPS

final class PriorityScheduleScopeTests: XCTestCase {

    // MARK: - Fixtures

    /// A project with one task that still needs a date (active, no start/end).
    private func schedulable(_ id: String) -> Project {
        let p = Project(id: id, title: id, status: .inProgress)
        let t = ProjectTask(id: "\(id)-t", projectId: id, taskTypeId: "tt", companyId: "co")
        t.startDate = nil
        t.endDate = nil
        t.project = p
        p.tasks.append(t)
        return p
    }

    /// A project whose only task is already fully scheduled — no work to place.
    private func fullyScheduled(_ id: String) -> Project {
        let p = Project(id: id, title: id, status: .inProgress)
        let t = ProjectTask(id: "\(id)-t", projectId: id, taskTypeId: "tt", companyId: "co")
        let now = Date()
        t.startDate = now
        t.endDate = now
        t.project = p
        p.tasks.append(t)
        return p
    }

    // MARK: - candidates

    func testRankedScopeTargetsOnlyRankedProjects() {
        let r1 = schedulable("r1"), r2 = schedulable("r2")
        let u1 = schedulable("u1")
        let ids = PriorityScheduleScoping
            .candidates(for: .ranked, ranked: [r1, r2], unranked: [u1])
            .map(\.id)
        XCTAssertEqual(ids, ["r1", "r2"], "ranked scope leaves unranked work untouched")
    }

    func testAllScopeTargetsRankedFirstThenUnranked() {
        let r1 = schedulable("r1"), r2 = schedulable("r2")
        let u1 = schedulable("u1"), u2 = schedulable("u2")
        let ids = PriorityScheduleScoping
            .candidates(for: .all, ranked: [r1, r2], unranked: [u1, u2])
            .map(\.id)
        XCTAssertEqual(ids, ["r1", "r2", "u1", "u2"],
                       "all scope sweeps in the unranked tail but keeps priority order first")
    }

    func testAllScopeWithNothingRankedTargetsEveryProject() {
        let u1 = schedulable("u1"), u2 = schedulable("u2")
        let ids = PriorityScheduleScoping
            .candidates(for: .all, ranked: [], unranked: [u1, u2])
            .map(\.id)
        XCTAssertEqual(ids, ["u1", "u2"], "with no priorities set, all scope still targets everything")
    }

    // MARK: - canSchedule (the run-button enabled state)

    func testCanScheduleAllIsLiveWithNoPrioritiesSet() {
        // The core regression: nothing ranked, but unranked work exists.
        // SCHEDULE ALL must be live so the user can schedule everything.
        let u1 = schedulable("u1")
        XCTAssertTrue(
            PriorityScheduleScoping.canSchedule(scope: .all, ranked: [], unranked: [u1]),
            "SCHEDULE ALL must be enabled when any project has work, even with no ranking"
        )
    }

    func testCanScheduleRankedIsDeadWhenNothingRanked() {
        let u1 = schedulable("u1")
        XCTAssertFalse(
            PriorityScheduleScoping.canSchedule(scope: .ranked, ranked: [], unranked: [u1]),
            "SCHEDULE RANKED has nothing to act on until something is ranked"
        )
    }

    func testCanScheduleRankedIsLiveWhenRankedHasWork() {
        let r1 = schedulable("r1")
        let u1 = fullyScheduled("u1")
        XCTAssertTrue(
            PriorityScheduleScoping.canSchedule(scope: .ranked, ranked: [r1], unranked: [u1]),
            "ranked work present → SCHEDULE RANKED is live"
        )
    }

    func testCanScheduleAllIsDeadWhenAllWorkIsAlreadyScheduled() {
        let r1 = fullyScheduled("r1")
        let u1 = fullyScheduled("u1")
        XCTAssertFalse(
            PriorityScheduleScoping.canSchedule(scope: .all, ranked: [r1], unranked: [u1]),
            "no unscheduled work anywhere → nothing to do, button is disabled (not a dead-tap)"
        )
    }

    // MARK: - hasSchedulableTask

    func testFullyScheduledProjectHasNoSchedulableTask() {
        XCTAssertFalse(PriorityScheduleScoping.hasSchedulableTask(fullyScheduled("p")))
    }

    func testProjectWithUndatedActiveTaskIsSchedulable() {
        XCTAssertTrue(PriorityScheduleScoping.hasSchedulableTask(schedulable("p")))
    }

    func testDeletedTaskDoesNotCountAsSchedulable() {
        let p = Project(id: "p", title: "p", status: .inProgress)
        let t = ProjectTask(id: "p-t", projectId: "p", taskTypeId: "tt", companyId: "co")
        t.startDate = nil
        t.endDate = nil
        t.deletedAt = Date()
        t.project = p
        p.tasks.append(t)
        XCTAssertFalse(PriorityScheduleScoping.hasSchedulableTask(p),
                       "a soft-deleted task is never scheduled")
    }
}
