import CoreGraphics
import DeckKit
import UIKit
import XCTest
@testable import OPS

final class DeckRendererOpeningOverlayTests: XCTestCase {
    func testPlanRendererAttachesHouseOpeningOverlaySnapshot() throws {
        let data = Self.houseOpeningDrawing()
        let anchors = DeckPlanOpeningOverlay.openingGlyphAnchors(
            data: data,
            transform: .identity
        )

        XCTAssertEqual(anchors.map(\.tag), ["D1", "W1"])

        let image = try XCTUnwrap(
            DeckRenderer.renderToPNG(
                drawingData: data,
                size: CGSize(width: 420, height: 320)
            )
        )
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)

        let attachment = XCTAttachment(image: image)
        attachment.name = "plan-view-house-opening-overlay"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func houseOpeningDrawing() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 180, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 180, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        data.edges = [
            DeckEdge(
                id: "house-edge",
                startVertexId: "v1",
                endVertexId: "v2",
                edgeType: .houseEdge,
                dimension: 180,
                houseEdgeMaterial: .stucco
            ),
            DeckEdge(id: "right", startVertexId: "v2", endVertexId: "v3", dimension: 120),
            DeckEdge(id: "front", startVertexId: "v3", endVertexId: "v4", dimension: 180),
            DeckEdge(id: "left", startVertexId: "v4", endVertexId: "v1", dimension: 120),
        ]
        data.footprint = DeckFootprint(isClosed: true)
        data.house = HouseModel(
            floorLineFeet: 9,
            storyHeights: [9],
            openings: [
                WallOpening(
                    id: "door",
                    edgeId: "house-edge",
                    kind: .patioDoor,
                    widthInches: 60,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
                WallOpening(
                    id: "window",
                    edgeId: "house-edge",
                    kind: .window,
                    widthInches: 42,
                    heightInches: 36,
                    sillHeightInches: 36,
                    offsetAlongEdgeInches: 114
                ),
            ]
        )
        return data
    }
}
