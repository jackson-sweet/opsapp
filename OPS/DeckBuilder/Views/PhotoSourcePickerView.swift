// OPS/OPS/DeckBuilder/Views/PhotoSourcePickerView.swift

import SwiftUI
import SwiftData
import PhotosUI

struct PhotoSourcePickerView: View {
    let projectId: String?
    let onPhotoSelected: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryImages: [UIImage] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Source buttons
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    sourceButton(
                        icon: "camera.fill",
                        label: "Take Photo",
                        action: { showingCamera = true }
                    )

                    sourceButton(
                        icon: "photo.on.rectangle",
                        label: "Choose from Library",
                        action: { showingLibrary = true }
                    )
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)

                // Recent project photos
                if let projectId, !projectPhotoURLs(projectId: projectId).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECENT PROJECT PHOTOS")
                            .font(OPSStyle.Typography.smallCaption)
                            .tracking(0.5)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                ForEach(projectPhotoURLs(projectId: projectId), id: \.self) { urlString in
                                    projectPhotoThumbnail(urlString: urlString)
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing4)
                }

                Spacer()
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Select Site Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            OverlayCameraCapture { image in
                if let image {
                    onPhotoSelected(image)
                }
            }
        }
        .sheet(isPresented: $showingLibrary) {
            OverlayLibraryPicker(images: $libraryImages) {
                if let image = libraryImages.first {
                    onPhotoSelected(image)
                }
                libraryImages = []
            }
        }
    }

    // MARK: - Source Button

    private func sourceButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 28)

                Text(label)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Project Photo Thumbnail

    private func projectPhotoThumbnail(urlString: String) -> some View {
        Button {
            loadImageFromURL(urlString)
        } label: {
            PhotoThumbnail(url: urlString, project: nil)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
    }

    // MARK: - Helpers

    private func projectPhotoURLs(projectId: String) -> [String] {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        guard let project = try? modelContext.fetch(descriptor).first else { return [] }
        return project.getProjectImages()
    }

    private func loadImageFromURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        onPhotoSelected(image)
                    }
                }
            } catch {
                print("[PhotoSourcePicker] Failed to load project photo: \(error)")
            }
        }
    }
}

// MARK: - Camera Capture (UIImagePickerController wrapper)

private struct OverlayCameraCapture: UIViewControllerRepresentable {
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

// MARK: - Library Picker (PHPicker wrapper)

private struct OverlayLibraryPicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
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
        let parent: OverlayLibraryPicker

        init(parent: OverlayLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first,
                  result.itemProvider.canLoadObject(ofClass: UIImage.self) else { return }

            result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                if let image = image as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.images = [image]
                        self.parent.onComplete()
                    }
                }
            }
        }
    }
}
