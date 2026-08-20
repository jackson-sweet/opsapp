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
    /// Token that changes exactly when `drawingData` changes — the persisted
    /// `DeckDesign.drawingDataJSON` at every production call site. It is the
    /// scene-rebuild decision, so it must never be a constant when the host can
    /// hand down a mutated drawing.
    ///
    /// WHY a token and not a re-serialization: this viewer used to answer "did
    /// the drawing change?" by calling `DeckDrawingData.toJSON()` on every
    /// SwiftUI update — a `ComponentEmitter` pass, a full `JSONEncoder` pass, a
    /// lexical re-parse and a re-render of the WHOLE drawing, on the main
    /// thread, inside `layoutSubviews`. `DeckDesign` already documents the same
    /// failure mode on the decode side (see `DeckDrawingDataCache`), and a
    /// device watchdog report caught this encode running inside
    /// `GraphHost.flushTransactions()`. The host already holds the canonical
    /// string, so the comparison costs nothing.
    let drawingIdentity: String
    /// Called on the main thread when the user starts or stops panning/zooming
    /// the scene. `true` = gesture active; `false` = gesture ended (debounced
    /// ~0.25s so back-to-back pan+pinch phases don't flicker the badges).
    var onInteractingChange: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            if geo.size.height > 0 {
                DeckTab3DSceneView(drawingData: drawingData,
                                   drawingIdentity: drawingIdentity,
                                   onInteractingChange: onInteractingChange)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - SceneKit UIViewRepresentable

private struct DeckTab3DSceneView: UIViewRepresentable {
    let drawingData: DeckDrawingData
    let drawingIdentity: String
    var onInteractingChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInteractingChange: onInteractingChange)
    }

    // MARK: Coordinator — pan/pinch gesture handling

    /// Adds a `UIPanGestureRecognizer` and `UIPinchGestureRecognizer` on top of
    /// SceneKit's built-in `allowsCameraControl` recognizers. The coordinator
    /// implements `UIGestureRecognizerDelegate.shouldRecognizeSimultaneouslyWith`
    /// returning `true` so our recognizers coexist with SceneKit's internal ones
    /// without blocking camera movement. It surfaces an `onInteractingChange`
    /// callback: `true` on `.began`/`.changed`, `false` on `.ended`/`.cancelled`/
    /// `.failed` with a 0.25s trailing debounce — preventing flicker when the user
    /// transitions from a pan to a pinch phase mid-gesture.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onInteractingChange: (Bool) -> Void
        /// Pending "ended" work item — cancelled if a new began/changed fires
        /// before the debounce window elapses.
        private var endWork: DispatchWorkItem?
        /// Identity of the drawing the scene was last built from. `updateUIView`
        /// only rebuilds when this changes, so unrelated SwiftUI re-renders —
        /// notably the badge-fade `@State` flip that fires at the start of every
        /// pan/pinch — don't reset the camera out from under the user's gesture.
        /// Optional so the FIRST update after `makeUIView` can't be mistaken for
        /// a change when the host's identity is legitimately the empty string.
        var lastDrawingIdentity: String?

        init(onInteractingChange: @escaping (Bool) -> Void) {
            self.onInteractingChange = onInteractingChange
        }

        @objc func handle(_ gr: UIGestureRecognizer) {
            switch gr.state {
            case .began, .changed:
                // Cancel any pending "ended" callback so a pan→pinch transition
                // doesn't briefly flash the badges visible between the two phases.
                endWork?.cancel()
                onInteractingChange(true)
            case .ended, .cancelled, .failed:
                let work = DispatchWorkItem { [weak self] in
                    self?.onInteractingChange(false)
                }
                endWork = work
                // 0.25s trailing debounce per spec (Task 4, Step 2).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            default:
                break
            }
        }

        /// Allow our recognizers to fire simultaneously with SceneKit's
        /// built-in camera-control recognizers. Without this, returning `false`
        /// (the default) would cause one recognizer to cancel the other,
        /// potentially blocking camera pan/zoom.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)
        scnView.preferredFramesPerSecond = 60

        // Pan recognizer — tracks single/two-finger drag (orbit + translate).
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        pan.delegate = context.coordinator
        scnView.addGestureRecognizer(pan)

        // Pinch recognizer — tracks two-finger spread/pinch (zoom).
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        pinch.delegate = context.coordinator
        scnView.addGestureRecognizer(pinch)

        let scene = buildScene()
        scnView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            scnView.pointOfView = cam
        }
        context.coordinator.lastDrawingIdentity = drawingIdentity

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Only rebuild when the drawing ACTUALLY changed. Rebuilding on every
        // SwiftUI re-render — including the badge-fade `@State` flip in
        // DeckTabView that fires at the START of every pan/pinch — would
        // reassign the scene and reset `pointOfView`, snapping the camera home
        // and fighting the gesture the user just made. Mirrors the revision
        // gate in DeckScene3DView (the builder's viewer): a token comparison,
        // never a re-serialization of the drawing.
        guard drawingIdentity != context.coordinator.lastDrawingIdentity else { return }
        let scene = buildScene()
        uiView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            uiView.pointOfView = cam
        }
        context.coordinator.lastDrawingIdentity = drawingIdentity
    }

    /// Render through the canonical `DeckSceneBuilder`. Calibrated designs use
    /// their stored `scaleFactor`; uncalibrated designs are rendered against a
    /// copy carrying `effectiveScaleFactor` (the prescale every freehand edge
    /// was already dimensioned at), so the builder reproduces true proportions
    /// instead of the old normalized-footprint/real-meter mix. Shared with the
    /// builder's own 3D canvas via `buildCalibratedScene(from:)`.
    private func buildScene() -> SCNScene {
        DeckSceneBuilder.buildCalibratedScene(from: drawingData)
    }
}
