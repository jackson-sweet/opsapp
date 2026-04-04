// OPS/OPSTests/DeckBuilder/DeckMeshGeneratorTests.swift

import XCTest
@testable import OPS

final class DeckMeshGeneratorTests: XCTestCase {

    func testTriangulate_triangle() {
        let verts: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: 1)
        ]
        let tris = DeckMeshGenerator.triangulate(vertices: verts)
        XCTAssertEqual(tris.count, 1)
    }

    func testTriangulate_square() {
        let verts: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)
        ]
        let tris = DeckMeshGenerator.triangulate(vertices: verts)
        XCTAssertEqual(tris.count, 2) // square = 2 triangles
    }

    func testTriangulate_lShape() {
        // 6-vertex L-shape
        let verts: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0),
            CGPoint(x: 2, y: 1), CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 2), CGPoint(x: 0, y: 2)
        ]
        let tris = DeckMeshGenerator.triangulate(vertices: verts)
        XCTAssertEqual(tris.count, 4) // 6 vertices = 4 triangles
    }

    func testTriangulate_pentagon() {
        let verts: [CGPoint] = [
            CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.4),
            CGPoint(x: 0.8, y: 1), CGPoint(x: 0.2, y: 1),
            CGPoint(x: 0, y: 0.4)
        ]
        let tris = DeckMeshGenerator.triangulate(vertices: verts)
        XCTAssertEqual(tris.count, 3) // 5 vertices = 3 triangles
    }

    func testTriangulate_tooFewVertices() {
        let tris = DeckMeshGenerator.triangulate(vertices: [CGPoint(x: 0, y: 0)])
        XCTAssertTrue(tris.isEmpty)
    }

    func testTriangulate_allIndicesValid() {
        let verts: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)
        ]
        let tris = DeckMeshGenerator.triangulate(vertices: verts)
        for (a, b, c) in tris {
            XCTAssertTrue(a >= 0 && a < verts.count)
            XCTAssertTrue(b >= 0 && b < verts.count)
            XCTAssertTrue(c >= 0 && c < verts.count)
        }
    }

    func testCreatePolygonGeometry_square() {
        let verts: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)
        ]
        let geo = DeckMeshGenerator.createPolygonGeometry(vertices: verts, yHeight: 1.0)
        XCTAssertNotNil(geo)
    }

    func testTriangulate_clockwiseWinding() {
        // CW square — algorithm should still produce 2 triangles
        let verts: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1),
            CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0)
        ]
        let tris = DeckMeshGenerator.triangulate(vertices: verts)
        XCTAssertEqual(tris.count, 2)
    }

    func testTriangulate_tShape() {
        // 8-vertex T-shape
        let verts: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0),
            CGPoint(x: 3, y: 1), CGPoint(x: 2, y: 1),
            CGPoint(x: 2, y: 2), CGPoint(x: 1, y: 2),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)
        ]
        let tris = DeckMeshGenerator.triangulate(vertices: verts)
        XCTAssertEqual(tris.count, 6) // 8 vertices = 6 triangles
    }
}
