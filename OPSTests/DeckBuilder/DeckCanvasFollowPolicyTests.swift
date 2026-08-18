//
//  DeckCanvasFollowPolicyTests.swift
//  OPSTests
//
//  Bug 5f285f64 — "when in quick draw/dictate mode the deck designer doesn't
//  pan to the next point."
//
//  The camera followed the anchor, so the point being created could sit off
//  screen indefinitely. These assert the policy that replaced it: the new point
//  is always brought into view, the anchor comes too when both fit, and the
//  camera moves the least it can.
//
//  Pure screen-space maths — no rendering, no waiting.
//

import CoreGraphics
import XCTest
@testable import OPS

final class DeckCanvasFollowPolicyTests: XCTestCase {

    /// A 390 × 700 phone viewport inset by one touch target on every side.
    private let safeArea = CGRect(x: 0, y: 0, width: 390, height: 700)
        .insetBy(dx: 44, dy: 44)

    // MARK: - The reported failure

    /// The dictated endpoint lands past the right edge. The camera must move.
    func testPansWhenTheNewPointIsOffScreen() {
        let pan = DeckCanvasFollowPolicy.pan(
            focus: CGPoint(x: 520, y: 300),
            context: CGPoint(x: 200, y: 300),
            safeArea: safeArea
        )

        XCTAssertLessThan(pan.width, 0, "the canvas must slide left to reveal the new point")
        XCTAssertEqual(pan.height, 0, accuracy: 1e-9, "nothing was off-screen vertically")
    }

    /// After the pan the new point is inside the work area — the whole point of
    /// the exercise.
    func testPanActuallyBringsTheNewPointIntoView() {
        let focus = CGPoint(x: 520, y: 900)
        let pan = DeckCanvasFollowPolicy.pan(
            focus: focus,
            context: CGPoint(x: 480, y: 860),
            safeArea: safeArea
        )
        let moved = CGPoint(x: focus.x + pan.width, y: focus.y + pan.height)

        assertInside(moved, "focus still outside the work area after panning")
    }

    /// Successive dictated points keep walking the drawing along; each one
    /// must land in view.
    func testEachSuccessivePointIsBroughtIntoView() {
        var offset = CGSize.zero
        var anchor = CGPoint(x: 100, y: 100)

        for step in 1...6 {
            let end = CGPoint(x: anchor.x + 260, y: anchor.y + 120)
            let onScreenAnchor = CGPoint(x: anchor.x + offset.width, y: anchor.y + offset.height)
            let onScreenEnd = CGPoint(x: end.x + offset.width, y: end.y + offset.height)

            let pan = DeckCanvasFollowPolicy.pan(
                focus: onScreenEnd,
                context: onScreenAnchor,
                safeArea: safeArea
            )
            offset = CGSize(width: offset.width + pan.width, height: offset.height + pan.height)

            let settled = CGPoint(x: end.x + offset.width, y: end.y + offset.height)
            assertInside(settled, "point \(step) never came into view")
            anchor = end
        }
    }

    // MARK: - Restraint

    /// Nothing moves while the work is already visible. A camera that nudged on
    /// every keystroke would be worse than one that never moved.
    func testDoesNotMoveWhenBothPointsAreAlreadyVisible() {
        let pan = DeckCanvasFollowPolicy.pan(
            focus: CGPoint(x: 200, y: 300),
            context: CGPoint(x: 120, y: 260),
            safeArea: safeArea
        )

        XCTAssertEqual(pan.width, 0, accuracy: 1e-9)
        XCTAssertEqual(pan.height, 0, accuracy: 1e-9)
    }

    /// The pan is the minimum that works — not a recentre. A recentre here
    /// would move the focus to the middle of the work area (x = 195).
    func testPansTheMinimumDistanceRatherThanRecentring() {
        let focus = CGPoint(x: 400, y: 300)
        let pan = DeckCanvasFollowPolicy.pan(
            focus: focus,
            context: CGPoint(x: 380, y: 300),
            safeArea: safeArea
        )

        // Right edge of the work area is 390 - 44 = 346, so the shift is -54.
        XCTAssertEqual(pan.width, -54, accuracy: 1e-9)
        let moved = focus.x + pan.width
        XCTAssertEqual(moved, safeArea.maxX, accuracy: 1e-9, "focus should rest on the edge it entered from")
    }

    // MARK: - Priority

    /// A run longer than the viewport cannot show both ends. The new point wins
    /// — it is the one the operator is placing.
    func testNewPointWinsWhenTheSegmentIsLongerThanTheViewport() {
        let focus = CGPoint(x: 1400, y: 300)
        let pan = DeckCanvasFollowPolicy.pan(
            focus: focus,
            context: CGPoint(x: -600, y: 300),
            safeArea: safeArea
        )
        let moved = CGPoint(x: focus.x + pan.width, y: focus.y + pan.height)

        assertInside(moved, "the point being created must always be visible")
    }

    /// When both fit, the anchor is carried into view with the new point so the
    /// operator can see the segment they just described.
    func testBringsTheAnchorAlongWhenBothFit() {
        let focus = CGPoint(x: 500, y: 300)
        let context = CGPoint(x: 420, y: 300)
        let pan = DeckCanvasFollowPolicy.pan(focus: focus, context: context, safeArea: safeArea)

        let movedFocus = CGPoint(x: focus.x + pan.width, y: focus.y + pan.height)
        let movedContext = CGPoint(x: context.x + pan.width, y: context.y + pan.height)
        assertInside(movedFocus)
        assertInside(movedContext)
    }

    // MARK: - Degenerate input

    func testIgnoresNonFiniteAndEmptyInput() {
        XCTAssertEqual(
            DeckCanvasFollowPolicy.pan(
                focus: CGPoint(x: CGFloat.nan, y: 0),
                context: nil,
                safeArea: safeArea
            ),
            .zero
        )
        XCTAssertEqual(
            DeckCanvasFollowPolicy.pan(
                focus: CGPoint(x: 900, y: 900),
                context: nil,
                safeArea: .zero
            ),
            .zero
        )
    }

    /// A missing anchor is fine — the new point alone still gets followed.
    func testFollowsTheNewPointWithNoAnchor() {
        let focus = CGPoint(x: 900, y: 900)
        let pan = DeckCanvasFollowPolicy.pan(focus: focus, context: nil, safeArea: safeArea)
        let moved = CGPoint(x: focus.x + pan.width, y: focus.y + pan.height)

        assertInside(moved)
    }

    // MARK: - Helper

    /// Inclusive containment. A minimum pan deliberately rests the point ON the
    /// edge it entered from, which `CGRect.contains` reports as outside.
    private func assertInside(
        _ point: CGPoint,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let slack: CGFloat = 1e-6
        XCTAssertGreaterThanOrEqual(point.x, safeArea.minX - slack, message, file: file, line: line)
        XCTAssertLessThanOrEqual(point.x, safeArea.maxX + slack, message, file: file, line: line)
        XCTAssertGreaterThanOrEqual(point.y, safeArea.minY - slack, message, file: file, line: line)
        XCTAssertLessThanOrEqual(point.y, safeArea.maxY + slack, message, file: file, line: line)
    }
}
