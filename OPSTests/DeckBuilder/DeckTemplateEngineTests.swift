// OPS/OPSTests/DeckBuilder/DeckTemplateEngineTests.swift

import XCTest
@testable import OPS

final class DeckTemplateEngineTests: XCTestCase {

    // MARK: - Rectangle

    func testRectangle_produces4Vertices4Edges() {
        let data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [288, 192] // 24' x 16' in inches
        )
        XCTAssertNotNil(data)
        XCTAssertEqual(data!.vertices.count, 4)
        XCTAssertEqual(data!.edges.count, 4)
        XCTAssertTrue(data!.isClosed)
        XCTAssertTrue(data!.footprint.isClosed)
    }

    func testRectangle_dimensionsCorrect() {
        let data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [288, 192]
        )!
        XCTAssertEqual(data.edges[0].dimension, 288)
        XCTAssertEqual(data.edges[1].dimension, 192)
        XCTAssertEqual(data.edges[2].dimension, 288)
        XCTAssertEqual(data.edges[3].dimension, 192)
    }

    func testRectangle_houseEdgeOnTop() {
        let data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [288, 192]
        )!
        XCTAssertEqual(data.edges[0].edgeType, .houseEdge)
        XCTAssertEqual(data.edges[1].edgeType, .deckEdge)
        XCTAssertEqual(data.edges[2].edgeType, .deckEdge)
        XCTAssertEqual(data.edges[3].edgeType, .deckEdge)
    }

    func testRectangle_hasScaleFactor() {
        let data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [288, 192]
        )!
        XCTAssertNotNil(data.scaleFactor)
        XCTAssertGreaterThan(data.scaleFactor!, 0)
    }

    func testRectangle_allDimensionSourcesManual() {
        let data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [288, 192]
        )!
        for edge in data.edges {
            XCTAssertEqual(edge.dimensionSource, .manual)
        }
    }

    // MARK: - Freestanding

    func testFreestanding_noHouseEdge() {
        let data = DeckTemplateEngine.generate(
            template: .freestanding,
            dimensions: [240, 144]
        )!
        for edge in data.edges {
            XCTAssertEqual(edge.edgeType, .deckEdge)
        }
    }

    // MARK: - L-Shape

    func testLShape_produces6Vertices6Edges() {
        let data = DeckTemplateEngine.generate(
            template: .lShape,
            dimensions: [288, 180, 120, 60]
        )
        XCTAssertNotNil(data)
        XCTAssertEqual(data!.vertices.count, 6)
        XCTAssertEqual(data!.edges.count, 6)
        XCTAssertTrue(data!.isClosed)
    }

    func testLShape_derivedDimensionsCorrect() {
        let data = DeckTemplateEngine.generate(
            template: .lShape,
            dimensions: [288, 180, 120, 60]
        )!
        XCTAssertEqual(data.edges[0].dimension, 288)    // top (A)
        XCTAssertEqual(data.edges[1].dimension, 60)     // right upper (D)
        XCTAssertEqual(data.edges[2].dimension, 120)    // step horizontal (C)
        XCTAssertEqual(data.edges[3].dimension, 120)    // step vertical (B-D)
        XCTAssertEqual(data.edges[4].dimension, 168)    // bottom (A-C)
        XCTAssertEqual(data.edges[5].dimension, 180)    // left (B)
    }

    // MARK: - Wraparound

    func testWraparound_produces6Vertices6Edges() {
        let data = DeckTemplateEngine.generate(
            template: .wraparound,
            dimensions: [288, 180, 120, 60]
        )
        XCTAssertNotNil(data)
        XCTAssertEqual(data!.vertices.count, 6)
        XCTAssertEqual(data!.edges.count, 6)
        XCTAssertTrue(data!.isClosed)
    }

    func testWraparound_twoHouseEdges() {
        let data = DeckTemplateEngine.generate(
            template: .wraparound,
            dimensions: [288, 180, 120, 60]
        )!
        let houseEdges = data.edges.filter { $0.edgeType == .houseEdge }
        XCTAssertEqual(houseEdges.count, 2)
    }

    // MARK: - T-Shape

    func testTShape_produces8Vertices8Edges() {
        let data = DeckTemplateEngine.generate(
            template: .tShape,
            dimensions: [288, 240, 120, 60]
        )
        XCTAssertNotNil(data)
        XCTAssertEqual(data!.vertices.count, 8)
        XCTAssertEqual(data!.edges.count, 8)
        XCTAssertTrue(data!.isClosed)
    }

    // MARK: - Validation

    func testInsufficientDimensions_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .lShape,
            dimensions: [288, 180]
        )
        XCTAssertNil(data)
    }

    func testZeroDimension_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [0, 192]
        )
        XCTAssertNil(data)
    }

    func testNegativeDimension_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [-100, 192]
        )
        XCTAssertNil(data)
    }

    // MARK: - Copy

    func testCopyDrawingData_producesNewIds() {
        let original = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [288, 192]
        )!

        let copy = DeckTemplateEngine.copyDrawingData(original)

        XCTAssertEqual(copy.vertices.count, original.vertices.count)
        XCTAssertEqual(copy.edges.count, original.edges.count)

        for i in 0..<copy.vertices.count {
            XCTAssertNotEqual(copy.vertices[i].id, original.vertices[i].id)
        }
        for i in 0..<copy.edges.count {
            XCTAssertNotEqual(copy.edges[i].id, original.edges[i].id)
        }

        for i in 0..<copy.edges.count {
            XCTAssertEqual(copy.edges[i].dimension, original.edges[i].dimension)
        }
    }

    func testCopyDrawingData_edgesReferenceNewVertexIds() {
        let original = DeckTemplateEngine.generate(
            template: .rectangle,
            dimensions: [288, 192]
        )!

        let copy = DeckTemplateEngine.copyDrawingData(original)
        let copyVertexIds = Set(copy.vertices.map { $0.id })

        for edge in copy.edges {
            XCTAssertTrue(copyVertexIds.contains(edge.startVertexId))
            XCTAssertTrue(copyVertexIds.contains(edge.endVertexId))
        }
    }

    func testCopyDrawingData_copiedDataIsClosed() {
        let original = DeckTemplateEngine.generate(
            template: .lShape,
            dimensions: [288, 180, 120, 60]
        )!

        let copy = DeckTemplateEngine.copyDrawingData(original)
        XCTAssertTrue(copy.isClosed)
        XCTAssertTrue(copy.footprint.isClosed)
    }
}
