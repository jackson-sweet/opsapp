//
//  PhotoStorageManagementView.swift
//  OPS
//
//  Per-project photo storage breakdown + capacity management. The budget
//  slider + Apply card + cap-hit banner live in the reusable
//  PhotoStorageBudgetCard component; this view composes that with the
//  per-project list and action buttons specific to the All Photos context.
//

import SwiftUI

struct PhotoStorageManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var downloadManager = PhotoDownloadManager.shared

    let allPhotoItems: [PhotoItem]
    let allProjects: [Project]

    /// Standard entry point from AllPhotosGalleryView, which already has the
    /// enriched PhotoItem list (with annotations, authors, etc).
    init(allPhotoItems: [PhotoItem], allProjects: [Project]) {
        self.allPhotoItems = allPhotoItems
        self.allProjects = allProjects
    }

    /// Lightweight entry point for the notification-rail auto-navigate path.
    /// Builds a minimal PhotoItem list from projects alone.
    init(allProjects: [Project]) {
        self.allProjects = allProjects
        self.allPhotoItems = allProjects.flatMap { project in
            project.getProjectImages().map { url in
                PhotoItem(
                    id: url,
                    url: url,
                    projectId: project.id,
                    projectTitle: project.title,
                    date: project.lastSyncedAt ?? Date(),
                    authorId: nil,
                    note: nil,
                    searchHaystack: ""
                )
            }
        }
    }

    // MARK: - State

    @State private var showClearConfirmation = false
    @State private var showFreeUpConfirmation = false

    // MARK: - Derived

    private var projectBreakdown: [(project: Project, photos: [String], onDeviceCount: Int)] {
        allProjects
            .compactMap { project -> (project: Project, photos: [String], onDeviceCount: Int)? in
                let photos = project.getProjectImages()
                guard !photos.isEmpty else { return nil }
                let onDevice = downloadManager.onDeviceCount(from: photos)
                return (project: project, photos: photos, onDeviceCount: onDevice)
            }
            .sorted { $0.project.title.localizedCaseInsensitiveCompare($1.project.title) == .orderedAscending }
    }

    private var totalOnDevice: Int {
        downloadManager.onDeviceCount(from: allPhotoItems.map { $0.url })
    }

    private var totalPhotos: Int {
        allPhotoItems.count
    }

    private var projectsWithPhotosPayload: [(projectUpdatedAt: Date, photoURLs: [String])] {
        allProjects.compactMap { project in
            let urls = project.getProjectImages().filter { $0.contains("://") || $0.hasPrefix("//") }
            guard !urls.isEmpty else { return nil }
            let score = max(
                project.startDate ?? .distantPast,
                project.endDate ?? .distantPast,
                project.lastSyncedAt ?? .distantPast
            )
            return (projectUpdatedAt: score, photoURLs: urls)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        summarySection
                        budgetSection
                        prefetchPreferencesSection
                        projectBreakdownSection
                        actionsSection
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PHOTO STORAGE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: OPSStyle.Icons.chevronLeft)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            }
            .alert("Clear All Photos?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    downloadManager.clearAllCachedPhotos()
                }
            } message: {
                Text("This will remove all cached photos from your device. Photos will still be available in the cloud.")
            }
            .alert("Free Up Space?", isPresented: $showFreeUpConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Oldest", role: .destructive) {
                    freeUpSpace()
                }
            } message: {
                Text("This will delete cached photos from your oldest projects until you're back under your budget. Pinned photos are kept.")
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("[ ON DEVICE ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("\(totalOnDevice) of \(totalPhotos) photos")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("[ STORAGE BUDGET ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            PhotoStorageBudgetCard()
                .environmentObject(dataController)
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .padding(.horizontal, 20)
    }

    private var prefetchPreferencesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("[ AUTO-DOWNLOAD ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            PhotoPrefetchPreferencesCard()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .padding(.horizontal, 20)
    }

    private var projectBreakdownSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("[ BY PROJECT ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                ForEach(projectBreakdown, id: \.project.id) { item in
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.project.title)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)

                                let bytes = downloadManager.estimateStorageBytes(urls: item.photos.filter { downloadManager.isOnDevice($0) })
                                Text("\(item.photos.count) photos · \(item.onDeviceCount) on device · \(StorageProfiler.formatBytes(bytes))")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }

                            Spacer()

                            if item.onDeviceCount == item.photos.count {
                                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                    .foregroundColor(OPSStyle.Colors.successStatus)
                            } else {
                                Button(action: {
                                    Task { await downloadManager.downloadAllForProject(item.photos) }
                                }) {
                                    Text("Download")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }

                    if item.project.id != projectBreakdown.last?.project.id {
                        OPSStyle.Colors.separator
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .padding(.horizontal, 20)
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: { showFreeUpConfirmation = true }) {
                Text("Free Up Space (Delete Oldest)")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.warningStatus, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }

            Button(action: { showClearConfirmation = true }) {
                Text("Clear All Local Photos")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func freeUpSpace() {
        let result = downloadManager.enforceCapacityPolicy(
            projectsWithPhotos: projectsWithPhotosPayload
        )
        print("[PhotoStorageManagementView] Freed \(result.deleted) photos (\(StorageProfiler.formatBytes(result.bytesFreed)))")
    }
}
