// OPS/OPSTests/DeckBuilder/ARCoordinateConverterTests.swift

import XCTest
@testable import OPS

final class ARCoordinateConverterTests: XCTestCase {

    func testConvert_rectangle_4Vertices4Edges() {
        // 5m x 3m rectangle in AR space
        let vertices = [
            ARCoordinateConverter.ARVertex(id: "v1", x: 0, z: 0, y: 0),
            ARCoordinateConverter.ARVertex(id: "v2", x: 5, z: 0, y: 0),
            ARCoordinateConverter.ARVertex(id: "v3", x: 5, z: 3, y: 0),
            ARCoordinateConverter.ARVertex(id: "v4", x: 0, z: 3, y: 0),
        ]
        let edges = [
            ARCoordinateConverter.AREdge(id: "e1", startVertexId: "v1", endVertexId: "v2", distanceMeters: 5.0, accuracyPercent: 2.5),
            ARCoordinateConverter.AREdge(id: "e2", startVertexId: "v2", endVertexId: "v3", distanceMeters: 3.0, accuracyPercent: 1.5),
            ARCoordinateConverter.AREdge(id: "e3", startVertexId: "v3", endVertexId: "v4", distanceMeters: 5.0, accuracyPercent: 2.5),
            ARCoordinateConverter.AREdge(id: "e4", startVertexId: "v4", endVertexId: "v1", distanceMeters: 3.0, accuracyPercent: 1.5),
        ]

        let data = ARCoordinateConverter.convert(arVertices: vertices, arEdges: edges, isClosed: true)

        XCTAssertEqual(data.vertices.count, 4)
        XCTAssertEqual(data.edges.count, 4)
        XCTAssertTrue(data.footprint.isClosed)
        XCTAssertNotNil(data.scaleFactor)
    }

    func testConvert_dimensionsInInches() {
        let vertices = [
            ARCoordinateConverter.ARVertex(id: "v1", x: 0, z: 0, y: 0),
            ARCoordinateConverter.ARVertex(id: "v2", x: 5, z: 0, y: 0),
        ]
        let edges = [
            ARCoordinateConverter.AREdge(id: "e1", startVertexId: "v1", endVertexId: "v2", distanceMeters: 5.0, accuracyPercent: 2.5),
        ]

        let data = ARCoordinateConverter.convert(arVertices: vertices, arEdges: edges, isClosed: false)

        // 5 meters = 196.85 inches
        XCTAssertEqual(data.edges[0].dimension!, 196.85, accuracy: 0.1)
        XCTAssertEqual(data.edges[0].dimensionSource, .ar)
        XCTAssertEqual(data.edges[0].accuracyPercent, 2.5)
    }

    func testConvert_preservesHouseEdgeAndDropsInvalidRailing() {
        let vertices = [
            ARCoordinateConverter.ARVertex(id: "v1", x: 0, z: 0, y: 0),
            ARCoordinateConverter.ARVertex(id: "v2", x: 5, z: 0, y: 0),
        ]
        let railingConfig = RailingConfig(railingType: .glass, maxPostSpacing: 60)
        let edges = [
            ARCoordinateConverter.AREdge(
                id: "e1", startVertexId: "v1", endVertexId: "v2",
                distanceMeters: 5.0, accuracyPercent: 2.5,
                edgeType: .houseEdge, railingConfig: railingConfig
            ),
        ]

        let data = ARCoordinateConverter.convert(arVertices: vertices, arEdges: edges, isClosed: false)

        XCTAssertEqual(data.edges[0].edgeType, .houseEdge)
        XCTAssertNil(data.edges[0].railingConfig)
    }

    func testCalculateElevation() {
        // Deck at Y=1.0m, ground at Y=0.0m → 1m = 39.37 inches
        let elevation = ARCoordinateConverter.calculateElevation(deckPointY: 1.0, groundPointY: 0.0)
        XCTAssertEqual(elevation, 39.3701, accuracy: 0.01)
    }

    func testConvert_emptyInput() {
        let data = ARCoordinateConverter.convert(arVertices: [], arEdges: [], isClosed: false)
        XCTAssertTrue(data.vertices.isEmpty)
        XCTAssertTrue(data.edges.isEmpty)
    }
}
