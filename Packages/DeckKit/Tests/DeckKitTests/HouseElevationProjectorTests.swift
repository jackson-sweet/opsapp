import CoreGraphics
import XCTest
@testable import DeckKit

final class HouseElevationProjectorTests: XCTestCase {
    func test_project_returnsNilForNonHouseEdge() {
        let data = drawingData(edgeType: .deckEdge)

        XCTAssertNil(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )
    }

    func test_deckSurfaceY_fromFloorLine() throws {
        var data = drawingData(floorLineFeet: 9, overallElevation: 8)

        let elevation = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )

        XCTAssertEqual(elevation.deckSurfaceYInches, 108)

        data.house?.floorLineFeet = nil

        let fallback = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )

        XCTAssertEqual(fallback.deckSurfaceYInches, 96)
    }

    func test_deckSurfaceY_prefersSelectedLevelBeforeOverallElevation() throws {
        var level = deckLevel(edgeType: .houseEdge)
        level.elevation = 7
        var data = DeckDrawingData()
        data.levels = [level]
        data.overallElevation = 4
        data.house = HouseModel(floorLineFeet: nil, storyHeights: [9])

        let elevation = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: level.id,
                data: data
            )
        )

        XCTAssertEqual(elevation.deckSurfaceYInches, 84)
    }

    func test_wallTopY_usesGoverningStoryHeight() throws {
        let data = drawingData(floorLineFeet: 9, storyHeights: [9, 8])

        let elevation = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )

        XCTAssertEqual(elevation.wallTopYInches, 216)
    }

    func test_projectedOpeningRect_offsetsAboveGrade() throws {
        let opening = WallOpening(
            id: "W1",
            edgeId: "e1",
            kind: .window,
            widthInches: 48,
            heightInches: 48,
            sillHeightInches: 30,
            offsetAlongEdgeInches: 24
        )
        let data = drawingData(floorLineFeet: 9, openings: [opening])

        let elevation = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )
        let projected = try XCTUnwrap(elevation.openings.first)

        XCTAssertEqual(projected.rect.origin.x, 24)
        XCTAssertEqual(projected.rect.origin.y, 138)
        XCTAssertEqual(projected.rect.height, 48)
    }

    func test_doorRect_sitsOnDeckSurface() throws {
        let opening = WallOpening(
            id: "D1",
            edgeId: "e1",
            kind: .patioDoor,
            widthInches: 72,
            heightInches: 80,
            sillHeightInches: 0,
            offsetAlongEdgeInches: 36
        )
        let data = drawingData(floorLineFeet: 9, openings: [opening])

        let elevation = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )
        let projected = try XCTUnwrap(elevation.openings.first)

        XCTAssertEqual(projected.rect.origin.y, elevation.deckSurfaceYInches)
        XCTAssertEqual(projected.rect.height, 80)
    }

    func test_storyLines_forMultistory() throws {
        let data = drawingData(floorLineFeet: 9, storyHeights: [9, 8])

        let elevation = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )

        XCTAssertEqual(elevation.storyLines, [108, 216])
    }

    func test_calloutTags_areDeterministicDoorWindowSequences() throws {
        let openings = [
            WallOpening(
                id: "window-first-on-wall",
                edgeId: "e1",
                kind: .window,
                widthInches: 48,
                heightInches: 42,
                sillHeightInches: 30,
                offsetAlongEdgeInches: 96
            ),
            WallOpening(
                id: "door",
                edgeId: "e1",
                kind: .sliderDoor,
                widthInches: 72,
                heightInches: 80,
                sillHeightInches: 0,
                offsetAlongEdgeInches: 12
            ),
            WallOpening(
                id: "window-second-on-wall",
                edgeId: "e1",
                kind: .window,
                widthInches: 36,
                heightInches: 42,
                sillHeightInches: 30,
                offsetAlongEdgeInches: 132
            ),
        ]
        let data = drawingData(floorLineFeet: 9, openings: openings)

        let elevation = try XCTUnwrap(
            HouseElevationProjector.project(
                edgeId: "e1",
                levelId: nil,
                data: data
            )
        )

        XCTAssertEqual(elevation.openings.map(\.id), [
            "door",
            "window-first-on-wall",
            "window-second-on-wall",
        ])
        XCTAssertEqual(elevation.openings.map(\.calloutTag), ["D1", "W1", "W2"])
    }

    func test_projectAllFaces_returnsEveryHouseEdge() {
        var data = drawingData(edgeId: "house-1")
        data.edges.append(
            DeckEdge(
                id: "deck-edge",
                startVertexId: "v2",
                endVertexId: "v3",
                edgeType: .deckEdge,
                dimension: 96
            )
        )
        data.edges.append(
            DeckEdge(
                id: "house-2",
                startVertexId: "v3",
                endVertexId: "v4",
                edgeType: .houseEdge,
                dimension: 96
            )
        )

        let faces = HouseElevationProjector.projectAllFaces(data)

        XCTAssertEqual(faces.map(\.edgeId), ["house-1", "house-2"])
    }

    private func drawingData(
        edgeId: String = "e1",
        edgeType: EdgeType = .houseEdge,
        floorLineFeet: Double? = nil,
        storyHeights: [Double] = [9],
        openings: [WallOpening] = [],
        overallElevation: Double? = nil
    ) -> DeckDrawingData {
        var data = DeckDrawingData()
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 240, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 240, y: 120))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        data.vertices = [v1, v2, v3, v4]
        data.edges = [
            DeckEdge(
                id: edgeId,
                startVertexId: "v1",
                endVertexId: "v2",
                edgeType: edgeType,
                dimension: 120
            ),
        ]
        data.scaleFactor = 2
        data.overallElevation = overallElevation
        data.house = HouseModel(
            floorLineFeet: floorLineFeet,
            storyHeights: storyHeights,
            openings: openings
        )
        return data
    }

    private func deckLevel(edgeType: EdgeType) -> DeckLevel {
        var level = DeckLevel(id: "level-1", name: "Upper")
        level.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 240, y: 0)),
        ]
        level.edges = [
            DeckEdge(
                id: "e1",
                startVertexId: "v1",
                endVertexId: "v2",
                edgeType: edgeType,
                dimension: 120
            ),
        ]
        return level
    }
}
