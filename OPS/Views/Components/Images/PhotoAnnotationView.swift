//
//  PhotoAnnotationView.swift
//  OPS
//
//  Full-screen photo annotation view with PencilKit drawing and text notes.
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
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var imageSize: CGSize = CGSize(width: 1080, height: 1920)
    @State private var showToolPicker = false
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
                                            Color.clear.onAppear {
                                                imageSize = imageGeometry.size
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

                        // Layer 2: Existing annotation overlay (when not editing)
                        if !isEditing, let annotationURL = existingAnnotation?.annotationURL,
                           let url = URL(string: annotationURL) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                }
                            }
                        }

                        // Layer 3: PencilKit canvas (editing mode)
                        if isEditing {
                            PencilKitCanvas(
                                drawing: $drawing,
                                showToolPicker: $showToolPicker
                            )
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
                Image(systemName: OPSStyle.Icons.close)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

            Spacer()

            if isEditing {
                Button(action: { undoLastStroke() }) {
                    Image(systemName: OPSStyle.Icons.undo)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

                Button(action: { clearDrawing() }) {
                    Text("CLEAR")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            if isEditing {
                Button(action: { cancelEditing() }) {
                    Text("CANCEL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

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
            } else {
                Button(action: { startEditing() }) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.pencilTip)
                            .font(OPSStyle.Typography.caption)
                        Text("ANNOTATE")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
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

    private func startEditing() {
        withAnimation(OPSStyle.Animation.fast) {
            isEditing = true
            showToolPicker = true
        }
    }

    private func cancelEditing() {
        withAnimation(OPSStyle.Animation.fast) {
            // Restore original drawing if we had one
            if let data = existingAnnotation?.localDrawingData,
               let restored = try? PKDrawing(data: data) {
                drawing = restored
            } else {
                drawing = PKDrawing()
            }
            isEditing = false
            showToolPicker = false
        }
    }

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
            isEditing = false
            showToolPicker = false
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - PencilKit Canvas (UIViewRepresentable)

struct PencilKitCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var showToolPicker: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput  // Works with finger and pencil

        // Default tool: thin white pen
        canvas.tool = PKInkingTool(.pen, color: .white, width: 3)

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }

        // Show/hide tool picker
        if showToolPicker {
            if let window = canvas.window {
                let toolPicker = PKToolPicker.shared(for: window)
                toolPicker?.setVisible(true, forFirstResponder: canvas)
                toolPicker?.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        } else {
            if let window = canvas.window {
                let toolPicker = PKToolPicker.shared(for: window)
                toolPicker?.setVisible(false, forFirstResponder: canvas)
                toolPicker?.removeObserver(canvas)
                canvas.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: PencilKitCanvas

        init(_ parent: PencilKitCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
