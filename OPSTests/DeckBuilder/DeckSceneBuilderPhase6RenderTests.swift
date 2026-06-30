import CoreGraphics
import DeckKit
import SceneKit
import XCTest
@testable import OPS

final class DeckSceneBuilderPhase6RenderTests: XCTestCase {
    func testBuildSceneEmitsPatternSurfaceAndOverheadLayer() throws {
        let scene = DeckSceneBuilder.buildScene(from: Self.phase6Deck())

        let patternSurface = scene.rootNode.childNode(
            withName: "deck_pattern.surface.surface-main",
            recursively: true
        )
        let overheadLayer = scene.rootNode.childNode(
            withName: DeckSceneLayerToggle.overheadLayerNodeName,
            recursively: true
        )

        XCTAssertNotNil(patternSurface)
        XCTAssertEqual(patternSurface?.geometry?.name, "deck_pattern.diagonal")
        XCTAssertNotNil(overheadLayer)
        XCTAssertEqual(overheadLayer?.allNodes(namedPrefix: "overhead.member.joist.").count, 3)
    }

    private static func phase6Deck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.overallElevation = 3

        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 192, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 192, y: 144))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144))
        data.vertices = [v1, v2, v3, v4]

        var e1 = DeckEdge(id: "e1", startVertexId: v1.id, endVertexId: v2.id)
        e1.dimension = 192
        var e2 = DeckEdge(id: "e2", startVertexId: v2.id, endVertexId: v3.id)
        e2.dimension = 144
        var e3 = DeckEdge(id: "e3", startVertexId: v3.id, endVertexId: v4.id)
        e3.dimension = 192
        var e4 = DeckEdge(id: "e4", startVertexId: v4.id, endVertexId: v1.id)
        e4.dimension = 144
        data.edges = [e1, e2, e3, e4]

        data.surfaces = [
            DeckSurface(
                id: "surface-main",
                vertexIds: Set(data.vertices.map(\.id)),
                assignedItems: [],
                color: "Brown",
                boardMaterial: "composite"
            ),
        ]
        data.surfaceFeatures = SurfaceFeaturePlan(
            patterns: [
                SurfacePatternSpec(
                    surfaceId: "surface-main",
                    pattern: .diagonal,
                    boardAngleDegrees: 45,
                    pictureFrameCourses: 0
                ),
            ]
        )
        data.overhead = OverheadStructurePlan(
            structures: [
                OverheadStructure(
                    id: "pergola-1",
                    kind: .pergola,
                    footprint: data.vertices.map(\.position),
                    framing: (0..<3).map { index in
                        FramingMember(
                            id: "rafter-\(index)",
                            role: .joist,
                            start: CGPoint(x: 0, y: 24 + index * 36),
                            end: CGPoint(x: 192, y: 24 + index * 36),
                            nominalSize: .twoBySix,
                            plyCount: 1,
                            species: .douglasFirLarch,
                            grade: .no2
                        )
                    },
                    shadePercent: 45
                ),
            ]
        )
        return data
    }
}

private extension SCNNode {
    func allNodes(namedPrefix prefix: String) -> [SCNNode] {
        var matches: [SCNNode] = []
        if let name, name.hasPrefix(prefix) {
            matches.append(self)
        }
        for child in childNodes {
            matches.append(contentsOf: child.allNodes(namedPrefix: prefix))
        }
        return matches
    }
}
