// OPS/OPS/DeckBuilder/Views/PhotoOverlayEditorView.swift

import SwiftUI
import Supabase

struct PhotoOverlayEditorView: View {
    let initialSitePhoto: UIImage
    let drawingData: DeckDrawingData
    let projectId: String?
    let companyId: String
    let userId: String?
    let deckTitle: String
    let onSave: (PhotoOverlayState) -> Void
    let onDismiss: () -> Void

    // MARK: - Photo State

    @State private var currentPhoto: UIImage?

    // MARK: - Gesture State (using @State per OPS pattern, NOT @GestureState)

    @State private var overlayOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var overlayScale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var overlayRotation: Angle = .zero
    @State private var baseRotation: Angle = .zero
    @State private var fillOpacity: Double = 0.3

    // MARK: - Rendered Overlay

    @State private var overlayImage: UIImage?

    // MARK: - Save / Share State

    @State private var isSaving: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var compositeImage: UIImage?
    @State private var photoDisplaySize: CGSize = .zero
    @State private var saveError: String?

    // MARK: - Retake Photo

    @State private var showingRetakePhotoPicker: Bool = false

    private var sitePhoto: UIImage {
        currentPhoto ?? initialSitePhoto
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                ZStack {
                    // Base photo (fills the space, aspect fit)
                    Image(uiImage: sitePhoto)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(
                            GeometryReader { photoGeo in
                                Color.clear
                                    .onAppear {
                                        photoDisplaySize = fittedImageSize(
                                            imageSize: sitePhoto.size,
                                            containerSize: photoGeo.size
                                        )
                                    }
                                    .onChange(of: photoGeo.size) { _, newSize in
                                        photoDisplaySize = fittedImageSize(
                                            imageSize: sitePhoto.size,
                                            containerSize: newSize
                                        )
                                    }
                            }
                        )

                    // Deck overlay (transformed)
                    if let overlay = overlayImage {
                        Image(uiImage: overlay)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: overlayDisplaySize(in: geo.size).width,
                                height: overlayDisplaySize(in: geo.size).height
                            )
                            .scaleEffect(overlayScale)
                            .rotationEffect(overlayRotation)
                            .offset(overlayOffset)
                            .simultaneousGesture(dragGesture)
                            .simultaneousGesture(pinchGesture)
                            .simultaneousGesture(rotationGesture)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            bottomControls
        }
        .background(Color.black)
        .onAppear {
            loadSavedState()
            renderOverlay()
        }
        .onChange(of: fillOpacity) { _, _ in
            renderOverlay()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = compositeImage {
                ActivityView(items: [image])
            }
        }
        .sheet(isPresented: $showingRetakePhotoPicker) {
            PhotoSourcePickerView(
                projectId: projectId,
                onPhotoSelected: { photo in
                    currentPhoto = photo
                    showingRetakePhotoPicker = false
                    resetPosition()
                    // Recompute display size on next layout pass
                    photoDisplaySize = .zero
                }
            )
        }
        // Save failures route through the canonical Toast system.
        .errorToast($saveError, label: Feedback.Err.saveFailed)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            // Save
            Button {
                Task { await saveComposite() }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .medium))
                        Text("Save")
                            .font(OPSStyle.Typography.bodyBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, 12)
                }
            }
            .disabled(isSaving)

            // Share
            Button {
                Task { await shareComposite() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                    Text("Share")
                        .font(OPSStyle.Typography.bodyBold)
                }
                .foregroundColor(.white)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .padding(.horizontal, 12)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Opacity slider
            VStack(spacing: OPSStyle.Layout.spacing1) {
                Text("Opacity: \(Int(fillOpacity * 100))%")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Slider(value: $fillOpacity, in: 0.1...0.8, step: 0.05)
                    .tint(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Action buttons
            HStack {
                Button {
                    showingRetakePhotoPicker = true
                } label: {
                    Text("Retake Photo")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                }

                Spacer()

                Button {
                    resetPosition()
                } label: {
                    Text("Reset Position")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                overlayOffset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                baseOffset = overlayOffset
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                overlayScale = max(0.1, min(5.0, baseScale * value))
            }
            .onEnded { _ in
                baseScale = overlayScale
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                overlayRotation = baseRotation + value
            }
            .onEnded { _ in
                baseRotation = overlayRotation
            }
    }

    // MARK: - Overlay Rendering

    private func renderOverlay() {
        overlayImage = DeckOverlayRenderer.renderOverlay(
            drawingData: drawingData,
            fillOpacity: fillOpacity
        )
    }

    // MARK: - Save

    private func saveComposite() async {
        isSaving = true
        defer { isSaving = false }

        guard let overlay = overlayImage else { return }

        let composite = DeckOverlayRenderer.compositeOverlayOnPhoto(
            photo: sitePhoto,
            overlay: overlay,
            offset: overlayOffset,
            scale: overlayScale,
            rotation: overlayRotation,
            displaySize: photoDisplaySize
        )

        guard let imageData = composite.jpegData(compressionQuality: 0.85) else { return }

        // Upload to S3
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "deck_overlay_\(timestamp).jpg"
        let folder = "deck_designs/\(companyId)"

        do {
            let publicUrl = try await PresignedURLUploadService.shared.uploadImageData(
                imageData,
                filename: filename,
                folder: folder
            )

            // Insert project_photos row
            if let projectId {
                try await insertProjectPhoto(
                    url: publicUrl,
                    projectId: projectId,
                    companyId: companyId,
                    uploadedBy: userId ?? ""
                )
            }

            // Save overlay state for re-editing
            let state = PhotoOverlayState(
                photoURL: publicUrl,
                offsetX: Double(overlayOffset.width),
                offsetY: Double(overlayOffset.height),
                scale: Double(overlayScale),
                rotation: overlayRotation.degrees,
                opacity: fillOpacity
            )
            onSave(state)

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            print("[PhotoOverlayEditor] Failed to save composite: \(error)")
            saveError = "Save failed \u{2014} check your connection and try again."
        }
    }

    // MARK: - Share

    private func shareComposite() async {
        guard let overlay = overlayImage else { return }

        let composite = DeckOverlayRenderer.compositeOverlayOnPhoto(
            photo: sitePhoto,
            overlay: overlay,
            offset: overlayOffset,
            scale: overlayScale,
            rotation: overlayRotation,
            displaySize: photoDisplaySize
        )

        compositeImage = composite
        showingShareSheet = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Reset

    private func resetPosition() {
        withAnimation(OPSStyle.Animation.spring) {
            overlayOffset = .zero
            baseOffset = .zero
            overlayScale = 1.0
            baseScale = 1.0
            overlayRotation = .zero
            baseRotation = .zero
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Load Saved State

    private func loadSavedState() {
        if let saved = drawingData.photoOverlay {
            overlayOffset = CGSize(width: saved.offsetX, height: saved.offsetY)
            baseOffset = overlayOffset
            overlayScale = CGFloat(saved.scale)
            baseScale = overlayScale
            overlayRotation = Angle(degrees: saved.rotation)
            baseRotation = overlayRotation
            fillOpacity = saved.opacity
        }
    }

    // MARK: - Helpers

    private func overlayDisplaySize(in containerSize: CGSize) -> CGSize {
        guard let overlay = overlayImage else { return .zero }
        let maxWidth = containerSize.width * DeckOverlayRenderer.overlayWidthRatio
        let aspectRatio = overlay.size.height / overlay.size.width
        return CGSize(width: maxWidth, height: maxWidth * aspectRatio)
    }

    private func fittedImageSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return containerSize }
        let scaleX = containerSize.width / imageSize.width
        let scaleY = containerSize.height / imageSize.height
        let fitScale = min(scaleX, scaleY)
        return CGSize(
            width: imageSize.width * fitScale,
            height: imageSize.height * fitScale
        )
    }

    private func insertProjectPhoto(url: String, projectId: String, companyId: String, uploadedBy: String) async throws {
        struct ProjectPhotoInsert: Codable {
            let project_id: String
            let company_id: String
            let url: String
            let source: String
            let uploaded_by: String
            let caption: String
            let is_client_visible: Bool
        }

        let insert = ProjectPhotoInsert(
            project_id: projectId,
            company_id: companyId,
            url: url,
            source: "deck_design",
            uploaded_by: uploadedBy,
            caption: "Deck overlay \u{2014} \(deckTitle)",
            is_client_visible: true
        )

        try await SupabaseService.shared.client
            .from("project_photos")
            .insert(insert)
            .execute()
    }
}
