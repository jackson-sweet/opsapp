//
//  DeckEdgeNamingTests.swift
//  OPSTests
//
//  Bug 2f717747 — the stair sheet's edge picker listed "Edge 1–2", "Edge 2–3".
//  Vertex indices are an implementation detail: they appear nowhere on the
//  canvas, so the operator had no way to tell which row was the edge they
//  meant. An edge is named by what the operator called it, or by the side of
//  the deck it faces and how long it is.
//

import CoreGraphics
import XCTest
@testable import OPS

final class DeckEdgeNamingTests: XCTestCase {

    /// A 12'×12' square, wound clockwise in screen space (y grows DOWN):
    /// e1 runs along the top (faces north), e2 down the right (east),
    /// e3 along the bottom (south), e4 up the left (west).
    private func squareLevel() -> DeckLevel {
        var level = DeckLevel(id: "level-a", name: "Level 1")
        level.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        level.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        return level
    }

    // MARK: - Which way an edge faces

    func testEachSideOfASquareResolvesToItsCompassFacing() {
        let level = squareLevel()

        XCTAssertEqual(DeckEdgeNaming.side(ofEdgeId: "e1", in: level), .north)
        XCTAssertEqual(DeckEdgeNaming.side(ofEdgeId: "e2", in: level), .east)
        XCTAssertEqual(DeckEdgeNaming.side(ofEdgeId: "e3", in: level), .south)
        XCTAssertEqual(DeckEdgeNaming.side(ofEdgeId: "e4", in: level), .west)
    }

    func testAnEdgeWithNoResolvableGeometryHasNoSide() {
        var level = squareLevel()
        level.edges.append(DeckEdge(id: "orphan", startVertexId: "gone", endVertexId: "alsogone"))

        XCTAssertNil(DeckEdgeNaming.side(ofEdgeId: "orphan", in: level))
    }

    // MARK: - Display name

    func testAnUnlabelledEdgeIsNamedBySideAndLength() {
        var level = squareLevel()
        level.edges[0].dimension = 150  // 12' 6"

        XCTAssertEqual(
            DeckEdgeNaming.displayName(forEdgeId: "e1", in: level, system: .imperial),
            "North edge · 12' 6\""
        )
    }

    /// The operator's own name wins outright — that is the whole point of
    /// having labelled it.
    func testALabelledEdgeUsesTheOperatorsOwnName() {
        var level = squareLevel()
        level.edges[0].label = "Hot tub side"
        level.edges[0].dimension = 150

        XCTAssertEqual(
            DeckEdgeNaming.displayName(forEdgeId: "e1", in: level, system: .imperial),
            "Hot tub side"
        )
    }

    func testABlankLabelFallsBackToSideAndLength() {
        var level = squareLevel()
        level.edges[0].label = "   "
        level.edges[0].dimension = 150

        XCTAssertEqual(
            DeckEdgeNaming.displayName(forEdgeId: "e1", in: level, system: .imperial),
            "North edge · 12' 6\""
        )
    }

    func testAnEdgeWithNoDimensionIsNamedBySideAlone() {
        let level = squareLevel()

        XCTAssertEqual(
            DeckEdgeNaming.displayName(forEdgeId: "e2", in: level, system: .imperial),
            "East edge"
        )
    }

    /// Nothing to say about it — never invent a fake identifier.
    func testAnUnresolvableEdgeFallsBackToAPlainNoun() {
        var level = squareLevel()
        level.edges.append(DeckEdge(id: "orphan", startVertexId: "gone", endVertexId: "alsogone"))

        XCTAssertEqual(
            DeckEdgeNaming.displayName(forEdgeId: "orphan", in: level, system: .imperial),
            "Edge"
        )
    }

    /// A metric drawing reads its own units. `dimension` is stored in inches
    /// on both systems, so 150" comes back as 3.81 m.
    func testLengthFollowsTheDrawingsMeasurementSystem() {
        var level = squareLevel()
        level.edges[0].dimension = 150

        XCTAssertEqual(
            DeckEdgeNaming.displayName(forEdgeId: "e1", in: level, system: .metric),
            "North edge · 3.81 m"
        )
    }
}
