//
//  RailingTakeoffTests.swift
//  OPSTests
//
//  Railing run takeoff from a Deck Designer drawing: linear feet, left/right
//  end posts, 90° corners, off-angle corners and house returns per railing
//  run group (plan 2026-09-15 recipe-engine-railing-bridge, D5–D9).
//
//  Canvas coordinates are y-down. Every fixture uses scaleFactor 2 (two
//  canvas points per real-world inch) so positions and `dimension` agree.
//

import XCTest
import CoreGraphics
@testable import OPS

final class RailingTakeoffTests: XCTestCase {

    // MARK: - Fixture builder

    private static let scale: Double = 2.0

    private struct Sketch {
        var vertices: [String: DeckVertex] = [:]
        var order: [String] = []
        var edges: [DeckEdge] = []

        /// Adds a vertex at a real-world position in inches.
        mutating func point(_ id: String, _ xInches: Double, _ yInches: Double) {
            let v = DeckVertex(
                id: id,
                position: CGPoint(x: xInches * RailingTakeoffTests.scale, y: yInches * RailingTakeoffTests.scale)
            )
            vertices[id] = v
            order.append(id)
        }

        /// Adds an edge whose `dimension` is the real-world distance between
        /// its endpoints (unless `dimension` is given explicitly).
        mutating func edge(
            _ id: String,
            _ from: String,
            _ to: String,
            type: EdgeType = .deckEdge,
            railing: RailingConfig? = nil,
            stairWidth: Double? = nil,
            gates: Int = 0,
            dimension: Double? = nil
        ) {
            let a = vertices[from]!.position
            let b = vertices[to]!.position
            let canvasLength = hypot(Double(b.x - a.x), Double(b.y - a.y))
            var e = DeckEdge(
                id: id,
                startVertexId: from,
                endVertexId: to,
                edgeType: type,
                dimension: dimension ?? (canvasLength / RailingTakeoffTests.scale),
                railingConfig: railing
            )
            if let stairWidth { e.stairConfig = StairConfig(width: stairWidth) }
            e.assignedItems = (0..<gates).map { i in
                AssignedItem(id: "\(id)-gate-\(i)", name: "Gate", unitType: .each, isGate: true)
            }
            edges.append(e)
        }

        var drawing: DeckDrawingData {
            var data = DeckDrawingData()
            data.scaleFactor = RailingTakeoffTests.scale
            data.vertices = order.map { vertices[$0]! }
            data.edges = edges
            return data
        }

        func level(_ id: String) -> DeckLevel {
            var level = DeckLevel(id: id, name: id)
            level.vertices = order.map { vertices[$0]! }
            level.edges = edges
            return level
        }
    }

    private let picket = RailingConfig(railingType: .picket, maxPostSpacing: 84)
    private let glass = RailingConfig(railingType: .glass, maxPostSpacing: 60)

    private func only(_ groups: [RailingTakeoff.Group], file: StaticString = #filePath, line: UInt = #line) throws -> RailingTakeoff.Group {
        XCTAssertEqual(groups.count, 1, "expected exactly one railing group", file: file, line: line)
        return try XCTUnwrap(groups.first, file: file, line: line)
    }

    private func assertCounts(
        _ g: RailingTakeoff.Group,
        lf: Double, left: Int, right: Int, corners: Int, offAngle: Int, houseReturns: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(g.linearFeet, lf, accuracy: 0.001, "linearFeet", file: file, line: line)
        XCTAssertEqual(g.leftEnds, left, "leftEnds", file: file, line: line)
        XCTAssertEqual(g.rightEnds, right, "rightEnds", file: file, line: line)
        XCTAssertEqual(g.corners, corners, "corners", file: file, line: line)
        XCTAssertEqual(g.offAngleCorners, offAngle, "offAngleCorners", file: file, line: line)
        XCTAssertEqual(g.houseReturns, houseReturns, "houseReturns", file: file, line: line)
    }

    // MARK: - Empty

    func test_noRailingEdges_noGroups() {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 240, 0)
        s.edge("e1", "a", "b")
        XCTAssertTrue(RailingTakeoff.compute(data: s.drawing).isEmpty)
        XCTAssertTrue(RailingTakeoff.compute(data: DeckDrawingData()).isEmpty)
    }

    // MARK: - Single straight 20 ft edge

    func test_singleStraightEdge_oneLeftOneRight() throws {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 240, 0)
        s.edge("e1", "a", "b", railing: picket)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 20, left: 1, right: 1, corners: 0, offAngle: 0, houseReturns: 0)
        XCTAssertEqual(g.railingType, .picket)
        XCTAssertEqual(g.handednessBasis, .edgeOrder, "no closed surface decides the deck side")
        XCTAssertEqual(g.edgeIds, ["e1"])
    }

    // MARK: - 10 ft + 10 ft, convex 90° corner, closed footprint

    /// Railing a→b→c on a 120 × 240 rectangle. c→d and e→a are unrailed deck
    /// edges; d→e is the house. The house never touches a railing end.
    private func convexCornerSketch() -> Sketch {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 120, 0); s.point("c", 120, 120)
        s.point("d", 120, 240); s.point("e", 0, 240)
        s.edge("e1", "a", "b", railing: picket)
        s.edge("e2", "b", "c", railing: picket)
        s.edge("e3", "c", "d")
        s.edge("e4", "d", "e", type: .houseEdge)
        s.edge("e5", "e", "a")
        return s
    }

    func test_twoEdges_convex90Corner_countsOneCorner() throws {
        let g = try only(RailingTakeoff.compute(data: convexCornerSketch().drawing))
        assertCounts(g, lf: 20, left: 1, right: 1, corners: 1, offAngle: 0, houseReturns: 0)
        XCTAssertEqual(g.handednessBasis, .surface)
        XCTAssertEqual(Set(g.edgeIds), ["e1", "e2"], "house and unrailed deck edges are ignored")
    }

    // MARK: - U shape

    func test_uShape_twoCorners_andHouseReturnsAtBothEnds() throws {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 240, 0); s.point("c", 240, 240); s.point("d", 0, 240)
        s.edge("house", "a", "b", type: .houseEdge)
        s.edge("e1", "b", "c", railing: picket)
        s.edge("e2", "c", "d", railing: picket)
        s.edge("e3", "d", "a", railing: picket)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 60, left: 1, right: 1, corners: 2, offAngle: 0, houseReturns: 2)
        XCTAssertEqual(g.handednessBasis, .surface)
    }

    // MARK: - Off-angle vertex

    func test_135DegreeVertex_countsOffAngleCornerAndTwoExtraEnds() throws {
        var s = Sketch()
        let run = 120 / 2.0.squareRoot() // 120 in along a 45° diagonal
        s.point("a", 0, 0); s.point("b", 240, 0); s.point("c", 240 + run, run)
        s.edge("e1", "a", "b", railing: picket)
        s.edge("e2", "b", "c", railing: picket)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 30, left: 2, right: 2, corners: 0, offAngle: 1, houseReturns: 0)
    }

    func test_nearlyStraight178Degrees_countsNoCorner() throws {
        var s = Sketch()
        let rise = 240 * tan(2.0 * .pi / 180)
        s.point("a", 0, 0); s.point("b", 240, 0); s.point("c", 480, rise)
        s.edge("e1", "a", "b", railing: picket)
        s.edge("e2", "b", "c", railing: picket, dimension: 240)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 40, left: 1, right: 1, corners: 0, offAngle: 0, houseReturns: 0)
    }

    // MARK: - Closed loop

    func test_closedRailingLoop_fourCornersNoEnds() throws {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 144, 0); s.point("c", 144, 144); s.point("d", 0, 144)
        s.edge("e1", "a", "b", railing: picket)
        s.edge("e2", "b", "c", railing: picket)
        s.edge("e3", "c", "d", railing: picket)
        s.edge("e4", "d", "a", railing: picket)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 48, left: 0, right: 0, corners: 4, offAngle: 0, houseReturns: 0)
        XCTAssertEqual(g.handednessBasis, .surface)
        XCTAssertTrue(g.terminals.isEmpty)
    }

    // MARK: - House return

    func test_chainEndOnHouseEdge_countsHouseReturn_endsUnchanged() throws {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 240, 0); s.point("h", 240, -120)
        s.edge("e1", "a", "b", railing: picket)
        s.edge("wall", "b", "h", type: .houseEdge)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 20, left: 1, right: 1, corners: 0, offAngle: 0, houseReturns: 1)
        let houseTerminal = try XCTUnwrap(g.terminals.first { $0.isHouseReturn })
        XCTAssertEqual(houseTerminal.vertexId, "b")
    }

    // MARK: - Openings

    func test_stairOpening_deductsWidth_andAddsBothEnds() throws {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 240, 0)
        s.edge("e1", "a", "b", railing: picket, stairWidth: 48)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 16, left: 2, right: 2, corners: 0, offAngle: 0, houseReturns: 0)
    }

    func test_gateOpening_deductsGateWidth_andAddsBothEnds() throws {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 144, 0)
        s.edge("e1", "a", "b", railing: picket, gates: 1)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 9, left: 2, right: 2, corners: 0, offAngle: 0, houseReturns: 0)
    }

    func test_linearFeet_matchesComponentEmitterNetLengthRule() {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 144, 0)
        s.edge("e1", "a", "b", railing: picket, stairWidth: 36, gates: 2)
        let edge = s.edges[0]
        XCTAssertEqual(ComponentEmitter.netRailingInches(edge: edge), 144 - 36 - 72, accuracy: 0.0001)

        var over = edge
        over.stairConfig = StairConfig(width: 200)
        XCTAssertEqual(ComponentEmitter.netRailingInches(edge: over), 0, "never negative")
    }

    // MARK: - Grouping

    func test_twoRailingTypes_twoGroups_neverJoinedAcrossTypes() throws {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 120, 0); s.point("c", 120, 120)
        s.edge("e1", "a", "b", railing: picket)
        s.edge("e2", "b", "c", railing: glass)

        let groups = RailingTakeoff.compute(data: s.drawing)
        XCTAssertEqual(groups.map(\.railingType), [.glass, .picket], "ordered by RailingType.allCases")
        for g in groups {
            assertCounts(g, lf: 10, left: 1, right: 1, corners: 0, offAngle: 0, houseReturns: 0)
        }
    }

    /// Same railing type in two colours is two products on the estimate —
    /// a white run must never be priced and ordered as black.
    func test_sameTypeDifferentColor_splitsIntoTwoGroups() {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 120, 0); s.point("c", 240, 0)
        var white = picket
        white.color = "White"
        s.edge("e1", "a", "b", railing: picket)
        s.edge("e2", "b", "c", railing: white)

        let groups = RailingTakeoff.compute(data: s.drawing)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.color), ["Black", "White"])
        XCTAssertEqual(groups.map(\.leftEnds), [1, 1])
    }

    func test_houseEdgeCarryingRailingConfig_isIgnored() {
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 240, 0)
        s.edge("e1", "a", "b", type: .houseEdge, railing: picket)
        XCTAssertTrue(RailingTakeoff.compute(data: s.drawing).isEmpty)
    }

    // MARK: - Inside corner (L-shaped footprint)

    /// L-shaped deck, both windings. Railing runs b→c→d around the reflex
    /// vertex c (the notch). Inside 90° corners are discontinued: they take an
    /// end post on each side instead of a corner sleeve.
    private func lShapeSketch(reversed: Bool) -> Sketch {
        var s = Sketch()
        // (0,0) (240,0) (240,120) (120,120) (120,240) (0,240)
        s.point("a", 0, 0); s.point("b", 240, 0); s.point("c", 240, 120)
        s.point("r", 120, 120); s.point("d", 120, 240); s.point("e", 0, 240)
        let ring = ["a", "b", "c", "r", "d", "e"]
        let walk = reversed ? Array(ring.reversed()) : ring
        for i in 0..<walk.count {
            let from = walk[i], to = walk[(i + 1) % walk.count]
            let pair = Set([from, to])
            let railed = pair == ["c", "r"] || pair == ["r", "d"]
            s.edge("\(from)\(to)", from, to, railing: railed ? picket : nil)
        }
        return s
    }

    func test_insideCorner_onLShapedFootprint_countsEndsNotCorner_bothWindings() throws {
        for reversed in [false, true] {
            let g = try only(RailingTakeoff.compute(data: lShapeSketch(reversed: reversed).drawing))
            assertCounts(g, lf: 20, left: 2, right: 2, corners: 0, offAngle: 0, houseReturns: 0)
            XCTAssertEqual(g.handednessBasis, .surface, "reversed=\(reversed)")
        }
    }

    func test_convexCorner_detectedInBothWindings() throws {
        // Same rectangle as convexCornerSketch, but every edge drawn backwards
        // (counter-clockwise on screen instead of clockwise).
        var s = Sketch()
        s.point("a", 0, 0); s.point("b", 120, 0); s.point("c", 120, 120)
        s.point("d", 120, 240); s.point("e", 0, 240)
        s.edge("e1", "b", "a", railing: picket)
        s.edge("e2", "c", "b", railing: picket)
        s.edge("e3", "d", "c")
        s.edge("e4", "e", "d", type: .houseEdge)
        s.edge("e5", "a", "e")

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 20, left: 1, right: 1, corners: 1, offAngle: 0, houseReturns: 0)
    }

    // MARK: - Handedness (D6)

    /// Railing on the TOP edge of a deck that sits below it on screen. A
    /// person outside (above) facing the railing looks down the screen, so
    /// their left hand points to +x: the left end is the east vertex.
    func test_handedness_topEdge_leftEndIsEast_regardlessOfDrawDirection() throws {
        for drawnBackwards in [false, true] {
            var s = Sketch()
            s.point("w", 0, 0); s.point("east", 240, 0); s.point("se", 240, 240); s.point("sw", 0, 240)
            if drawnBackwards {
                s.edge("top", "east", "w", railing: picket)
            } else {
                s.edge("top", "w", "east", railing: picket)
            }
            s.edge("r", "east", "se")
            s.edge("b", "se", "sw", type: .houseEdge)
            s.edge("l", "sw", "w")

            let g = try only(RailingTakeoff.compute(data: s.drawing))
            XCTAssertEqual(g.handednessBasis, .surface)
            XCTAssertEqual(g.terminals.first { $0.hand == .left }?.vertexId, "east", "drawnBackwards=\(drawnBackwards)")
            XCTAssertEqual(g.terminals.first { $0.hand == .right }?.vertexId, "w", "drawnBackwards=\(drawnBackwards)")
        }
    }

    /// Railing on the BOTTOM edge: the person stands below facing up the
    /// screen, so their left is -x: the left end is the west vertex.
    func test_handedness_bottomEdge_leftEndIsWest() throws {
        var s = Sketch()
        s.point("nw", 0, 0); s.point("ne", 240, 0); s.point("east", 240, 240); s.point("west", 0, 240)
        s.edge("top", "nw", "ne", type: .houseEdge)
        s.edge("r", "ne", "east")
        s.edge("bottom", "east", "west", railing: picket)
        s.edge("l", "west", "nw")

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        XCTAssertEqual(g.terminals.first { $0.hand == .left }?.vertexId, "west")
        XCTAssertEqual(g.terminals.first { $0.hand == .right }?.vertexId, "east")
    }

    /// No closed surface: walk order is edge order, and the final vertex of
    /// the walk is the left end.
    func test_handedness_withoutSurface_usesEdgeOrder() throws {
        var s = Sketch()
        s.point("start", 0, 0); s.point("finish", 240, 0)
        s.edge("e1", "start", "finish", railing: picket)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        XCTAssertEqual(g.handednessBasis, .edgeOrder)
        XCTAssertEqual(g.terminals.first { $0.hand == .left }?.vertexId, "finish")
        XCTAssertEqual(g.terminals.first { $0.hand == .right }?.vertexId, "start")
    }

    // MARK: - Junctions (3+ railing edges at one vertex)

    /// Judgment call: at a vertex joining three or more same-group railing
    /// edges every run terminates, so each incident run takes its own end
    /// post there. A T of three 20 ft runs is three runs: L3 R3, no corners.
    func test_tJunction_everyIncidentRunTerminates() throws {
        var s = Sketch()
        s.point("w", 0, 0); s.point("j", 240, 0); s.point("e", 480, 0); s.point("s", 240, 240)
        s.edge("e1", "w", "j", railing: picket)
        s.edge("e2", "j", "e", railing: picket)
        s.edge("e3", "j", "s", railing: picket)

        let g = try only(RailingTakeoff.compute(data: s.drawing))
        assertCounts(g, lf: 60, left: 3, right: 3, corners: 0, offAngle: 0, houseReturns: 0)
        XCTAssertEqual(g.terminals.filter { $0.vertexId == "j" }.count, 3)
    }

    // MARK: - Multi-level

    /// Two levels that happen to reuse vertex ids. Runs never join across
    /// levels: each level's single edge is its own run.
    func test_multiLevel_runsBuiltPerLevel_totalsAggregatedPerGroup() throws {
        var upper = Sketch()
        upper.point("v1", 0, 0); upper.point("v2", 120, 0)
        upper.edge("u1", "v1", "v2", railing: picket)
        var lower = Sketch()
        lower.point("v2", 120, 0); lower.point("v3", 120, 120)
        lower.edge("l1", "v2", "v3", railing: picket)

        var data = DeckDrawingData()
        data.scaleFactor = Self.scale
        data.levels = [upper.level("upper"), lower.level("lower")]

        let g = try only(RailingTakeoff.compute(data: data))
        assertCounts(g, lf: 20, left: 2, right: 2, corners: 0, offAngle: 0, houseReturns: 0)
        XCTAssertEqual(Set(g.terminals.map(\.levelId)), ["upper", "lower"])
    }

    // MARK: - Component metadata

    func test_componentMetadata_carriesTotalsAndVocabulary() throws {
        let g = try only(RailingTakeoff.compute(data: convexCornerSketch().drawing))
        let meta = g.componentMetadata
        XCTAssertEqual(meta["linear_feet"], AnyCodable(20.0))
        XCTAssertEqual(meta["left_ends"], AnyCodable(1))
        XCTAssertEqual(meta["right_ends"], AnyCodable(1))
        XCTAssertEqual(meta["corners"], AnyCodable(1))
        XCTAssertEqual(meta["off_angle_corners"], AnyCodable(0))
        XCTAssertEqual(meta["house_returns"], AnyCodable(0))
        XCTAssertEqual(meta["handedness_basis"], AnyCodable("surface"))
        XCTAssertEqual(meta["railing_type"], AnyCodable("picket"))
        XCTAssertEqual(meta["color"], AnyCodable("Black"))
        XCTAssertEqual(meta["mount_type"], AnyCodable("Topmount"))
        XCTAssertEqual(meta["mount_surface"], AnyCodable("Surface"))
        XCTAssertNil(meta["wall_material"])
    }
}
