//
//  PhotoAnnotationView.swift
//  OPS
//
//  Full-screen photo annotation view with PencilKit drawing and text notes.
//  Used by ProjectPhotosGrid (fullScreenCover entry point). The zoomable
//  photo + canvas lives in ZoomablePhotoAnnotationCanvas (shared with
//  PhotoCommentViewer's inline markup).
//
//  Collaborative markup (spec 2026-06-23): each author owns a layer. Peers'
//  overlays composite as a non-editable base UNDER the current user's canvas
//  (the #1 fix — a teammate's marks are visible and never overwritten). A
//  change-log sheet lists every author with a per-viewer show/hide toggle.
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

    // MARK: Collaborative markup state
    /// Flattened composite of every visible PEER layer — the non-editable base.
    @State private var peerOverlayImage: UIImage? = nil
    /// Per-viewer show/hide selections (local-only — never synced).
    @State private var hiddenAuthorIds: Set<String> = []
    @State private var showingChangeLog = false
    @State private var didResolveOwnStroke = false
    @State private var didFireArrivalHaptic = false

    init(photoURL: String, projectId: String, existingAnnotation: PhotoAnnotation? = nil) {
        self.photoURL = photoURL
        self.projectId = projectId
        self.existingAnnotation = existingAnnotation
        self._noteText = State(initialValue: existingAnnotation?.note ?? "")

        // Optimistic seed from the device-local drawing (fast path for the
        // author's own device). The .task reconciles against the synced
        // strokeRef when the canvas is otherwise empty (cross-device resume).
        if let data = existingAnnotation?.localDrawingData,
           let restoredDrawing = try? PKDrawing(data: data) {
            self._drawing = State(initialValue: restoredDrawing)
        }
        self._hiddenAuthorIds = State(initialValue: existingAnnotation?.hiddenAuthorIds ?? [])
    }

    // MARK: - Derived layer state

    private var currentUserId: String { dataController.currentUser?.id ?? "" }

    /// Layers to reason about — real layers, or a synthesized legacy layer (see
    /// PhotoAnnotation.effectiveMarkupLayers).
    private var effectiveLayers: [MarkupLayer] {
        existingAnnotation?.effectiveMarkupLayers() ?? []
    }

    private var ownLayer: MarkupLayer? {
        effectiveLayers.first { $0.layerId == currentUserId }
    }

    /// Visible peers (active, not me, not locally hidden), in z-order.
    private var peerLayers: [MarkupLayer] {
        effectiveLayers
            .filter { $0.layerId != currentUserId && $0.isActive && !hiddenAuthorIds.contains($0.authorId) }
            .sorted { $0.zIndex < $1.zIndex }
    }

    /// Distinct active authors — drives the toolbar badge + change-log sheet.
    private var activeAuthorLayers: [MarkupLayer] {
        effectiveLayers.filter { $0.isActive }.sorted { $0.zIndex < $1.zIndex }
    }

    /// Only surface the change-log control when there's a collaborator to reason
    /// about — a solo author never sees a trivial one-row sheet.
    private var hasPeers: Bool {
        effectiveLayers.contains { $0.layerId != currentUserId && $0.isActive }
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
                            // The peer-overlay base layers UNDER the canvas.
                            ZoomablePhotoAnnotationCanvas(
                                image: image,
                                drawing: $drawing,
                                displayedCanvasSize: $displayedCanvasSize,
                                peerOverlayImage: peerOverlayImage
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
            await resolveOwnStrokeIfNeeded()
            await recomputePeerOverlay()
            fireArrivalHapticIfNeeded()
        }
        .onChange(of: hiddenAuthorIds) { _, newValue in
            // Persist the per-viewer preference locally (never synced).
            if let annotation = existingAnnotation {
                annotation.hiddenAuthorIds = newValue
                try? modelContext.save()
            }
            Task { await recomputePeerOverlay() }
        }
        .sheet(isPresented: $showingChangeLog) {
            MarkupChangeLogSheet(
                authorLayers: activeAuthorLayers,
                changeLog: (existingAnnotation?.changeLog ?? []),
                currentUserId: currentUserId,
                hiddenAuthorIds: $hiddenAuthorIds
            )
        }
    }

    /// Bug 8824a41c — load the photo as a UIImage up-front so we can hand
    /// it to a UIScrollView-backed canvas. AsyncImage's SwiftUI Image
    /// can't be sized into a UIView's content area, so we own the load.
    private func loadImage() async {
        guard loadedImage == nil, !loadFailed else { return }
        let cacheKey = photoURL.hasPrefix("//") ? "https:" + photoURL : photoURL
        // Load the RAW original only (disk first, network below). The in-memory
        // ImageCache[cacheKey] is intentionally not consulted — it holds the
        // flattened composite for display, and drawing on top of it would bake
        // the existing markup into the base, doubling it on the next save.
        if let cached = ImageFileManager.shared.loadImage(localID: photoURL)
            ?? ImageFileManager.shared.loadImage(localID: cacheKey) {
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

    /// Resume the current user's own editable strokes from the synced stroke blob
    /// when the local canvas is empty (e.g. a fresh device that never authored
    /// here). Never overwrites a non-empty canvas — the local seed / live edits win.
    private func resolveOwnStrokeIfNeeded() async {
        guard !didResolveOwnStroke else { return }
        didResolveOwnStroke = true
        guard drawing.strokes.isEmpty,
              let strokeRef = ownLayer?.strokeRef,
              let restored = await MarkupStrokeStore.loadDrawing(strokeRef: strokeRef) else { return }
        await MainActor.run {
            if self.drawing.strokes.isEmpty { self.drawing = restored }
        }
    }

    /// Flatten the visible peers' overlays into the non-editable base image.
    private func recomputePeerOverlay() async {
        let layers = peerLayers
        guard !layers.isEmpty, let sourceSize = loadedImage?.size else {
            await MainActor.run { self.peerOverlayImage = nil }
            return
        }
        let composited = await MarkupOverlayCompositor.compositePeerOverlays(layers, sourceSize: sourceSize)
        await MainActor.run { self.peerOverlayImage = composited }
    }

    /// A single light impact when entering markup that ALREADY carries a
    /// collaborator's marks — earned ("someone else worked this photo"), not spam.
    private func fireArrivalHapticIfNeeded() {
        guard !didFireArrivalHaptic, hasPeers else { return }
        didFireArrivalHaptic = true
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
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

            // Change-log / layers — only when a collaborator's marks are present.
            if hasPeers {
                Button(action: { showingChangeLog = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "square.stack.3d.up")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("\(activeAuthorLayers.count)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.background)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            .offset(x: 8, y: -8)
                    }
                }
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                .accessibilityLabel("Markup authors")
            }

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
        .background(OPSStyle.Colors.glassDenseApprox)
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
        .background(OPSStyle.Colors.glassDenseApprox)
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
                authorName: user.fullName,
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
