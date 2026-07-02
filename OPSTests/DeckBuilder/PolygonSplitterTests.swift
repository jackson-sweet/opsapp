// OPS/OPSTests/DeckBuilder/PolygonSplitterTests.swift

import XCTest
@testable import OPS

final class PolygonSplitterTests: XCTestCase {

    private let square: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    func testVerticalCut_splitsSquareInHalf() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: -20), lineB: CGPoint(x: 50, y: 120)
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideA), 5000, accuracy: 1)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideB), 5000, accuracy: 1)
    }

    func testEndpointsInsideFace_lineStillExtends() {
        // Both taps INSIDE the square — the infinite line through them must
        // still cut the full face (Jackson's free-endpoint requirement).
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: 40), lineB: CGPoint(x: 50, y: 60)
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideA), 5000, accuracy: 1)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideB), 5000, accuracy: 1)
    }

    func testDiagonalCut_areasConserve() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: -10, y: -10), lineB: CGPoint(x: 110, y: 110)
        )
        XCTAssertTrue(r.didSplit)
        let total = PolygonMath.area(vertices: r.sideA) + PolygonMath.area(vertices: r.sideB)
        XCTAssertEqual(total, 10000, accuracy: 1)
        XCTAssertEqual(PolygonMath.area(vertices: r.sideA), 5000, accuracy: 1)
    }

    func testUnevenCut_areasMatchGeometry() {
        // Vertical line at x=25 → 2500 / 7500.
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 25, y: -5), lineB: CGPoint(x: 25, y: 105)
        )
        let areas = [PolygonMath.area(vertices: r.sideA), PolygonMath.area(vertices: r.sideB)].sorted()
        XCTAssertEqual(areas[0], 2500, accuracy: 1)
        XCTAssertEqual(areas[1], 7500, accuracy: 1)
    }

    func testConcaveL_multiPieceSideTotalsCorrect() {
        // L-shape = 100×100 minus the x∈[50,100], y∈[0,50] quadrant (area 7500).
        // Horizontal line y=75 cuts the L into: below (both legs' lower parts)
        // and above. Below y=75: full-width strip y∈[75,100] is ABOVE... use
        // y-down canvas: region y∈[0,75] of the L = left column x∈[0,50],y∈[0,75]
        // (3750) + right block x∈[50,100],y∈[50,75] (1250) = 5000; remainder 2500.
        let lShape: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 50),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        let r = PolygonSplitter.split(
            polygon: lShape,
            lineA: CGPoint(x: -10, y: 75), lineB: CGPoint(x: 110, y: 75)
        )
        XCTAssertTrue(r.didSplit)
        let areas = [PolygonMath.area(vertices: r.sideA), PolygonMath.area(vertices: r.sideB)].sorted()
        XCTAssertEqual(areas[0], 2500, accuracy: 1)
        XCTAssertEqual(areas[1], 5000, accuracy: 1)
    }

    func testLineMissesFace_noSplit() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 200, y: 0), lineB: CGPoint(x: 200, y: 100)
        )
        XCTAssertFalse(r.didSplit)
    }

    func testLineAlongEdge_noSplit() {
        // Colinear with the left edge — one side is the whole face.
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 0, y: -10), lineB: CGPoint(x: 0, y: 110)
        )
        XCTAssertFalse(r.didSplit)
    }

    func testCoincidentPoints_noSplit() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: 50), lineB: CGPoint(x: 50, y: 50)
        )
        XCTAssertFalse(r.didSplit)
    }

    func testChord_verticalCutChordSpansFace() {
        let r = PolygonSplitter.split(
            polygon: square,
            lineA: CGPoint(x: 50, y: -20), lineB: CGPoint(x: 50, y: 120)
        )
        XCTAssertEqual(r.chordSegments.count, 1)
        let seg = r.chordSegments[0]
        XCTAssertEqual(min(seg.start.y, seg.end.y), 0, accuracy: 0.5)
        XCTAssertEqual(max(seg.start.y, seg.end.y), 100, accuracy: 0.5)
        XCTAssertEqual(seg.start.x, 50, accuracy: 0.5)
    }

    func testChord_concaveGivesTwoSegments() {
        // Horizontal line y=25 crosses only the LEFT leg of the L (x∈[0,50])
        // — one chord. Line y=75 crosses the full width — one chord. A line
        // crossing a concave notch gives 2 chords: use a U-shape.
        let uShape: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0),
            CGPoint(x: 30, y: 60), CGPoint(x: 70, y: 60),
            CGPoint(x: 70, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        let r = PolygonSplitter.split(
            polygon: uShape,
            lineA: CGPoint(x: -10, y: 30), lineB: CGPoint(x: 110, y: 30)
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(r.chordSegments.count, 2, "the line crosses both arms of the U")
    }
}
