import CoreGraphics
import XCTest
@testable import DeckKit

final class DeckPlanOpeningOverlayTests: XCTestCase {
    func test_planOverlayPlacesGlyphAtOpeningCenterOffset() throws {
        let transform = CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: 20)
        let anchors = DeckPlanOpeningOverlay.openingGlyphAnchors(
            data: houseEdgeDrawing(openings: [
                WallOpening(
                    id: "door-1",
                    edgeId: "house-edge",
                    kind: .patioDoor,
                    widthInches: 20,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 30
                ),
            ]),
            transform: transform
        )

        let anchor = try XCTUnwrap(anchors.first)
        XCTAssertEqual(anchor.id, "door-1")
        XCTAssertEqual(anchor.tag, "D1")
        XCTAssertEqual(anchor.kind, .patioDoor)
        XCTAssertEqual(anchor.point.x, 90, accuracy: 0.001)
        XCTAssertEqual(anchor.point.y, 20, accuracy: 0.001)
        XCTAssertEqual(anchor.openingWidthPoints, 40, accuracy: 0.001)
        XCTAssertEqual(anchor.tangent.dx, 1, accuracy: 0.001)
        XCTAssertEqual(anchor.tangent.dy, 0, accuracy: 0.001)
    }

    func test_noOpeningsNoOverlayAnchors() {
        XCTAssertEqual(
            DeckPlanOpeningOverlay.openingGlyphAnchors(
                data: houseEdgeDrawing(openings: []),
                transform: .identity
            ),
            []
        )

        var nilHouseDrawing = houseEdgeDrawing(openings: [])
        nilHouseDrawing.house = nil

        XCTAssertEqual(
            DeckPlanOpeningOverlay.openingGlyphAnchors(
                data: nilHouseDrawing,
                transform: .identity
            ),
            []
        )
    }

    func test_ignoresMissingOrNonHouseOpeningEdges() {
        var data = houseEdgeDrawing(openings: [
            WallOpening(
                id: "missing",
                edgeId: "missing-edge",
                kind: .window,
                widthInches: 30,
                heightInches: 36,
                sillHeightInches: 30,
                offsetAlongEdgeInches: 12
            ),
            WallOpening(
                id: "deck-edge-window",
                edgeId: "deck-edge",
                kind: .window,
                widthInches: 30,
                heightInches: 36,
                sillHeightInches: 30,
                offsetAlongEdgeInches: 12
            ),
        ])
        data.edges.append(
            DeckEdge(
                id: "deck-edge",
                startVertexId: "v2",
                endVertexId: "v3",
                edgeType: .deckEdge,
                dimension: 100
            )
        )

        XCTAssertEqual(
            DeckPlanOpeningOverlay.openingGlyphAnchors(data: data, transform: .identity),
            []
        )
    }

    private func houseEdgeDrawing(openings: [WallOpening]) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
        ]
        data.edges = [
            DeckEdge(
                id: "house-edge",
                startVertexId: "v1",
                endVertexId: "v2",
                edgeType: .houseEdge,
                dimension: 100,
                houseEdgeMaterial: .stucco
            ),
        ]
        data.house = HouseModel(openings: openings)
        return data
    }
}
