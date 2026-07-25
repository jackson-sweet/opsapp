import CoreGraphics
import XCTest
@testable import OPS

final class DeckViewerSurfaceLabelResolverTests: XCTestCase {

    func testFullscreenUnnamedDisconnectedSurfacesReceiveDeterministicFallbackLabels() {
        let original = disconnectedRectangles()
        let originalLabels = labelsBySurfaceID(in: original)

        XCTAssertEqual(
            original.detectedSurfaces.enumerated().compactMap { index, surface in
                originalLabels[surface.id]
            },
            ["Surface 1", "Surface 2"]
        )

        var reordered = original
        reordered.vertices.reverse()
        reordered.edges.reverse()

        XCTAssertEqual(labelsBySurfaceID(in: reordered), originalLabels)
    }

    func testDisplayLabelUsesExplicitThenMaterialThenExpandedFallback() {
        let material = AssignedItem(
            name: "  Vinyl Membrane  ",
            unitType: .squareFoot
        )

        XCTAssertEqual(
            DeckViewerSurfaceLabelResolver.resolve(
                userLabel: "  Upper Landing  ",
                assignedItems: [material],
                fallbackOrdinal: 1
            ),
            "Upper Landing"
        )
        XCTAssertEqual(
            DeckViewerSurfaceLabelResolver.resolve(
                userLabel: " \n ",
                assignedItems: [material],
                fallbackOrdinal: 1
            ),
            "Vinyl Membrane"
        )
        XCTAssertEqual(
            DeckViewerSurfaceLabelResolver.resolve(
                userLabel: nil,
                assignedItems: [],
                fallbackOrdinal: 1
            ),
            "Surface 1"
        )
        XCTAssertNil(
            DeckViewerSurfaceLabelResolver.resolve(
                userLabel: nil,
                assignedItems: [],
                fallbackOrdinal: nil
            )
        )
    }

    private func labelsBySurfaceID(in data: DeckDrawingData) -> [String: String] {
        Dictionary(uniqueKeysWithValues: data.detectedSurfaces.enumerated().compactMap { index, surface in
            DeckViewerSurfaceLabelResolver.resolve(
                userLabel: nil,
                assignedItems: [],
                fallbackOrdinal: index + 1
            ).map { (surface.id, $0) }
        })
    }

    private func disconnectedRectangles() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "a1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "a2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "a3", position: CGPoint(x: 120, y: 80)),
            DeckVertex(id: "a4", position: CGPoint(x: 0, y: 80)),
            DeckVertex(id: "b1", position: CGPoint(x: 180, y: 20)),
            DeckVertex(id: "b2", position: CGPoint(x: 300, y: 20)),
            DeckVertex(id: "b3", position: CGPoint(x: 300, y: 100)),
            DeckVertex(id: "b4", position: CGPoint(x: 180, y: 100))
        ]
        data.edges = [
            edge("a-e1", "a1", "a2"),
            edge("a-e2", "a2", "a3"),
            edge("a-e3", "a3", "a4"),
            edge("a-e4", "a4", "a1"),
            edge("b-e1", "b1", "b2"),
            edge("b-e2", "b2", "b3"),
            edge("b-e3", "b3", "b4"),
            edge("b-e4", "b4", "b1")
        ]
        return data
    }

    private func edge(_ id: String, _ start: String, _ end: String) -> DeckEdge {
        DeckEdge(id: id, startVertexId: start, endVertexId: end)
    }
}
