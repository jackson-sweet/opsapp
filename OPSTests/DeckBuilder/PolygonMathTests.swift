// OPS/OPSTests/DeckBuilder/PolygonMathTests.swift

import XCTest
@testable import OPS

final class PolygonMathTests: XCTestCase {

    // MARK: - Area

    func testArea_square() {
        let vertices: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100),
        ]
        XCTAssertEqual(PolygonMath.area(vertices: vertices), 10000.0, accuracy: 0.001)
    }

    func testArea_triangle() {
        let vertices: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 50, y: 100),
        ]
        XCTAssertEqual(PolygonMath.area(vertices: vertices), 5000.0, accuracy: 0.001)
    }

    func testArea_lessThan3Vertices_returnsZero() {
        XCTAssertEqual(PolygonMath.area(vertices: []), 0)
        XCTAssertEqual(PolygonMath.area(vertices: [.zero]), 0)
        XCTAssertEqual(PolygonMath.area(vertices: [.zero, CGPoint(x: 1, y: 0)]), 0)
    }

    func testRealWorldArea_withScaleFactor() {
        // 100pt x 100pt square, scale = 10 pts/inch → 10" x 10" = 100 sq in
        let vertices: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100),
        ]
        let area = PolygonMath.realWorldArea(vertices: vertices, scaleFactor: 10.0)
        XCTAssertEqual(area, 100.0, accuracy: 0.001)
    }

    // MARK: - Point in Polygon

    func testPointInPolygon_inside() {
        let square: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        XCTAssertTrue(PolygonMath.pointInPolygon(CGPoint(x: 50, y: 50), vertices: square))
    }

    func testPointInPolygon_outside() {
        let square: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        XCTAssertFalse(PolygonMath.pointInPolygon(CGPoint(x: 150, y: 50), vertices: square))
    }

    // MARK: - Edge Hit Testing

    func testClosestPointOnSegment_midpoint() {
        let (closest, dist) = PolygonMath.closestPointOnSegment(
            point: CGPoint(x: 50, y: 10),
            segStart: CGPoint(x: 0, y: 0),
            segEnd: CGPoint(x: 100, y: 0)
        )
        XCTAssertEqual(closest.x, 50.0, accuracy: 0.1)
        XCTAssertEqual(closest.y, 0.0, accuracy: 0.1)
        XCTAssertEqual(dist, 10.0, accuracy: 0.1)
    }

    func testClosestPointOnSegment_pastEnd() {
        let (closest, _) = PolygonMath.closestPointOnSegment(
            point: CGPoint(x: 150, y: 0),
            segStart: CGPoint(x: 0, y: 0),
            segEnd: CGPoint(x: 100, y: 0)
        )
        XCTAssertEqual(closest.x, 100.0, accuracy: 0.1)
        XCTAssertEqual(closest.y, 0.0, accuracy: 0.1)
    }

    // MARK: - Perimeter

    func testPerimeter_square() {
        let vertices: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        XCTAssertEqual(PolygonMath.perimeter(vertices: vertices), 400.0, accuracy: 0.001)
    }

    // MARK: - Polygon Centroid

    func testPolygonCentroid_square() {
        let vertices: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        let c = PolygonMath.polygonCentroid(vertices: vertices)
        XCTAssertEqual(c?.x ?? -1, 50.0, accuracy: 0.001)
        XCTAssertEqual(c?.y ?? -1, 50.0, accuracy: 0.001)
    }

    func testPolygonCentroid_lShape_areaWeighted() {
        // L-shape: 100×100 square with the top-right 50×50 quadrant removed.
        // Area-weighted centroid = (41.6667, 58.3333); the plain vertex
        // average gives (50, 58.33) for x — the area weighting must win.
        let vertices: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 50),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        let c = PolygonMath.polygonCentroid(vertices: vertices)
        XCTAssertEqual(c?.x ?? -1, 41.6667, accuracy: 0.01)
        XCTAssertEqual(c?.y ?? -1, 58.3333, accuracy: 0.01)
    }

    func testPolygonCentroid_degenerateFallsBackToVertexAverage() {
        // Two points (no area) — falls back to the midpoint.
        let c2 = PolygonMath.polygonCentroid(vertices: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 40)])
        XCTAssertEqual(c2?.x ?? -1, 50.0, accuracy: 0.001)
        XCTAssertEqual(c2?.y ?? -1, 20.0, accuracy: 0.001)

        // Colinear triangle (zero area) — vertex average, not a divide-by-zero.
        let c3 = PolygonMath.polygonCentroid(vertices: [
            CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0),
        ])
        XCTAssertEqual(c3?.x ?? -1, 50.0, accuracy: 0.001)
        XCTAssertEqual(c3?.y ?? -1, 0.0, accuracy: 0.001)
    }

    func testPolygonCentroid_emptyIsNil() {
        XCTAssertNil(PolygonMath.polygonCentroid(vertices: []))
    }
}
