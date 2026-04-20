//
//  PhotoStorageManagementView.swift
//  OPS
//
//  Capacity-aware photo storage management. Replaces the older time-based
//  "auto-keep" presets (1/3/6/12 months) with a device-capacity budget.
//  Budget is calibrated at first login by StorageProfiler; user can adjust
//  via the slider. Cleanup (via "Free Up Space") and prefetch pause are both
//  user-initiated — we never silently delete.
//

import SwiftUI

struct PhotoStorageManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var downloadManager = PhotoDownloadManager.shared
    @ObservedObject private var prefetchService = PhotoPrefetchService.shared

    let allPhotoItems: [PhotoItem]
    let allProjects: [Project]

    /// Standard entry point from AllPhotosGalleryView, which already has the
    /// enriched PhotoItem list (with annotations, authors, etc).
    init(allPhotoItems: [PhotoItem], allProjects: [Project]) {
        self.allPhotoItems = allPhotoItems
        self.allProjects = allProjects
    }

    /// Lightweight entry point for the notification-rail auto-navigate path.
    /// Builds a minimal PhotoItem list from projects alone (no annotations,
    /// no author metadata) — sufficient for the counts + per-project sections.
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
    @State private var capHitReport: PhotoPrefetchBudgetReport?
    @State private var budgetSliderMB: Double = 0
    @State private var didLoadInitialBudget = false

    // MARK: - Derived Values

    private var profiler: StorageProfiler { .shared }

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

    private var currentUsageBytes: Int64 {
        profiler.currentUsageBytes()
    }

    private var budgetBytes: Int64 {
        profiler.budgetBytes
    }

    private var usagePercent: Double {
        let budget = Double(budgetBytes)
        guard budget > 0 else { return 0 }
        return min(1.0, Double(currentUsageBytes) / budget)
    }

    private var isOverBudget: Bool {
        currentUsageBytes > budgetBytes
    }

    private var sliderMin: Double { Double(StorageProfiler.minBudget) / 1_048_576.0 }
    private var sliderMax: Double { Double(profiler.maxAllowedBudget()) / 1_048_576.0 }

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
                        if let report = capHitReport {
                            capHitBanner(report: report)
                        }

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
            .onAppear {
                if !didLoadInitialBudget {
                    budgetSliderMB = Double(budgetBytes) / 1_048_576.0
                    didLoadInitialBudget = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .photoStorageBudgetExceeded)) { notification in
                if let report = notification.userInfo?["report"] as? PhotoPrefetchBudgetReport {
                    capHitReport = report
                }
            }
        }
    }

    // MARK: - Sections

    private func capHitBanner(report: PhotoPrefetchBudgetReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                Text("STORAGE LIMIT REACHED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
            Text("\(report.photosRemaining) photo\(report.photosRemaining == 1 ? "" : "s") still to download. Raise your limit below, or free up space to continue.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(OPSStyle.Colors.warningStatus.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal, 20)
    }

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

            VStack(alignment: .leading, spacing: 12) {
                // Usage / budget header
                HStack {
                    Text(StorageProfiler.formatBytes(currentUsageBytes))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(isOverBudget ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
                    Text("of \(StorageProfiler.formatBytes(budgetBytes))")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                    Text("\(Int(usagePercent * 100))%")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                        Rectangle()
                            .fill(isOverBudget ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent)
                            .frame(width: geo.size.width * usagePercent)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 8)

                // Device free space context
                if let free = profiler.currentDeviceFreeBytes() {
                    Text("Device free: \(StorageProfiler.formatBytes(free))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                // Slider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adjust limit")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Slider(
                        value: $budgetSliderMB,
                        in: sliderMin...max(sliderMin + 1, sliderMax),
                        onEditingChanged: { editing in
                            if !editing {
                                profiler.setBudget(Int64(budgetSliderMB * 1_048_576))
                                // If budget was raised above current usage, clear the cap-hit banner
                                if !profiler.wouldExceedBudget(adding: 0) {
                                    capHitReport = nil
                                }
                            }
                        }
                    )
                    .tint(OPSStyle.Colors.primaryAccent)

                    HStack {
                        Text(StorageProfiler.formatBytes(Int64(sliderMin * 1_048_576)))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                        Text("Limit: \(StorageProfiler.formatBytes(Int64(budgetSliderMB * 1_048_576)))")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        Text(StorageProfiler.formatBytes(Int64(sliderMax * 1_048_576)))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
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

            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { prefetchService.isEnabled },
                    set: { prefetchService.isEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-download new photos")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("After each sync, download photos from your most recent projects")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .tint(OPSStyle.Colors.primaryAccent)
                .padding()

                OPSStyle.Colors.separator.frame(height: 1)

                Toggle(isOn: Binding(
                    get: { prefetchService.allowCellular },
                    set: { prefetchService.allowCellular = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow on cellular")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("Default off — only download over WiFi")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .tint(OPSStyle.Colors.primaryAccent)
                .padding()
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
        capHitReport = nil  // Budget likely OK now; re-appear if next sync exceeds again
    }
}
