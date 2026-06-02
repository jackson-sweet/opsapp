//
//  DeckSceneSnapshotTests.swift
//  OPSTests
//
//  Offscreen render harness for the 3D deck scene. NOT a pass/fail test —
//  it renders DeckSceneBuilder's SCNScene to PNG attachments from the app's
//  camera presets so the 3D output can be eyeballed and dialed in headlessly.
//  Run, then export attachments from the .xcresult.
//

import SceneKit
import UIKit
import XCTest
@testable import OPS

final class DeckSceneSnapshotTests: XCTestCase {

    // MARK: - Render + attach

    private func render(_ data: DeckDrawingData, preset: CameraPreset, name: String) {
        renderView(data, azimuthDeg: preset.azimuth, elevationDeg: preset.elevation, name: name)
    }

    /// Render from an arbitrary orbit angle. `distanceScale` < 1 zooms in;
    /// `focus` (a fraction 0...1 within the deck's bounding box per axis)
    /// re-aims the camera for close-ups (e.g. the stairs at the front edge).
    private func renderView(
        _ data: DeckDrawingData,
        azimuthDeg: Float,
        elevationDeg: Float,
        name: String,
        distanceScale: Float = 1.0,
        focus: SCNVector3? = nil,
        size: CGSize = CGSize(width: 1200, height: 850)
    ) {
        let scene = DeckSceneBuilder.buildScene(from: data)
        scene.background.contents = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)

        // Frame the DECK (exclude the ground plane — it dwarfs the bounding box).
        let ground = scene.rootNode.childNode(withName: "groundPlane", recursively: false)
        ground?.removeFromParentNode()
        let (minB, maxB) = scene.rootNode.boundingBox
        if let ground { scene.rootNode.addChildNode(ground) }

        let cx = (minB.x + maxB.x) / 2
        let cy = (minB.y + maxB.y) / 2
        let cz = (minB.z + maxB.z) / 2
        let spanX = maxB.x - minB.x
        let spanZ = maxB.z - minB.z
        let maxSpan = max(spanX, spanZ) * 1.2
        let distance = max(maxSpan * 2.0, 3.0) * distanceScale

        let look: SCNVector3
        if let f = focus {
            look = SCNVector3(minB.x + (maxB.x - minB.x) * f.x,
                              minB.y + (maxB.y - minB.y) * f.y,
                              minB.z + (maxB.z - minB.z) * f.z)
        } else {
            look = SCNVector3(cx, cy, cz)
        }

        let az = azimuthDeg * .pi / 180
        let el = elevationDeg * .pi / 180
        let camPos = SCNVector3(
            look.x + distance * cos(el) * sin(az),
            look.y + distance * sin(el),
            look.z + distance * cos(el) * cos(az)
        )

        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.zNear = 0.01
        cam.zFar = 2000
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = camPos
        camNode.look(at: look)
        scene.rootNode.addChildNode(camNode)

        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("no Metal device")
            return
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camNode
        renderer.autoenablesDefaultLighting = false  // match the app — rely on scene lights

        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - The render pass

    func testRenderDeckScenes() {
        let single = Self.singleLevelDeck()
        render(single, preset: .perspective, name: "01-single-perspective")
        render(single, preset: .side, name: "02-single-side")
        render(single, preset: .front, name: "03-single-front")
        render(single, preset: .birdsEye, name: "04-single-birdseye")
        // Low side-elevation profile — shows railing height + any understructure.
        renderView(single, azimuthDeg: 270, elevationDeg: 4, name: "07-single-profile", distanceScale: 0.95)
        // Stair close-ups (front edge of the deck, low angle, zoomed).
        renderView(single, azimuthDeg: 200, elevationDeg: 12, name: "08-stairs-near", distanceScale: 0.45, focus: SCNVector3(0.4, 0.1, 0.0))
        renderView(single, azimuthDeg: 200, elevationDeg: 12, name: "09-stairs-near-flip", distanceScale: 0.45, focus: SCNVector3(0.4, 0.1, 1.0))
        // Stair SIDE elevation — look along the stair width so the cut-stringer
        // sawtooth profile faces the camera.
        renderView(single, azimuthDeg: 90, elevationDeg: 4, name: "10-stairs-sawtooth", distanceScale: 0.5, focus: SCNVector3(0.5, 0.2, 0.0))
        renderView(single, azimuthDeg: 270, elevationDeg: 4, name: "11-stairs-sawtooth2", distanceScale: 0.5, focus: SCNVector3(0.5, 0.2, 0.0))

        let multi = Self.multiLevelDeck()
        render(multi, preset: .perspective, name: "05-multi-perspective")
        render(multi, preset: .side, name: "06-multi-side")
    }

    // MARK: - Representative decks

    /// 20' x 14' deck, 3' off grade. House edge (Hardie) at the back, glass rail
    /// right, wood rail left, a 4' stair with a glass handrail off the front.
    static func singleLevelDeck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0           // 1 canvas unit = 1 inch
        data.overallElevation = 3.0      // feet off grade

        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 240, y: 168)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 168)),
        ]

        // Front edge: stairs (with handrail).
        var front = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        front.dimension = 240
        front.stairConfig = StairConfig(
            width: 48,
            railingConfig: RailingConfig(railingType: .glass, maxPostSpacing: 48),
            totalRiseInches: 36
        )

        // Right edge: glass railing.
        var right = DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3")
        right.dimension = 168
        right.railingConfig = RailingConfig(railingType: .glass, maxPostSpacing: 48)

        // Back edge: house edge (cladding).
        var back = DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4")
        back.dimension = 240
        back.edgeType = .houseEdge
        back.houseEdgeMaterial = .hardie

        // Left edge: wood railing.
        var left = DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        left.dimension = 168
        left.railingConfig = RailingConfig(railingType: .wood, maxPostSpacing: 72)

        data.edges = [front, right, back, left]
        return data
    }

    /// Two stacked levels (lower 2', upper 5') with a connecting stair.
    static func multiLevelDeck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0

        var lower = DeckLevel(name: "Lower")
        lower.elevation = 2.0
        lower.vertices = [
            DeckVertex(id: "l1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "l2", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "l3", position: CGPoint(x: 240, y: 180)),
            DeckVertex(id: "l4", position: CGPoint(x: 0, y: 180)),
        ]
        lower.edges = [
            edge("le1", "l1", "l2", dim: 240),
            edge("le2", "l2", "l3", dim: 180, rail: .glass),
            edge("le3", "l3", "l4", dim: 240, rail: .glass),
            edge("le4", "l4", "l1", dim: 180, rail: .glass),
        ]

        var upper = DeckLevel(name: "Upper")
        upper.elevation = 5.0
        upper.vertices = [
            DeckVertex(id: "u1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "u2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "u3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "u4", position: CGPoint(x: 0, y: 120)),
        ]
        upper.edges = [
            edge("ue1", "u1", "u2", dim: 120),
            edge("ue2", "u2", "u3", dim: 120, rail: .glass),
            edge("ue3", "u3", "u4", dim: 120, rail: .glass),
            edge("ue4", "u4", "u1", dim: 120, rail: .glass),
        ]

        data.levels = [lower, upper]
        data.levelConnections = [
            LevelConnection(
                upperLevelId: upper.id,
                lowerLevelId: lower.id,
                upperEdgeId: "ue1",
                stairConfig: StairConfig(width: 48, railingConfig: RailingConfig(railingType: .glass, maxPostSpacing: 48))
            )
        ]
        return data
    }

    private static func edge(_ id: String, _ s: String, _ e: String, dim: Double, rail: RailingType? = nil) -> DeckEdge {
        var edge = DeckEdge(id: id, startVertexId: s, endVertexId: e)
        edge.dimension = dim
        if let rail { edge.railingConfig = RailingConfig(railingType: rail, maxPostSpacing: 48) }
        return edge
    }
}
