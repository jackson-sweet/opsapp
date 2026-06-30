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
