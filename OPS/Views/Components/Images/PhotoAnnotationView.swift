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
    @State private var imageSize: CGSize = .zero
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
                        // Layer 1: Original photo
                        AsyncImage(url: URL(string: photoURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                    .background(
                                        GeometryReader { imageGeometry in
                                            Color.clear
                                                .onAppear {
                                                    imageSize = imageGeometry.size
                                                }
                                                .onChange(of: imageGeometry.size) { _, newSize in
                                                    imageSize = newSize
                                                }
                                        }
                                    )
                            case .failure:
                                Image(systemName: OPSStyle.Icons.photo)
                                    .font(OPSStyle.Typography.largeTitle)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            case .empty:
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            @unknown default:
                                EmptyView()
                            }
                        }

                        // Layer 2: PencilKit canvas — only appears once image size is known
                        if imageSize.width > 0 && imageSize.height > 0 {
                            AnnotationCanvas(drawing: $drawing)
                                .frame(width: imageSize.width, height: imageSize.height)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Bottom bar with note field
                bottomBar
            }
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

        do {
            _ = try await PhotoAnnotationSyncManager.shared.saveAnnotation(
                drawing: drawing,
                note: noteText,
                photoURL: photoURL,
                imageSize: imageSize,
                projectId: projectId,
                companyId: companyId,
                authorId: user.id,
                existingAnnotationId: existingAnnotation?.id,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
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
