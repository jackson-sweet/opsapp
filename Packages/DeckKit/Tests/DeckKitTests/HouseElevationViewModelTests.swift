import CoreGraphics
import XCTest
@testable import DeckKit

final class HouseElevationViewModelTests: XCTestCase {
    func test_elevationViewModel_listsOnlyHouseFacesAndUsesEdgeLabels() {
        let model = HouseElevationViewModel(data: drawingData())

        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.faces.map(\.edgeId), ["house-a", "house-b"])
        XCTAssertEqual(model.faces.map(\.label), ["KITCHEN WALL", "FACE 2"])
    }

    func test_elevationViewModel_emptyWhenNoHouseFaces() {
        var data = drawingData()
        data.edges = data.edges.filter { $0.edgeType != .houseEdge }

        let model = HouseElevationViewModel(data: data)

        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.emptyStateText, "—")
        XCTAssertEqual(model.faces, [])
    }

    private func drawingData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 240, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        data.edges = [
            DeckEdge(
                id: "house-a",
                startVertexId: "v1",
                endVertexId: "v2",
                edgeType: .houseEdge,
                dimension: 120,
                label: "Kitchen wall"
            ),
            DeckEdge(
                id: "deck-edge",
                startVertexId: "v2",
                endVertexId: "v3",
                edgeType: .deckEdge,
                dimension: 96
            ),
            DeckEdge(
                id: "house-b",
                startVertexId: "v3",
                endVertexId: "v4",
                edgeType: .houseEdge,
                dimension: 120
            ),
        ]
        data.scaleFactor = 2
        data.house = HouseModel(
            floorLineFeet: 9,
            storyHeights: [9],
            openings: [
                WallOpening(
                    id: "door",
                    edgeId: "house-a",
                    kind: .patioDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 12
                ),
            ]
        )
        return data
    }
}
