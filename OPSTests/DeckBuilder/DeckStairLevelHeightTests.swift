//
//  DeckStairLevelHeightTests.swift
//  OPSTests
//
//  Level-scoped height writes and the one-stair-per-edge contract behind the
//  stair sheet overhaul: HEIGHT edits exactly the selected level, connected
//  stairs track level heights through the resolved ladder, and an edge never
//  carries a fixed-rise stair and a level connection at the same time.
//

import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class DeckStairLevelHeightTests: XCTestCase {

    // MARK: - Fixtures

    /// A closed 12'×12' square level offset so the two levels don't overlap.
    private func squareLevel(idPrefix: String, name: String, originX: CGFloat, sortOrder: Int) -> DeckLevel {
        var level = DeckLevel(name: name, sortOrder: sortOrder)
        level.vertices = [
            DeckVertex(id: "\(idPrefix)v1", position: CGPoint(x: originX, y: 0)),
            DeckVertex(id: "\(idPrefix)v2", position: CGPoint(x: originX + 144, y: 0)),
            DeckVertex(id: "\(idPrefix)v3", position: CGPoint(x: originX + 144, y: 144)),
            DeckVertex(id: "\(idPrefix)v4", position: CGPoint(x: originX, y: 144)),
        ]
        level.edges = [
            DeckEdge(id: "\(idPrefix)e1", startVertexId: "\(idPrefix)v1", endVertexId: "\(idPrefix)v2"),
            DeckEdge(id: "\(idPrefix)e2", startVertexId: "\(idPrefix)v2", endVertexId: "\(idPrefix)v3"),
            DeckEdge(id: "\(idPrefix)e3", startVertexId: "\(idPrefix)v3", endVertexId: "\(idPrefix)v4"),
            DeckEdge(id: "\(idPrefix)e4", startVertexId: "\(idPrefix)v4", endVertexId: "\(idPrefix)v1"),
        ]
        return level
    }

    private func multiLevelData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.levels = [
            squareLevel(idPrefix: "a", name: "Level 1", originX: 0, sortOrder: 0),
            squareLevel(idPrefix: "b", name: "Level 2", originX: 240, sortOrder: 1),
        ]
        return data
    }

    /// Drawing data is assigned post-init, not serialized into the design:
    /// `toJSON()` prunes edgeless vertices, so single-level fixtures with
    /// bare corners would come back empty through the round-trip (same idiom
    /// as the deck snapshot tests).
    private func viewModel(_ data: DeckDrawingData) -> DeckBuilderViewModel {
        let viewModel = DeckBuilderViewModel(deckDesign: DeckDesign(
            companyId: "company-1",
            title: "Stair/height deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        ))
        viewModel.drawingData = data
        return viewModel
    }

    // MARK: - HEIGHT scopes to the selected level

    func testSetLevelElevation_writesOnlyTheTargetLevel() {
        var data = multiLevelData()
        data.levels[1].elevation = 6.0
        let vm = viewModel(data)

        vm.setLevelElevation(at: 0, elevation: 3.0)

        XCTAssertEqual(vm.drawingData.levels[0].elevation, 3.0)
        XCTAssertEqual(vm.drawingData.levels[1].elevation, 6.0, "the other level's explicit height must survive")
        XCTAssertNil(vm.drawingData.overallElevation, "level heights never route through the deck-wide overall")
    }

    func testSetLevelElevation_clearsThatLevelsPerVertexHeights() {
        var data = multiLevelData()
        data.levels[0].vertices[0].elevation = 1.0
        data.levels[0].perVertexElevation = true
        data.levels[1].vertices[0].elevation = 9.0
        let vm = viewModel(data)

        vm.setLevelElevation(at: 0, elevation: 3.0)

        XCTAssertTrue(vm.drawingData.levels[0].vertices.allSatisfy { $0.elevation == nil })
        XCTAssertFalse(vm.drawingData.levels[0].perVertexElevation)
        XCTAssertEqual(vm.drawingData.levels[1].vertices[0].elevation, 9.0, "other levels' corners untouched")
    }

    func testApplyLevelSlopedElevations_clearsUniformSoTheSlopeRenders() {
        var data = multiLevelData()
        data.levels[0].elevation = 4.0
        let vm = viewModel(data)

        vm.applyLevelSlopedElevations(at: 0, heights: ["av1": 2.0, "av2": 3.0])

        XCTAssertNil(vm.drawingData.levels[0].elevation)
        XCTAssertTrue(vm.drawingData.levels[0].perVertexElevation)
        XCTAssertEqual(vm.drawingData.levels[0].vertex(byId: "av1")?.elevation, 2.0)
        XCTAssertEqual(vm.drawingData.levels[0].vertex(byId: "av2")?.elevation, 3.0)
    }

    func testSetVertexHeightBreakingUniform_multiLevel_clearsTheLevelsUniform() {
        var data = multiLevelData()
        data.levels[0].elevation = 4.0
        let vm = viewModel(data)
        vm.activeLevelIndex = 0

        vm.setVertexHeightBreakingUniform("av3", elevation: 5.5)

        XCTAssertNil(vm.drawingData.levels[0].elevation)
        XCTAssertTrue(vm.drawingData.levels[0].perVertexElevation)
        XCTAssertEqual(vm.drawingData.levels[0].vertex(byId: "av3")?.elevation, 5.5)
    }

    // MARK: - Single-level applies stay atomic

    func testApplyUniformDeckElevation_singleLevel_clearsCornerHeights() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        data.vertices[0].elevation = 6.0
        let vm = viewModel(data)

        vm.applyUniformDeckElevation(3.0)

        XCTAssertEqual(vm.drawingData.overallElevation, 3.0)
        XCTAssertTrue(vm.drawingData.vertices.allSatisfy { $0.elevation == nil })
    }

    func testApplySlopedDeckElevations_singleLevel_clearsOverall() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        data.overallElevation = 4.0
        let vm = viewModel(data)

        vm.applySlopedDeckElevations(heights: ["v1": 2.0, "v2": 3.0])

        XCTAssertNil(vm.drawingData.overallElevation)
        XCTAssertEqual(vm.drawingData.vertex(byId: "v1")?.elevation, 2.0)
        XCTAssertEqual(vm.drawingData.vertex(byId: "v2")?.elevation, 3.0)
    }

    // MARK: - Explicit heights outrank stair-derived rise

    func testRenderElevation_explicitLevelHeightBeatsStairRise() {
        var data = multiLevelData()
        data.levels[0].elevation = 5.0
        data.levels[0].edges[0].stairConfig = StairConfig(width: 48, totalRiseInches: 96)

        XCTAssertEqual(data.renderElevationFeet(for: data.levels[0], levelIndex: 0), 5.0,
                       "editing a stair must never move a level with an explicit height")

        data.levels[0].elevation = nil
        XCTAssertEqual(data.renderElevationFeet(for: data.levels[0], levelIndex: 0), 8.0,
                       "with no explicit height the stair's rise is the only real signal")
    }

    // MARK: - elevationDifference resolves implicit heights

    func testElevationDifference_fallsBackToResolvedHeights() {
        let data = multiLevelData()
        // No explicit elevations anywhere: levels resolve to the 2.5' stagger
        // (2.5' and 5.0'), so the difference is 2.5' = 30".
        let diff = data.elevationDifference(
            upperLevelId: data.levels[1].id,
            lowerLevelId: data.levels[0].id
        )
        XCTAssertEqual(diff ?? 0, 30.0, accuracy: 0.001)

        XCTAssertNil(data.elevationDifference(upperLevelId: "missing", lowerLevelId: data.levels[0].id))
    }

    // MARK: - One stair per edge

    func testConnectLevels_resolvedHeights_createsSyncedConnectionAndClearsEdgeStair() throws {
        var data = multiLevelData()
        // The stair being replaced would resolve the upper level to 2' —
        // BELOW the lower level's 2.5' stagger. The connection must measure
        // the drop with that stair excluded (it is deleted by this commit),
        // so the levels resolve to the 2.5'/5' stagger and the connect works.
        data.levels[1].edges[0].stairConfig = StairConfig(width: 36, totalRiseInches: 24)
        let vm = viewModel(data)
        vm.activeLevelIndex = 1

        vm.connectLevels(
            upperLevelId: vm.drawingData.levels[1].id,
            lowerLevelId: vm.drawingData.levels[0].id,
            upperEdgeId: "be1",
            stairConfig: StairConfig(width: 48)
        )

        XCTAssertEqual(vm.drawingData.levelConnections.count, 1)
        let connection = try XCTUnwrap(vm.drawingData.levelConnections.first)
        // 30" post-replacement difference at 7.5" per step → 4 treads.
        XCTAssertEqual(connection.stairConfig.treadCount, 4)
        XCTAssertNil(connection.stairConfig.totalRiseInches,
                     "a connected stair's rise derives from the levels — a stored constant would go stale")
        XCTAssertNil(vm.drawingData.levels[1].edge(byId: "be1")?.stairConfig,
                     "connecting replaces the fixed-rise stair on that edge")
    }

    func testConnectLevels_replacesPriorConnectionOnTheSameEdge() {
        let vm = viewModel(multiLevelData())
        vm.activeLevelIndex = 1
        let upper = vm.drawingData.levels[1].id
        let lower = vm.drawingData.levels[0].id

        vm.connectLevels(upperLevelId: upper, lowerLevelId: lower, upperEdgeId: "be1", stairConfig: StairConfig(width: 48))
        vm.connectLevels(upperLevelId: upper, lowerLevelId: lower, upperEdgeId: "be1", stairConfig: StairConfig(width: 36))

        XCTAssertEqual(vm.drawingData.levelConnections.count, 1)
        XCTAssertEqual(vm.drawingData.levelConnections.first?.stairConfig.width, 36)
    }

    func testSetStairs_replacesConnectionOnTheSameEdge() {
        let vm = viewModel(multiLevelData())
        vm.activeLevelIndex = 1
        vm.connectLevels(
            upperLevelId: vm.drawingData.levels[1].id,
            lowerLevelId: vm.drawingData.levels[0].id,
            upperEdgeId: "be1",
            stairConfig: StairConfig(width: 48)
        )

        vm.setStairs("be1", config: StairConfig(width: 42, totalRiseInches: 36))

        XCTAssertTrue(vm.drawingData.levelConnections.isEmpty,
                      "an edge carries one stair — fixed-rise replaces the connection")
        XCTAssertEqual(vm.drawingData.levels[1].edge(byId: "be1")?.stairConfig?.width, 42)
    }

    func testRemoveStairs_clearsBothStores() {
        var data = multiLevelData()
        data.levels[1].edges[1].stairConfig = StairConfig(width: 48, totalRiseInches: 30)
        let vm = viewModel(data)
        vm.activeLevelIndex = 1
        vm.connectLevels(
            upperLevelId: vm.drawingData.levels[1].id,
            lowerLevelId: vm.drawingData.levels[0].id,
            upperEdgeId: "be1",
            stairConfig: StairConfig(width: 48)
        )

        vm.removeStairs(edgeId: "be1")
        vm.removeStairs(edgeId: "be2")

        XCTAssertTrue(vm.drawingData.levelConnections.isEmpty)
        XCTAssertNil(vm.drawingData.levels[1].edge(byId: "be2")?.stairConfig)
    }

    // MARK: - Rail run labels (2D)

    func testStairRailInfo_edgeStair_usesStoredRiseHypotenuse() {
        var data = multiLevelData()
        // 30" rise, 4 treads × 10" run = 40" → 30-40-50 triangle: rail = 50".
        data.levels[1].edges[0].stairConfig = StairConfig(
            width: 48, runPerTread: 10, treadCount: 4, totalRiseInches: 30
        )

        let info = data.stairRailInfo(for: data.levels[1].edges[0])
        XCTAssertEqual(info?.treadCount, 4)
        XCTAssertEqual(info?.railRunInches ?? 0, 50.0, accuracy: 0.001)
    }

    func testStairRailInfo_edgeStair_fallsBackToContextHeightWhenNoStoredRise() {
        var data = DeckDrawingData()
        data.overallElevation = 2.5   // 30" — with 4 × 10" treads → rail 50"
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
        ]
        var edge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        edge.stairConfig = StairConfig(width: 48, runPerTread: 10, treadCount: 4)
        data.edges = [edge]

        let info = data.stairRailInfo(for: data.edges[0])
        XCTAssertEqual(info?.railRunInches ?? 0, 50.0, accuracy: 0.001)
    }

    func testStairRailInfo_connection_derivesFromResolvedLevelHeights() {
        var data = multiLevelData()
        data.levels[0].elevation = 2.5
        data.levels[1].elevation = 5.0   // 30" drop
        let connection = LevelConnection(
            upperLevelId: data.levels[1].id,
            lowerLevelId: data.levels[0].id,
            upperEdgeId: "be1",
            stairConfig: StairConfig(width: 48, runPerTread: 10)   // treadCount nil → derived
        )
        data.levelConnections = [connection]

        let info = data.stairRailInfo(for: connection)
        XCTAssertEqual(info?.treadCount, 4, "30\" at 7.5\"/step derives 4 treads")
        XCTAssertEqual(info?.railRunInches ?? 0, 50.0, accuracy: 0.001)

        // Same-height levels have no drop — no tread/rail claims.
        data.levels[1].elevation = 2.5
        XCTAssertNil(data.stairRailInfo(for: connection))
    }

    // MARK: - Connected stairs track height edits

    func testSetLevelElevation_recalculatesConnectionTreadCounts() {
        let vm = viewModel(multiLevelData())
        vm.activeLevelIndex = 1
        vm.connectLevels(
            upperLevelId: vm.drawingData.levels[1].id,
            lowerLevelId: vm.drawingData.levels[0].id,
            upperEdgeId: "be1",
            stairConfig: StairConfig(width: 48)
        )
        XCTAssertEqual(vm.drawingData.levelConnections.first?.stairConfig.treadCount, 4)

        // Lowering the lower level to 1' widens the drop to 4' = 48" → 7 treads.
        vm.setLevelElevation(at: 0, elevation: 1.0)

        XCTAssertEqual(vm.drawingData.levelConnections.first?.stairConfig.treadCount, 7)
    }
}
