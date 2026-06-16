//
//  SharePhotoToProjectSheet.swift
//  OPS
//
//  In-app photo → project attach flow (Bug 1b7e59f7).
//
//  Lets the user pick one or more photos from their Photos library, then
//  pick a project to attach them to. Re-usable from any entry point. A
//  future iOS Share Extension target can call into this same flow.
//
//  Why this component exists without a full Share Extension: the extension
//  requires Xcode project target additions (Info.plist, entitlements, app
//  group) which are out of scope for an agent sweep. This component
//  provides the functional equivalent — pick a photo, pick a project,
//  attach — so users can import library photos into projects today.
//

import SwiftUI
import SwiftData
import PhotosUI

struct SharePhotoToProjectSheet: View {
    /// Optional pre-selected photos (e.g. if the sheet is invoked with
    /// photos already chosen by an upstream picker). When nil, the sheet
    /// starts at the photo-selection step.
    let initialPhotos: [UIImage]

    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var loadedImages: [UIImage] = []
    @State private var isLoadingPhotos = false
    @State private var selectedProject: Project?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var projectSearchText = ""

    @Query(
        filter: #Predicate<Project> { project in
            project.deletedAt == nil
        },
        sort: \Project.lastSyncedAt,
        order: .reverse
    ) private var allProjects: [Project]

    private var visibleProjects: [Project] {
        // Exclude closed/archived so users don't accidentally attach
        // photos to a completed project.
        let active = allProjects.filter { project in
            project.status != .closed && project.status != .archived
        }
        if projectSearchText.isEmpty { return active }
        let query = projectSearchText.lowercased()
        return active.filter { project in
            project.title.lowercased().contains(query) ||
            (project.effectiveClientName.lowercased().contains(query))
        }
    }

    init(initialPhotos: [UIImage] = [], onDismiss: @escaping () -> Void = {}) {
        self.initialPhotos = initialPhotos
        self.onDismiss = onDismiss
        self._loadedImages = State(initialValue: initialPhotos)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                content
            }
            .standardSheetToolbar(
                title: "Attach to Project",
                actionText: "Attach",
                isActionEnabled: canAttach,
                isSaving: isUploading,
                onCancel: {
                    onDismiss()
                    dismiss()
                },
                onAction: { attachAndDismiss() }
            )
        }
        .errorToast($uploadError, label: Feedback.Err.uploadFailed)
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task { await loadPhotoItems(newItems) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                photosSection
                projectSection
            }
            .padding(OPSStyle.Layout.spacing3)
            .padding(.bottom, 80)
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("PHOTOS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if loadedImages.isEmpty {
                photoPickerButton
            } else {
                photoGrid
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "plus.circle")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("Add more photos")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    private var photoPickerButton: some View {
        PhotosPicker(
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        ) {
            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text("Select from Photos")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("Up to 10 photos at a time")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing5)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
            GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
            GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2)
        ], spacing: OPSStyle.Layout.spacing2) {
            ForEach(Array(loadedImages.enumerated()), id: \.offset) { index, image in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 100)
                        .clipped()
                        .cornerRadius(OPSStyle.Layout.buttonRadius)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        loadedImages.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6).clipShape(Circle()))
                            .padding(OPSStyle.Layout.spacing1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                TextField("Search projects", text: $projectSearchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if !projectSearchText.isEmpty {
                    Button {
                        projectSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            // Project list
            VStack(spacing: 0) {
                ForEach(visibleProjects.prefix(20)) { project in
                    projectRow(project)
                    if project.id != visibleProjects.prefix(20).last?.id {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorderSubtle)
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }
                if visibleProjects.isEmpty {
                    Text(projectSearchText.isEmpty ? "No active projects" : "No matches")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing4)
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let isSelected = selectedProject?.id == project.id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedProject = project
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Text(project.effectiveClientName)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.text)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Actions

    private var canAttach: Bool {
        !loadedImages.isEmpty && selectedProject != nil && !isUploading
    }

    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        var newImages: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                newImages.append(image)
            }
        }

        await MainActor.run {
            loadedImages.append(contentsOf: newImages)
            selectedPhotoItems = [] // reset for additive adds
        }
    }

    private func attachAndDismiss() {
        guard let project = selectedProject, !loadedImages.isEmpty else { return }

        isUploading = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let images = loadedImages
        Task { @MainActor in
            defer { isUploading = false }

            // imageSyncManager is an implicitly-unwrapped optional on
            // DataController; treat it defensively in case the setup method
            // hasn't run yet (shouldn't happen in practice but don't crash).
            if dataController.imageSyncManager != nil {
                let urls = await dataController.imageSyncManager.saveImages(images, for: project)
                if urls.isEmpty {
                    uploadError = "Upload failed. Check your connection and try again."
                    return
                }
            } else {
                // Local fallback — encode and save to disk.
                for image in images {
                    guard let data = image.jpegData(compressionQuality: 0.7) else { continue }
                    let localID = "project_\(project.id)_\(UUID().uuidString).jpg"
                    if ImageFileManager.shared.saveImage(data: data, localID: localID) {
                        var existing = project.getProjectImages()
                        existing.append("local://project_images/\(localID)")
                        project.setProjectImageURLs(existing)
                    }
                }
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(Feedback.Photo.uploaded)
            onDismiss()
            dismiss()
        }
    }
}
