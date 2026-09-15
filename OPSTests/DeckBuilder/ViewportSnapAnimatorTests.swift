//
//  ViewportSnapAnimatorTests.swift
//  OPSTests
//
//  Bug 5f285f64 — "when in quick draw/dictate mode the deck designer doesn't
//  pan to the next point."
//
//  The speed-draw chrome grows ~150–190pt when a length picker replaces the
//  status strip, and it animates that height over the same 200ms the camera pan
//  needs. The layout handler used to STOP the snap on every one of those frames,
//  so the pan died at roughly 0% progress and the operator saw a twitch instead
//  of a glide.
//
//  The fix is to retarget rather than cancel. These assert that: an in-flight
//  ramp can be shifted mid-ramp, it lands on the shifted destination, and it
//  never travels backwards while doing so.
//
//  The animator is driven by an injected clock here, so a 200ms ramp is asserted
//  in microseconds instead of waited on.
//

import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class ViewportSnapAnimatorTests: XCTestCase {

    private let tick: TimeInterval = 1.0 / 60.0

    // MARK: - Retarget

    /// The reported failure, in miniature: a pan is 30% of the way to its
    /// destination when the chrome resizes under it. The ramp must absorb the
    /// correction and carry on to the corrected destination.
    func testRetargetingAnInFlightSnapLandsOnTheShiftedTarget() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let animator = ViewportSnapAnimator(driver: .manual, now: { clock })
        var emitted: [CGSize] = []

        animator.animate(
            from: .zero,
            to: CGSize(width: 100, height: 0),
            duration: 0.2,
            reduceMotion: false
        ) { emitted.append($0) }

        // 30% of the way along.
        clock = clock.addingTimeInterval(0.06)
        animator.advance(to: clock)
        let midRampWidth = emitted.last?.width ?? .nan
        XCTAssertGreaterThan(midRampWidth, 0)
        XCTAssertLessThan(midRampWidth, 100)

        // The chrome grew: lift the camera by 80pt without cancelling the pan.
        XCTAssertTrue(animator.translateTarget(by: CGSize(width: 0, height: -80)))
        XCTAssertEqual(emitted.last?.height ?? .nan, -80, accuracy: 0.0001,
                       "the correction must land in the same frame as the chrome change")
        XCTAssertEqual(emitted.last?.width ?? .nan, midRampWidth, accuracy: 0.0001,
                       "retargeting must not disturb progress already made")

        for _ in 0..<20 {
            clock = clock.addingTimeInterval(tick)
            animator.advance(to: clock)
        }

        XCTAssertEqual(emitted.last?.width ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(emitted.last?.height ?? .nan, -80, accuracy: 0.0001)
    }

    /// A retarget must never read as a stutter: every step moves toward the
    /// destination on both axes, never back.
    func testRetargetedRampNeverMovesBackwards() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let animator = ViewportSnapAnimator(driver: .manual, now: { clock })
        var emitted: [CGSize] = []

        animator.animate(
            from: .zero,
            to: CGSize(width: 100, height: 0),
            duration: 0.2,
            reduceMotion: false
        ) { emitted.append($0) }

        for step in 0..<20 {
            clock = clock.addingTimeInterval(tick)
            animator.advance(to: clock)
            if step == 3 {
                animator.translateTarget(by: CGSize(width: 0, height: -80))
            }
        }

        for (previous, next) in zip(emitted, emitted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.width, previous.width - 1e-9, "horizontal pan reversed")
            XCTAssertLessThanOrEqual(next.height, previous.height + 1e-9, "vertical pan reversed")
        }
        XCTAssertEqual(emitted.last?.width ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(emitted.last?.height ?? .nan, -80, accuracy: 0.0001)
    }

    /// Successive chrome frames each shift the ramp a little; they accumulate.
    func testSuccessiveRetargetsAccumulate() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let animator = ViewportSnapAnimator(driver: .manual, now: { clock })
        var emitted: [CGSize] = []

        animator.animate(
            from: .zero,
            to: CGSize(width: 100, height: 0),
            duration: 0.2,
            reduceMotion: false
        ) { emitted.append($0) }

        for _ in 0..<5 {
            clock = clock.addingTimeInterval(tick)
            animator.advance(to: clock)
            animator.translateTarget(by: CGSize(width: 0, height: -16))
        }
        for _ in 0..<20 {
            clock = clock.addingTimeInterval(tick)
            animator.advance(to: clock)
        }

        XCTAssertEqual(emitted.last?.width ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(emitted.last?.height ?? .nan, -80, accuracy: 0.0001)
    }

    // MARK: - Refusals

    /// With nothing in flight the caller owns the camera and must place it
    /// itself — the animator says so rather than silently swallowing the move.
    func testRetargetIsRefusedWhenNothingIsInFlight() {
        let animator = ViewportSnapAnimator(driver: .manual, now: { Date(timeIntervalSinceReferenceDate: 0) })

        XCTAssertFalse(animator.translateTarget(by: CGSize(width: 0, height: -80)))
    }

    func testRetargetIsRefusedOnceTheSnapHasFinished() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let animator = ViewportSnapAnimator(driver: .manual, now: { clock })
        var emitted: [CGSize] = []

        animator.animate(
            from: .zero,
            to: CGSize(width: 100, height: 0),
            duration: 0.2,
            reduceMotion: false
        ) { emitted.append($0) }

        clock = clock.addingTimeInterval(0.25)
        animator.advance(to: clock)

        XCTAssertEqual(emitted.last?.width ?? .nan, 100, accuracy: 0.0001)
        XCTAssertFalse(animator.translateTarget(by: CGSize(width: 0, height: -80)))
    }

    func testRetargetIgnoresNonFiniteDeltas() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let animator = ViewportSnapAnimator(driver: .manual, now: { clock })
        var emitted: [CGSize] = []

        animator.animate(
            from: .zero,
            to: CGSize(width: 100, height: 0),
            duration: 0.2,
            reduceMotion: false
        ) { emitted.append($0) }
        clock = clock.addingTimeInterval(0.06)
        animator.advance(to: clock)

        XCTAssertFalse(animator.translateTarget(by: CGSize(width: .nan, height: 0)))

        clock = clock.addingTimeInterval(0.25)
        animator.advance(to: clock)
        XCTAssertEqual(emitted.last?.width ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(emitted.last?.height ?? .nan, 0, accuracy: 0.0001)
    }

    func testStopEndsTheRamp() {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let animator = ViewportSnapAnimator(driver: .manual, now: { clock })
        var emitted: [CGSize] = []

        animator.animate(
            from: .zero,
            to: CGSize(width: 100, height: 0),
            duration: 0.2,
            reduceMotion: false
        ) { emitted.append($0) }
        animator.stop()

        clock = clock.addingTimeInterval(0.1)
        animator.advance(to: clock)

        XCTAssertEqual(emitted.count, 1, "a stopped ramp emits nothing further")
        XCTAssertFalse(animator.translateTarget(by: CGSize(width: 0, height: -80)))
    }

    // MARK: - Reduced motion

    /// Reduce Motion places the camera at the destination immediately. There is
    /// no ramp to retarget — the caller keeps ownership.
    func testReducedMotionPlacesTheCameraImmediatelyAndHasNothingToRetarget() {
        let animator = ViewportSnapAnimator(driver: .manual, now: { Date(timeIntervalSinceReferenceDate: 0) })
        var emitted: [CGSize] = []

        animator.animate(
            from: .zero,
            to: CGSize(width: 100, height: -40),
            duration: 0.2,
            reduceMotion: true
        ) { emitted.append($0) }

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.width ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(emitted.first?.height ?? .nan, -40, accuracy: 0.0001)
        XCTAssertFalse(animator.translateTarget(by: CGSize(width: 0, height: -80)))
    }
}
