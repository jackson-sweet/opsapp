//
//  CameraBatchView.swift
//  OPS
//
//  Camera-first batch photo capture view.
//  Opens camera directly, shows thumbnail strip of captures,
//  allows adding from photo library, and uploads all at once.
//

import SwiftUI
import PhotosUI

struct CameraBatchView: View {
    let onUpload: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var capturedImages: [UIImage] = []
    @State private var showingCamera = false
    @State private var showingGallery = false
    @State private var galleryImages: [UIImage] = []

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Camera prompt when no photos
                if capturedImages.isEmpty {
                    emptyPrompt
                }

                Spacer()

                // Thumbnail strip
                if !capturedImages.isEmpty {
                    thumbnailStrip
                }

                // Bottom controls
                bottomControls
            }
        }
        .onAppear {
            // Open camera immediately on first appearance
            showingCamera = true
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCapture { image in
                if let image = image {
                    capturedImages.append(image)
                }
                // Re-present camera for continuous capture
                // User must explicitly close to stop
            }
        }
        .sheet(isPresented: $showingGallery) {
            GalleryPickerWrapper(images: $galleryImages) {
                capturedImages.append(contentsOf: galleryImages)
                galleryImages = []
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            if !capturedImages.isEmpty {
                Text("\(capturedImages.count) PHOTO\(capturedImages.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.smallCaption)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            // Spacer to balance layout
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Empty Prompt

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("TAP CAPTURE TO START")
                .font(OPSStyle.Typography.smallCaption)
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(capturedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))

                        // Remove button
                        Button(action: { capturedImages.remove(at: index) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Gallery button
            Button(action: { showingGallery = true }) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                    Text("GALLERY")
                        .font(OPSStyle.Typography.miniLabel)
                }
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 56, height: 56)
            }

            // Capture button
            Button(action: { showingCamera = true }) {
                ZStack {
                    Circle()
                        .stroke(OPSStyle.Colors.primaryText, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(width: 60, height: 60)
                }
            }

            // Upload button
            Button(action: {
                onUpload(capturedImages)
                dismiss()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                    Text(capturedImages.isEmpty ? "UPLOAD" : "UPLOAD (\(capturedImages.count))")
                        .font(OPSStyle.Typography.miniLabel)
                }
                .foregroundColor(capturedImages.isEmpty ? OPSStyle.Colors.tertiaryText.opacity(0.3) : OPSStyle.Colors.primaryAccent)
                .frame(width: 56, height: 56)
            }
            .disabled(capturedImages.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Camera Capture (UIImagePickerController wrapper)

private struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onCapture(image)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Gallery Picker Wrapper (PHPicker)

private struct GalleryPickerWrapper: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 20
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: GalleryPickerWrapper

        init(parent: GalleryPickerWrapper) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            var loaded: [UIImage] = []

            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    defer { group.leave() }
                    if let image = image as? UIImage {
                        loaded.append(image)
                    }
                }
            }

            group.notify(queue: .main) {
                self.parent.images = loaded
                self.parent.onComplete()
            }
        }
    }
}
