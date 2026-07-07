// OPSTests/DeckBuilder/DeckMaterialsInputBuilderTests.swift
//
// Coverage for the read-only surface-input builder: persisted-surface label
// reuse, the empty-store detected-faces fallback, and edge-type carry-through.

import CoreGraphics
import XCTest
@testable import OPS

final class DeckMaterialsInputBuilderTests: XCTestCase {

    /// A 100×100 canvas square (scale 1pt = 1"), one closed detected face.
    private func closedSquare() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100))
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]
        return data
    }

    func testEmptyPersistedStoreFallsBackToDetectedFace() {
        let data = closedSquare()
        let result = DeckMaterialsInputBuilder.surfaceInputs(for: data, scale: 1.0)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.input.label, "Surface 1")
        XCTAssertEqual(result.first?.input.positions.count, 4)
        XCTAssertTrue(result.first?.assignedItems.isEmpty ?? false)
    }

    func testMatchedPersistedSurfaceUsesItsLabel() {
        var data = closedSquare()
        data.surfaces = [
            DeckSurface(id: "s1", vertexIds: Set(["v1", "v2", "v3", "v4"]), label: "BBQ AREA")
        ]
        let result = DeckMaterialsInputBuilder.surfaceInputs(for: data, scale: 1.0)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.input.label, "BBQ AREA")
    }

    func testMatchedPersistedSurfaceCarriesAssignedItems() {
        var data = closedSquare()
        let item = AssignedItem(name: "Vinyl Membrane", unitType: .squareFoot)
        data.surfaces = [
            DeckSurface(id: "s1", vertexIds: Set(["v1", "v2", "v3", "v4"]), assignedItems: [item])
        ]
        let result = DeckMaterialsInputBuilder.surfaceInputs(for: data, scale: 1.0)
        XCTAssertEqual(result.first?.assignedItems.count, 1)
        XCTAssertEqual(result.first?.assignedItems.first?.name, "Vinyl Membrane")
    }

    func testHouseEdgeTypeCarriedOntoSurfaceEdge() {
        var data = closedSquare()
        data.edges[2].edgeType = .houseEdge // e3 (v3–v4)
        let result = DeckMaterialsInputBuilder.surfaceInputs(for: data, scale: 1.0)
        let edges = result.first?.input.edges ?? []
        XCTAssertEqual(edges.filter { $0.edgeType == .houseEdge }.count, 1)
        XCTAssertEqual(edges.filter { $0.edgeType == .deckEdge }.count, 3)
    }
}
