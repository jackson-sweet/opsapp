import CoreGraphics
import DeckKit
import SceneKit
import UIKit
import XCTest
@testable import OPS

final class DeckSceneBuilderHouseWallOpeningTests: XCTestCase {
    func test_wallFacePathWithoutOpeningsHasOnlyOuterPath() {
        let path = DeckSceneBuilder.wallFacePath(
            wallLengthInches: 144,
            wallHeightInches: 96,
            openings: [],
            storyHeightInches: 96
        )

        XCTAssertTrue(path.usesEvenOddFillRule)
        XCTAssertEqual(path.cgPath.moveToSubpathCount, 1)
        XCTAssertEqual(path.cgPath.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 144, height: 96))
    }

    func test_wallFacePathWithOneOpeningHasOneHole() {
        let path = DeckSceneBuilder.wallFacePath(
            wallLengthInches: 144,
            wallHeightInches: 96,
            openings: [
                WallOpening(
                    id: "door",
                    edgeId: "e1",
                    kind: .patioDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
            ],
            storyHeightInches: 96
        )

        XCTAssertTrue(path.usesEvenOddFillRule)
        XCTAssertEqual(path.cgPath.moveToSubpathCount, 2)
    }

    func test_wallFacePathWithTwoOpeningsHasTwoHoles() {
        let path = DeckSceneBuilder.wallFacePath(
            wallLengthInches: 144,
            wallHeightInches: 96,
            openings: [
                WallOpening(
                    id: "door",
                    edgeId: "e1",
                    kind: .patioDoor,
                    widthInches: 48,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 12
                ),
                WallOpening(
                    id: "window",
                    edgeId: "e1",
                    kind: .window,
                    widthInches: 36,
                    heightInches: 42,
                    sillHeightInches: 30,
                    offsetAlongEdgeInches: 90
                ),
            ],
            storyHeightInches: 96
        )

        XCTAssertEqual(path.cgPath.moveToSubpathCount, 3)
    }

    func test_wallWithoutOpeningsUsesSpanningBoxFastPath() throws {
        var data = drawingData()
        data.house = HouseModel(floorLineFeet: 3, storyHeights: [8], openings: [])

        let wallNode = try houseWallNode(in: DeckSceneBuilder.buildScene(from: data))

        XCTAssertNotNil(wallNode.geometry as? SCNBox)
    }

    func test_wallWithOpeningUsesShapeWithHole() throws {
        var data = drawingData()
        data.house = HouseModel(
            floorLineFeet: 3,
            storyHeights: [8],
            openings: [
                WallOpening(
                    id: "door",
                    edgeId: "e1",
                    kind: .patioDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
            ]
        )

        let wallNode = try houseWallNode(in: DeckSceneBuilder.buildScene(from: data))
        let shape = try XCTUnwrap(wallNode.geometry as? SCNShape)
        let path = try XCTUnwrap(shape.path)

        XCTAssertEqual(path.cgPath.moveToSubpathCount, 2)
        XCTAssertEqual(shape.extrusionDepth, CGFloat(2.0 / 39.3701), accuracy: 0.0001)
    }

    @MainActor
    func test_fullTwoStorySceneBuildsHouseWallWithThreeOpeningHolesAndFallbackBeam() throws {
        let data = resolvedTwoStoryFreestandingData()

        let scene = DeckSceneBuilder.buildScene(from: data)
        let wallNode = try houseWallNode(in: scene)
        let shape = try XCTUnwrap(wallNode.geometry as? SCNShape)
        let path = try XCTUnwrap(shape.path)

        XCTAssertEqual(path.cgPath.moveToSubpathCount, 4)
        XCTAssertNotNil(
            scene.rootNode.childNode(
                withName: "framing.beam.ledger-fallback-beam-upper-house-edge",
                recursively: true
            )
        )
    }

    private func drawingData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = 3.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", edgeType: .houseEdge, houseEdgeMaterial: .stucco),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        return data
    }

    @MainActor
    private func resolvedTwoStoryFreestandingData() -> DeckDrawingData {
        let model = DeckDrawingEditorModel(
            drawingData: twoStoryHouseDrawingData(),
            capabilities: .full
        )

        guard case .freestanding? = model.resolveLedger(
            forEdge: "upper-house-edge",
            houseSideBeamSpanInches: 240
        ) else {
            XCTFail("Expected brick cladding to resolve as freestanding.")
            return model.drawingData
        }

        return model.drawingData
    }

    private func twoStoryHouseDrawingData() -> DeckDrawingData {
        var lower = DeckLevel(id: "lower-level", name: "Lower deck", displayColor: .green, sortOrder: 0)
        lower.elevation = 0
        lower.vertices = [
            DeckVertex(id: "lower-v1", position: CGPoint(x: 80, y: 220)),
            DeckVertex(id: "lower-v2", position: CGPoint(x: 260, y: 220)),
            DeckVertex(id: "lower-v3", position: CGPoint(x: 260, y: 340)),
            DeckVertex(id: "lower-v4", position: CGPoint(x: 80, y: 340)),
        ]
        lower.edges = [
            DeckEdge(id: "lower-back", startVertexId: "lower-v1", endVertexId: "lower-v2"),
            DeckEdge(id: "lower-side", startVertexId: "lower-v2", endVertexId: "lower-v3"),
            DeckEdge(id: "lower-front", startVertexId: "lower-v3", endVertexId: "lower-v4"),
            DeckEdge(id: "lower-return", startVertexId: "lower-v4", endVertexId: "lower-v1"),
        ]

        var upper = DeckLevel(id: "upper-level", name: "Upper deck", displayColor: .blue, sortOrder: 1)
        upper.elevation = 9
        upper.vertices = [
            DeckVertex(id: "upper-v1", position: CGPoint(x: 40, y: 20)),
            DeckVertex(id: "upper-v2", position: CGPoint(x: 280, y: 20)),
            DeckVertex(id: "upper-v3", position: CGPoint(x: 280, y: 164)),
            DeckVertex(id: "upper-v4", position: CGPoint(x: 40, y: 164)),
        ]
        upper.edges = [
            DeckEdge(
                id: "upper-house-edge",
                startVertexId: "upper-v1",
                endVertexId: "upper-v2",
                edgeType: .houseEdge,
                dimension: 240,
                label: "Kitchen wall",
                houseEdgeMaterial: .brick
            ),
            DeckEdge(id: "upper-side", startVertexId: "upper-v2", endVertexId: "upper-v3"),
            DeckEdge(id: "upper-front", startVertexId: "upper-v3", endVertexId: "upper-v4"),
            DeckEdge(id: "upper-return", startVertexId: "upper-v4", endVertexId: "upper-v1"),
        ]

        var data = DeckDrawingData()
        data.schemaVersion = 5
        data.scaleFactor = 1
        data.levels = [lower, upper]
        data.house = HouseModel(
            floorLineFeet: 9,
            storyHeights: [9, 8],
            openings: [
                WallOpening(
                    id: "patio-door",
                    edgeId: "upper-house-edge",
                    kind: .patioDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
                WallOpening(
                    id: "kitchen-window",
                    edgeId: "upper-house-edge",
                    kind: .window,
                    widthInches: 42,
                    heightInches: 48,
                    sillHeightInches: 36,
                    offsetAlongEdgeInches: 132
                ),
                WallOpening(
                    id: "living-window",
                    edgeId: "upper-house-edge",
                    kind: .window,
                    widthInches: 36,
                    heightInches: 36,
                    sillHeightInches: 42,
                    offsetAlongEdgeInches: 184
                ),
            ]
        )
        return data
    }

    private func houseWallNode(in scene: SCNScene) throws -> SCNNode {
        try XCTUnwrap(scene.rootNode.childNode(withName: "houseWall", recursively: true))
    }
}

private extension CGPath {
    var moveToSubpathCount: Int {
        var count = 0
        applyWithBlock { elementPointer in
            if elementPointer.pointee.type == .moveToPoint {
                count += 1
            }
        }
        return count
    }
}
