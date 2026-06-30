import CoreGraphics
import XCTest
@testable import DeckKit

final class WallOpeningGeometryTests: XCTestCase {
    func test_wallLength_usesEffectiveScaleFactor() throws {
        var data = rectangleData(widthPoints: 240, heightPoints: 120, scaleFactor: 2)
        let houseEdge = try XCTUnwrap(data.edges.first)

        XCTAssertEqual(
            WallOpeningGeometry.wallLengthInches(edge: houseEdge, in: data),
            120
        )

        data.edges[0].dimension = 96

        XCTAssertEqual(
            WallOpeningGeometry.wallLengthInches(edge: data.edges[0], in: data),
            96
        )
    }

    func test_validate_okWhenFits() {
        let opening = WallOpening(
            edgeId: "E1",
            kind: .patioDoor,
            widthInches: 36,
            heightInches: 80,
            sillHeightInches: 0,
            offsetAlongEdgeInches: 24
        )

        XCTAssertEqual(
            WallOpeningGeometry.validate(
                opening,
                wallLengthInches: 120,
                storyHeightInches: 96,
                existing: []
            ),
            .ok
        )
    }

    func test_validate_clampsWhenOffsetPushesPastWallEnd() {
        let opening = WallOpening(
            edgeId: "E1",
            widthInches: 48,
            heightInches: 80,
            offsetAlongEdgeInches: 90
        )

        XCTAssertEqual(
            WallOpeningGeometry.validate(
                opening,
                wallLengthInches: 120,
                storyHeightInches: 96,
                existing: []
            ),
            .clampedToWall(adjustedOffsetInches: 72)
        )
    }

    func test_validate_detectsOverlap() {
        let existing = WallOpening(
            id: "existing",
            edgeId: "E1",
            widthInches: 36,
            heightInches: 80,
            offsetAlongEdgeInches: 24
        )
        let opening = WallOpening(
            edgeId: "E1",
            widthInches: 30,
            heightInches: 80,
            offsetAlongEdgeInches: 50
        )

        XCTAssertEqual(
            WallOpeningGeometry.validate(
                opening,
                wallLengthInches: 120,
                storyHeightInches: 96,
                existing: [existing]
            ),
            .overlapsOpening(otherId: "existing")
        )
    }

    func test_validate_treatsTouchingEdgesAsNonOverlapping() {
        let existing = WallOpening(
            id: "existing",
            edgeId: "E1",
            widthInches: 36,
            heightInches: 80,
            offsetAlongEdgeInches: 24
        )
        let opening = WallOpening(
            edgeId: "E1",
            widthInches: 30,
            heightInches: 80,
            offsetAlongEdgeInches: 60
        )

        XCTAssertEqual(
            WallOpeningGeometry.validate(
                opening,
                wallLengthInches: 120,
                storyHeightInches: 96,
                existing: [existing]
            ),
            .ok
        )
    }

    func test_validate_flagsHeadExceedsStory() {
        let opening = WallOpening(
            edgeId: "E1",
            kind: .window,
            widthInches: 48,
            heightInches: 60,
            sillHeightInches: 40,
            offsetAlongEdgeInches: 24
        )

        XCTAssertEqual(
            WallOpeningGeometry.validate(
                opening,
                wallLengthInches: 120,
                storyHeightInches: 96,
                existing: []
            ),
            .headExceedsStory(headInches: 100, storyHeightInches: 96)
        )
    }

    func test_validate_zeroSize() {
        let opening = WallOpening(
            edgeId: "E1",
            widthInches: 0,
            heightInches: 80,
            offsetAlongEdgeInches: 24
        )

        XCTAssertEqual(
            WallOpeningGeometry.validate(
                opening,
                wallLengthInches: 120,
                storyHeightInches: 96,
                existing: []
            ),
            .zeroOrNegativeSize
        )
    }

    func test_clamped_pushesInboard() {
        let opening = WallOpening(
            edgeId: "E1",
            widthInches: 48,
            heightInches: 80,
            offsetAlongEdgeInches: 90
        )

        let clamped = WallOpeningGeometry.clamped(opening, wallLengthInches: 120)

        XCTAssertEqual(clamped.offsetAlongEdgeInches, 72)
        XCTAssertEqual(clamped.widthInches, 48)
        XCTAssertLessThanOrEqual(
            clamped.offsetAlongEdgeInches + clamped.widthInches,
            120
        )
    }

    func test_cutoutRect2D_doorSitsOnBase() {
        let opening = WallOpening(
            edgeId: "E1",
            kind: .patioDoor,
            widthInches: 72,
            heightInches: 80,
            sillHeightInches: 0,
            offsetAlongEdgeInches: 24
        )

        let rect = WallOpeningGeometry.cutoutRect2D(opening)

        XCTAssertEqual(rect.origin.y, 0)
        XCTAssertEqual(rect.height, 80)
    }

    func test_cutoutRect2D_windowFloatsAtSill() {
        let opening = WallOpening(
            edgeId: "E1",
            kind: .window,
            widthInches: 48,
            heightInches: 48,
            sillHeightInches: 30,
            offsetAlongEdgeInches: 24
        )

        let rect = WallOpeningGeometry.cutoutRect2D(opening)

        XCTAssertEqual(rect.origin.x, 24)
        XCTAssertEqual(rect.origin.y, 30)
        XCTAssertEqual(rect.height, 48)
    }

    func test_cutoutProfile3D_nilForZeroSize() {
        let opening = WallOpening(
            edgeId: "E1",
            widthInches: 0,
            heightInches: 80,
            offsetAlongEdgeInches: 24
        )

        XCTAssertNil(WallOpeningGeometry.cutoutProfile3D(opening, storyHeightInches: 96))
    }

    private func rectangleData(widthPoints: Double, heightPoints: Double, scaleFactor: Double) -> DeckDrawingData {
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: widthPoints, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: widthPoints, y: heightPoints))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: heightPoints))
        var e1 = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", edgeType: .houseEdge)
        e1.dimension = nil
        let e2 = DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3")
        let e3 = DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4")
        let e4 = DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        var data = DeckDrawingData()
        data.vertices = [v1, v2, v3, v4]
        data.edges = [e1, e2, e3, e4]
        data.scaleFactor = scaleFactor
        return data
    }
}
