// OPS/OPS/DeckBuilder/3D/DeckScene3DView.swift

import SwiftUI
import DeckKit
import SceneKit

// MARK: - Scene Controller (shared between 3D view and parent)

@MainActor
class Scene3DController: ObservableObject {
    fileprivate var scnView: SCNView?
    fileprivate var scene: SCNScene?
    fileprivate var lastDrawingJSON: String = ""

    func setCameraPreset(_ preset: CameraPreset) {
        guard let scnView = scnView, let scene = scene else { return }

        // Frame the DECK, not the whole scene — the ground plane otherwise
        // dominates the bounding box and every preset zooms out to a tiny deck.
        let ground = scene.rootNode.childNode(withName: "groundPlane", recursively: false)
        ground?.removeFromParentNode()
        let (minBound, maxBound) = scene.rootNode.boundingBox
        if let ground { scene.rootNode.addChildNode(ground) }
        let centerX = (minBound.x + maxBound.x) / 2
        let centerY = (minBound.y + maxBound.y) / 2
        let centerZ = (minBound.z + maxBound.z) / 2
        let spanX = maxBound.x - minBound.x
        let spanZ = maxBound.z - minBound.z
        let maxSpan = max(spanX, spanZ) * 1.2
        let distance = max(maxSpan * 2.0, 3.0)

        let azimuthRad = preset.azimuth * .pi / 180.0
        let elevationRad = preset.elevation * .pi / 180.0

        let camX = centerX + distance * cos(elevationRad) * sin(azimuthRad)
        let camY = centerY + distance * sin(elevationRad)
        let camZ = centerZ + distance * cos(elevationRad) * cos(azimuthRad)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5

        scnView.pointOfView?.position = SCNVector3(camX, camY, camZ)
        scnView.pointOfView?.look(at: SCNVector3(centerX, centerY, centerZ))

        SCNTransaction.commit()
    }

    func captureScreenshot() -> UIImage? {
        scnView?.snapshot()
    }
}

// MARK: - 3D View

struct DeckScene3DView: UIViewRepresentable {
    let drawingData: DeckDrawingData
    let controller: Scene3DController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {}

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)
        scnView.preferredFramesPerSecond = 60

        let scene = DeckSceneBuilder.buildScene(from: drawingData)
        scnView.scene = scene

        if let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: true) {
            scnView.pointOfView = cameraNode
        }

        controller.scnView = scnView
        controller.scene = scene
        controller.lastDrawingJSON = drawingData.toJSON()

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let currentJSON = drawingData.toJSON()
        guard currentJSON != controller.lastDrawingJSON else { return }

        let scene = DeckSceneBuilder.buildScene(from: drawingData)
        uiView.scene = scene

        if let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: true) {
            uiView.pointOfView = cameraNode
        }

        controller.scene = scene
        controller.lastDrawingJSON = currentJSON
    }
}

// MARK: - Camera Presets

enum CameraPreset: String, CaseIterable, Identifiable {
    case front
    case side
    case birdsEye
    case perspective

    var id: String { rawValue }

    var azimuth: Float {
        switch self {
        case .front:       return 180
        case .side:        return 270
        case .birdsEye:    return 0
        case .perspective: return 225
        }
    }

    var elevation: Float {
        switch self {
        case .front:       return 30
        case .side:        return 30
        case .birdsEye:    return 80
        case .perspective: return 35
        }
    }

    var displayName: String {
        switch self {
        case .front:       return "Front"
        case .side:        return "Side"
        case .birdsEye:    return "Bird's Eye"
        case .perspective: return "Reset"
        }
    }

    var iconName: String {
        switch self {
        case .front:       return "arrow.up.square"
        case .side:        return "arrow.right.square"
        case .birdsEye:    return "eye"
        case .perspective: return "arrow.counterclockwise"
        }
    }
}
