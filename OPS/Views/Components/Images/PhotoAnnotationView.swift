//
//  PhotoAnnotationView.swift
//  OPS
//
//  Full-screen photo annotation view with PencilKit drawing and text notes.
//  Used by ProjectPhotosGrid (fullScreenCover entry point). The zoomable
//  photo + canvas lives in ZoomablePhotoAnnotationCanvas (shared with
//  PhotoCommentViewer's inline markup).
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
    @State private var displayedCanvasSize: CGSize = .zero

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
                                drawing: $drawing,
                                displayedCanvasSize: $displayedCanvasSize
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
        let cacheKey = photoURL.hasPrefix("//") ? "https:" + photoURL : photoURL
        if let cached = ImageFileManager.shared.loadImage(localID: photoURL)
            ?? ImageFileManager.shared.loadImage(localID: cacheKey)
            ?? ImageCache.shared.get(forKey: cacheKey) {
            loadedImage = cached
            return
        }

        guard let url = URL(string: cacheKey) else {
            loadFailed = true
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                _ = ImageFileManager.shared.saveImage(data: data, localID: cacheKey)
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

        let canvasSize = PhotoAnnotationRenderGeometry.renderSize(
            displayedCanvasSize: displayedCanvasSize,
            sourceImageSize: loadedImage?.size ?? .zero
        )

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
