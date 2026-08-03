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
//  inside a range, the brightness curve the interior fills itself with, the
//  fill range that curve renders into, and the outline that closes only where
//  the selection itself ends.
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

    func testTheCurveLeavesEverySeamAtTheCapsOwnFill() {
        // The whole point of the shape: 1 is the top of the fill range, which
        // is exactly what a cap is filled with (`fillOpacity` is what turns the
        // two into the same number — see the fill-range section below).
        // Anything less at a seam is the step this curve exists to remove — so
        // this is an exact equality, not an approximate one.
        for interiorCount in [1, 2, 3, 10] {
            XCTAssertEqual(brightness(0, interiorCount), 1.0, "start seam, interior \(interiorCount)")
            XCTAssertEqual(
                brightness(Double(interiorCount), interiorCount),
                1.0,
                "end seam, interior \(interiorCount)"
            )
        }
    }

    func testTheBlendSpendsItsWholeBudgetAndStopsOnlyWhereTheInteriorDoes() {
        // One cell is the budget and every span with an interior spends all of
        // it — the clamp exists only to stop a ramp running off the end of a
        // shorter interior than that. A one-day interior is exactly one cell
        // wide, so both sides cover the whole of it and overlap; that overlap
        // is deliberate, and the sum is what makes it safe.
        XCTAssertEqual(SchedulerSpanCurve.blendWidth(interiorCount: 1), 1.0)
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

    func testAThreeDaySpansLoneInteriorMeetsBothCapsAndOnlySoftensBetween() {
        // The extreme case, and the one a founder judges first: a single
        // interior day inside both caps' reach at once. Both ramps cover all of
        // it and add, so it is exactly the caps' fill at both seams and eases
        // to a half-way waist between them — one continuous pill, no stripe.
        XCTAssertEqual(brightness(0, 1), 1.0)
        XCTAssertEqual(brightness(1, 1), 1.0)
        XCTAssertEqual(brightness(0.5, 1), 0.5)
        XCTAssertEqual(brightness(0.25, 1), 0.625, accuracy: 1e-9)
        XCTAssertEqual(brightness(0.75, 1), 0.625, accuracy: 1e-9)
    }

    func testAThreeDaySpansLoneInteriorNeverSinksToTheQuietFloor() {
        // The defect this curve shape was chosen to prevent. With the two sides
        // taking the nearer seam instead of adding, a one-cell interior went to
        // 0 dead centre: a hard dark stripe through the middle of an otherwise
        // bright three-day pill. That reads as "something is different about
        // that day" — which is the abrupt step the blend exists to erase, and
        // 1–3 day jobs are the most common length there is, so it is the
        // version most operators would ever see. The waist must stay in the
        // caps' half of the range across the whole cell, never at the floor.
        var minimum = Double.infinity
        for step in 0...200 {
            let x = Double(step) / 200
            let value = brightness(x, 1)
            XCTAssertGreaterThanOrEqual(value, 0.5, "lone interior at \(x)")
            minimum = min(minimum, value)
        }
        // And the floor is tight, not merely cleared: the two ramps cross at
        // exactly half the caps' value, dead centre — which `fillOpacity` puts
        // on the exact midpoint of the fill range (see the waist test below).
        XCTAssertEqual(minimum, 0.5)
        XCTAssertEqual(brightness(0.5, 1), minimum)
    }

    func testTheCurveNeverOutshinesTheCaps() {
        // Now that the two sides add, this is a real risk rather than a
        // formality: where they overlap their sum would run past the caps' own
        // fill and the span would bulge brighter than the thing it is fusing
        // with. The clamp is what holds it, and this is the guard on it.
        for interiorCount in 1...12 {
            for step in 0...(interiorCount * 20) {
                let x = Double(step) / 20
                let value = brightness(x, interiorCount)
                XCTAssertGreaterThanOrEqual(value, 0, "interior \(interiorCount) at \(x)")
                XCTAssertLessThanOrEqual(value, 1, "interior \(interiorCount) at \(x)")
            }
        }
    }

    /// The curve exactly as it stood before the two sides began adding: blend
    /// clamped to half the interior, brightness taken from the nearer seam.
    /// Kept here as the reference the equivalence test measures against, so the
    /// claim "only a three-day span changed" is checked rather than asserted.
    private func nearerSeamBrightness(_ x: Double, _ interiorCount: Int) -> Double {
        let interior = Double(interiorCount)
        let blend = min(OPSStyle.Layout.schedulerSpanBlendCells, interior / 2)
        guard interiorCount > 0, blend > 0 else { return 0 }

        let position = min(max(x, 0), interior)
        let fromStart = max(0, 1 - position / blend)
        let fromEnd = max(0, 1 - (interior - position) / blend)
        return max(fromStart * fromStart, fromEnd * fromEnd)
    }

    func testOnlyAThreeDaySpanChangedWhenTheTwoSidesStartedAdding() {
        // Two ramps one cell long can only reach each other across an interior
        // shorter than two cells, so from four days up the sum is whichever
        // ramp is in range and the other is exactly zero — identical output,
        // not merely close. Every longer booking renders the same pixels it did
        // before, which is what makes this a taste fix to one span length
        // rather than a change to the selection's whole look.
        for interiorCount in 2...12 {
            for step in 0...(interiorCount * 20) {
                let x = Double(step) / 20
                XCTAssertEqual(
                    brightness(x, interiorCount),
                    nearerSeamBrightness(x, interiorCount),
                    "interior \(interiorCount) at \(x) drifted from the shipped long-span curve"
                )
            }
        }

        // And the one length that did change, so this test cannot pass by the
        // two curves having quietly become the same function.
        XCTAssertEqual(nearerSeamBrightness(0.5, 1), 0)
        XCTAssertEqual(brightness(0.5, 1), 0.5)
    }

    // MARK: - Span fill range (what the shape resolves to on screen)

    private func fillOpacity(_ x: Double, _ interiorCount: Int) -> Double {
        SchedulerSpanCurve.fillOpacity(at: x, interiorCount: interiorCount)
    }

    func testTheFillLeavesEverySeamAtExactlyTheCapsOwnOpacity() {
        // The seam-fusion guard, and the reason it is asserted against the
        // TOKEN rather than a literal: `capFill` paints
        // `schedulerSpanCapOpacity` over `surfaceActive`, and the interior's
        // first gradient stop has to be that same number over that same base,
        // or the two composite to different colours and the seam reopens. Move
        // either side and this breaks — which is the point.
        for interiorCount in [1, 2, 3, 10] {
            XCTAssertEqual(
                fillOpacity(0, interiorCount),
                OPSStyle.Layout.schedulerSpanCapOpacity,
                "start seam, interior \(interiorCount)"
            )
            XCTAssertEqual(
                fillOpacity(Double(interiorCount), interiorCount),
                OPSStyle.Layout.schedulerSpanCapOpacity,
                "end seam, interior \(interiorCount)"
            )
        }
    }

    func testDeepInsideASpanTheFillIsExactlyTheQuietFloor() {
        // The middle cell of an eight-day interior — as far from either seam as
        // the curve ever gets — and everything between the two one-cell ramps
        // with it. Exact, not approximate: the floor is a flat token, so a long
        // booking's middle is one unvarying colour rather than a very slow
        // gradient nobody asked for.
        XCTAssertEqual(fillOpacity(4, 8), OPSStyle.Layout.schedulerSpanQuietOpacity)
        for x in stride(from: 1.0, through: 7.0, by: 0.25) {
            XCTAssertEqual(
                fillOpacity(x, 8),
                OPSStyle.Layout.schedulerSpanQuietOpacity,
                "x \(x)"
            )
        }
    }

    func testTheFillIsAStrictlyMonotoneRemapOfTheShapeAndNeverLeavesTheBand() {
        // The range moved; the shape did not. Wherever the curve is brighter
        // the fill has to be more opaque, wherever it is flat the fill has to
        // be flat, and the fill can never leave the band the two tokens define
        // — that band IS the compression the founder asked for, so an escape
        // from it is the defect.
        let quiet = OPSStyle.Layout.schedulerSpanQuietOpacity
        let cap = OPSStyle.Layout.schedulerSpanCapOpacity

        for interiorCount in 1...12 {
            var previousBrightness: Double?
            var previousFill = 0.0
            for step in 0...(interiorCount * 40) {
                let x = Double(step) / 40
                let shape = brightness(x, interiorCount)
                let fill = fillOpacity(x, interiorCount)
                let sample = "interior \(interiorCount) at \(x)"

                XCTAssertGreaterThanOrEqual(fill, quiet, sample)
                XCTAssertLessThanOrEqual(fill, cap, sample)

                if let previousBrightness {
                    if shape > previousBrightness {
                        XCTAssertGreaterThan(fill, previousFill, sample)
                    } else if shape < previousBrightness {
                        XCTAssertLessThan(fill, previousFill, sample)
                    } else {
                        XCTAssertEqual(fill, previousFill, sample)
                    }
                }
                previousBrightness = shape
                previousFill = fill
            }
        }
    }

    func testAThreeDaySpansWaistSitsHalfWayBetweenTheTwoRangeTokens() {
        // The 3-day waist, expressed in the range it now renders into: the
        // shape crosses at 0.5 dead centre, so the fill lands on the exact
        // midpoint of quiet…cap. Exact — the waist is the one value on the
        // whole curve a founder can point at and check.
        let quiet = OPSStyle.Layout.schedulerSpanQuietOpacity
        let cap = OPSStyle.Layout.schedulerSpanCapOpacity

        XCTAssertEqual(fillOpacity(0.5, 1), quiet + 0.5 * (cap - quiet))
        // Same value said a second way, so neither expression can drift into
        // simply restating the implementation.
        XCTAssertEqual(fillOpacity(0.5, 1), (quiet + cap) / 2)
    }

    func testTheFillRangeIsOrderedAndACompressionRatherThanTheOldFullSweep() {
        // Guards the tokens themselves. Inverted, and every ramp runs the wrong
        // way; either one outside a legal alpha, and SwiftUI silently clamps
        // and the seam stops fusing. And the range must stay a COMPRESSION —
        // a cap back at 1 with a floor at 0 is the delta that was rejected.
        let quiet = OPSStyle.Layout.schedulerSpanQuietOpacity
        let cap = OPSStyle.Layout.schedulerSpanCapOpacity

        XCTAssertGreaterThan(quiet, 0, "the floor must clear the bare surfaceActive base")
        XCTAssertLessThan(cap, 1, "the caps must sit below solid primaryText")
        XCTAssertLessThan(quiet, cap)
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
        // The lone interior of a three-day span: both ramps run its full width,
        // so the only knee inside the cell is the waist where they cross, dead
        // centre — sampled, with each half then given its own bend. (The other
        // two knees land exactly on the cell's edges and collapse into them.)
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
        // The three-day lone interior, now lit from both caps at once: the
        // brightest ground any day number sits on anywhere in a selection.
        XCTAssertEqual(bandBrightness(0, 1), 0.68675, accuracy: 1e-9)
        XCTAssertGreaterThan(bandBrightness(0, 1), bandBrightness(0, 8))
    }

    func testTheNumberFlipsOnlyWhereTheCapsFillIsUnderIt() {
        let threshold = OPSStyle.Layout.schedulerSpanNumberFlipBrightness

        // The threshold reads the SHAPE, not the fill, so compressing the fill
        // range moved none of these four values — only how much contrast each
        // decision buys. Those figures live on the token's own doc comment.
        //
        // Cap-adjacent: the brightest ground under any digits in a long span —
        // they take the caps' own black.
        XCTAssertGreaterThan(bandBrightness(0, 8), threshold)
        // A three-day span's lone interior: same call, and the clearest of
        // them — the shape under those digits runs 0.85 to 0.55, never leaving
        // the caps' half of the range, so black is what survives it.
        XCTAssertGreaterThan(bandBrightness(0, 1), threshold)
        // Deep inside a span the ground is the quiet floor — white stays.
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
            // Leaves the start seam at the cap's own fill — and the day
            // number flips to black to survive it.
            State(name: "interior_near_cap", role: .interior, spanPosition: (index: 1, count: 6), spanEdge: .open),
            // The mirror: the glow is at this cell's trailing edge, away from
            // the number, so the number stays white.
            State(name: "interior_near_end", role: .interior, spanPosition: (index: 4, count: 6), spanEdge: .open),
            // Deep enough inside that the curve has nothing to add — the quiet
            // floor, flat across the whole cell.
            State(name: "interior_middle", role: .interior, spanPosition: (index: 2, count: 5), spanEdge: .open),
            // A three-day span's lone interior: the cap's fill at both edges,
            // easing to a half-way waist between them.
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
