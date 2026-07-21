import XCTest
@testable import OPS

final class MonthGridEventSlotPlannerTests: XCTestCase {
    func testTwoEventsUseBothRowsWithoutOverflowAtDefaultHeight() {
        let plan = makePlan([
            .init(id: "a", startDayIndex: 0, endDayIndex: 0),
            .init(id: "b", startDayIndex: 0, endDayIndex: 0),
        ])

        XCTAssertEqual(plan.rowByEventId, ["a": 0, "b": 1])
        XCTAssertTrue(plan.hiddenEventIdsByDay[0].isEmpty)
        XCTAssertFalse(plan.indicatorDays.contains(0))
    }

    func testThreeEventsReserveIndicatorOnlyWhenOverflowExists() {
        let plan = makePlan([
            .init(id: "a", startDayIndex: 0, endDayIndex: 0),
            .init(id: "b", startDayIndex: 0, endDayIndex: 0),
            .init(id: "c", startDayIndex: 0, endDayIndex: 0),
        ])

        XCTAssertEqual(plan.rowByEventId, ["a": 0])
        XCTAssertEqual(plan.hiddenEventIdsByDay[0], ["b", "c"])
        XCTAssertEqual(plan.indicatorRow, 1)
        XCTAssertTrue(plan.indicatorDays.contains(0))
    }

    func testOverlappingMultiDayEventsKeepStableRows() {
        let plan = makePlan([
            .init(id: "a", startDayIndex: 0, endDayIndex: 2),
            .init(id: "b", startDayIndex: 0, endDayIndex: 2),
        ])

        XCTAssertEqual(plan.rowByEventId, ["a": 0, "b": 1])
        XCTAssertTrue(plan.indicatorDays.isEmpty)
    }

    func testHiddenMultiDayEventPropagatesIndicatorsAcrossItsSpan() {
        let plan = makePlan([
            .init(id: "a", startDayIndex: 0, endDayIndex: 0),
            .init(id: "b", startDayIndex: 0, endDayIndex: 0),
            .init(id: "c", startDayIndex: 0, endDayIndex: 2),
        ])

        XCTAssertEqual(plan.rowByEventId, ["a": 0])
        XCTAssertEqual(plan.indicatorDays, Set([0, 1, 2]))
        XCTAssertEqual(plan.hiddenEventIdsByDay[0], ["b", "c"])
        XCTAssertEqual(plan.hiddenEventIdsByDay[1], ["c"])
        XCTAssertEqual(plan.hiddenEventIdsByDay[2], ["c"])
    }

    private func makePlan(
        _ candidates: [MonthGridEventSlotPlanner.Candidate]
    ) -> MonthGridEventSlotPlanner.Plan {
        var eventIdsByDay = Array(repeating: [String](), count: 7)
        for candidate in candidates {
            for day in candidate.startDayIndex...candidate.endDayIndex {
                eventIdsByDay[day].append(candidate.id)
            }
        }
        return MonthGridEventSlotPlanner.plan(
            candidates: candidates,
            eventIdsByDay: eventIdsByDay,
            cellHeight: OPSStyle.Layout.monthGridStandardHeightThreshold
        )
    }
}
