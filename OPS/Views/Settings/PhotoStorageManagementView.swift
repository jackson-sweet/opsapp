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
    /// Skips the eager PhotoItem materialization — totals and breakdown are
    /// computed asynchronously in `refreshBreakdown()` off the main actor.
    init(allProjects: [Project]) {
        self.allProjects = allProjects
        self.allPhotoItems = []
    }

    // MARK: - State

    @State private var showClearConfirmation = false
    @State private var showFreeUpConfirmation = false

    // MARK: - Cache
    //
    // All per-project filesystem inspection happens in `refreshBreakdown()`
    // off the main actor. SwiftUI body evaluations read these plain @State
    // values, so slider drags and scroll don't trigger thousands of
    // FileManager calls per frame.

    @State private var cachedBreakdown: [ProjectSummary] = []
    @State private var cachedTotalOnDevice: Int = 0
    @State private var cachedTotalPhotos: Int = 0
    @State private var isLoadingBreakdown: Bool = true

    struct ProjectSummary: Identifiable {
        let id: String
        let title: String
        let photos: [String]
        let onDeviceCount: Int
        let bytesOnDevice: Int64
        var allOnDevice: Bool { onDeviceCount == photos.count }
    }

    // MARK: - Derived

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
                    Task { await refreshBreakdown() }
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
            .task {
                await refreshBreakdown()
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("[ ON DEVICE ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if isLoadingBreakdown {
                Text("Calculating…")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                Text("\(cachedTotalOnDevice) of \(cachedTotalPhotos) photos")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
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
                if isLoadingBreakdown {
                    HStack {
                        ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        Text("Scanning project photos…")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(cachedBreakdown) { item in
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .lineLimit(1)

                                    Text("\(item.photos.count) photos · \(item.onDeviceCount) on device · \(StorageProfiler.formatBytes(item.bytesOnDevice))")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }

                                Spacer()

                                if item.allOnDevice {
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

                        if item.id != cachedBreakdown.last?.id {
                            OPSStyle.Colors.separator
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
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
        // If free-up got us back under budget, clear the rail warning. When
        // pinned photos exhaust the budget on their own, eviction can't free
        // enough and the warning legitimately stays — only resolve when we
        // actually made it under.
        if !StorageProfiler.shared.wouldExceedBudget(adding: 0) {
            PhotoPrefetchService.shared.resolveCapHitRailNotifications()
        }
        Task { await refreshBreakdown() }
    }

    // MARK: - Cache Refresh

    /// Builds the per-project breakdown off the main actor. Captures project
    /// snapshots (id, title, photo URLs) on main, then walks the filesystem
    /// in a detached task so SwiftUI can render the sheet immediately with a
    /// "Calculating…" state.
    private func refreshBreakdown() async {
        isLoadingBreakdown = true

        // Snapshot what we need from SwiftData on main — the detached task
        // can't safely touch Project models.
        struct ProjectSnapshot {
            let id: String
            let title: String
            let photos: [String]
        }
        let snapshots: [ProjectSnapshot] = allProjects.compactMap { project in
            let photos = project.getProjectImages()
            guard !photos.isEmpty else { return nil }
            return ProjectSnapshot(id: project.id, title: project.title, photos: photos)
        }

        let summaries: [ProjectSummary] = await Task.detached {
            snapshots.map { snap -> ProjectSummary in
                var onDevice = 0
                var bytes: Int64 = 0
                for url in snap.photos {
                    let cacheKey = url.hasPrefix("//") ? "https:" + url : url
                    guard let size = ImageFileManager.shared.imageFileSize(localID: cacheKey),
                          size > 0 else { continue }
                    onDevice += 1
                    bytes += size
                }
                return ProjectSummary(
                    id: snap.id,
                    title: snap.title,
                    photos: snap.photos,
                    onDeviceCount: onDevice,
                    bytesOnDevice: bytes
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }.value

        cachedBreakdown = summaries
        cachedTotalOnDevice = summaries.reduce(0) { $0 + $1.onDeviceCount }
        cachedTotalPhotos = summaries.reduce(0) { $0 + $1.photos.count }
        isLoadingBreakdown = false
        print("[PhotoStorageManagementView] Breakdown refreshed — \(summaries.count) projects, \(cachedTotalOnDevice)/\(cachedTotalPhotos) on device")
    }
}
