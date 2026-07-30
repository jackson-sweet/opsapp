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
//  inside a range, the brightness curve the interior fills itself with, and
//  the outline that closes only where the selection itself ends.
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

    // MARK: - Span curve (what the interior fills itself with)

    private func brightness(_ x: Double, _ interiorCount: Int) -> Double {
        SchedulerSpanCurve.brightness(at: x, interiorCount: interiorCount)
    }

    func testTheCurveLeavesEverySeamAtTheCapsOwnWhite() {
        // The whole point of the shape: brightness 1 is `primaryText` at full
        // strength, which is exactly what a cap is filled with. Anything less
        // at a seam is the step this curve exists to remove — so this is an
        // exact equality, not an approximate one.
        for interiorCount in [1, 2, 3, 10] {
            XCTAssertEqual(brightness(0, interiorCount), 1.0, "start seam, interior \(interiorCount)")
            XCTAssertEqual(
                brightness(Double(interiorCount), interiorCount),
                1.0,
                "end seam, interior \(interiorCount)"
            )
        }
    }

    func testTheBlendClampsToHalfTheInteriorOnShortSpans() {
        // One cell is the budget, but a span with one or two interior days
        // cannot spend it — the two sides would overlap. They meet instead.
        XCTAssertEqual(SchedulerSpanCurve.blendWidth(interiorCount: 1), 0.5)
        XCTAssertEqual(SchedulerSpanCurve.blendWidth(interiorCount: 2), 1.0)
        XCTAssertEqual(
            SchedulerSpanCurve.blendWidth(interiorCount: 3),
            OPSStyle.Layout.schedulerSpanBlendCells
        )
        XCTAssertEqual(
            SchedulerSpanCurve.blendWidth(interiorCount: 40),
            OPSStyle.Layout.schedulerSpanBlendCells
        )
        // A two-day span has no interior at all; there is no curve to draw.
        XCTAssertEqual(SchedulerSpanCurve.blendWidth(interiorCount: 0), 0)
        XCTAssertEqual(brightness(0, 0), 0)
    }

    func testTheGlowFallsAwayQuadraticallyInsideTheBlend() {
        // interior 4 → a full one-cell blend from the start seam.
        XCTAssertEqual(brightness(0.25, 4), 0.5625, accuracy: 1e-9)
        XCTAssertEqual(brightness(0.5, 4), 0.25, accuracy: 1e-9)
        XCTAssertEqual(brightness(0.75, 4), 0.0625, accuracy: 1e-9)
        XCTAssertEqual(brightness(1.0, 4), 0, accuracy: 1e-9)

        // Strictly downhill the whole way in — no plateau, no second bump.
        var previous = brightness(0, 4)
        for step in 1...20 {
            let value = brightness(Double(step) / 20, 4)
            XCTAssertLessThan(value, previous, "step \(step)")
            previous = value
        }
    }

    func testEverythingDeeperThanTheBlendIsQuiet() {
        // A five-day interior: one cell of glow at each end, three cells of
        // nothing in between. A long booking has nothing to say in its middle.
        for x in stride(from: 1.0, through: 4.0, by: 0.25) {
            XCTAssertEqual(brightness(x, 5), 0, accuracy: 1e-12, "x \(x)")
        }
    }

    func testTheCurveIsSymmetricAboutTheSpansMiddle() {
        // Neither cap is the important one; a range read backwards looks the
        // same as a range read forwards.
        for x in [0, 0.3, 0.75, 1.4, 3.0] {
            XCTAssertEqual(brightness(x, 6), brightness(6 - x, 6), accuracy: 1e-12, "x \(x)")
        }
    }

    func testAThreeDaySpansLoneInteriorLeavesBothSeamsWhiteAndDipsToNothing() {
        // The extreme case, and the one a founder judges first: a single
        // interior day owned by both caps at once. It takes whichever side is
        // nearer, so it is white at both edges and exactly nothing dead
        // centre — the curve telling the truth about where the middle is.
        XCTAssertEqual(brightness(0, 1), 1.0)
        XCTAssertEqual(brightness(1, 1), 1.0)
        XCTAssertEqual(brightness(0.5, 1), 0)
        XCTAssertEqual(brightness(0.25, 1), 0.25, accuracy: 1e-9)
        XCTAssertEqual(brightness(0.75, 1), 0.25, accuracy: 1e-9)
    }

    func testTheCurveNeverOutshinesTheCaps() {
        // Taking the nearer seam rather than adding the two is what keeps this
        // true: overlapping sides would drive the interior past the caps' own
        // white and the span would bulge in the middle.
        for interiorCount in [1, 2, 3, 7] {
            for step in 0...(interiorCount * 20) {
                let x = Double(step) / 20
                let value = brightness(x, interiorCount)
                XCTAssertGreaterThanOrEqual(value, 0, "interior \(interiorCount) at \(x)")
                XCTAssertLessThanOrEqual(value, 1, "interior \(interiorCount) at \(x)")
            }
        }
    }

    // MARK: - Span curve sampling (what each cell hands the gradient)

    func testEveryCellSamplesItsOwnEdgesAndNothingOutsideThem() {
        for (index, count) in [(0, 1), (0, 2), (1, 2), (0, 8), (3, 8), (7, 8)] {
            let positions = SchedulerSpanCurve.stopPositions(interiorIndex: index, interiorCount: count)
            XCTAssertEqual(positions.first, Double(index), "cell \(index)/\(count)")
            XCTAssertEqual(positions.last, Double(index) + 1, "cell \(index)/\(count)")
            XCTAssertEqual(positions, positions.sorted(), "cell \(index)/\(count) out of order")
            XCTAssertEqual(Set(positions).count, positions.count, "cell \(index)/\(count) has a duplicate")
        }
    }

    func testASeamCellIsSampledThroughTheBendAndAQuietCellIsNot() {
        // Cap-adjacent cell of a long span: two edges plus one sample through
        // the middle of the ease, so the ramp does not straighten out.
        XCTAssertEqual(
            SchedulerSpanCurve.stopPositions(interiorIndex: 0, interiorCount: 8),
            [0, 0.5, 1]
        )
        // The lone interior of a three-day span: the two sides meet in its
        // centre, so that knee is sampled too, and each half gets its bend.
        XCTAssertEqual(
            SchedulerSpanCurve.stopPositions(interiorIndex: 0, interiorCount: 1),
            [0, 0.25, 0.5, 0.75, 1]
        )
        // A flat cell buys nothing: a straight line between two zeroes is
        // already exact. (The middle knee still lands, harmlessly, at 1.5.)
        XCTAssertEqual(
            SchedulerSpanCurve.stopPositions(interiorIndex: 1, interiorCount: 3),
            [1, 1.5, 2]
        )
        for position in SchedulerSpanCurve.stopPositions(interiorIndex: 1, interiorCount: 3) {
            XCTAssertEqual(brightness(position, 3), 0, accuracy: 1e-12)
        }
    }

    // MARK: - Adaptive day number

    private func bandBrightness(_ index: Int, _ count: Int) -> Double {
        SchedulerSpanCurve.numberBandBrightness(interiorIndex: index, interiorCount: count)
    }

    func testTheNumberBandReadsTheCurveWhereTheGlyphsActuallySit() {
        // Expected means for the shipped band — leading padding to the end of
        // a two-digit run. The number is leading-aligned, so a cell's band
        // always sits at its LEADING end: bright next to the start cap, quiet
        // next to the end cap, whatever that cell's other edge is doing.
        XCTAssertEqual(bandBrightness(0, 8), 0.628375, accuracy: 1e-9)   // hard against the start cap
        XCTAssertEqual(bandBrightness(7, 8), 0.058375, accuracy: 1e-9)   // last interior, quiet end
        XCTAssertEqual(bandBrightness(3, 8), 0, accuracy: 1e-12)         // deep middle
        XCTAssertEqual(bandBrightness(0, 1), 0.3735, accuracy: 1e-9)     // three-day lone interior
    }

    func testTheNumberFlipsOnlyWhereTheCapsWhiteIsUnderIt() {
        let threshold = OPSStyle.Layout.schedulerSpanNumberFlipBrightness

        // Cap-adjacent: near-white ground under the digits — they take the
        // caps' own black.
        XCTAssertGreaterThan(bandBrightness(0, 8), threshold)
        // A three-day span's lone interior: same call, and the loudest case.
        XCTAssertGreaterThan(bandBrightness(0, 1), threshold)
        // Deep inside a span the ground is the quiet base — white stays.
        XCTAssertLessThan(bandBrightness(3, 8), threshold)
        // And the cell before the end cap keeps white too: its glow is at the
        // trailing edge, where no digit is. The flip is a reading of the
        // ground under the glyphs, not of the cell.
        XCTAssertLessThan(bandBrightness(7, 8), threshold)
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
            // Leaves the start seam at the cap's own white — and the day
            // number flips to black to survive it.
            State(name: "interior_near_cap", role: .interior, spanPosition: (index: 1, count: 6), spanEdge: .open),
            // The mirror: the glow is at this cell's trailing edge, away from
            // the number, so the number stays white.
            State(name: "interior_near_end", role: .interior, spanPosition: (index: 4, count: 6), spanEdge: .open),
            // Deep enough inside that the curve has nothing to add — the quiet
            // base, flat across the whole cell.
            State(name: "interior_middle", role: .interior, spanPosition: (index: 2, count: 5), spanEdge: .open),
            // A three-day span's lone interior: white at both edges, nothing
            // dead centre.
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
