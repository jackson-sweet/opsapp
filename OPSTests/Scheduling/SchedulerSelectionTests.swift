//
//  SchedulerSelectionTests.swift
//  OPSTests
//
//  The schedule sheet's date-selection machine, plus a render smoke test for
//  the day cell it drives. The machine is the whole contract between tapping a
//  day and being allowed to save, so it is pinned here rather than inferred
//  from the view.
//
//  It also owns the span's geometry: the ordinal position each day holds
//  inside a range (which the interior gradient samples) and the outline that
//  closes only where the selection itself ends.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class SchedulerSelectionTests: XCTestCase {

    private let calendar = Calendar.current

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: - Transitions

    func testFirstTapStartsAndSecondTapCompletesARange() {
        var selection = SchedulerSelection.none
        XCTAssertFalse(selection.isCommittable)

        selection = selection.tapping(day(2026, 8, 10), calendar: calendar)
        XCTAssertEqual(selection, .start(day(2026, 8, 10)))
        XCTAssertFalse(selection.isCommittable)

        selection = selection.tapping(day(2026, 8, 13), calendar: calendar)
        XCTAssertEqual(selection, .range(day(2026, 8, 10), day(2026, 8, 13)))
        XCTAssertTrue(selection.isCommittable)
        XCTAssertEqual(selection.dayCount(calendar: calendar), 4)
    }

    func testABackwardsSecondTapSortsItselfIntoAValidRange() {
        let selection = SchedulerSelection
            .start(day(2026, 8, 13))
            .tapping(day(2026, 8, 10), calendar: calendar)

        XCTAssertEqual(selection, .range(day(2026, 8, 10), day(2026, 8, 13)))
        XCTAssertTrue(selection.isCommittable)
    }

    func testTappingTheSameDayTwiceIsAOneDayJob() {
        let selection = SchedulerSelection
            .none
            .tapping(day(2026, 8, 10), calendar: calendar)
            .tapping(day(2026, 8, 10), calendar: calendar)

        XCTAssertEqual(selection, .range(day(2026, 8, 10), day(2026, 8, 10)))
        XCTAssertEqual(selection.dayCount(calendar: calendar), 1)
        XCTAssertTrue(selection.isCommittable)
    }

    func testTappingWithACompleteRangeRestartsFromThatDay() {
        let selection = SchedulerSelection
            .range(day(2026, 8, 10), day(2026, 8, 13))
            .tapping(day(2026, 8, 20), calendar: calendar)

        XCTAssertEqual(selection, .start(day(2026, 8, 20)))
        XCTAssertFalse(selection.isCommittable)
    }

    func testPrefillFromPersistedDatesMakesSaveImmediatelyValid() {
        let prefilled = SchedulerSelection.prefilled(
            start: day(2026, 8, 10),
            end: day(2026, 8, 12),
            calendar: calendar
        )
        XCTAssertEqual(prefilled, .range(day(2026, 8, 10), day(2026, 8, 12)))
        XCTAssertTrue(prefilled.isCommittable)

        XCTAssertEqual(
            SchedulerSelection.prefilled(start: day(2026, 8, 10), end: nil, calendar: calendar),
            .start(day(2026, 8, 10))
        )
        XCTAssertEqual(
            SchedulerSelection.prefilled(start: nil, end: nil, calendar: calendar),
            .none
        )
        // A record whose dates were stored backwards still opens as a range.
        XCTAssertEqual(
            SchedulerSelection.prefilled(start: day(2026, 8, 12), end: day(2026, 8, 10), calendar: calendar),
            .range(day(2026, 8, 10), day(2026, 8, 12))
        )
    }

    func testClearingReturnsToTheEmptySelectionWithoutTouchingPersistedDates() {
        // CLEAR is a local reset — the machine simply returns to `.none`, and
        // nothing in the machine can unschedule anything.
        var selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 12))
        selection = .none
        XCTAssertNil(selection.startDate)
        XCTAssertNil(selection.endDate)
        XCTAssertFalse(selection.isCommittable)
    }

    // MARK: - Day-inspector action

    func testTheDaySheetOffersEndOnlyWhileAStartIsWaiting() {
        XCTAssertEqual(SchedulerSelection.none.dayAction, .useAsStart)
        XCTAssertEqual(SchedulerSelection.start(day(2026, 8, 10)).dayAction, .useAsEnd)
        XCTAssertEqual(
            SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 12)).dayAction,
            .useAsStart
        )
    }

    func testUseAsStartFromACompleteRangeRestartsAtThatDay() {
        let selection = SchedulerSelection
            .range(day(2026, 8, 10), day(2026, 8, 12))
            .tapping(day(2026, 8, 25), calendar: calendar)

        XCTAssertEqual(selection, .start(day(2026, 8, 25)))
    }

    // MARK: - Day roles (what each cell draws)

    func testDayRolesDescribeCapsInteriorAndOutside() {
        let selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 13))

        XCTAssertEqual(selection.role(for: day(2026, 8, 9), calendar: calendar), .none)
        XCTAssertEqual(selection.role(for: day(2026, 8, 10), calendar: calendar), .start)
        XCTAssertEqual(selection.role(for: day(2026, 8, 11), calendar: calendar), .interior)
        XCTAssertEqual(selection.role(for: day(2026, 8, 13), calendar: calendar), .end)
        XCTAssertEqual(selection.role(for: day(2026, 8, 14), calendar: calendar), .none)
    }

    func testAHalfMadeSelectionDrawsAClosedCapNotAnOpenBar() {
        let selection = SchedulerSelection.start(day(2026, 8, 10))
        XCTAssertEqual(selection.role(for: day(2026, 8, 10), calendar: calendar), .single)
        XCTAssertEqual(selection.role(for: day(2026, 8, 11), calendar: calendar), .none)
    }

    func testASingleDayRangeDrawsOneCap() {
        let selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 10))
        XCTAssertEqual(selection.role(for: day(2026, 8, 10), calendar: calendar), .single)
    }

    // MARK: - Span position (the interior gradient's coordinate system)

    func testSpanPositionIndexesEveryDayOfARange() {
        let selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 13))

        for index in 0...3 {
            let probe = calendar.date(byAdding: .day, value: index, to: day(2026, 8, 10))!
            let position = selection.spanPosition(for: probe, calendar: calendar)
            XCTAssertEqual(position?.index, index, "day \(index)")
            XCTAssertEqual(position?.count, 4, "day \(index)")
        }
    }

    func testSpanPositionIsNilOutsideTheRangeAndBeforeOneExists() {
        let selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 13))
        XCTAssertNil(selection.spanPosition(for: day(2026, 8, 9), calendar: calendar))
        XCTAssertNil(selection.spanPosition(for: day(2026, 8, 14), calendar: calendar))

        // There is no curve to slice until both ends of the span exist.
        XCTAssertNil(SchedulerSelection.none.spanPosition(for: day(2026, 8, 10), calendar: calendar))
        XCTAssertNil(
            SchedulerSelection
                .start(day(2026, 8, 10))
                .spanPosition(for: day(2026, 8, 10), calendar: calendar)
        )
    }

    func testASingleDayRangeIsPositionZeroOfOne() {
        let position = SchedulerSelection
            .range(day(2026, 8, 10), day(2026, 8, 10))
            .spanPosition(for: day(2026, 8, 10), calendar: calendar)

        XCTAssertEqual(position?.index, 0)
        XCTAssertEqual(position?.count, 1)
    }

    func testSpanPositionCountsDaysNotWeekRows() {
        // Twenty days across three week rows. The index is purely ordinal, so
        // the gradient joins across a wrap exactly as it does mid-row.
        let start = day(2026, 8, 5)
        let end = calendar.date(byAdding: .day, value: 19, to: start)!
        let selection = SchedulerSelection.range(start, end)

        let first = selection.spanPosition(for: start, calendar: calendar)
        XCTAssertEqual(first?.index, 0)
        XCTAssertEqual(first?.count, 20)

        // The day that lands in the next week row simply carries the next
        // index — no weekday arithmetic anywhere in the answer.
        let wrapped = calendar.date(byAdding: .day, value: 7, to: start)!
        XCTAssertEqual(selection.spanPosition(for: wrapped, calendar: calendar)?.index, 7)

        let last = selection.spanPosition(for: end, calendar: calendar)
        XCTAssertEqual(last?.index, 19)
        XCTAssertEqual(last?.count, 20)
    }

    func testSpanPositionNormalisesATimeOfDay() {
        // Persisted dates carry a clock time; an index must not shift by one
        // because a range was stored late in the evening.
        let selection = SchedulerSelection.range(day(2026, 8, 10), day(2026, 8, 13))
        let lateOnTheEleventh = calendar.date(byAdding: .hour, value: 23, to: day(2026, 8, 11))!

        XCTAssertEqual(selection.spanPosition(for: lateOnTheEleventh, calendar: calendar)?.index, 1)
    }

    // MARK: - Span outline geometry

    private var cellRect: CGRect {
        CGRect(x: 0, y: 0, width: 52, height: OPSStyle.Layout.schedulerDayCellHeight)
    }

    private func stroke(_ closure: SpanEdgeStroke.Closure) -> Path {
        SpanEdgeStroke(
            closure: closure,
            cornerRadius: OPSStyle.Layout.cardCornerRadius,
            inset: OPSStyle.Layout.Border.standard / 2
        )
        .path(in: cellRect)
    }

    func testAnOpenSpanEdgeRunsFlushToBothMargins() {
        // Two bare hairlines, edge to edge — nothing vertical fencing off a
        // week wrap or an interior day boundary.
        let open = stroke(.open)

        XCTAssertFalse(open.isEmpty)
        XCTAssertEqual(open.boundingRect.minX, cellRect.minX, accuracy: 0.01)
        XCTAssertEqual(open.boundingRect.maxX, cellRect.maxX, accuracy: 0.01)
    }

    func testOnlyTheClosedEndOfASpanEdgeCurvesIn() {
        let leading = stroke(.leading)
        let trailing = stroke(.trailing)

        // The cap side closes; the other side still runs to the margin so the
        // next row picks the same span back up.
        XCTAssertGreaterThan(leading.boundingRect.minX, cellRect.minX)
        XCTAssertEqual(leading.boundingRect.maxX, cellRect.maxX, accuracy: 0.01)
        XCTAssertEqual(trailing.boundingRect.minX, cellRect.minX, accuracy: 0.01)
        XCTAssertLessThan(trailing.boundingRect.maxX, cellRect.maxX)
    }

    func testEverySpanEdgeStaysInsideItsCell() {
        // A centred hairline drawn on the cell's own edge would bleed into the
        // gap between week rows; the inset keeps the whole outline in bounds.
        for closure in [SpanEdgeStroke.Closure.open, .leading, .trailing, .both] {
            let box = stroke(closure).boundingRect
            XCTAssertGreaterThan(box.minY, cellRect.minY, "\(closure)")
            XCTAssertLessThan(box.maxY, cellRect.maxY, "\(closure)")
        }
    }

    // MARK: - Render smoke

    /// Renders the day cell in every signal state through a real
    /// UIHostingController in a UIWindow. ImageRenderer cannot resolve OPS
    /// asset colours, so this is the only harness that proves the cell paints.
    func testDayCellRendersEverySignalState() {
        struct State {
            let name: String
            var signals = SchedulerDayContext.DaySignals()
            var role = SchedulerSelection.DayRole.none
            var spanPosition: (index: Int, count: Int)?
            var spanEdge: SpanEdgeStroke.Closure?
        }

        let states: [State] = [
            State(name: "clear"),
            State(name: "this_project", signals: .init(thisProject: true)),
            State(name: "crew_busy", signals: .init(crewBusy: true)),
            State(name: "crew_off", signals: .init(crewTimeOff: true)),
            State(
                name: "stacked",
                signals: .init(thisProject: true, crewBusy: true, crewTimeOff: true, otherCount: 2)
            ),
            State(name: "pre_floor", signals: .init(crewBusy: true, isPreFloor: true)),
            State(name: "start_cap", role: .start, spanPosition: (index: 0, count: 6), spanEdge: .leading),
            // Brightest slice of the curve — hard against the start cap.
            State(name: "interior_near_cap", role: .interior, spanPosition: (index: 1, count: 6), spanEdge: .open),
            // The cell holding the curve's vertex, so a three-stop gradient.
            State(name: "interior_vertex", role: .interior, spanPosition: (index: 2, count: 5), spanEdge: .open),
            // A three-day span's lone interior: it dips in its own centre.
            State(name: "interior_lone", role: .interior, spanPosition: (index: 1, count: 3), spanEdge: .open),
            State(name: "end_cap", role: .end, spanPosition: (index: 5, count: 6), spanEdge: .trailing),
            State(name: "single", role: .single)
        ]

        let size = CGSize(width: 52, height: OPSStyle.Layout.schedulerDayCellHeight)
        for state in states {
            let name = state.name
            let host = UIHostingController(
                rootView: SchedulerDayCell(
                    date: Date(),
                    signals: state.signals,
                    role: state.role,
                    spanPosition: state.spanPosition,
                    spanEdge: state.spanEdge,
                    isToday: name == "clear",
                    onTap: {},
                    onLongPress: {}
                )
                .frame(width: size.width, height: size.height)
                .background(Color.black)
            )
            host.overrideUserInterfaceStyle = .dark
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.backgroundColor = .black

            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertNotNil(image.pngData(), "day cell state \(name) failed to render")
        }
    }
}
#endif
