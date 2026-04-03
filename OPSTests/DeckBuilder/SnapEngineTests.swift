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
}
