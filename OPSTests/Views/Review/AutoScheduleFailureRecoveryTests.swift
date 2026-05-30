//
//  AutoScheduleFailureRecoveryTests.swift
//  OPSTests
//
//  Regression coverage for no-placement recovery copy.
//

import XCTest
@testable import OPS

final class AutoScheduleFailureRecoveryTests: XCTestCase {

    func testNoPlacementWithWindowConflictUsesOperatorReadableCopy() {
        let plan = SchedulePlan(
            placements: [],
            conflicts: [
                ScheduleConflict(
                    id: "task-1",
                    type: .noAvailableWindow,
                    message: "scheduler returned no available slot after scanning constraints"
                )
            ],
            metadata: .empty
        )

        XCTAssertEqual(
            AutoScheduleFailureRecovery.message(for: plan),
            "NO SLOT FOUND — SCHEDULE MANUALLY"
        )
        XCTAssertTrue(AutoScheduleFailureRecovery.offersManualSchedule(for: plan))
        XCTAssertEqual(AutoScheduleFailureRecovery.recoveryAction(for: plan), .manualSchedule)
    }

    func testNoCrewConflictOffersAssignCrewInsteadOfManualSchedule() {
        let plan = SchedulePlan(
            placements: [],
            conflicts: [
                ScheduleConflict(
                    id: "task-1",
                    type: .noCrewAssigned,
                    message: "task has no assigned crew"
                )
            ],
            metadata: .empty
        )

        XCTAssertEqual(
            AutoScheduleFailureRecovery.message(for: plan),
            "CREW MISSING — ASSIGN CREW"
        )
        XCTAssertFalse(AutoScheduleFailureRecovery.offersManualSchedule(for: plan))
        XCTAssertEqual(AutoScheduleFailureRecovery.recoveryAction(for: plan), .assignCrew)
    }

    func testNoPlacementWithoutConflictStillOffersManualSchedule() {
        let plan = SchedulePlan(
            placements: [],
            conflicts: [],
            metadata: .empty
        )

        XCTAssertEqual(
            AutoScheduleFailureRecovery.message(for: plan),
            "NO SLOT FOUND — SCHEDULE MANUALLY"
        )
        XCTAssertTrue(AutoScheduleFailureRecovery.offersManualSchedule(for: plan))
        XCTAssertEqual(AutoScheduleFailureRecovery.recoveryAction(for: plan), .manualSchedule)
    }
}
