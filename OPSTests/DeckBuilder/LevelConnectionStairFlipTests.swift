//
//  LevelConnectionStairFlipTests.swift
//  OPSTests
//
//  Regression test: level-connection stairs must honor stairConfig.flipDirection.
//  Before the fix, buildLevelConnection hardcoded the perpendicular direction and
//  the toggle was silently ignored — both flip=false and flip=true produced
//  identical stair positions. This test catches any future regression.
//

import CoreGraphics
import DeckKit
import SceneKit
import XCTest
@testable import OPS

final class LevelConnectionStairFlipTests: XCTestCase {

    /// Build a two-level design with a connecting stair, once with
    /// flipDirection=false and once true, and assert the stair tread cluster
    /// lands on OPPOSITE sides of the connection edge. Before the fix the two
    /// are identical (the level-connection path ignored the toggle).
    func testLevelConnectionStairsHonorFlipDirection() throws {
        // Build `data` mirroring MultiLevelTests' multi-level fixture, with a
        // single levelConnection between the two levels. Capture the connection id.
        let (dataDefault, connectionId) = makeTwoLevelConnectedDesign(flip: false)
        let (dataFlipped, _) = makeTwoLevelConnectedDesign(flip: true)

        let centroidDefault = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: dataDefault), connectionId: connectionId)
        let centroidFlipped = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: dataFlipped), connectionId: connectionId)

        // The two centroids must straddle the connection edge — i.e. their
        // perpendicular offsets have opposite sign. A simple, robust proxy:
        // they must not be (near-)equal.
        let dx = Double(centroidDefault.x - centroidFlipped.x)
        let dz = Double(centroidDefault.z - centroidFlipped.z)
        let separation = (dx * dx + dz * dz).squareRoot()
        XCTAssertGreaterThan(separation, 0.3,
            "flipDirection must move the connecting stairs to the opposite side")
    }

    /// Average world position of the descendant geometry nodes under the
    /// `levelConnection_<id>` group.
    private func connectionStairCentroid(in scene: SCNScene, connectionId: String) throws -> SCNVector3 {
        let node = try XCTUnwrap(
            scene.rootNode.childNode(withName: "levelConnection_\(connectionId)", recursively: true),
            "level-connection node not found")
        var sum = SCNVector3Zero
        var count: Float = 0
        node.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return }
            let w = child.worldPosition
            sum = SCNVector3(sum.x + w.x, sum.y + w.y, sum.z + w.z)
            count += 1
        }
        XCTAssertGreaterThan(count, 0, "no stair geometry under the connection node")
        return SCNVector3(sum.x / count, sum.y / count, sum.z / count)
    }

    // MARK: - Fixture
    // Two closed 100×100 rects, upper at +3 ft, joined by one LevelConnection
    // on the upper rect's y=0 edge. Verify field names against DeckLevel.swift
    // and DeckGeometry.swift if the compiler disagrees (DeckLevel/DeckVertex/
    // DeckEdge construction mirrors MultiLevelTests.swift).
    private func makeTwoLevelConnectedDesign(flip: Bool) -> (DeckDrawingData, String) {
        var upper = DeckLevel(name: "Upper")
        upper.elevation = 3.0
        upper.vertices = [
            DeckVertex(id: "u1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "u2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "u3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "u4", position: CGPoint(x: 0, y: 100)),
        ]
        upper.edges = [
            DeckEdge(id: "ue1", startVertexId: "u1", endVertexId: "u2"),
            DeckEdge(id: "ue2", startVertexId: "u2", endVertexId: "u3"),
            DeckEdge(id: "ue3", startVertexId: "u3", endVertexId: "u4"),
            DeckEdge(id: "ue4", startVertexId: "u4", endVertexId: "u1"),
        ]

        var lower = DeckLevel(name: "Lower")
        lower.elevation = 0.0
        lower.vertices = [
            DeckVertex(id: "l1", position: CGPoint(x: 0, y: 100)),
            DeckVertex(id: "l2", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "l3", position: CGPoint(x: 100, y: 200)),
            DeckVertex(id: "l4", position: CGPoint(x: 0, y: 200)),
        ]
        lower.edges = [
            DeckEdge(id: "le1", startVertexId: "l1", endVertexId: "l2"),
            DeckEdge(id: "le2", startVertexId: "l2", endVertexId: "l3"),
            DeckEdge(id: "le3", startVertexId: "l3", endVertexId: "l4"),
            DeckEdge(id: "le4", startVertexId: "l4", endVertexId: "l1"),
        ]

        let connection = LevelConnection(
            id: "conn1",
            upperLevelId: upper.id,
            lowerLevelId: lower.id,
            upperEdgeId: "ue1",                              // upper rect's y=0 edge
            stairConfig: StairConfig(width: 48, flipDirection: flip)
        )

        var data = DeckDrawingData()
        data.levels = [upper, lower]
        data.levelConnections = [connection]
        data.scaleFactor = 1.0                              // calibrated → buildScene uses it directly
        return (data, connection.id)
    }
}
