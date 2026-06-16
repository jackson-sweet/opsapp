//
//  DeckTab3DView.swift
//  OPS
//
//  Read-only 3D SceneKit viewer for deck designs in project details.
//  Delegates scene construction to DeckSceneBuilder so the viewer renders
//  the same geometry as the editor — including stairs, house walls,
//  railings, support posts, per-surface materials, and ALL levels.
//
//  Uncalibrated drawings (no `scaleFactor` — ~93% of saved decks) are
//  rendered through the SAME canonical builder using `effectiveScaleFactor`.
//  Every freehand edge is already dimensioned against that prescale, so the
//  builder reproduces the deck at true real-world proportions. This replaced
//  a hand-rolled fallback scene that normalized the footprint to a fixed
//  size while drawing walls, deck elevation, and stairs in real meters —
//  which made house walls tower over the deck and stair stringers slope the
//  wrong way on flipped/diagonal edges. One renderer, correct geometry for
//  every deck.
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

    /// Render through the canonical `DeckSceneBuilder`. Calibrated designs use
    /// their stored `scaleFactor`; uncalibrated designs are rendered against a
    /// copy carrying `effectiveScaleFactor` (the prescale every freehand edge
    /// was already dimensioned at), so the builder reproduces true proportions
    /// instead of the old normalized-footprint/real-meter mix.
    private func buildScene() -> SCNScene {
        if let scale = drawingData.scaleFactor, scale > 0 {
            return DeckSceneBuilder.buildScene(from: drawingData)
        }
        var calibrated = drawingData
        calibrated.scaleFactor = drawingData.effectiveScaleFactor
        return DeckSceneBuilder.buildScene(from: calibrated)
    }
}
