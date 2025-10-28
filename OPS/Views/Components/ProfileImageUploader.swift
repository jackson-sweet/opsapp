//
//  ProfileImageUploader.swift
//  OPS
//
//  Reusable component for uploading profile images and company logos
//

import SwiftUI
import UIKit

// MARK: - Configuration

struct ImageUploaderConfig {
    let currentImageURL: String?
    let currentImageData: Data?
    let placeholderText: String
    let size: CGFloat
    let shape: ImageShape
    let allowDelete: Bool
    let backgroundColor: Color
    let uploadButtonText: String?

    init(
        currentImageURL: String? = nil,
        currentImageData: Data? = nil,
        placeholderText: String,
        size: CGFloat = 80,
        shape: ImageShape = .circle,
        allowDelete: Bool = true,
        backgroundColor: Color = .gray,
        uploadButtonText: String? = nil
    ) {
        self.currentImageURL = currentImageURL
        self.currentImageData = currentImageData
        self.placeholderText = placeholderText
        self.size = size
        self.shape = shape
        self.allowDelete = allowDelete
        self.backgroundColor = backgroundColor
        self.uploadButtonText = uploadButtonText
    }
}

enum ImageShape: Equatable {
    case circle
    case roundedSquare(cornerRadius: CGFloat)
}

// MARK: - Main Component

struct ProfileImageUploader: View {
    let config: ImageUploaderConfig
    let onUpload: (UIImage) async throws -> String
    let onDelete: (() async throws -> Void)?

    @State private var isUploading = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingActionSheet = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var localImage: UIImage?
    @State private var loadedImage: UIImage?
    @State private var isLoadingImage = false

    var body: some View {
        VStack(spacing: 12) {
            // Image Display
            imageView
                .onTapGesture {
                    showingActionSheet = true
                }

            // Status/Error Messages
            if isUploading {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(0.8)
                    Text("UPLOADING")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            } else if let error = errorMessage {
                Text(error)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .multilineTextAlignment(.center)
            }
        }
        .confirmationDialog("", isPresented: $showingActionSheet, titleVisibility: .hidden) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("CAMERA") {
                    showingCamera = true
                }
            }
            Button("PHOTO LIBRARY") {
                showingImagePicker = true
            }
            if config.allowDelete && hasImage {
                Button("REMOVE PHOTO", role: .destructive) {
                    handleDelete()
                }
            }
            Button("CANCEL", role: .cancel) {}
        }
        .sheet(isPresented: $showingImagePicker) {
            SimpleImagePicker(sourceType: .photoLibrary) { image in
                handleImageSelected(image)
            }
        }
        .sheet(isPresented: $showingCamera) {
            SimpleImagePicker(sourceType: .camera) { image in
                handleImageSelected(image)
            }
        }
        .alert("ERROR", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: config.currentImageURL) { _, _ in
            loadImageIfNeeded()
        }
    }

    // MARK: - Views

    private var imageView: some View {
        Group {
            switch config.shape {
            case .circle:
                circleImageView
            case .roundedSquare(let radius):
                roundedSquareImageView(cornerRadius: radius)
            }
        }
    }

    private var circleImageView: some View {
        ZStack {
            // Background shape
            Circle()
                .fill(config.backgroundColor.opacity(0.1))
                .overlay(
                    Circle()
                        .stroke(config.backgroundColor, lineWidth: 2)
                )

            // Image or placeholder
            if let displayImage = displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: config.size, height: config.size)
                    .clipShape(Circle())
            } else {
                Text(config.placeholderText)
                    .font(.custom("Mohave-Bold", size: config.size * 0.35))
                    .foregroundColor(config.backgroundColor)
            }

            // Upload overlay when uploading
            if isUploading {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    )
            }

            // Loading overlay when downloading image
            if isLoadingImage {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    )
            }

            // Camera icon hint - centered when no image
            if !isUploading && !isLoadingImage && !hasImage {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(config.backgroundColor.opacity(0.6))
                    Text("TAP TO UPLOAD")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(config.backgroundColor.opacity(0.6))
                }
            }
        }
        .frame(width: config.size, height: config.size)
    }

    private func roundedSquareImageView(cornerRadius: CGFloat) -> some View {
        ZStack {
            // Background shape
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(config.backgroundColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(config.backgroundColor, lineWidth: 2)
                )

            // Image or placeholder
            if let displayImage = displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: config.size, height: config.size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                Text(config.placeholderText)
                    .font(.custom("Mohave-Bold", size: config.size * 0.35))
                    .foregroundColor(config.backgroundColor)
            }

            // Upload overlay when uploading
            if isUploading {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    )
            }

            // Loading overlay when downloading image
            if isLoadingImage {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    )
            }

            // Camera icon hint - centered when no image
            if !isUploading && !isLoadingImage && !hasImage {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(config.backgroundColor.opacity(0.6))
                    Text("TAP TO UPLOAD")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(config.backgroundColor.opacity(0.6))
                }
            }
        }
        .frame(width: config.size, height: config.size)
    }

    // MARK: - Computed Properties

    private var hasImage: Bool {
        localImage != nil || loadedImage != nil || config.currentImageData != nil
    }

    private var displayImage: UIImage? {
        // Priority: local image > cached data > downloaded image
        if let local = localImage {
            return local
        }
        if let data = config.currentImageData, let image = UIImage(data: data) {
            return image
        }
        return loadedImage
    }

    // MARK: - Actions

    private func handleImageSelected(_ image: UIImage) {
        localImage = image
        errorMessage = nil

        Task {
            await MainActor.run { isUploading = true }

            do {
                let imageURL = try await onUpload(image)
                print("[IMAGE_UPLOADER] ✅ Upload successful: \(imageURL)")
                await MainActor.run {
                    isUploading = false
                    errorMessage = nil
                }
            } catch {
                print("[IMAGE_UPLOADER] ❌ Upload failed: \(error)")
                await MainActor.run {
                    isUploading = false
                    errorMessage = "UPLOAD FAILED"
                    showingError = true
                    // Keep local image so user can see what failed
                }
            }
        }
    }

    private func handleDelete() {
        guard let deleteHandler = onDelete else { return }

        Task {
            await MainActor.run { isUploading = true }

            do {
                try await deleteHandler()
                print("[IMAGE_UPLOADER] ✅ Image deleted successfully")
                await MainActor.run {
                    localImage = nil
                    loadedImage = nil
                    isUploading = false
                }
            } catch {
                print("[IMAGE_UPLOADER] ❌ Delete failed: \(error)")
                await MainActor.run {
                    isUploading = false
                    errorMessage = "DELETE FAILED"
                    showingError = true
                }
            }
        }
    }

    private func loadImageIfNeeded() {
        // Don't load if we already have image data or a loaded image
        guard loadedImage == nil,
              config.currentImageData == nil,
              localImage == nil,
              let urlString = config.currentImageURL,
              !urlString.isEmpty else {
            return
        }

        // Fix URLs that start with // by adding https:
        var fixedURLString = urlString
        if urlString.hasPrefix("//") {
            fixedURLString = "https:" + urlString
        }

        guard let url = URL(string: fixedURLString) else {
            return
        }

        // Check cache first
        if let cachedImage = ImageCache.shared.get(forKey: urlString) {
            self.loadedImage = cachedImage
            return
        }

        // Download image
        isLoadingImage = true

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.loadedImage = image
                        self.isLoadingImage = false
                        ImageCache.shared.set(image, forKey: urlString)
                    }
                }
            } catch {
                print("[IMAGE_UPLOADER] ⚠️ Failed to load image from URL: \(error)")
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
}

// MARK: - Simple Image Picker

/// Simple wrapper around UIImagePickerController with closure-based API
struct SimpleImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true

        if sourceType == .camera {
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SimpleImagePicker

        init(_ parent: SimpleImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Preview

#Preview("Profile Image Uploader") {
    VStack(spacing: 40) {
        // User avatar style (circle)
        ProfileImageUploader(
            config: ImageUploaderConfig(
                placeholderText: "JS",
                size: 80,
                shape: .circle,
                allowDelete: true,
                backgroundColor: OPSStyle.Colors.primaryAccent
            ),
            onUpload: { image in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "https://example.com/image.jpg"
            },
            onDelete: {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )

        // Company logo style (rounded square)
        ProfileImageUploader(
            config: ImageUploaderConfig(
                placeholderText: "OPS",
                size: 100,
                shape: .roundedSquare(cornerRadius: 12),
                allowDelete: true,
                backgroundColor: OPSStyle.Colors.primaryAccent,
                uploadButtonText: "UPLOAD LOGO"
            ),
            onUpload: { image in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "https://example.com/logo.jpg"
            },
            onDelete: {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
    }
    .padding()
    .background(OPSStyle.Colors.background)
}
