//
//  ZoomablePhotoAnnotationCanvas.swift
//  OPS
//
//  UIScrollView-backed photo + PencilKit canvas that zoom and pan as one unit.
//  Shared by PhotoAnnotationView (photos-grid markup) and PhotoCommentViewer
//  (inline photo-viewer markup) so both surfaces get identical iOS Photos-style
//  pinch-to-zoom-while-drawing behaviour.
//

import SwiftUI
import PencilKit

// MARK: - ZoomablePhotoAnnotationCanvas (Bug 8824a41c)

/// UIScrollView wrapper around an aspect-fit photo + a transparent
/// PencilKit canvas, layered so they zoom and pan as one unit. Mirrors
/// the iOS Photos.app markup interaction model:
///
/// - Single-finger touches go to PencilKit for drawing.
/// - Two-finger touches drive scrollView pan + pinch-to-zoom (1×–5×).
/// - Drawing coordinates are stored in the canvas's own (unscaled) space,
///   so strokes laid down at any zoom level remain perfectly aligned with
///   the underlying pixels of the photo.
struct ZoomablePhotoAnnotationCanvas: UIViewRepresentable {
    let image: UIImage
    @Binding var drawing: PKDrawing
    @Binding var displayedCanvasSize: CGSize

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        // Critical — drawing is one finger, pan/zoom is two. Without
        // this clamp the scroll view eats every touch and PencilKit
        // never sees a stroke.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2

        let container = UIView()
        container.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false

        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .white, width: 3)
        canvas.delegate = context.coordinator
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.overrideUserInterfaceStyle = .dark
        // PKCanvasView is itself a UIScrollView; disable its own scroll
        // so the outer scroll view owns zoom/pan. Otherwise both fight
        // over pinch gestures.
        canvas.isScrollEnabled = false

        container.addSubview(imageView)
        container.addSubview(canvas)
        scrollView.addSubview(container)

        context.coordinator.scrollView = scrollView
        context.coordinator.container = container
        context.coordinator.imageView = imageView
        context.coordinator.canvas = canvas

        // Defer initial layout + tool picker until the scroll view has
        // a real bounds rect from autolayout.
        DispatchQueue.main.async {
            context.coordinator.layoutForCurrentBounds()
            context.coordinator.showToolPicker()
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }

        // Re-fit if the scroll bounds changed (rotation, sheet resize).
        context.coordinator.layoutForCurrentBounds()

        if context.coordinator.isInternalUpdate {
            context.coordinator.isInternalUpdate = false
            return
        }
        context.coordinator.isProgrammaticUpdate = true
        canvas.drawing = drawing
        context.coordinator.isProgrammaticUpdate = false
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.hideToolPicker()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {
        let parent: ZoomablePhotoAnnotationCanvas
        weak var scrollView: UIScrollView?
        weak var container: UIView?
        weak var imageView: UIImageView?
        weak var canvas: PKCanvasView?

        private var toolPicker: PKToolPicker?
        var isInternalUpdate = false
        var isProgrammaticUpdate = false
        private var lastFittedBounds: CGSize = .zero

        init(parent: ZoomablePhotoAnnotationCanvas) {
            self.parent = parent
        }

        // MARK: Layout

        func layoutForCurrentBounds() {
            guard let scrollView = scrollView,
                  let container = container,
                  let imageView = imageView,
                  let canvas = canvas else { return }

            let bounds = scrollView.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return }
            // Skip when bounds haven't changed (avoids resetting zoom on
            // every SwiftUI re-render).
            if bounds == lastFittedBounds { return }
            lastFittedBounds = bounds

            let imgSize = parent.image.size
            guard imgSize.width > 0, imgSize.height > 0 else { return }

            let imageAspect = imgSize.width / imgSize.height
            let frameAspect = bounds.width / bounds.height
            let fitted: CGSize
            if imageAspect > frameAspect {
                let w = bounds.width
                let h = w / imageAspect
                fitted = CGSize(width: w, height: h)
            } else {
                let h = bounds.height
                let w = h * imageAspect
                fitted = CGSize(width: w, height: h)
            }

            container.frame = CGRect(origin: .zero, size: fitted)
            imageView.frame = container.bounds
            canvas.frame = container.bounds
            parent.displayedCanvasSize = fitted

            scrollView.contentSize = fitted
            scrollView.zoomScale = 1.0
            centerContainer()
        }

        private func centerContainer() {
            guard let scrollView = scrollView, let container = container else { return }
            let boundsSize = scrollView.bounds.size
            var frame = container.frame
            frame.origin.x = max(0, (boundsSize.width - frame.size.width) / 2)
            frame.origin.y = max(0, (boundsSize.height - frame.size.height) / 2)
            container.frame = frame
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return container
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContainer()
        }

        // MARK: Tool picker

        func showToolPicker() {
            guard let canvas = canvas else { return }
            let picker = PKToolPicker()
            picker.setVisible(true, forFirstResponder: canvas)
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
            self.toolPicker = picker
        }

        func hideToolPicker() {
            guard let canvas = canvas else { return }
            toolPicker?.setVisible(false, forFirstResponder: canvas)
            toolPicker?.removeObserver(canvas)
            canvas.resignFirstResponder()
            toolPicker = nil
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isProgrammaticUpdate else { return }
            isInternalUpdate = true
            parent.drawing = canvasView.drawing
        }
    }
}
