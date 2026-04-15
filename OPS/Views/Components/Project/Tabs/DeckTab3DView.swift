//
//  DeckTab3DView.swift
//  OPS
//
//  Read-only 3D SceneKit viewer for deck designs in project details.
//  Builds geometry directly from canvas coordinates and normalizes to fill viewport.
//  Does NOT require scaleFactor — works with any drawing data that has vertices.
//

import SwiftUI
import SceneKit

struct DeckTab3DView: View {
    let drawingData: DeckDrawingData
    @State private var sceneReady = false

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

        let scene = buildNormalizedScene()
        scnView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            scnView.pointOfView = cam
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Build Scene from Canvas Coordinates

    private func buildNormalizedScene() -> SCNScene {
        let scene = SCNScene()

        let positions: [CGPoint]
        let edges: [DeckEdge]
        let isClosed: Bool

        if drawingData.isMultiLevel, let level = drawingData.levels.first {
            positions = level.orderedPositions
            edges = level.edges
            isClosed = level.isClosed
        } else {
            positions = drawingData.orderedPositions
            edges = drawingData.edges
            isClosed = drawingData.isClosed
        }

        guard positions.count >= 2 else { return scene }

        // Calculate bounds and normalize to a 5-unit cube centered at origin
        let xs = positions.map { Float($0.x) }
        let ys = positions.map { Float($0.y) }
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

        // Convert canvas point to normalized 3D coordinate (XZ plane)
        func toScene(_ p: CGPoint) -> (x: Float, z: Float) {
            let x = (Float(p.x) - centerX) * scale
            let z = (Float(p.y) - centerY) * scale
            return (x, z)
        }

        let deckHeight: Float = 0.5 // Visual deck thickness
        let postHeight: Float = 1.5 // Posts below deck

        // --- Deck surface (filled polygon) ---
        if isClosed, positions.count >= 3 {
            let scenePoints = positions.map { p -> CGPoint in
                let s = toScene(p)
                return CGPoint(x: CGFloat(s.x), y: CGFloat(s.z))
            }
            if let surfaceGeo = DeckMeshGenerator.createPolygonGeometry(
                vertices: scenePoints,
                yHeight: deckHeight
            ) {
                let surfaceMat = SCNMaterial()
                surfaceMat.diffuse.contents = UIColor(red: 196/255, green: 149/255, blue: 106/255, alpha: 1)
                surfaceMat.isDoubleSided = true
                surfaceGeo.materials = [surfaceMat]
                let surfaceNode = SCNNode(geometry: surfaceGeo)
                scene.rootNode.addChildNode(surfaceNode)
            }

            // Deck underside (slightly below)
            if let undersideGeo = DeckMeshGenerator.createPolygonGeometry(
                vertices: scenePoints,
                yHeight: deckHeight - 0.05
            ) {
                let underMat = SCNMaterial()
                underMat.diffuse.contents = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1)
                underMat.isDoubleSided = true
                undersideGeo.materials = [underMat]
                let underNode = SCNNode(geometry: undersideGeo)
                scene.rootNode.addChildNode(underNode)
            }
        }

        // --- Edge beams (along each edge on top of deck) ---
        let beamHeight: Float = 0.08
        let beamWidth: Float = 0.06
        for edge in edges {
            guard let startVert = vertexLookup(edge.startVertexId),
                  let endVert = vertexLookup(edge.endVertexId) else { continue }

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
            beamNode.position = SCNVector3(midX, deckHeight + beamHeight / 2, midZ)
            beamNode.eulerAngles.y = -angle
            scene.rootNode.addChildNode(beamNode)

            // Railing posts if configured
            if edge.railingConfig != nil {
                let postSpacing: Float = 0.8
                let numPosts = max(2, Int(length / postSpacing))
                for i in 0...numPosts {
                    let t = Float(i) / Float(numPosts)
                    let px = s.x + dx * t
                    let pz = s.z + dz * t
                    let railHeight: Float = 0.7

                    let postGeo = SCNBox(width: 0.04, height: CGFloat(railHeight), length: 0.04, chamferRadius: 0)
                    let postMat = SCNMaterial()
                    postMat.diffuse.contents = UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 1)
                    postGeo.materials = [postMat]

                    let postNode = SCNNode(geometry: postGeo)
                    postNode.position = SCNVector3(px, deckHeight + railHeight / 2, pz)
                    scene.rootNode.addChildNode(postNode)
                }

                // Top rail
                let railGeo = SCNBox(width: 0.05, height: 0.03, length: CGFloat(length), chamferRadius: 0)
                let railMat = SCNMaterial()
                railMat.diffuse.contents = UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 1)
                railGeo.materials = [railMat]
                let railNode = SCNNode(geometry: railGeo)
                railNode.position = SCNVector3(midX, deckHeight + 0.7, midZ)
                railNode.eulerAngles.y = -angle
                scene.rootNode.addChildNode(railNode)
            }
        }

        // --- Posts at each vertex ---
        for vertex in (drawingData.isMultiLevel ? (drawingData.levels.first?.vertices ?? []) : drawingData.vertices) {
            let s = toScene(vertex.position)
            let postGeo = SCNBox(width: 0.1, height: CGFloat(postHeight), length: 0.1, chamferRadius: 0)
            let postMat = SCNMaterial()
            postMat.diffuse.contents = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1)
            postGeo.materials = [postMat]

            let postNode = SCNNode(geometry: postGeo)
            postNode.position = SCNVector3(s.x, deckHeight - postHeight / 2, s.z)
            scene.rootNode.addChildNode(postNode)
        }

        // --- Ground plane ---
        let groundGeo = SCNPlane(width: CGFloat(targetSize * 4), height: CGFloat(targetSize * 4))
        let groundMat = SCNMaterial()
        groundMat.diffuse.contents = UIColor(red: 74/255, green: 94/255, blue: 58/255, alpha: 0.3)
        groundMat.isDoubleSided = true
        groundGeo.materials = [groundMat]
        let groundNode = SCNNode(geometry: groundGeo)
        groundNode.eulerAngles.x = -.pi / 2
        groundNode.position = SCNVector3(0, -0.01, 0)
        scene.rootNode.addChildNode(groundNode)

        // --- Lighting ---
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

        // --- Camera ---
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

        return scene
    }

    // MARK: - Vertex Lookup

    private func vertexLookup(_ id: String) -> DeckVertex? {
        if drawingData.isMultiLevel {
            return drawingData.levels.first?.vertex(byId: id)
        }
        return drawingData.vertex(byId: id)
    }
}
