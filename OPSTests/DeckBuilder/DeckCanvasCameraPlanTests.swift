//
//  DeckCanvasCameraPlanTests.swift
//  OPSTests
//
//  Bug 5f285f64 — "when in quick draw/dictate mode the deck designer doesn't
//  pan to the next point."
//
//  The camera used to recentre on the ANCHOR for every perimeter-entry change,
//  which meant a commit parked the view on the point the operator had just left
//  and a direction change moved nothing at all. These assert the single pure
//  decision that replaced it: for any perimeter-entry transition, which world
//  point is the operator actually working on right now.
//
//  Pure geometry — no view, no animation, no waiting.
//

import CoreGraphics
import XCTest
@testable import OPS

final class DeckCanvasCameraPlanTests: XCTestCase {

    // MARK: - Fixtures

    /// An absolute-direction anchor (no incoming edge — the first point of a run).
    private func absoluteAnchor(at position: CGPoint, id: String = "v1") -> PerimeterEntryAnchor {
        PerimeterEntryAnchor(
            vertexId: id,
            position: position,
            incomingAngleDegrees: nil,
            rootVertexId: "v1"
        )
    }

    /// A relative-direction anchor — the operator has already drawn into it.
    private func relativeAnchor(
        at position: CGPoint,
        incomingAngleDegrees: Double,
        id: String = "v2"
    ) -> PerimeterEntryAnchor {
        PerimeterEntryAnchor(
            vertexId: id,
            position: position,
            incomingAngleDegrees: incomingAngleDegrees,
            rootVertexId: "v1"
        )
    }

    private func inches(_ value: Double) -> PerimeterLengthDraft {
        PerimeterLengthDraft(measurementSystem: .imperial, totalInches: value)
    }

    private let zeroDraft = PerimeterLengthDraft.zero(system: .imperial)

    // MARK: - Commit

    /// The reported failure. Committing a length moves the state to
    /// `.choosingDirection` on the vertex that was just created — THAT is the
    /// point the operator is now working from, so that is what the camera follows.
    func testCommitFollowsTheNewAnchor() {
        let previous = PerimeterEntryMode.enteringLength(
            anchor: absoluteAnchor(at: CGPoint(x: 0, y: 0)),
            direction: .right,
            draft: inches(120)
        )
        let next = PerimeterEntryMode.choosingDirection(
            anchor: absoluteAnchor(at: CGPoint(x: 120, y: 0), id: "v2")
        )

        XCTAssertEqual(
            DeckCanvasCameraPlan.focus(after: next, previous: previous, ghostLength: 96),
            CGPoint(x: 120, y: 0)
        )
    }

    /// Stepping back from a length to the direction wheel keeps the same anchor;
    /// following it is a no-op pan, never a jump somewhere new.
    func testSteppingBackToTheDirectionWheelFollowsTheSameAnchor() {
        let anchor = absoluteAnchor(at: CGPoint(x: 340, y: -80))
        let previous = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .down, draft: inches(48))
        let next = PerimeterEntryMode.choosingDirection(anchor: anchor)

        XCTAssertEqual(
            DeckCanvasCameraPlan.focus(after: next, previous: previous, ghostLength: 96),
            anchor.position
        )
    }

    // MARK: - Direction change

    /// Picking a direction off the wheel produces no length yet — only the ghost
    /// ray. The camera follows the ray's tip so the operator can see where the
    /// run is about to go even when the anchor sits near an edge.
    func testDirectionChangeWithZeroLengthFollowsTheGhostEnd() {
        let anchor = absoluteAnchor(at: CGPoint(x: 100, y: 100))
        let previous = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .right, draft: zeroDraft)
        let next = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .up, draft: zeroDraft)

        let focus = DeckCanvasCameraPlan.focus(after: next, previous: previous, ghostLength: 96)

        // `.up` is 270° in canvas space — screen y decreases.
        XCTAssertEqual(focus?.x ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(focus?.y ?? .nan, 4, accuracy: 0.0001)
    }

    /// A relative anchor rotates the ghost by the incoming heading, exactly as
    /// the canvas draws it.
    func testGhostEndUsesTheAnchorIncomingHeading() {
        let anchor = relativeAnchor(at: CGPoint(x: 200, y: 200), incomingAngleDegrees: 90)
        let previous = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .straight, draft: zeroDraft)
        let next = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .left90, draft: zeroDraft)

        // Incoming 90° (heading south) turned -90° = 0° → due east.
        let focus = DeckCanvasCameraPlan.focus(after: next, previous: previous, ghostLength: 100)

        XCTAssertEqual(focus?.x ?? .nan, 300, accuracy: 0.0001)
        XCTAssertEqual(focus?.y ?? .nan, 200, accuracy: 0.0001)
    }

    /// Reorienting a draft that already has a length swings its far end around
    /// the anchor. The far end is the work — follow it, not the anchor.
    func testDirectionChangeWithLengthFollowsTheDraftEnd() {
        let anchor = absoluteAnchor(at: CGPoint(x: 100, y: 100))
        let previous = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .right, draft: inches(72))
        let next = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .up, draft: inches(72))

        let expected = PerimeterEntryGeometry.endpoint(
            from: anchor.position,
            direction: .up,
            lengthInches: 72,
            scaleFactor: 1,
            incomingAngleDegrees: nil,
            fallbackScale: DeckBuilderViewModel.prescaleFallbackScale
        )
        let focus = DeckCanvasCameraPlan.focus(
            after: next,
            previous: previous,
            ghostLength: 96,
            scaleFactor: 1
        )

        XCTAssertEqual(focus?.x ?? .nan, expected.x, accuracy: 0.0001)
        XCTAssertEqual(focus?.y ?? .nan, expected.y, accuracy: 0.0001)
        XCTAssertEqual(focus?.y ?? .nan, 28, accuracy: 0.0001)
    }

    // MARK: - Length change

    /// Dictating digits grows the draft. Each new far end must be followed — the
    /// original symptom was a dictated run walking straight off the screen.
    func testLengthChangeFollowsTheDraftEnd() {
        let anchor = absoluteAnchor(at: CGPoint(x: 0, y: 0))
        let previous = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .right, draft: inches(12))
        let next = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .right, draft: inches(240))

        let focus = DeckCanvasCameraPlan.focus(
            after: next,
            previous: previous,
            ghostLength: 96,
            scaleFactor: 1
        )

        XCTAssertEqual(focus?.x ?? .nan, 240, accuracy: 0.0001)
        XCTAssertEqual(focus?.y ?? .nan, 0, accuracy: 0.0001)
    }

    /// An uncalibrated drawing has no `scaleFactor` yet still draws at a sound
    /// internal scale. The plan must use the same prescale fallback the canvas,
    /// the snap grid and every committed edge already use.
    func testUncalibratedDraftUsesThePrescaleFallback() {
        let anchor = absoluteAnchor(at: CGPoint(x: 0, y: 0))
        let previous = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .right, draft: inches(0))
        let next = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .right, draft: inches(72))

        let focus = DeckCanvasCameraPlan.focus(after: next, previous: previous, ghostLength: 96)

        XCTAssertEqual(
            focus?.x ?? .nan,
            72 * DeckBuilderViewModel.prescaleFallbackScale,
            accuracy: 0.0001
        )
    }

    // MARK: - No focus

    func testIdleTransitionHasNoFocus() {
        XCTAssertNil(DeckCanvasCameraPlan.focus(after: .idle, previous: .idle, ghostLength: 96))
    }

    /// Cancelling or closing the loop ends the walk. Nothing is being placed, so
    /// the camera has nothing to follow.
    func testLeavingPerimeterEntryHasNoFocus() {
        let previous = PerimeterEntryMode.enteringLength(
            anchor: absoluteAnchor(at: CGPoint(x: 10, y: 10)),
            direction: .right,
            draft: inches(36)
        )

        XCTAssertNil(DeckCanvasCameraPlan.focus(after: .idle, previous: previous, ghostLength: 96))
    }

    /// Starting a walk is the one transition that still deserves a recentre: the
    /// operator has just planted a point and needs their bearings. The plan hands
    /// that case back to the view by reporting no follow focus.
    func testStartingAWalkFromIdleHasNoFollowFocus() {
        let next = PerimeterEntryMode.choosingDirection(anchor: absoluteAnchor(at: CGPoint(x: 900, y: 900)))

        XCTAssertNil(DeckCanvasCameraPlan.focus(after: next, previous: .idle, ghostLength: 96))
    }

    // MARK: - State-only focus (drag release)

    /// A direction drag emits no state change when the finger lifts on the
    /// direction it was already on, so the release path asks the plan about the
    /// CURRENT state rather than a transition. Same answer, no transition needed.
    func testFocusForCurrentStateTracksTheDraftEndWithoutATransition() {
        let anchor = absoluteAnchor(at: CGPoint(x: 100, y: 100))
        let mode = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .down, draft: inches(60))

        let focus = DeckCanvasCameraPlan.focus(for: mode, ghostLength: 96, scaleFactor: 1)

        XCTAssertEqual(focus?.x ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(focus?.y ?? .nan, 160, accuracy: 0.0001)
    }

    func testFocusForIdleStateIsNil() {
        XCTAssertNil(DeckCanvasCameraPlan.focus(for: .idle, ghostLength: 96))
    }

    // MARK: - Degenerate input

    func testNonFiniteGhostLengthFallsBackToTheAnchor() {
        let anchor = absoluteAnchor(at: CGPoint(x: 40, y: 40))
        let previous = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .right, draft: zeroDraft)
        let next = PerimeterEntryMode.enteringLength(anchor: anchor, direction: .up, draft: zeroDraft)

        XCTAssertEqual(
            DeckCanvasCameraPlan.focus(after: next, previous: previous, ghostLength: .nan),
            anchor.position
        )
    }
}
