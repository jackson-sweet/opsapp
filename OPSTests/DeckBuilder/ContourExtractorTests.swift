// OPS/OPSTests/DeckBuilder/ContourExtractorTests.swift

import XCTest
@testable import OPS

final class ContourExtractorTests: XCTestCase {

    // MARK: - Angle Snapping

    func testSnapSegmentAngles_snapsTo90() {
        // Nearly horizontal segment (3° off) → should snap to 0°
        let segments = [DetectedLineSegment(startPoint: .zero, endPoint: CGPoint(x: 100, y: 3))]
        let snapped = ContourExtractor.snapSegmentAngles(segments, increment: 15.0, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(snapped[0].angleDegrees, 0.0, accuracy: 1.0)
    }

    func testSnapSegmentAngles_snapsTo45() {
        // Segment pointing up-right at ~44.4° (y is negative because image coords: up = negative y)
        let segments = [DetectedLineSegment(startPoint: .zero, endPoint: CGPoint(x: 100, y: -98))]
        let snapped = ContourExtractor.snapSegmentAngles(segments, increment: 15.0, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(snapped[0].angleDegrees, 45.0, accuracy: 1.0)
    }

    func testSnapSegmentAngles_preservesStartPoint() {
        let start = CGPoint(x: 50, y: 75)
        let segments = [DetectedLineSegment(startPoint: start, endPoint: CGPoint(x: 150, y: 72))]
        let snapped = ContourExtractor.snapSegmentAngles(segments, increment: 15.0, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(snapped[0].startPoint.x, start.x, accuracy: 0.001)
        XCTAssertEqual(snapped[0].startPoint.y, start.y, accuracy: 0.001)
    }

    func testSnapSegmentAngles_preservesLength() {
        let segments = [DetectedLineSegment(startPoint: .zero, endPoint: CGPoint(x: 100, y: -5))]
        let originalLength = segments[0].lengthPixels
        let snapped = ContourExtractor.snapSegmentAngles(segments, increment: 15.0, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(snapped[0].lengthPixels, originalLength, accuracy: 1.0)
    }

    func testSnapSegmentAngles_snapsTo90Vertical() {
        // Nearly vertical segment (88°-ish) → should snap to 90°
        let segments = [DetectedLineSegment(startPoint: .zero, endPoint: CGPoint(x: 3, y: -100))]
        let snapped = ContourExtractor.snapSegmentAngles(segments, increment: 15.0, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(snapped[0].angleDegrees, 90.0, accuracy: 1.0)
    }

    // MARK: - Contour Simplification (start/end seam wraparound merge)

    /// Total length of a segment chain.
    private func perimeter(_ segments: [DetectedLineSegment]) -> Double {
        segments.reduce(0.0) { $0 + $1.lengthPixels }
    }

    func testSimplifyContour_mergesNearCollinearWraparound_withoutShorteningShape() {
        // Rectangle 200 wide × 100 tall whose BOTTOM edge is split at the start/end
        // seam into two near-collinear halves. The contour walk begins mid-bottom:
        //   p0 (60,100) seam → p1 (200,100) BR → p2 (200,0) TR → p3 (0,0) TL
        //   → p4 (0,100) BL → back to p0
        // simplifyContour wraps last→first, so the two bottom halves (first + last
        // segments) must merge into ONE full-width bottom edge: (0,100)→(200,100).
        // Image 1000×1000 → minLength ≈ 21.2px; every edge here is ≥ 60px, so none
        // are filtered out.
        let imageSize = CGSize(width: 1000, height: 1000)
        let points = [
            CGPoint(x: 60, y: 100),   // p0 — seam (mid bottom)
            CGPoint(x: 200, y: 100),  // p1 — bottom-right
            CGPoint(x: 200, y: 0),    // p2 — top-right
            CGPoint(x: 0, y: 0),      // p3 — top-left
            CGPoint(x: 0, y: 100)     // p4 — bottom-left
        ]

        let segments = ContourExtractor.simplifyContour(points, imageSize: imageSize)

        // 5 input edges, two of which (the bottom halves) are collinear at the seam →
        // they collapse to a single edge → 4 edges total (the rectangle's four sides).
        XCTAssertEqual(segments.count, 4, "Collinear wraparound halves should merge into one edge")

        // Shape must NOT be shortened: full rectangle perimeter is 2*(200+100) = 600.
        XCTAssertEqual(perimeter(segments), 600.0, accuracy: 0.5,
                       "Wraparound merge must not truncate the shape or introduce a gap")

        // The merged terminal (bottom) edge must span the FULL width: (0,100)→(200,100),
        // i.e. length 200 — not a truncated half.
        let bottomEdge = segments.first { seg in
            abs(seg.lengthPixels - 200.0) < 0.5
        }
        XCTAssertNotNil(bottomEdge, "Expected a full-width 200px bottom edge after merge")

        // Chain must remain closed (each edge's end coincides with the next edge's start,
        // cyclically) — no gap opened by the merge.
        for i in 0..<segments.count {
            let curr = segments[i]
            let next = segments[(i + 1) % segments.count]
            let gap = SnapEngine.distance(curr.endPoint, next.startPoint)
            XCTAssertEqual(gap, 0.0, accuracy: 0.5, "Edge \(i) must connect to the next with no gap")
        }
    }

    func testSimplifyContour_doesNotMergeWraparoundAtRealCorner() {
        // A clean rectangle whose seam sits exactly on a 90° corner. The first edge
        // (bottom, 0°) and last edge (left, vertical) are NOT collinear, so the
        // wraparound merge must NOT fire — all four edges are preserved.
        let imageSize = CGSize(width: 1000, height: 1000)
        let points = [
            CGPoint(x: 0, y: 100),    // p0 — bottom-left (seam at corner)
            CGPoint(x: 200, y: 100),  // p1 — bottom-right
            CGPoint(x: 200, y: 0),    // p2 — top-right
            CGPoint(x: 0, y: 0)       // p3 — top-left
        ]

        let segments = ContourExtractor.simplifyContour(points, imageSize: imageSize)

        XCTAssertEqual(segments.count, 4, "Non-collinear seam must keep all four edges")
        XCTAssertEqual(perimeter(segments), 600.0, accuracy: 0.5)
    }

    // MARK: - Vertex Building

    func testBuildVertices_mergesNearbyEndpoints() {
        // seg1 ends at (100, 0), seg2 starts at (102, 1) — within mergeRadius 10
        let seg1 = DetectedLineSegment(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 0))
        let seg2 = DetectedLineSegment(startPoint: CGPoint(x: 102, y: 1), endPoint: CGPoint(x: 200, y: 0))
        let (vertices, _) = ContourExtractor.buildVerticesAndSegments(from: [seg1, seg2], mergeRadius: 10.0)
        // seg1.start (0,0), merged middle (~101, 0.5), seg2.end (200, 0) = 3 vertices
        XCTAssertEqual(vertices.count, 3)
    }

    func testBuildVertices_doesNotMergeDistantPoints() {
        // seg1 ends at (100, 0), seg2 starts at (200, 0) — well beyond mergeRadius 10
        let seg1 = DetectedLineSegment(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 0))
        let seg2 = DetectedLineSegment(startPoint: CGPoint(x: 200, y: 0), endPoint: CGPoint(x: 300, y: 0))
        let (vertices, _) = ContourExtractor.buildVerticesAndSegments(from: [seg1, seg2], mergeRadius: 10.0)
        // All four endpoints are distinct: 4 vertices
        XCTAssertEqual(vertices.count, 4)
    }

    func testBuildVertices_updatesSegmentEndpoints() {
        // Two segments whose meeting point should be averaged
        let seg1 = DetectedLineSegment(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 0))
        let seg2 = DetectedLineSegment(startPoint: CGPoint(x: 104, y: 0), endPoint: CGPoint(x: 200, y: 0))
        let (_, updatedSegments) = ContourExtractor.buildVerticesAndSegments(from: [seg1, seg2], mergeRadius: 10.0)
        // The merged vertex should be at the average: ~(102, 0)
        // seg1's endpoint and seg2's start point should both reference that vertex position
        XCTAssertEqual(updatedSegments[0].endPoint.x, updatedSegments[1].startPoint.x, accuracy: 0.001)
        XCTAssertEqual(updatedSegments[0].endPoint.y, updatedSegments[1].startPoint.y, accuracy: 0.001)
    }

    func testBuildVertices_setsConnectedSegmentIds() {
        let seg1 = DetectedLineSegment(id: "s1", startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 0))
        let seg2 = DetectedLineSegment(id: "s2", startPoint: CGPoint(x: 102, y: 1), endPoint: CGPoint(x: 200, y: 0))
        let (vertices, _) = ContourExtractor.buildVerticesAndSegments(from: [seg1, seg2], mergeRadius: 10.0)
        // The merged middle vertex should be connected to both s1 and s2
        let middleVertex = vertices.first { $0.connectedSegmentIds.contains("s1") && $0.connectedSegmentIds.contains("s2") }
        XCTAssertNotNil(middleVertex)
    }

    func testBuildVertices_emptyInput() {
        let (vertices, segments) = ContourExtractor.buildVerticesAndSegments(from: [], mergeRadius: 10.0)
        XCTAssertTrue(vertices.isEmpty)
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - Closed Polygon Check

    func testCheckClosed_closedSquare() {
        let v1 = DetectedVertex(id: "v1", position: CGPoint(x: 0, y: 0), connectedSegmentIds: ["s1", "s4"])
        let v2 = DetectedVertex(id: "v2", position: CGPoint(x: 100, y: 0), connectedSegmentIds: ["s1", "s2"])
        let v3 = DetectedVertex(id: "v3", position: CGPoint(x: 100, y: 100), connectedSegmentIds: ["s2", "s3"])
        let v4 = DetectedVertex(id: "v4", position: CGPoint(x: 0, y: 100), connectedSegmentIds: ["s3", "s4"])
        let segments = [
            DetectedLineSegment(id: "s1", startPoint: v1.position, endPoint: v2.position),
            DetectedLineSegment(id: "s2", startPoint: v2.position, endPoint: v3.position),
            DetectedLineSegment(id: "s3", startPoint: v3.position, endPoint: v4.position),
            DetectedLineSegment(id: "s4", startPoint: v4.position, endPoint: v1.position),
        ]
        XCTAssertTrue(ContourExtractor.checkClosed(vertices: [v1, v2, v3, v4], segments: segments))
    }

    func testCheckClosed_closedTriangle() {
        let v1 = DetectedVertex(id: "v1", position: CGPoint(x: 0, y: 0), connectedSegmentIds: ["s1", "s3"])
        let v2 = DetectedVertex(id: "v2", position: CGPoint(x: 100, y: 0), connectedSegmentIds: ["s1", "s2"])
        let v3 = DetectedVertex(id: "v3", position: CGPoint(x: 50, y: 100), connectedSegmentIds: ["s2", "s3"])
        let segments = [
            DetectedLineSegment(id: "s1", startPoint: v1.position, endPoint: v2.position),
            DetectedLineSegment(id: "s2", startPoint: v2.position, endPoint: v3.position),
            DetectedLineSegment(id: "s3", startPoint: v3.position, endPoint: v1.position),
        ]
        XCTAssertTrue(ContourExtractor.checkClosed(vertices: [v1, v2, v3], segments: segments))
    }

    func testCheckClosed_openShape() {
        let v1 = DetectedVertex(id: "v1", position: .zero, connectedSegmentIds: ["s1"])
        let v2 = DetectedVertex(id: "v2", position: CGPoint(x: 100, y: 0), connectedSegmentIds: ["s1", "s2"])
        let v3 = DetectedVertex(id: "v3", position: CGPoint(x: 100, y: 100), connectedSegmentIds: ["s2"])
        let segments = [
            DetectedLineSegment(id: "s1", startPoint: v1.position, endPoint: v2.position),
            DetectedLineSegment(id: "s2", startPoint: v2.position, endPoint: v3.position),
        ]
        XCTAssertFalse(ContourExtractor.checkClosed(vertices: [v1, v2, v3], segments: segments))
    }

    func testCheckClosed_vertexWithThreeConnections() {
        // T-junction: one vertex connects to 3 segments → not a simple closed polygon
        let v1 = DetectedVertex(id: "v1", position: CGPoint(x: 0, y: 0), connectedSegmentIds: ["s1", "s3"])
        let v2 = DetectedVertex(id: "v2", position: CGPoint(x: 100, y: 0), connectedSegmentIds: ["s1", "s2", "s4"])
        let v3 = DetectedVertex(id: "v3", position: CGPoint(x: 100, y: 100), connectedSegmentIds: ["s2", "s3"])
        let v4 = DetectedVertex(id: "v4", position: CGPoint(x: 200, y: 0), connectedSegmentIds: ["s4"])
        let segments = [
            DetectedLineSegment(id: "s1", startPoint: v1.position, endPoint: v2.position),
            DetectedLineSegment(id: "s2", startPoint: v2.position, endPoint: v3.position),
            DetectedLineSegment(id: "s3", startPoint: v3.position, endPoint: v1.position),
            DetectedLineSegment(id: "s4", startPoint: v2.position, endPoint: v4.position),
        ]
        XCTAssertFalse(ContourExtractor.checkClosed(vertices: [v1, v2, v3, v4], segments: segments))
    }

    func testCheckClosed_tooFewVertices() {
        let v1 = DetectedVertex(id: "v1", position: .zero, connectedSegmentIds: ["s1"])
        let v2 = DetectedVertex(id: "v2", position: CGPoint(x: 100, y: 0), connectedSegmentIds: ["s1"])
        let segments = [
            DetectedLineSegment(id: "s1", startPoint: v1.position, endPoint: v2.position),
        ]
        XCTAssertFalse(ContourExtractor.checkClosed(vertices: [v1, v2], segments: segments))
    }

    func testCheckClosed_emptyInput() {
        XCTAssertFalse(ContourExtractor.checkClosed(vertices: [], segments: []))
    }
}
