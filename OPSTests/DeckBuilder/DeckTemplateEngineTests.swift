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
            dimensions: [288, 180, 120, 60]
        )
        XCTAssertNotNil(data)
        XCTAssertEqual(data!.vertices.count, 8)
        XCTAssertEqual(data!.edges.count, 8)
        XCTAssertTrue(data!.isClosed)
    }

    /// Bug 22577979 — input semantics are now: A=top width, B=stem depth,
    /// C=stem width, D=top depth. Total height = stemDepth + topDepth, so an
    /// input of (288, 180, 120, 60) produces a 288-wide top × 60-deep top bar
    /// + a 120-wide × 180-deep stem (total height 240).
    func testTShape_stemDepthInterpretedCorrectly() {
        let data = DeckTemplateEngine.generate(
            template: .tShape,
            dimensions: [288, 180, 120, 60]
        )!
        // Top edge length = a = 288.
        XCTAssertEqual(data.edges[0].dimension, 288)
        // Right-of-top edge = topDepth = 60.
        XCTAssertEqual(data.edges[1].dimension, 60)
        // Stem-right vertical = stemDepth = 180.
        XCTAssertEqual(data.edges[3].dimension, 180)
        // Stem bottom = stemWidth = 120.
        XCTAssertEqual(data.edges[4].dimension, 120)
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

    // MARK: - Bug 22577979 — Silent Rectangle Fallback Fix

    /// L-shape with C >= A used to silently produce a rectangle (the user
    /// typed L-shape values, the engine fell back to rectangle, the import
    /// preview showed a rectangle). Now: returns nil so the input view can
    /// surface a validation error inline.
    func testLShape_extensionWiderThanLongSide_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .lShape,
            dimensions: [120, 96, 200, 48]
        )
        XCTAssertNil(data)
    }

    /// Same story for D ≥ B.
    func testLShape_extensionDeeperThanFullDepth_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .lShape,
            dimensions: [200, 100, 80, 200]
        )
        XCTAssertNil(data)
    }

    /// Wraparound respects the same constraint.
    func testWraparound_invalidConstraints_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .wraparound,
            dimensions: [120, 96, 200, 48]
        )
        XCTAssertNil(data)
    }

    /// T-shape: stem width must fit inside the top width.
    func testTShape_stemWiderThanTop_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .tShape,
            dimensions: [100, 80, 200, 40]
        )
        XCTAssertNil(data)
    }

    /// Pool deck: pool diameter must fit inside the deck.
    func testPoolDeck_poolBiggerThanDeck_returnsNil() {
        let data = DeckTemplateEngine.generate(
            template: .poolDeck,
            dimensions: [120, 96, 200]
        )
        XCTAssertNil(data)
    }

    // MARK: - DeckTemplateType.validationErrors

    func testValidationErrors_validLShape_isEmpty() {
        let errs = DeckTemplateType.lShape.validationErrors(for: [288, 180, 120, 60])
        XCTAssertTrue(errs.isEmpty)
    }

    func testValidationErrors_lShapeExtensionTooWide_reportsC() {
        let errs = DeckTemplateType.lShape.validationErrors(for: [120, 96, 200, 48])
        XCTAssertEqual(errs.count, 1)
        XCTAssertTrue(errs.first?.contains("Extension width") ?? false)
    }

    // MARK: - vertexPositions

    /// Engine and diagram MUST agree on geometry, else the preview lies about
    /// the export. Spot-check L-shape vertices match what `generateLShape`
    /// would produce.
    func testVertexPositions_lShape_matchesEngine() {
        let verts = DeckTemplateEngine.vertexPositions(
            template: .lShape,
            dimensions: [200, 100, 80, 40]
        )
        XCTAssertNotNil(verts)
        XCTAssertEqual(verts!.count, 6)
        // V0(0,0), V1(a,0), V2(a,d), V3(a-c,d), V4(a-c,b), V5(0,b).
        XCTAssertEqual(verts![0].x, 0); XCTAssertEqual(verts![0].y, 0)
        XCTAssertEqual(verts![1].x, 200); XCTAssertEqual(verts![1].y, 0)
        XCTAssertEqual(verts![2].x, 200); XCTAssertEqual(verts![2].y, 40)
        XCTAssertEqual(verts![3].x, 120); XCTAssertEqual(verts![3].y, 40)
        XCTAssertEqual(verts![4].x, 120); XCTAssertEqual(verts![4].y, 100)
        XCTAssertEqual(verts![5].x, 0); XCTAssertEqual(verts![5].y, 100)
    }

    func testVertexPositions_returnsNilForInvalidInputs() {
        let verts = DeckTemplateEngine.vertexPositions(
            template: .lShape,
            dimensions: [100, 80, 150, 40]   // C >= A
        )
        XCTAssertNil(verts)
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
