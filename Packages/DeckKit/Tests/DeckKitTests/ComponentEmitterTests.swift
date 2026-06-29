//
//  ComponentEmitterTests.swift
//  OPSTests
//
//  Verifies ComponentEmitter projects a DeckDrawingData into the catalog
//  adapter's `components` vocabulary correctly. Covers each scenario in
//  the deck-catalog integration spec § 8 (unit list).
//

import XCTest
import CoreGraphics
@testable import DeckKit

final class ComponentEmitterTests: XCTestCase {

    // MARK: - Empty / barebones

    func test_emit_emptyDrawing_returnsEmpty() {
        let data = DeckDrawingData()
        let rows = ComponentEmitter.emit(data)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Closed quad with railing on every edge (spec § 8 scenario 2)

    func test_emit_closedQuadWithRailings_emits4Railings4PostSets_cornersZeroPerEdge() {
        let data = makeClosedQuadWithRailings(
            railingType: .picket,
            color: "Black",
            mountType: "Topmount",
            mountSurface: "Surface",
            frameStyle: .framed,
            mountPlacement: .topMounted
        )
        let rows = ComponentEmitter.emit(data)

        let railings = rows.filter { $0.componentType == "railing" }
        let posts = rows.filter { $0.componentType == "post_set" }

        XCTAssertEqual(railings.count, 4, "Closed quad with 4 railing-bearing edges should emit 4 railings")
        XCTAssertEqual(posts.count, 4, "Each railing emits a paired post_set")

        for row in railings {
            XCTAssertEqual(row.metadata["corners_count"], AnyCodable(0),
                           "Per-edge corners_count is 0 — corners live at vertices shared between edges, not within an edge")
            XCTAssertEqual(row.metadata["color"], AnyCodable("Black"))
            XCTAssertEqual(row.metadata["mount_type"], AnyCodable("Topmount"))
            XCTAssertEqual(row.metadata["mount_surface"], AnyCodable("Surface"))
            XCTAssertEqual(row.metadata["frame_style"], AnyCodable("framed"))
            XCTAssertEqual(row.metadata["mount_placement"], AnyCodable("top_mounted"))
        }

        // Each railing pair (railing + post_set) should reference the same edge_id.
        let railingEdgeIds = Set(railings.compactMap { stringValue($0, "edge_id") })
        let postEdgeIds = Set(posts.compactMap { stringValue($0, "edge_id") })
        XCTAssertEqual(railingEdgeIds, postEdgeIds, "post_set pairs with its railing via edge_id")
        XCTAssertEqual(railingEdgeIds.count, 4, "Each of the 4 edges contributes one unique edge_id")
    }

    // MARK: - Single stair edge (scenario 3)

    func test_emit_singleStairEdge_emitsStairSet_withTreadCountFromCalculator() {
        let stairWidthInches: Double = 48 // 4 ft
        let elevationFt: Double = 4.0     // 4 ft = 48 inches rise
        let stair = StairConfig(width: stairWidthInches, color: "Black", mountType: "Surface")

        // Single edge with stair config + an overall elevation so totalRise is computable.
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = elevationFt

        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 120, y: 0))
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 120 // 10 ft
        edge.stairConfig = stair

        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)
        let stairs = rows.filter { $0.componentType == "stair_set" }
        XCTAssertEqual(stairs.count, 1)

        let row = stairs[0]
        let expectedTreads = StairConfig.calculateTreadCount(
            totalRise: elevationFt * 12.0, // feet -> inches
            risePerStep: stair.risePerStep
        )
        XCTAssertEqual(row.metadata["tread_count"], AnyCodable(expectedTreads))
        XCTAssertEqual(row.metadata["width"], AnyCodable(stairWidthInches))
        XCTAssertEqual(row.metadata["color"], AnyCodable("Black"))
        XCTAssertEqual(row.metadata["mount_type"], AnyCodable("Surface"))
        XCTAssertEqual(row.metadata["stringer_style"], AnyCodable("open"))
        XCTAssertEqual(row.metadata["stringer_material"], AnyCodable("pressure_treated_wood"))
        XCTAssertEqual(row.metadata["tread_material"], AnyCodable("composite"))
    }

    // MARK: - Multi-level connection stair (scenario 4)

    func test_emit_multiLevelConnectionStair_emitsStairSetWithLevelIdAtUpperLevel() {
        var upper = DeckLevel(name: "Upper")
        upper.elevation = 4.0  // feet
        let uv1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let uv2 = DeckVertex(position: CGPoint(x: 120, y: 0))
        let uv3 = DeckVertex(position: CGPoint(x: 120, y: 120))
        let uv4 = DeckVertex(position: CGPoint(x: 0, y: 120))
        var ue1 = DeckEdge(startVertexId: uv1.id, endVertexId: uv2.id)
        ue1.dimension = 120
        var ue2 = DeckEdge(startVertexId: uv2.id, endVertexId: uv3.id)
        ue2.dimension = 120
        var ue3 = DeckEdge(startVertexId: uv3.id, endVertexId: uv4.id)
        ue3.dimension = 120
        var ue4 = DeckEdge(startVertexId: uv4.id, endVertexId: uv1.id)
        ue4.dimension = 120
        upper.vertices = [uv1, uv2, uv3, uv4]
        upper.edges = [ue1, ue2, ue3, ue4]

        var lower = DeckLevel(name: "Lower")
        lower.elevation = 0.0
        let lv1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let lv2 = DeckVertex(position: CGPoint(x: 120, y: 0))
        let lv3 = DeckVertex(position: CGPoint(x: 120, y: 120))
        let lv4 = DeckVertex(position: CGPoint(x: 0, y: 120))
        var le1 = DeckEdge(startVertexId: lv1.id, endVertexId: lv2.id)
        le1.dimension = 120
        var le2 = DeckEdge(startVertexId: lv2.id, endVertexId: lv3.id)
        le2.dimension = 120
        var le3 = DeckEdge(startVertexId: lv3.id, endVertexId: lv4.id)
        le3.dimension = 120
        var le4 = DeckEdge(startVertexId: lv4.id, endVertexId: lv1.id)
        le4.dimension = 120
        lower.vertices = [lv1, lv2, lv3, lv4]
        lower.edges = [le1, le2, le3, le4]

        let connection = LevelConnection(
            upperLevelId: upper.id,
            lowerLevelId: lower.id,
            upperEdgeId: ue1.id,
            lowerEdgeId: le1.id,
            stairConfig: StairConfig(width: 48, color: "Black", mountType: "Top")
        )

        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.levels = [upper, lower]
        data.levelConnections = [connection]

        let rows = ComponentEmitter.emit(data)
        let connectionStairs = rows.filter {
            $0.componentType == "stair_set" && $0.metadata["connection_id"] == AnyCodable(connection.id)
        }
        XCTAssertEqual(connectionStairs.count, 1, "One stair_set per LevelConnection")
        let row = connectionStairs[0]
        XCTAssertEqual(row.metadata["level_id"], AnyCodable(upper.id),
                       "Connection stair's level_id is the upper level (stairs descend from there)")
        XCTAssertEqual(row.metadata["mount_type"], AnyCodable("Top"))
        XCTAssertEqual(row.metadata["stringer_style"], AnyCodable("open"))
        XCTAssertEqual(row.metadata["stringer_material"], AnyCodable("pressure_treated_wood"))
        XCTAssertEqual(row.metadata["tread_material"], AnyCodable("composite"))

        let totalRiseInches = (upper.elevation! - lower.elevation!) * 12.0
        let expectedTreads = StairConfig.calculateTreadCount(totalRise: totalRiseInches)
        XCTAssertEqual(row.metadata["tread_count"], AnyCodable(expectedTreads))
    }

    // MARK: - Surface assignment carries material (scenario 5)

    func test_emit_surfaceWithBoardMaterialPVC_emitsDeckBoardCarryingMaterial() {
        // 12 ft × 12 ft canvas square (144 × 144 inches at scaleFactor 1.0)
        // → 144 sq ft real-world. makeClosedQuadDrawing builds exactly that
        // shape with no railings.
        var data = makeClosedQuadDrawing()

        let surface = DeckSurface(
            vertexIds: Set(data.vertices.map(\.id)),
            assignedItems: [AssignedItem(name: "Decking", unitType: .squareFoot)],
            color: "Brown",
            boardMaterial: "pvc"
        )
        data.surfaces = [surface]

        let rows = ComponentEmitter.emit(data)
        let boards = rows.filter { $0.componentType == "deck_board" }
        XCTAssertEqual(boards.count, 1)
        let row = boards[0]
        XCTAssertEqual(row.metadata["material"], AnyCodable("pvc"))
        XCTAssertEqual(row.metadata["color"], AnyCodable("Brown"))
        XCTAssertEqual(row.metadata["surface_id"], AnyCodable(surface.id))
        // sqft = 144 (12 ft x 12 ft), rounded to 2 decimals = 144.0
        XCTAssertEqual(row.metadata["sqft"], AnyCodable(144.0))
    }

    // MARK: - Gate on a 12 ft railing edge (scenario 6)

    func test_emit_gateOn12ftRailingEdge_emitsGateAndRailingWithLinearFeet9() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 144, y: 0)) // 12 ft canvas span
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 144 // 12 ft real-world
        edge.railingConfig = RailingConfig(
            railingType: .picket,
            maxPostSpacing: 84,
            color: "Black",
            mountType: "Topmount",
            mountSurface: "Surface"
        )
        edge.assignedItems = [
            AssignedItem(name: "Gate", unitType: .each, isGate: true)
        ]

        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)
        let gates = rows.filter { $0.componentType == "gate" }
        let railings = rows.filter { $0.componentType == "railing" }

        XCTAssertEqual(gates.count, 1, "One gate component per gate-flagged AssignedItem")
        XCTAssertEqual(railings.count, 1)
        XCTAssertEqual(railings[0].metadata["linear_feet"], AnyCodable(9.0),
                       "Gate width (36 in = 3 ft) is subtracted from edge length (12 ft) → 9 ft")
        XCTAssertEqual(gates[0].metadata["width"], AnyCodable(ComponentEmitter.defaultGateWidthInches))
        XCTAssertEqual(gates[0].metadata["count"], AnyCodable(1))
        XCTAssertEqual(gates[0].metadata["color"], AnyCodable("Black"))
        XCTAssertEqual(gates[0].metadata["mount_type"], AnyCodable("Topmount"))
        XCTAssertEqual(gates[0].metadata["mount_surface"], AnyCodable("Surface"))
        XCTAssertEqual(gates[0].metadata["mount_placement"], AnyCodable("top_mounted"))
    }

    func test_emit_glassRailingCarriesFrameStyleAndMountPlacement() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 144, y: 0))
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 144
        edge.railingConfig = RailingConfig(
            railingType: .glass,
            maxPostSpacing: 60,
            color: "Clear",
            mountType: "Sidemount",
            mountSurface: "Fascia",
            frameStyle: .frameless,
            mountPlacement: .fasciaMounted
        )

        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)
        let railing = rows.first { $0.componentType == "railing" }
        let post = rows.first { $0.componentType == "post_set" }

        XCTAssertEqual(railing?.metadata["frame_style"], AnyCodable("frameless"))
        XCTAssertEqual(railing?.metadata["mount_placement"], AnyCodable("fascia_mounted"))
        XCTAssertEqual(post?.metadata["mount_placement"], AnyCodable("fascia_mounted"))
    }

    func test_emit_stairCarriesStringerAndTreadProductOptions() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = 4.0

        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 120, y: 0))
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 120
        edge.stairConfig = StairConfig(
            width: 48,
            stringerStyle: .closed,
            stringerMaterial: .steel,
            treadMaterial: .twoBySix
        )

        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)
        let stair = rows.first { $0.componentType == "stair_set" }

        XCTAssertEqual(stair?.metadata["stringer_style"], AnyCodable("closed"))
        XCTAssertEqual(stair?.metadata["stringer_material"], AnyCodable("steel"))
        XCTAssertEqual(stair?.metadata["tread_material"], AnyCodable("2x6"))
    }

    // MARK: - Stair span subtracted from railing linear_feet

    func test_emit_railingEdgeWithStair_subtractsStairSpanFromLinearFeet() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = 4.0

        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 120, y: 0)) // 10 ft canvas
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 120 // 10 ft real-world
        edge.railingConfig = RailingConfig(railingType: .picket, maxPostSpacing: 84)
        edge.stairConfig = StairConfig(width: 48) // 4 ft stair span

        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)
        let railing = rows.first { $0.componentType == "railing" }
        XCTAssertNotNil(railing)
        // 10 ft - 4 ft stair = 6 ft railing
        XCTAssertEqual(railing?.metadata["linear_feet"], AnyCodable(6.0))
    }

    // MARK: - post_set count uses DimensionEngine

    func test_emit_postSet_usesDimensionEnginePostCount() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0

        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 168, y: 0)) // 14 ft
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 168
        edge.railingConfig = RailingConfig(railingType: .picket, maxPostSpacing: 84)
        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)
        let post = rows.first { $0.componentType == "post_set" }
        XCTAssertNotNil(post)
        let expected = DimensionEngine.postCount(edgeLengthInches: 168, maxSpacing: 84)
        XCTAssertEqual(post?.metadata["count"], AnyCodable(expected))
        XCTAssertEqual(post?.metadata["height"], AnyCodable(36.0)) // RailingConfig default
    }

    // MARK: - JSON round-trip (DeckDrawingData carries components on encode)

    func test_toJSON_includesComponentsArray() {
        let data = makeClosedQuadWithRailings()
        let json = data.toJSON()
        XCTAssertTrue(json.contains("\"components\""), "toJSON output should carry the components array")
        XCTAssertTrue(json.contains("\"component_type\""), "Each row exposes component_type")
        XCTAssertTrue(json.contains("\"railing\""), "Closed quad with railings should emit at least one railing component_type")
    }

    func test_legacyJSON_withoutComponentsKey_decodesAndEmitterFiresOnLoadedData() {
        // Hand-craft a minimal legacy JSON without the components key — only
        // the keys the v1 model carried.
        let legacy = """
        {
          "config": {"angleSnapIncrement":15,"endpointSnapRadius":20,"gridVisible":true,"lengthSnapIncrement":6,"measurementSystem":"imperial","snappingEnabled":true},
          "edges": [],
          "footprint": {"assignedItems":[],"isClosed":false},
          "levelConnections": [],
          "levels": [],
          "surfaces": [],
          "vertices": []
        }
        """
        let decoded = DeckDrawingData.fromJSON(legacy)
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.components, "Legacy JSON without components key decodes with components == nil")

        // The emitter still runs against a legacy-decoded structure (just
        // produces empty rows for an empty drawing).
        if let d = decoded {
            let rows = ComponentEmitter.emit(d)
            XCTAssertTrue(rows.isEmpty)
        }
    }

    // MARK: - Default vocabulary on partially-configured drawings

    func test_emit_defaultVocabularyApplied_whenRailingFieldsUntouched() {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 120, y: 0))
        var edge = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        edge.dimension = 120
        // RailingConfig with default color/mountType/mountSurface/postHeight.
        edge.railingConfig = RailingConfig(railingType: .picket, maxPostSpacing: 84)
        data.vertices = [v1, v2]
        data.edges = [edge]

        let rows = ComponentEmitter.emit(data)
        let railing = rows.first { $0.componentType == "railing" }
        XCTAssertEqual(railing?.metadata["color"], AnyCodable("Black"))
        XCTAssertEqual(railing?.metadata["mount_type"], AnyCodable("Topmount"))
        XCTAssertEqual(railing?.metadata["mount_surface"], AnyCodable("Surface"))
    }

    // MARK: - Framing components

    func test_emit_addsFramingRows_additively() throws {
        var data = makeClosedQuadWithRailings()
        data.surfaces = [
            DeckSurface(
                vertexIds: Set(data.vertices.map(\.id)),
                assignedItems: [AssignedItem(name: "Decking", unitType: .squareFoot)]
            )
        ]
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(levelId: "", members: [
                    framingMember(
                        id: "joist-0",
                        role: .joist,
                        start: .zero,
                        end: CGPoint(x: 144, y: 0),
                        nominalSize: .twoByEight
                    ),
                    framingMember(
                        id: "beam-0",
                        role: .beam,
                        start: CGPoint(x: 0, y: 120),
                        end: CGPoint(x: 144, y: 120),
                        nominalSize: .twoByTen,
                        plyCount: 2
                    ),
                    framingMember(
                        id: "post-0",
                        role: .post,
                        start: CGPoint(x: 0, y: 120),
                        end: CGPoint(x: 0, y: 120),
                        nominalSize: .sixBySix
                    ),
                    framingMember(
                        id: "rim-0",
                        role: .rimBand,
                        start: CGPoint(x: 0, y: 144),
                        end: CGPoint(x: 144, y: 144),
                        nominalSize: .twoByEight
                    ),
                    framingMember(
                        id: "blocking-0",
                        role: .blocking,
                        start: CGPoint(x: 72, y: 0),
                        end: CGPoint(x: 72, y: 144),
                        nominalSize: .twoByEight
                    ),
                ])
            ],
            generationSource: .manual
        )

        let rows = ComponentEmitter.emit(data)
        let types = Set(rows.map(\.componentType))

        XCTAssertTrue(types.isSuperset(of: ["joist", "beam", "post", "rim_joist", "blocking"]))
        XCTAssertTrue(types.contains("deck_board"))
        XCTAssertTrue(types.contains("railing"))
        XCTAssertTrue(types.contains("post_set"), "Railing posts stay distinct from structural post rows.")

        let joist = try XCTUnwrap(rows.first { $0.componentType == "joist" })
        XCTAssertEqual(joist.metadata["linear_feet"], AnyCodable(12.0))
        XCTAssertEqual(joist.metadata["nominal_size"], AnyCodable("2x8"))
        XCTAssertEqual(joist.metadata["ply_count"], AnyCodable(1))
        XCTAssertEqual(joist.metadata["count"], AnyCodable(1))
        XCTAssertEqual(joist.metadata["species"], AnyCodable("spf"))
        XCTAssertEqual(joist.metadata["grade"], AnyCodable("no2"))
        XCTAssertEqual(joist.metadata["level_id"], AnyCodable(""))
        XCTAssertEqual(joist.metadata["member_id"], AnyCodable("joist-0"))
    }

    func test_emit_noFraming_doesNotAddStructuralRows() {
        let data = makeClosedQuadWithRailings()

        let rows = ComponentEmitter.emit(data)
        let types = Set(rows.map(\.componentType))

        XCTAssertEqual(types, Set(["railing", "post_set", "deck_board"]))
        XCTAssertFalse(types.contains("joist"))
        XCTAssertFalse(types.contains("beam"))
        XCTAssertFalse(types.contains("post"))
        XCTAssertFalse(types.contains("rim_joist"))
        XCTAssertFalse(types.contains("blocking"))
    }

    // MARK: - Helpers

    /// 4-vertex 4-edge closed quad with railings on every edge, all 144 inches
    /// (12 ft) long. Useful for exercising every per-edge component.
    private func makeClosedQuadWithRailings(
        railingType: RailingType = .picket,
        color: String = "Black",
        mountType: String = "Topmount",
        mountSurface: String = "Surface",
        frameStyle: RailingFrameStyle = .framed,
        mountPlacement: RailingMountPlacement = .topMounted
    ) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0

        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 144, y: 0))
        let v3 = DeckVertex(position: CGPoint(x: 144, y: 144))
        let v4 = DeckVertex(position: CGPoint(x: 0, y: 144))

        let railing = RailingConfig(
            railingType: railingType,
            maxPostSpacing: railingType.defaultMaxPostSpacing,
            color: color,
            mountType: mountType,
            mountSurface: mountSurface,
            frameStyle: frameStyle,
            mountPlacement: mountPlacement
        )

        var e1 = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        var e2 = DeckEdge(startVertexId: v2.id, endVertexId: v3.id)
        var e3 = DeckEdge(startVertexId: v3.id, endVertexId: v4.id)
        var e4 = DeckEdge(startVertexId: v4.id, endVertexId: v1.id)
        for i in 0..<4 {
            switch i {
            case 0: e1.dimension = 144; e1.railingConfig = railing
            case 1: e2.dimension = 144; e2.railingConfig = railing
            case 2: e3.dimension = 144; e3.railingConfig = railing
            case 3: e4.dimension = 144; e4.railingConfig = railing
            default: break
            }
        }

        data.vertices = [v1, v2, v3, v4]
        data.edges = [e1, e2, e3, e4]
        return data
    }

    /// Pulls a String out of a row's metadata. Returns nil when the value
    /// isn't present or isn't a String — AnyCodable doesn't conform to
    /// Hashable so Set<AnyCodable> isn't viable; we work with the unwrapped
    /// scalars in tests instead.
    private func stringValue(_ row: DesignComponentRow, _ key: String) -> String? {
        return row.metadata[key]?.value as? String
    }

    /// Closed quad with NO railings — useful for surface-only scenarios.
    private func makeClosedQuadDrawing() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        let v1 = DeckVertex(position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(position: CGPoint(x: 144, y: 0))
        let v3 = DeckVertex(position: CGPoint(x: 144, y: 144))
        let v4 = DeckVertex(position: CGPoint(x: 0, y: 144))
        var e1 = DeckEdge(startVertexId: v1.id, endVertexId: v2.id)
        var e2 = DeckEdge(startVertexId: v2.id, endVertexId: v3.id)
        var e3 = DeckEdge(startVertexId: v3.id, endVertexId: v4.id)
        var e4 = DeckEdge(startVertexId: v4.id, endVertexId: v1.id)
        e1.dimension = 144
        e2.dimension = 144
        e3.dimension = 144
        e4.dimension = 144
        data.vertices = [v1, v2, v3, v4]
        data.edges = [e1, e2, e3, e4]
        return data
    }

    private func framingMember(
        id: String,
        role: FramingRole,
        start: CGPoint,
        end: CGPoint,
        nominalSize: LumberSize,
        plyCount: Int = 1
    ) -> FramingMember {
        FramingMember(
            id: id,
            role: role,
            start: start,
            end: end,
            nominalSize: nominalSize,
            plyCount: plyCount,
            species: .sprucePineFir,
            grade: .no2
        )
    }
}
