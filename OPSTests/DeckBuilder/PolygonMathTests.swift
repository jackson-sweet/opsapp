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
}
