import XCTest
@testable import OPS

final class MonthGridEventSlotPlannerTests: XCTestCase {
    func testThreeEventsRemainVisibleAtDefaultHeight() {
        let plan = makePlan(singleDayEvents(count: 3))

        XCTAssertEqual(plan.rowByEventId, ["event-0": 0, "event-1": 1, "event-2": 2])
        XCTAssertTrue(plan.hiddenEventIdsByDay[0].isEmpty)
        XCTAssertTrue(plan.indicatorDays.isEmpty)
    }

    func testFiveEventsFitBeforeReservingOverflowAtDefaultHeight() {
        let plan = makePlan(singleDayEvents(count: 5))

        XCTAssertEqual(plan.rowByEventId.count, 5)
        XCTAssertTrue(plan.hiddenEventIdsByDay[0].isEmpty)
        XCTAssertTrue(plan.indicatorDays.isEmpty)
    }

    func testOverflowCountsEveryEventDisplacedByTheIndicator() {
        let plan = makePlan(singleDayEvents(count: 6))

        XCTAssertEqual(plan.rowByEventId.count, 4)
        XCTAssertEqual(plan.hiddenEventIdsByDay[0], ["event-4", "event-5"])
        XCTAssertEqual(plan.indicatorRow, 4)
        XCTAssertEqual(plan.indicatorDays, Set([0]))
    }

    func testSmallestDayUsesCompactPreviews() {
        let visible = makePlan(singleDayEvents(count: 3), cellHeight: 80)
        let overflowing = makePlan(singleDayEvents(count: 4), cellHeight: 80)

        XCTAssertEqual(visible.rowByEventId.count, 3)
        XCTAssertTrue(visible.indicatorDays.isEmpty)
        XCTAssertEqual(overflowing.rowByEventId.count, 2)
        XCTAssertEqual(overflowing.hiddenEventIdsByDay[0], ["event-2", "event-3"])
    }

    func testExpandedEventsKeepIndependentFullSizeInteractionRows() {
        let height = OPSStyle.Layout.monthGridExpandedHeightThreshold
        let layout = MonthGridEventLayout(cellHeight: height)
        let plan = makePlan(singleDayEvents(count: 4), cellHeight: height)

        XCTAssertTrue(layout.allowsEventInteraction)
        XCTAssertEqual(layout.rowHeight, OPSStyle.Layout.touchTargetMin)
        XCTAssertEqual(plan.rowByEventId.count, 3)
        XCTAssertEqual(plan.hiddenEventIdsByDay[0], ["event-3"])
        XCTAssertEqual(plan.indicatorRow, 3)
    }

    func testOverviewPreviewsLeaveInteractionToTheDayCell() {
        let heights: [CGFloat] = [80, 119, 120, 179]
        for height in heights {
            let layout = MonthGridEventLayout(cellHeight: height)
            XCTAssertFalse(layout.allowsEventInteraction)
            XCTAssertEqual(layout.rowHeight, layout.badgeHeight + OPSStyle.Layout.spacing1)
        }
    }

    func testOverlappingMultiDayEventsKeepStableRowsAndAdjacentEventsReuseThem() {
        let plan = makePlan([
            .init(id: "a", startDayIndex: 0, endDayIndex: 2),
            .init(id: "b", startDayIndex: 0, endDayIndex: 2),
            .init(id: "c", startDayIndex: 3, endDayIndex: 6),
        ])

        XCTAssertEqual(plan.rowByEventId, ["a": 0, "b": 1, "c": 0])
        XCTAssertTrue(plan.indicatorDays.isEmpty)
    }

    func testMultiDayEventClipsToBothWeeksWithoutDroppingTheContinuation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 9)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 16)))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)))
        let dates = try (0..<14).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: monday))
        }
        let firstWeek = try XCTUnwrap(MonthGridEventSlotPlanner.Candidate(
            id: "visit", startDate: start, endDate: end,
            dates: Array(dates.prefix(7)).map(Optional.some), calendar: calendar
        ))
        let nextWeek = try XCTUnwrap(MonthGridEventSlotPlanner.Candidate(
            id: "visit", startDate: start, endDate: end,
            dates: Array(dates.suffix(7)).map(Optional.some), calendar: calendar
        ))

        XCTAssertEqual(firstWeek.startDayIndex, 5)
        XCTAssertEqual(firstWeek.endDayIndex, 6)
        XCTAssertEqual(nextWeek.startDayIndex, 0)
        XCTAssertEqual(nextWeek.endDayIndex, 1)
        XCTAssertEqual(makePlan([firstWeek]).rowByEventId["visit"], 0)
        XCTAssertEqual(makePlan([nextWeek]).rowByEventId["visit"], 0)
    }

    func testHiddenMultiDayEventPropagatesExactCountsAcrossItsSpan() {
        let plan = makePlan(singleDayEvents(count: 5) + [
            .init(id: "multi", startDayIndex: 0, endDayIndex: 2),
        ])

        XCTAssertEqual(plan.rowByEventId.count, 4)
        XCTAssertEqual(plan.indicatorDays, Set([0, 1, 2]))
        XCTAssertEqual(plan.hiddenEventIdsByDay[0], ["event-4", "multi"])
        XCTAssertEqual(plan.hiddenEventIdsByDay[1], ["multi"])
        XCTAssertEqual(plan.hiddenEventIdsByDay[2], ["multi"])
    }

    func testExpandedContinuationOpensTheVisibleDateInTheSecondWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let firstMonday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)))
        let monthDates = try (0..<14).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstMonday))
        }
        let secondWeek = Array(monthDates[7..<14]).map(Optional.some)
        let span = WeekEventSpan(
            id: "visit-week-2", eventId: "visit", title: "Site prep", color: "",
            startDate: monthDates[5], endDate: monthDates[9],
            startDayIndex: 0, endDayIndex: 2, row: 0,
            isFirstSegment: false, isLastSegment: true, isSingleDay: false, taskTypeDisplay: nil
        )

        // The continuation must open Sep 14, not the event's Sep 12 start or
        // Sep 7 from the first week of the month. Tap and View details share it.
        XCTAssertEqual(span.dayDetailsDate(weekDates: secondWeek), monthDates[7])
        XCTAssertNotEqual(span.dayDetailsDate(weekDates: secondWeek), monthDates[0])
        XCTAssertNotEqual(span.dayDetailsDate(weekDates: secondWeek), span.startDate)
    }

    func testEveryEventIsVisibleOrCountedWithoutLaneCollisionsAtEveryPinchHeight() {
        let candidates = [
            MonthGridEventSlotPlanner.Candidate(id: "week", startDayIndex: 0, endDayIndex: 6),
            .init(id: "first", startDayIndex: 0, endDayIndex: 2),
            .init(id: "middle", startDayIndex: 2, endDayIndex: 4),
            .init(id: "last", startDayIndex: 4, endDayIndex: 6),
        ] + (0..<7).flatMap { day in
            (0..<8).map { event in
                MonthGridEventSlotPlanner.Candidate(id: "\(day)-\(event)", startDayIndex: day, endDayIndex: day)
            }
        }

        for height in 80...320 {
            let layout = MonthGridEventLayout(cellHeight: CGFloat(height))
            let plan = makePlan(candidates, cellHeight: CGFloat(height))
            for day in 0..<7 {
                let events = candidates.filter { ($0.startDayIndex...$0.endDayIndex).contains(day) }
                let visibleRows = events.compactMap { plan.rowByEventId[$0.id] }
                let hiddenIds = plan.hiddenEventIdsByDay[day]
                XCTAssertEqual(visibleRows.count + hiddenIds.count, events.count)
                XCTAssertEqual(Set(visibleRows).count, visibleRows.count)
                for row in visibleRows {
                    XCTAssertLessThanOrEqual(OPSStyle.Layout.monthGridDayHeaderHeight + CGFloat(row + 1) * layout.rowHeight, CGFloat(height))
                }
                if !hiddenIds.isEmpty {
                    XCTAssertTrue(visibleRows.allSatisfy { $0 < plan.indicatorRow })
                    XCTAssertLessThanOrEqual(OPSStyle.Layout.monthGridDayHeaderHeight + CGFloat(plan.indicatorRow) * layout.rowHeight + layout.indicatorHeight, CGFloat(height))
                }
            }
        }
    }

    private func singleDayEvents(count: Int) -> [MonthGridEventSlotPlanner.Candidate] {
        (0..<count).map { .init(id: "event-\($0)", startDayIndex: 0, endDayIndex: 0) }
    }

    private func makePlan(
        _ candidates: [MonthGridEventSlotPlanner.Candidate],
        cellHeight: CGFloat = OPSStyle.Layout.monthGridStandardHeightThreshold
    ) -> MonthGridEventSlotPlanner.Plan {
        var eventIdsByDay = Array(repeating: [String](), count: 7)
        for candidate in candidates {
            for day in candidate.startDayIndex...candidate.endDayIndex {
                eventIdsByDay[day].append(candidate.id)
            }
        }
        return MonthGridEventSlotPlanner.plan(
            candidates: candidates, eventIdsByDay: eventIdsByDay, cellHeight: cellHeight
        )
    }
}
