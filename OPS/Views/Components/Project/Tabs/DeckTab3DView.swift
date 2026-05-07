//
//  DeckTab3DView.swift
//  OPS
//
//  Read-only 3D SceneKit viewer for deck designs in project details.
//  Delegates scene construction to DeckSceneBuilder so the viewer renders
//  the same geometry as the editor — including stairs, house walls,
//  railings, and ALL levels (not just the first). Falls back to a
//  geometry-from-canvas-coordinates pass when the design has no
//  scaleFactor set (uncalibrated drawings); the calibrated path is the
//  expected one for any deck saved from the builder.
//

import SwiftUI
import SceneKit

struct DeckTab3DView: View {
    let drawingData: DeckDrawingData

    var body: some View {
        GeometryReader { geo in
            if geo.size.height > 0 {
                DeckTab3DSceneView(drawingData: drawingData)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - SceneKit UIViewRepresentable

private struct DeckTab3DSceneView: UIViewRepresentable {
    let drawingData: DeckDrawingData

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)
        scnView.preferredFramesPerSecond = 60

        let scene = buildScene()
        scnView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            scnView.pointOfView = cam
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Rebuild when the drawing changes so edits in the editor flow through
        // to the project tab without a full screen tear-down.
        let scene = buildScene()
        uiView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            uiView.pointOfView = cam
        }
    }

    /// Prefer the canonical builder when the design is calibrated. Falls back
    /// to a minimal canvas-space scene when no scaleFactor exists so the
    /// viewer still shows *something* for early-draft designs that haven't
    /// been calibrated yet.
    private func buildScene() -> SCNScene {
        if let scale = drawingData.scaleFactor, scale > 0 {
            return DeckSceneBuilder.buildScene(from: drawingData)
        }
        return buildFallbackScene()
    }

    // MARK: - Fallback Scene (no scaleFactor)

    /// Minimal SceneKit scene built from raw canvas coordinates. Used only
    /// when the design lacks a scaleFactor — DeckSceneBuilder requires real
    /// units, so this provides a usable preview for uncalibrated drawings.
    /// Renders surfaces + edges across ALL levels (not just the first).
    private func buildFallbackScene() -> SCNScene {
        let scene = SCNScene()

        // Aggregate positions across every level so the camera frames the
        // whole design — fixes the prior bug where only level 1 was visible.
        let allPositions: [CGPoint]
        if drawingData.isMultiLevel {
            allPositions = drawingData.levels.flatMap { $0.orderedPositions }
        } else {
            allPositions = drawingData.orderedPositions
        }
        guard allPositions.count >= 2 else { return scene }

        let xs = allPositions.map { Float($0.x) }
        let ys = allPositions.map { Float($0.y) }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let spanX = maxX - minX
        let spanY = maxY - minY
        let maxSpan = max(spanX, spanY)
        guard maxSpan > 0.1 else { return scene }

        let targetSize: Float = 5.0
        let scale = targetSize / maxSpan

        func toScene(_ p: CGPoint) -> (x: Float, z: Float) {
            let x = (Float(p.x) - centerX) * scale
            let z = (Float(p.y) - centerY) * scale
            return (x, z)
        }

        let deckHeight: Float = 0.5
        let postHeight: Float = 1.5

        // Render every level — surfaces + edges + posts. Without this loop,
        // multi-level designs only ever showed level 1 in the viewer.
        let levelsToRender: [(positions: [CGPoint], edges: [DeckEdge], vertices: [DeckVertex], isClosed: Bool, levelOffset: Float)]
        if drawingData.isMultiLevel {
            levelsToRender = drawingData.levels.enumerated().map { idx, level in
                // Stack additional levels visually — each level above 0 sits
                // a small offset higher so they're distinguishable.
                let stackOffset = Float(idx) * (deckHeight * 1.5)
                return (level.orderedPositions, level.edges, level.vertices, level.isClosed, stackOffset)
            }
        } else {
            levelsToRender = [(drawingData.orderedPositions, drawingData.edges, drawingData.vertices, drawingData.isClosed, 0)]
        }

        for level in levelsToRender {
            let levelDeckY = deckHeight + level.levelOffset
            renderFallbackLevel(
                positions: level.positions,
                edges: level.edges,
                vertices: level.vertices,
                isClosed: level.isClosed,
                levelDeckY: levelDeckY,
                postHeight: postHeight,
                toScene: toScene,
                scene: scene
            )
        }

        addGroundPlane(scene: scene, targetSize: targetSize)
        addLighting(scene: scene)
        addCamera(scene: scene, targetSize: targetSize, deckHeight: deckHeight)

        return scene
    }

    private func renderFallbackLevel(
        positions: [CGPoint],
        edges: [DeckEdge],
        vertices: [DeckVertex],
        isClosed: Bool,
        levelDeckY: Float,
        postHeight: Float,
        toScene: (CGPoint) -> (x: Float, z: Float),
        scene: SCNScene
    ) {
        let beamHeight: Float = 0.08
        let beamWidth: Float = 0.06

        // Surface
        if isClosed, positions.count >= 3 {
            let scenePoints = positions.map { p -> CGPoint in
                let s = toScene(p)
                return CGPoint(x: CGFloat(s.x), y: CGFloat(s.z))
            }
            if let surfaceGeo = DeckMeshGenerator.createPolygonGeometry(vertices: scenePoints, yHeight: levelDeckY) {
                let surfaceMat = SCNMaterial()
                surfaceMat.diffuse.contents = UIColor(red: 196/255, green: 149/255, blue: 106/255, alpha: 1)
                surfaceMat.isDoubleSided = true
                surfaceGeo.materials = [surfaceMat]
                scene.rootNode.addChildNode(SCNNode(geometry: surfaceGeo))
            }
            if let undersideGeo = DeckMeshGenerator.createPolygonGeometry(vertices: scenePoints, yHeight: levelDeckY - 0.05) {
                let underMat = SCNMaterial()
                underMat.diffuse.contents = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1)
                underMat.isDoubleSided = true
                undersideGeo.materials = [underMat]
                scene.rootNode.addChildNode(SCNNode(geometry: undersideGeo))
            }
        }

        // Edge beams
        for edge in edges {
            guard let startVert = vertices.first(where: { $0.id == edge.startVertexId }),
                  let endVert = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }

            let s = toScene(startVert.position)
            let e = toScene(endVert.position)
            let dx = e.x - s.x
            let dz = e.z - s.z
            let length = sqrt(dx * dx + dz * dz)
            guard length > 0.01 else { continue }

            let midX = (s.x + e.x) / 2
            let midZ = (s.z + e.z) / 2
            let angle = atan2(dx, dz)

            let beamGeo = SCNBox(width: CGFloat(beamWidth), height: CGFloat(beamHeight), length: CGFloat(length), chamferRadius: 0)
            let beamMat = SCNMaterial()
            beamMat.diffuse.contents = edge.edgeType == .houseEdge
                ? UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 0.8)
                : UIColor(red: 170/255, green: 130/255, blue: 90/255, alpha: 1)
            beamGeo.materials = [beamMat]
            let beamNode = SCNNode(geometry: beamGeo)
            beamNode.position = SCNVector3(midX, levelDeckY + beamHeight / 2, midZ)
            beamNode.eulerAngles.y = -angle
            scene.rootNode.addChildNode(beamNode)
        }

        // Posts at every vertex
        for vertex in vertices {
            let s = toScene(vertex.position)
            let postGeo = SCNBox(width: 0.1, height: CGFloat(postHeight), length: 0.1, chamferRadius: 0)
            let postMat = SCNMaterial()
            postMat.diffuse.contents = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1)
            postGeo.materials = [postMat]
            let postNode = SCNNode(geometry: postGeo)
            postNode.position = SCNVector3(s.x, levelDeckY - postHeight / 2, s.z)
            scene.rootNode.addChildNode(postNode)
        }
    }

    private func addGroundPlane(scene: SCNScene, targetSize: Float) {
        let groundGeo = SCNPlane(width: CGFloat(targetSize * 4), height: CGFloat(targetSize * 4))
        let groundMat = SCNMaterial()
        groundMat.diffuse.contents = UIColor(red: 74/255, green: 94/255, blue: 58/255, alpha: 0.3)
        groundMat.isDoubleSided = true
        groundGeo.materials = [groundMat]
        let groundNode = SCNNode(geometry: groundGeo)
        groundNode.eulerAngles.x = -.pi / 2
        groundNode.position = SCNVector3(0, -0.01, 0)
        scene.rootNode.addChildNode(groundNode)
    }

    private func addLighting(scene: SCNScene) {
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 400
        ambientLight.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 800
        directionalLight.color = UIColor.white
        directionalLight.castsShadow = true
        directionalLight.shadowRadius = 3
        directionalLight.shadowMapSize = CGSize(width: 1024, height: 1024)
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(directionalNode)
    }

    private func addCamera(scene: SCNScene, targetSize: Float, deckHeight: Float) {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 50

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"

        let distance: Float = targetSize * 1.6
        let azimuthRad: Float = 225.0 * .pi / 180.0
        let elevationRad: Float = 35.0 * .pi / 180.0

        cameraNode.position = SCNVector3(
            distance * cos(elevationRad) * sin(azimuthRad),
            deckHeight + distance * sin(elevationRad),
            distance * cos(elevationRad) * cos(azimuthRad)
        )
        cameraNode.look(at: SCNVector3(0, deckHeight / 2, 0))
        scene.rootNode.addChildNode(cameraNode)
    }
}
