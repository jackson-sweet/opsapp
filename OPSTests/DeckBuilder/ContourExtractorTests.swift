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
