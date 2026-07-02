// OPS/OPSTests/DeckBuilder/SnapEngineTests.swift

import XCTest
@testable import OPS

final class SnapEngineTests: XCTestCase {

    // MARK: - Angle Snapping

    func testSnapAngle_exactMultiple() {
        XCTAssertEqual(SnapEngine.snapAngle(90.0, increment: 15.0), 90.0)
        XCTAssertEqual(SnapEngine.snapAngle(45.0, increment: 15.0), 45.0)
        XCTAssertEqual(SnapEngine.snapAngle(0.0, increment: 15.0), 0.0)
    }

    func testSnapAngle_roundsToNearest() {
        XCTAssertEqual(SnapEngine.snapAngle(92.0, increment: 15.0), 90.0)
        XCTAssertEqual(SnapEngine.snapAngle(98.0, increment: 15.0), 105.0)
        XCTAssertEqual(SnapEngine.snapAngle(7.0, increment: 15.0), 0.0)
        XCTAssertEqual(SnapEngine.snapAngle(8.0, increment: 15.0), 15.0)
    }

    func testSnapAngle_wrapsAround360() {
        XCTAssertEqual(SnapEngine.snapAngle(358.0, increment: 15.0), 0.0)
        XCTAssertEqual(SnapEngine.snapAngle(352.0, increment: 15.0), 345.0)
    }

    func testSnapAngle_zeroIncrement_noSnap() {
        XCTAssertEqual(SnapEngine.snapAngle(47.3, increment: 0.0), 47.3)
    }

    // MARK: - Line Angle

    func testLineAngle_rightward() {
        let angle = SnapEngine.lineAngle(from: .zero, to: CGPoint(x: 10, y: 0))
        XCTAssertEqual(angle, 0.0, accuracy: 0.001)
    }

    func testLineAngle_upward() {
        // SwiftUI Y is down-positive, so "up" on screen is negative Y
        let angle = SnapEngine.lineAngle(from: .zero, to: CGPoint(x: 0, y: -10))
        XCTAssertEqual(angle, 90.0, accuracy: 0.001)
    }

    func testLineAngle_leftward() {
        let angle = SnapEngine.lineAngle(from: .zero, to: CGPoint(x: -10, y: 0))
        XCTAssertEqual(angle, 180.0, accuracy: 0.001)
    }

    func testLineAngle_downward() {
        let angle = SnapEngine.lineAngle(from: .zero, to: CGPoint(x: 0, y: 10))
        XCTAssertEqual(angle, 270.0, accuracy: 0.001)
    }

    // MARK: - Endpoint Snapping

    func testSnapEndpoint_snapsAngleAndLength() {
        let start = CGPoint.zero
        let rawEnd = CGPoint(x: 97, y: -5) // nearly horizontal, ~97pt

        let snapped = SnapEngine.snapEndpoint(
            from: start,
            rawEnd: rawEnd,
            angleIncrement: 15.0,
            lengthIncrement: 10.0,
            snappingEnabled: true
        )

        // Should snap to 0° angle (horizontal) at 100pt length
        XCTAssertEqual(snapped.x, 100.0, accuracy: 0.1)
        XCTAssertEqual(snapped.y, 0.0, accuracy: 0.1)
    }

    func testSnapEndpoint_disabledSnapping_returnsRaw() {
        let start = CGPoint.zero
        let rawEnd = CGPoint(x: 97, y: -5)

        let snapped = SnapEngine.snapEndpoint(
            from: start,
            rawEnd: rawEnd,
            angleIncrement: 15.0,
            lengthIncrement: 10.0,
            snappingEnabled: false
        )

        XCTAssertEqual(snapped.x, rawEnd.x, accuracy: 0.001)
        XCTAssertEqual(snapped.y, rawEnd.y, accuracy: 0.001)
    }

    // MARK: - Magnetic Vertex Snap

    func testFindSnapTarget_findsNearestWithinRadius() {
        let vertices = [
            DeckVertex(id: "a", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "b", position: CGPoint(x: 200, y: 200)),
        ]

        let result = SnapEngine.findSnapTarget(
            point: CGPoint(x: 105, y: 103),
            vertices: vertices,
            snapRadius: 20.0
        )

        XCTAssertEqual(result, "a")
    }

    func testFindSnapTarget_nilWhenOutsideRadius() {
        let vertices = [
            DeckVertex(id: "a", position: CGPoint(x: 100, y: 100)),
        ]

        let result = SnapEngine.findSnapTarget(
            point: CGPoint(x: 200, y: 200),
            vertices: vertices,
            snapRadius: 20.0
        )

        XCTAssertNil(result)
    }

    func testFindSnapTarget_excludesSpecifiedVertices() {
        let vertices = [
            DeckVertex(id: "a", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "b", position: CGPoint(x: 110, y: 100)),
        ]

        let result = SnapEngine.findSnapTarget(
            point: CGPoint(x: 102, y: 100),
            vertices: vertices,
            snapRadius: 20.0,
            excludeVertexIds: ["a"]
        )

        XCTAssertEqual(result, "b")
    }

    // MARK: - Distance

    func testDistance_horizontal() {
        let d = SnapEngine.distance(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0))
        XCTAssertEqual(d, 10.0, accuracy: 0.001)
    }

    func testDistance_diagonal() {
        let d = SnapEngine.distance(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4))
        XCTAssertEqual(d, 5.0, accuracy: 0.001)
    }

    // MARK: - Measurement Angle Snap
    //
    // Regression guard for the "second measure tap lands mirrored" bug: the
    // reconstruction must negate Y back into SwiftUI screen space (down-positive).
    // A near-vertical measurement across a deck used to point-reflect through the
    // start because the end was rebuilt with `start.y + length·sin` instead of
    // `start.y - length·sin`.

    /// The horizontal reference edge every case below snaps against.
    private var horizontalEdge: (start: CGPoint, end: CGPoint) {
        (start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
    }

    func testSnapMeasurementEnd_verticalDown_staysBelowStart() {
        // User drags DOWN (screen +Y), ~1° off vertical — snaps to the edge's
        // perpendicular and must REMAIN below the start, not flip above it.
        let start = CGPoint(x: 50, y: 50)
        let candidate = CGPoint(x: 52, y: 150)
        let snapped = SnapEngine.snapMeasurementEnd(
            from: start, candidate: candidate, referenceEdges: [horizontalEdge]
        )
        XCTAssertGreaterThan(snapped.y, start.y, "snapped end must stay below start, not mirror above it")
        XCTAssertEqual(snapped.x, 50, accuracy: 0.5, "snaps to a clean vertical")
        XCTAssertEqual(
            SnapEngine.distance(start, snapped),
            SnapEngine.distance(start, candidate),
            accuracy: 0.001,
            "length is preserved by the angle snap"
        )
    }

    func testSnapMeasurementEnd_verticalUp_staysAboveStart() {
        // User drags UP (screen -Y) — snaps to vertical and stays above.
        let start = CGPoint(x: 50, y: 150)
        let candidate = CGPoint(x: 48, y: 50)
        let snapped = SnapEngine.snapMeasurementEnd(
            from: start, candidate: candidate, referenceEdges: [horizontalEdge]
        )
        XCTAssertLessThan(snapped.y, start.y, "snapped end must stay above start")
        XCTAssertEqual(snapped.x, 50, accuracy: 0.5)
    }

    func testSnapMeasurementEnd_horizontalParallel_snapsFlat() {
        // Near-horizontal drag to the right snaps parallel; y collapses to start.y.
        let start = CGPoint(x: 20, y: 40)
        let candidate = CGPoint(x: 120, y: 43)
        let snapped = SnapEngine.snapMeasurementEnd(
            from: start, candidate: candidate, referenceEdges: [horizontalEdge]
        )
        XCTAssertGreaterThan(snapped.x, start.x, "stays to the right of start")
        XCTAssertEqual(snapped.y, 40, accuracy: 0.5, "snaps flat onto the start's Y")
    }

    func testSnapMeasurementEnd_offAxisDiagonal_returnsCandidateUnchanged() {
        // A 45°-ish drag is outside the ±5° tolerance of any parallel/perp target,
        // so the candidate is returned verbatim (no snap, no reflection).
        let start = CGPoint(x: 0, y: 0)
        let candidate = CGPoint(x: 100, y: 100)
        let snapped = SnapEngine.snapMeasurementEnd(
            from: start, candidate: candidate, referenceEdges: [horizontalEdge]
        )
        XCTAssertEqual(snapped.x, candidate.x, accuracy: 0.001)
        XCTAssertEqual(snapped.y, candidate.y, accuracy: 0.001)
    }

    func testSnapMeasurementEnd_noReferenceEdges_returnsCandidate() {
        let start = CGPoint(x: 0, y: 0)
        let candidate = CGPoint(x: 10, y: 90)
        let snapped = SnapEngine.snapMeasurementEnd(
            from: start, candidate: candidate, referenceEdges: []
        )
        XCTAssertEqual(snapped.x, candidate.x, accuracy: 0.001)
        XCTAssertEqual(snapped.y, candidate.y, accuracy: 0.001)
    }

    /// Property: the snap must never reverse the user's drawn direction. For a
    /// full sweep of drawn angles against both a horizontal and a vertical edge,
    /// the snapped vector must keep a non-negative dot product with the drawn
    /// vector (angle between them < 90°). A mirror (≈180°) would go negative.
    func testSnapMeasurementEnd_neverReversesDirection() {
        let start = CGPoint(x: 200, y: 200)
        let edges = [
            (start: CGPoint(x: 0, y: 200), end: CGPoint(x: 400, y: 200)),   // horizontal
            (start: CGPoint(x: 200, y: 0), end: CGPoint(x: 200, y: 400))    // vertical
        ]
        for degrees in stride(from: 0.0, to: 360.0, by: 1.0) {
            let rad = degrees * .pi / 180
            // Candidate 100pt out at this SCREEN angle (screen Y is down-positive).
            let candidate = CGPoint(x: start.x + 100 * cos(rad), y: start.y + 100 * sin(rad))
            let snapped = SnapEngine.snapMeasurementEnd(
                from: start, candidate: candidate, referenceEdges: edges
            )
            let drawn = CGVector(dx: candidate.x - start.x, dy: candidate.y - start.y)
            let result = CGVector(dx: snapped.x - start.x, dy: snapped.y - start.y)
            let dot = Double(drawn.dx * result.dx + drawn.dy * result.dy)
            XCTAssertGreaterThan(dot, -0.001, "snap reversed the drawn direction at \(degrees)°")
        }
    }
}
