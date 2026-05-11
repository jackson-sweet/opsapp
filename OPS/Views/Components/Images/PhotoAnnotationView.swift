//
//  PhotoAnnotationView.swift
//  OPS
//
//  Full-screen photo annotation view with PencilKit drawing and text notes.
//  Used by ProjectPhotosGrid (fullScreenCover entry point).
//  PhotoCommentViewer uses inline annotation via AnnotationCanvas directly.
//

import SwiftUI
import PencilKit
import SwiftData

struct PhotoAnnotationView: View {
    let photoURL: String
    let projectId: String
    let existingAnnotation: PhotoAnnotation?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    @State private var drawing = PKDrawing()
    @State private var noteText: String = ""
    @State private var isSaving = false
    @State private var loadedImage: UIImage? = nil
    @State private var loadFailed: Bool = false
    @State private var error: String? = nil

    init(photoURL: String, projectId: String, existingAnnotation: PhotoAnnotation? = nil) {
        self.photoURL = photoURL
        self.projectId = projectId
        self.existingAnnotation = existingAnnotation
        self._noteText = State(initialValue: existingAnnotation?.note ?? "")

        // Restore drawing from local data if available
        if let data = existingAnnotation?.localDrawingData,
           let restoredDrawing = try? PKDrawing(data: data) {
            self._drawing = State(initialValue: restoredDrawing)
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top toolbar
                toolbar

                // Photo + annotation canvas
                GeometryReader { geometry in
                    ZStack {
                        if let image = loadedImage {
                            // Bug 8824a41c — photo + PencilKit live inside a
                            // single UIScrollView so the user can two-finger
                            // pinch to zoom (matching the system Photos
                            // markup behaviour). One-finger touches still
                            // route to PencilKit for drawing; the scroll
                            // view's pan only engages with two fingers.
                            ZoomablePhotoAnnotationCanvas(
                                image: image,
                                drawing: $drawing
                            )
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        } else if loadFailed {
                            Image(systemName: OPSStyle.Icons.photo)
                                .font(OPSStyle.Typography.largeTitle)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Bottom bar with note field
                bottomBar
            }
        }
        .task {
            await loadImage()
        }
    }

    /// Bug 8824a41c — load the photo as a UIImage up-front so we can hand
    /// it to a UIScrollView-backed canvas. AsyncImage's SwiftUI Image
    /// can't be sized into a UIView's content area, so we own the load.
    private func loadImage() async {
        guard loadedImage == nil, !loadFailed else { return }
        guard let url = URL(string: photoURL) else {
            loadFailed = true
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run { self.loadedImage = image }
            } else {
                await MainActor.run { self.loadFailed = true }
            }
        } catch {
            await MainActor.run { self.loadFailed = true }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

            Spacer()

            Button(action: { undoLastStroke() }) {
                Image(systemName: OPSStyle.Icons.undo)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(drawing.strokes.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(drawing.strokes.isEmpty)

            Button(action: { clearDrawing() }) {
                Text("CLEAR")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(drawing.strokes.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.errorStatus)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(drawing.strokes.isEmpty)

            Spacer()

            Button(action: { Task { await saveAnnotation() } }) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                } else {
                    Text("DONE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(isSaving)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.notes)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField("Add a note...", text: $noteText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)

            if let error = error {
                Text(error)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing1)
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Actions

    private func undoLastStroke() {
        guard !drawing.strokes.isEmpty else { return }
        var strokes = drawing.strokes
        strokes.removeLast()
        drawing = PKDrawing(strokes: strokes)
    }

    private func clearDrawing() {
        drawing = PKDrawing()
    }

    private func saveAnnotation() async {
        guard let user = dataController.currentUser,
              let companyId = user.companyId else { return }

        isSaving = true
        error = nil

        // Bug 8824a41c — pass the loaded image's natural pixel size as the
        // canonical canvas size. Annotations are saved against the source
        // photo's coordinate space (so they re-align when the photo loads
        // at a different fitted size on another device); the loaded UIImage
        // gives us that authoritative size directly.
        let canvasSize = loadedImage?.size ?? .zero

        do {
            _ = try await PhotoAnnotationSyncManager.shared.saveAnnotation(
                drawing: drawing,
                note: noteText,
                photoURL: photoURL,
                imageSize: canvasSize,
                projectId: projectId,
                companyId: companyId,
                authorId: user.id,
                existingAnnotationId: existingAnnotation?.id,
                modelContext: modelContext
            )
            NotificationCenter.default.post(name: Notification.Name("WizardPhotoAnnotated"), object: nil)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

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

// MARK: - AnnotationCanvas (UIViewRepresentable)

/// PencilKit canvas with proper PKToolPicker lifecycle.
///
/// Key fixes over old PencilKitCanvas:
/// 1. Creates and retains its own PKToolPicker (deprecated .shared(for:) returned nil)
/// 2. Shows picker after canvas is in the window hierarchy (delayed becomeFirstResponder)
/// 3. Uses internal-update flag to prevent SwiftUI re-render loop when user draws
///
struct AnnotationCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
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
        context.coordinator.canvasView = canvas

        // Show tool picker after the canvas is in the view hierarchy.
        // The canvas needs a window to attach the tool picker — use a
        // slightly longer delay to ensure the view is fully installed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            context.coordinator.showToolPicker()
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // If the drawing changed from user input (canvasViewDrawingDidChange),
        // skip re-assigning — the canvas already has the correct drawing.
        if context.coordinator.isInternalUpdate {
            context.coordinator.isInternalUpdate = false
            return
        }

        // External change (undo, clear) — apply to the canvas.
        context.coordinator.isProgrammaticUpdate = true
        canvas.drawing = drawing
        context.coordinator.isProgrammaticUpdate = false
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.hideToolPicker()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: AnnotationCanvas
        weak var canvasView: PKCanvasView?

        /// Strong reference to the tool picker — if this is released, the picker disappears.
        private var toolPicker: PKToolPicker?

        /// Set by canvasViewDrawingDidChange to tell updateUIView to skip re-assignment.
        var isInternalUpdate = false

        /// Set by updateUIView when programmatically setting drawing, so the delegate ignores it.
        var isProgrammaticUpdate = false

        init(parent: AnnotationCanvas) {
            self.parent = parent
        }

        func showToolPicker() {
            guard let canvas = canvasView else { return }
            let picker = PKToolPicker()
            picker.setVisible(true, forFirstResponder: canvas)
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
            self.toolPicker = picker
        }

        func hideToolPicker() {
            guard let canvas = canvasView else { return }
            toolPicker?.setVisible(false, forFirstResponder: canvas)
            toolPicker?.removeObserver(canvas)
            canvas.resignFirstResponder()
            toolPicker = nil
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Ignore delegate calls triggered by programmatic drawing assignment
            guard !isProgrammaticUpdate else { return }
            isInternalUpdate = true
            parent.drawing = canvasView.drawing
        }
    }
}
