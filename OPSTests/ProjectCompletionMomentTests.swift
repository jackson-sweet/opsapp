//
//  ProjectCompletionMomentTests.swift
//  OPSTests
//
//  Locks the completion moment's choreography against the brand motion
//  contract in `.claude/animation-studio.local.md`:
//
//    • primary gesture 250–350ms; whole sequence under ~600ms
//    • Reduce Motion → opacity-only at 150ms, and the completed state is
//      still reached (equivalence, not removal)
//    • the ring hands the eye to the state change rather than ending beside it
//    • the action bar outlives the moment, so the stamp is never cut off
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ProjectCompletionMomentTests
//

import XCTest
import SwiftUI
@testable import OPS

final class ProjectCompletionMomentTests: XCTestCase {

    private var full: ProjectCompletionMoment.Timeline {
        ProjectCompletionMoment.timeline(reduceMotion: false)
    }

    private var reduced: ProjectCompletionMoment.Timeline {
        ProjectCompletionMoment.timeline(reduceMotion: true)
    }

    // MARK: - Full motion

    func testRingSweepSitsInThePrimaryGestureWindow() {
        XCTAssertTrue(full.sweeps, "Full motion must actually sweep the ring")
        XCTAssertGreaterThanOrEqual(full.ringReveal.duration, 0.250)
        XCTAssertLessThanOrEqual(full.ringReveal.duration, 0.350)
        XCTAssertEqual(full.ringReveal.delay, 0, "The ring starts the moment; nothing precedes it")
    }

    func testWholeSequenceIsOverBeforeTheOperatorLooksAway() {
        XCTAssertLessThanOrEqual(
            full.motionDuration, 0.600,
            "Sequence including the status settle must not exceed ~600ms"
        )
    }

    func testStampBeginsWhileTheRingIsStillDrawing() {
        // The ring's job is to carry the eye INTO the state change. If the
        // stamp started after the ring closed, the two would read as separate
        // events instead of one.
        XCTAssertLessThan(
            full.stamp.delay, full.ringReveal.end,
            "The stamp must overlap the ring's tail"
        )
        XCTAssertGreaterThan(full.stamp.delay, 0, "The ring leads; the stamp follows")
    }

    func testRingRetiresOnlyOnceItHasDrawn() {
        XCTAssertGreaterThanOrEqual(
            full.ringFade.delay, full.ringReveal.end,
            "The ring must complete its single pass before fading"
        )
        XCTAssertEqual(full.ringFade.end, full.motionDuration, accuracy: 0.0001,
                       "The ring leaving is the last thing that happens")
    }

    func testStampIsFullySettledBeforeTheSequenceEnds() {
        XCTAssertLessThanOrEqual(full.stamp.end, full.motionDuration)
    }

    // MARK: - Reduced motion

    func testReducedMotionNeverMovesGeometry() {
        XCTAssertFalse(
            reduced.sweeps,
            "Reduce Motion must not sweep, scale, or trim — opacity only"
        )
    }

    func testReducedMotionUsesTheMandated150msSteps() {
        for (name, step) in [
            ("ringReveal", reduced.ringReveal),
            ("stamp", reduced.stamp),
            ("ringFade", reduced.ringFade)
        ] {
            XCTAssertEqual(
                step.duration, 0.150, accuracy: 0.0001,
                "\(name) must fall back to the 150ms opacity step"
            )
        }
    }

    func testReducedMotionStillReachesTheCompletedState() {
        // Equivalence, not removal: the stamp still happens, and it leads
        // rather than waiting for a sweep that is not there.
        XCTAssertEqual(reduced.stamp.delay, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(reduced.stamp.duration, 0)
        XCTAssertLessThan(reduced.motionDuration, full.motionDuration,
                          "The reduced branch is shorter, not merely re-curved")
    }

    func testReducedMotionRingStillRetires() {
        XCTAssertGreaterThanOrEqual(reduced.ringFade.delay, reduced.ringReveal.end)
        XCTAssertEqual(reduced.ringFade.end, reduced.motionDuration, accuracy: 0.0001)
    }

    // MARK: - The bar must outlive the moment

    func testExitDwellOutlastsTheMotionInBothBranches() {
        XCTAssertGreaterThan(
            full.exitDwell, full.motionDuration,
            "Project mode must stay open past the moment or the stamp is cut off"
        )
        XCTAssertGreaterThan(reduced.exitDwell, reduced.motionDuration)
        XCTAssertEqual(
            full.exitDwell - full.motionDuration,
            ProjectCompletionMoment.settleBeat,
            accuracy: 0.0001
        )
    }

    func testExitDwellIsStillShortEnoughToFeelDecisive() {
        // The old behaviour exited at 0.5s. The moment may extend that, but
        // not into "why is this screen still here" territory.
        XCTAssertLessThanOrEqual(full.exitDwell, 0.900)
    }

    // MARK: - Ring geometry

    func testRingClearsTheButtonButStaysInsideTheActionBar() {
        // Larger than the touch target, so it encircles the button…
        XCTAssertGreaterThan(
            ProjectCompletionMoment.ringDiameter,
            OPSStyle.Layout.touchTargetStandard
        )
        // …and small enough that the bar's 10pt vertical padding absorbs the
        // overhang, so the enclosing horizontal ScrollView never clips it.
        let overhang = (ProjectCompletionMoment.ringDiameter - OPSStyle.Layout.touchTargetStandard) / 2
            + ProjectCompletionMoment.ringLineWidth / 2
        XCTAssertLessThan(overhang, 10, "Ring would be clipped by the action bar's bounds")
    }

    func testRingScaleSweepsOutwardOnceAndLandsWithoutOvershoot() {
        XCTAssertEqual(
            ProjectCompletionMoment.ringScale(at: 0),
            ProjectCompletionMoment.ringStartScale,
            accuracy: 0.0001
        )
        XCTAssertEqual(ProjectCompletionMoment.ringScale(at: 1), 1, accuracy: 0.0001)
        // Monotonic — it expands once, it does not pulse or rebound.
        var previous = ProjectCompletionMoment.ringScale(at: 0)
        for step in 1...20 {
            let value = ProjectCompletionMoment.ringScale(at: Double(step) / 20)
            XCTAssertGreaterThan(value, previous, "Ring scale must never reverse")
            previous = value
        }
        // Never overshoots 1.0 — no bounce anywhere in the curve's domain.
        XCTAssertEqual(ProjectCompletionMoment.ringScale(at: 1.4), 1, accuracy: 0.0001)
    }

    // MARK: - Tokens, not literals

    func testStampedStateComesFromTheDesignSystemAndStatusVocabulary() {
        XCTAssertEqual(
            ProjectCompletionMoment.stampedLabel,
            Status.completed.displayName,
            "The button stamps to the project's actual status, not a new word"
        )
        XCTAssertEqual(ProjectCompletionMoment.stampedIcon, OPSStyle.Icons.complete)
        XCTAssertEqual(
            ProjectCompletionMoment.completedColor,
            OPSStyle.Colors.statusColor(for: .completed)
        )
        XCTAssertEqual(
            ProjectCompletionMoment.ringLineWidth,
            OPSStyle.Layout.Border.thick
        )
    }
}
