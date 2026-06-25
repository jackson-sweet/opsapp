//
//  DeckSurfaceEdgeResolverTests.swift
//  OPSTests
//
//  Regression coverage for ProjectDetails 3D edge planning.
//

import CoreGraphics
import DeckKit
import XCTest
@testable import OPS

final class DeckSurfaceEdgeResolverTests: XCTestCase {

    func testVisibleRimJoistEdgesExcludeSharedInteriorAndStrayEdges() {
        let edges = [
            DeckEdge(id: "ab", startVertexId: "a", endVertexId: "b"),
            DeckEdge(id: "bc", startVertexId: "b", endVertexId: "c"),
            DeckEdge(id: "cd", startVertexId: "c", endVertexId: "d"),
            DeckEdge(id: "da", startVertexId: "d", endVertexId: "a"),
            DeckEdge(id: "be", startVertexId: "b", endVertexId: "e"),
            DeckEdge(id: "ef", startVertexId: "e", endVertexId: "f"),
            DeckEdge(id: "fc", startVertexId: "f", endVertexId: "c"),
            DeckEdge(id: "xy", startVertexId: "x", endVertexId: "y")
        ]
        let surfaces = [
            DeckSceneBuilder.SurfaceMesh3D(
                positionsInMeters: [],
                vertexIds: ["a", "b", "c", "d"],
                assignedItems: [],
                color: "Brown",
                boardMaterial: "composite"
            ),
            DeckSceneBuilder.SurfaceMesh3D(
                positionsInMeters: [],
                vertexIds: ["b", "e", "f", "c"],
                assignedItems: [],
                color: "Brown",
                boardMaterial: "composite"
            )
        ]

        let visible = DeckSurfaceEdgeResolver.visibleRimJoistEdgeIds(
            edges: edges,
            surfaces: surfaces
        )

        XCTAssertEqual(visible, ["ab", "cd", "da", "be", "ef", "fc"])
        XCTAssertFalse(visible.contains("bc"))
        XCTAssertFalse(visible.contains("xy"))
    }
}
