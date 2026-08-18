//
//  LevelConnectionStairFlipTests.swift
//  OPSTests
//
//  Bug 4a773e11 — what a level-connection stair's direction is allowed to
//  depend on, asserted against the built SceneKit graph.
//
//  This file used to assert the OPPOSITE contract: that `stairConfig
//  .flipDirection` moved a connecting stair to the other side of its host
//  edge. That contract is what broke the drawing. 2D resolved the side from
//  the upper deck's own face while 3D used the raw edge-winding perpendicular,
//  so operators reached for the flip toggle to correct whichever view they
//  were looking at — and thereby guaranteed the other view was wrong. On
//  "3998 Holland Ave" the stored flip is true precisely because 3D needed it.
//
//  A connection stair descends onto a deck the drawing already identifies.
//  Its direction is a fact, so the toggle no longer votes, and 2D and 3D
//  resolve the identical answer through DeckStairGeometryResolver.
//

import CoreGraphics
import SceneKit
import XCTest
@testable import OPS

final class LevelConnectionStairFlipTests: XCTestCase {

    /// The toggle must not be able to send a connecting stair away from the
    /// deck it connects to. Both builds land in the same place.
    func testLevelConnectionStairsIgnoreFlipDirection() throws {
        let (dataDefault, connectionId) = makeTwoLevelConnectedDesign(flip: false)
        let (dataFlipped, _) = makeTwoLevelConnectedDesign(flip: true)

        let centroidDefault = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: dataDefault), connectionId: connectionId)
        let centroidFlipped = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: dataFlipped), connectionId: connectionId)

        XCTAssertEqual(Double(centroidDefault.x), Double(centroidFlipped.x), accuracy: 1e-4)
        XCTAssertEqual(Double(centroidDefault.z), Double(centroidFlipped.z), accuracy: 1e-4)
    }

    /// The lower level sits at greater canvas y than the connection edge, so
    /// the stair descends toward greater z in the scene. Canvas y maps to
    /// scene z with no axis flip.
    func testLevelConnectionStairsDescendTowardTheLowerLevel() throws {
        let (data, connectionId) = makeTwoLevelConnectedDesign(flip: false)
        let scene = DeckSceneBuilder.buildScene(from: data)
        let centroid = try connectionStairCentroid(in: scene, connectionId: connectionId)

        // Host edge is the upper rect's y = 100 side; the lower rect spans
        // y 100…200. The stair body must sit on the lower rect's side of it.
        let edgeZ = try edgeZInScene(data: data, connectionId: connectionId)
        XCTAssertGreaterThan(Double(centroid.z), Double(edgeZ),
                             "the connecting stair must run onto the deck below, not back across the deck above")
    }

    /// Whichever way the operator happened to draw the host edge, the stair
    /// lands in the same place. The raw edge-winding perpendicular this path
    /// used to trust flips with the stored vertex order.
    func testLevelConnectionStairsIgnoreStoredEdgeWinding() throws {
        let (forwardData, connectionId) = makeTwoLevelConnectedDesign(flip: false)
        let (reversedData, _) = makeTwoLevelConnectedDesign(flip: false, reverseHostEdge: true)

        let forward = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: forwardData), connectionId: connectionId)
        let reversed = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: reversedData), connectionId: connectionId)

        XCTAssertEqual(Double(forward.x), Double(reversed.x), accuracy: 1e-4)
        XCTAssertEqual(Double(forward.z), Double(reversed.z), accuracy: 1e-4)
    }

    /// The whole point of the resolver: plan and scene agree. Resolve the same
    /// connection in canvas space and assert the scene put the stair on the
    /// matching side of the host edge.
    func testPlanAndSceneAgreeOnTheSide() throws {
        let (data, connectionId) = makeTwoLevelConnectedDesign(flip: true)
        let connection = try XCTUnwrap(data.levelConnections.first)
        let plan = try XCTUnwrap(data.connectionStairPlan(for: connection))

        // Canvas: travel must point at greater y (toward the lower rect).
        XCTAssertGreaterThan(plan.orientation.travel.dy, 0.9)

        // Scene: the stair body must sit at greater z than the host edge.
        let centroid = try connectionStairCentroid(
            in: DeckSceneBuilder.buildScene(from: data), connectionId: connectionId)
        let edgeZ = try edgeZInScene(data: data, connectionId: connectionId)
        XCTAssertGreaterThan(Double(centroid.z), Double(edgeZ))
    }

    // MARK: - Scene helpers

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

    /// Scene z of the host edge. Both endpoints share a canvas y here, so a
    /// single converted value describes the whole edge.
    private func edgeZInScene(data: DeckDrawingData, connectionId: String) throws -> Float {
        let connection = try XCTUnwrap(data.levelConnections.first { $0.id == connectionId })
        let upper = try XCTUnwrap(data.level(byId: connection.upperLevelId))
        let edge = try XCTUnwrap(upper.edge(byId: connection.upperEdgeId))
        let start = try XCTUnwrap(upper.vertex(byId: edge.startVertexId))
        let end = try XCTUnwrap(upper.vertex(byId: edge.endVertexId))
        XCTAssertEqual(start.position.y, end.position.y, accuracy: 1e-6)

        // Mirror DeckSceneBuilder's canvas → metres map for the y/z axis. The
        // scene centres on the bounding box of every level's vertices.
        let allPoints = data.levels.flatMap { $0.vertices.map(\.position) }
        let minY = try XCTUnwrap(allPoints.map(\.y).min())
        let maxY = try XCTUnwrap(allPoints.map(\.y).max())
        let centreY = (minY + maxY) / 2
        let metresPerPoint = 1.0 / data.effectiveScaleFactor / 39.3701
        return Float((Double(start.position.y) - Double(centreY)) * metresPerPoint)
    }

    // MARK: - Fixture

    /// Two closed 100×100 rects stacked in canvas y: the upper deck (+3 ft) at
    /// y 0…100 and the lower deck (0 ft) at y 100…200, joined by one
    /// LevelConnection riding the shared y = 100 boundary. That is the real
    /// shape of a connection — the stair leaves the upper deck and lands on the
    /// lower one.
    private func makeTwoLevelConnectedDesign(
        flip: Bool,
        reverseHostEdge: Bool = false
    ) -> (DeckDrawingData, String) {
        var upper = DeckLevel(name: "Upper")
        upper.elevation = 3.0
        upper.vertices = [
            DeckVertex(id: "u1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "u2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "u3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "u4", position: CGPoint(x: 0, y: 100)),
        ]
        let hostEdge = reverseHostEdge
            ? DeckEdge(id: "ue3", startVertexId: "u4", endVertexId: "u3")
            : DeckEdge(id: "ue3", startVertexId: "u3", endVertexId: "u4")
        upper.edges = [
            DeckEdge(id: "ue1", startVertexId: "u1", endVertexId: "u2"),
            DeckEdge(id: "ue2", startVertexId: "u2", endVertexId: "u3"),
            hostEdge,
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
            upperEdgeId: "ue3",                              // the shared y = 100 boundary
            stairConfig: StairConfig(width: 48, treadCount: 4, flipDirection: flip)
        )

        var data = DeckDrawingData()
        data.levels = [upper, lower]
        data.levelConnections = [connection]
        data.scaleFactor = 1.0                              // calibrated → buildScene uses it directly
        return (data, connection.id)
    }
}
