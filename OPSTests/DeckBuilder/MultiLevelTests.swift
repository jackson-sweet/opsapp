// OPS/OPSTests/DeckBuilder/MultiLevelTests.swift

import XCTest
@testable import OPS

final class MultiLevelTests: XCTestCase {

    // MARK: - DeckLevel

    func testDeckLevel_isClosed_closedRectangle() {
        var level = DeckLevel(name: "Test")
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100))
        level.vertices = [v1, v2, v3, v4]
        level.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        XCTAssertTrue(level.isClosed)
    }

    func testDeckLevel_effectiveElevation_uniform() {
        var level = DeckLevel(name: "Test")
        level.elevation = 5.0
        level.perVertexElevation = false
        level.vertices = [DeckVertex(id: "v1", position: .zero, elevation: 8.0)]
        // Should use uniform elevation, not vertex elevation
        XCTAssertEqual(level.effectiveElevation(vertexId: "v1"), 5.0)
    }

    func testDeckLevel_effectiveElevation_perVertex() {
        var level = DeckLevel(name: "Test")
        level.elevation = 5.0
        level.perVertexElevation = true
        level.vertices = [DeckVertex(id: "v1", position: .zero, elevation: 8.0)]
        // Should use vertex elevation
        XCTAssertEqual(level.effectiveElevation(vertexId: "v1"), 8.0)
    }

    // MARK: - LevelColor

    func testLevelColor_nextAvailable() {
        XCTAssertEqual(LevelColor.nextAvailable(excluding: []), .blue)
        XCTAssertEqual(LevelColor.nextAvailable(excluding: [.blue]), .green)
        XCTAssertEqual(LevelColor.nextAvailable(excluding: [.blue, .green]), .amber)
        XCTAssertEqual(LevelColor.nextAvailable(excluding: [.blue, .green, .amber]), .blue) // fallback
    }

    // MARK: - DeckDrawingData Multi-Level

    func testIsMultiLevel_emptyLevels() {
        let data = DeckDrawingData()
        XCTAssertFalse(data.isMultiLevel)
    }

    func testIsMultiLevel_withLevels() {
        var data = DeckDrawingData()
        data.levels = [DeckLevel(name: "L1")]
        XCTAssertTrue(data.isMultiLevel)
    }

    func testAllVertices_singleLevel() {
        var data = DeckDrawingData()
        data.vertices = [DeckVertex(position: .zero)]
        XCTAssertEqual(data.allVertices.count, 1)
    }

    func testAllVertices_multiLevel() {
        var data = DeckDrawingData()
        var l1 = DeckLevel(name: "L1")
        l1.vertices = [DeckVertex(position: .zero), DeckVertex(position: CGPoint(x: 1, y: 0))]
        var l2 = DeckLevel(name: "L2")
        l2.vertices = [DeckVertex(position: CGPoint(x: 2, y: 0))]
        data.levels = [l1, l2]
        XCTAssertEqual(data.allVertices.count, 3) // 2 from L1 + 1 from L2
    }

    func testElevationDifference() {
        var data = DeckDrawingData()
        var l1 = DeckLevel(name: "Upper")
        l1.elevation = 5.0 // 5 feet
        var l2 = DeckLevel(name: "Lower")
        l2.elevation = 2.0 // 2 feet
        data.levels = [l1, l2]
        let diff = data.elevationDifference(upperLevelId: l1.id, lowerLevelId: l2.id)
        XCTAssertEqual(diff, 36.0) // 3 feet = 36 inches
    }

    func testMigrateToMultiLevel() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: .zero),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
        ]
        data.edges = [
            DeckEdge(startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(startVertexId: "v3", endVertexId: "v1"),
        ]
        data.overallElevation = 4.0

        data.migrateToMultiLevel()

        XCTAssertTrue(data.isMultiLevel)
        XCTAssertEqual(data.levels.count, 1)
        XCTAssertEqual(data.levels[0].vertices.count, 3)
        XCTAssertEqual(data.levels[0].edges.count, 3)
        XCTAssertEqual(data.levels[0].elevation, 4.0)
        XCTAssertEqual(data.levels[0].name, "Level 1")
    }

    func testAllEdges_multiLevel() {
        var data = DeckDrawingData()
        var l1 = DeckLevel(name: "L1")
        l1.edges = [
            DeckEdge(startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(startVertexId: "v2", endVertexId: "v3"),
        ]
        var l2 = DeckLevel(name: "L2")
        l2.edges = [
            DeckEdge(startVertexId: "v4", endVertexId: "v5"),
        ]
        data.levels = [l1, l2]
        XCTAssertEqual(data.allEdges.count, 3) // 2 from L1 + 1 from L2
    }

    func testDeckLevel_isClosed_openPolygon() {
        var level = DeckLevel(name: "Test")
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100))
        level.vertices = [v1, v2, v3]
        level.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
        ]
        // Open polygon: 3 vertices but only 2 edges (no closing edge)
        XCTAssertFalse(level.isClosed)
    }

    // MARK: - LevelConnection

    func testLevelConnection_stairCalcFromElevation() {
        var data = DeckDrawingData()
        var l1 = DeckLevel(name: "Upper")
        l1.elevation = 5.0
        var l2 = DeckLevel(name: "Lower")
        l2.elevation = 2.0
        data.levels = [l1, l2]

        let diff = data.elevationDifference(upperLevelId: l1.id, lowerLevelId: l2.id)!
        let spec = StairCalculator.calculate(totalRise: diff, width: 48)
        XCTAssertEqual(spec.treadCount, 5) // 36" / 7.5" = 4.8 -> ceil = 5
    }

    // MARK: - Stair-derived elevation fallback

    // When no elevation is set explicitly (no per-level, no per-vertex, no
    // overall), the deck adopts its height from an attached stair's total
    // rise — a stair spanning 36" means the deck sits 3' off grade.
    // `StairConfig.totalRiseInches` is inches, so the fallback divides by 12.

    func testRenderElevationSingleLevel_adoptsStairTotalRiseWhenNoExplicitElevation() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        var edge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        edge.stairConfig = StairConfig(width: 48, totalRiseInches: 36)
        data.edges = [edge]

        XCTAssertEqual(data.renderElevationFeetSingleLevel, 3.0, accuracy: 0.0001)
    }

    func testRenderElevationSingleLevel_explicitOverallElevationWinsOverStair() {
        var data = DeckDrawingData()
        data.overallElevation = 5.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        var edge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        edge.stairConfig = StairConfig(width: 48, totalRiseInches: 36)
        data.edges = [edge]

        XCTAssertEqual(data.renderElevationFeetSingleLevel, 5.0, accuracy: 0.0001)
    }

    func testRenderElevationSingleLevel_fallsBackToDefaultWithoutStairOrElevation() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        data.edges = [DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")]

        XCTAssertEqual(data.renderElevationFeetSingleLevel, 2.5, accuracy: 0.0001)
    }

    func testRenderElevationMultiLevel_adoptsStairTotalRiseWhenLevelElevationNil() {
        var level = DeckLevel(name: "Deck")
        level.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        var edge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        edge.stairConfig = StairConfig(width: 48, totalRiseInches: 48)
        level.edges = [edge]
        var data = DeckDrawingData()
        data.levels = [level]

        XCTAssertEqual(data.renderElevationFeet(for: level, levelIndex: 0), 4.0, accuracy: 0.0001)
    }

    func testRenderElevationMultiLevel_explicitLevelElevationWinsOverStair() {
        var level = DeckLevel(name: "Deck")
        level.elevation = 6.0
        level.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        var edge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        edge.stairConfig = StairConfig(width: 48, totalRiseInches: 48)
        level.edges = [edge]
        var data = DeckDrawingData()
        data.levels = [level]

        XCTAssertEqual(data.renderElevationFeet(for: level, levelIndex: 0), 6.0, accuracy: 0.0001)
    }
}
