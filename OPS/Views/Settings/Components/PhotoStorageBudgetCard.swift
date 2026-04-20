//
//  PhotoStorageBudgetCard.swift
//  OPS
//
//  Reusable UI for managing the photo storage budget. Surfaces:
//   - Current usage vs. budget (progress bar, byte counts, percentage)
//   - Device free space (context)
//   - Slider to adjust the budget — stages a pending change
//   - Apply card with context-sensitive preview of what Apply will do:
//       • Lowering below usage → "Will delete N photos (~M MB)"
//       • Raising limit       → "Gives X MB of headroom for new photos"
//       • Lowering above usage → "No photos will be deleted"
//   - Cap-hit banner when PhotoPrefetchService pauses at budget
//
//  Used in both PhotoStorageManagementView (sheet from All Photos gallery)
//  and DataStorageSettingsView (Settings → Data & Storage). Both surfaces
//  need the same controls; consolidating them prevents the "two sliders,
//  one is fake" trap we had before.
//

import SwiftUI
import SwiftData

struct PhotoStorageBudgetCard: View {
    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var downloadManager = PhotoDownloadManager.shared
    @ObservedObject private var prefetchService = PhotoPrefetchService.shared

    // MARK: - State

    @State private var capHitReport: PhotoPrefetchBudgetReport?

    /// Slider position in MB. Does NOT commit to profiler until Apply.
    @State private var budgetSliderMB: Double = 0
    /// Snapshot of committed budget (in MB). Used to detect hasPendingChange.
    @State private var committedBudgetMB: Double = 0
    @State private var didLoadInitialBudget = false

    // MARK: - Derived

    private var profiler: StorageProfiler { .shared }

    private var currentUsageBytes: Int64 { profiler.currentUsageBytes() }
    private var budgetBytes: Int64 { profiler.budgetBytes }

    private var usagePercent: Double {
        let budget = Double(budgetBytes)
        guard budget > 0 else { return 0 }
        return min(1.0, Double(currentUsageBytes) / budget)
    }

    private var isOverBudget: Bool { currentUsageBytes > budgetBytes }

    private var sliderMin: Double { Double(StorageProfiler.minBudget) / 1_048_576.0 }
    private var sliderMax: Double { Double(profiler.maxAllowedBudget()) / 1_048_576.0 }

    private var pendingBudgetBytes: Int64 { Int64(budgetSliderMB * 1_048_576) }

    private var hasPendingChange: Bool {
        abs(budgetSliderMB - committedBudgetMB) >= 1.0
    }

    private var wouldTriggerEviction: Bool { pendingBudgetBytes < currentUsageBytes }

    private var evictionPreview: (count: Int, bytesFreed: Int64) {
        downloadManager.previewEviction(
            projectsWithPhotos: projectsWithPhotosPayload,
            targetBudget: pendingBudgetBytes
        )
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

    /// Fetch projects through DataController. Eviction preview and real
    /// eviction need project recency to sort oldest-first.
    private var allProjects: [Project] {
        guard let ctx = dataController.modelContext else { return [] }
        let companyId = dataController.currentUser?.companyId ?? ""
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.companyId == companyId }
        )
        return ((try? ctx.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = capHitReport {
                capHitBanner(report: report)
            }

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

            if let free = profiler.currentDeviceFreeBytes() {
                Text("Device free: \(StorageProfiler.formatBytes(free))")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            // Slider — stages a pending change; commits via Apply
            VStack(alignment: .leading, spacing: 6) {
                Text("Adjust limit")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Slider(
                    value: $budgetSliderMB,
                    in: sliderMin...max(sliderMin + 1, sliderMax)
                )
                .tint(OPSStyle.Colors.primaryAccent)

                HStack {
                    Text(StorageProfiler.formatBytes(Int64(sliderMin * 1_048_576)))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                    Text(pendingBudgetLabel)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(hasPendingChange ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
                    Spacer()
                    Text(StorageProfiler.formatBytes(Int64(sliderMax * 1_048_576)))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            if hasPendingChange {
                applyPendingCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasPendingChange)
        .onAppear {
            if !didLoadInitialBudget {
                let initial = Double(budgetBytes) / 1_048_576.0
                budgetSliderMB = initial
                committedBudgetMB = initial
                didLoadInitialBudget = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .photoStorageBudgetExceeded)) { notification in
            if let report = notification.userInfo?["report"] as? PhotoPrefetchBudgetReport {
                capHitReport = report
            }
        }
    }

    // MARK: - Cap-hit banner

    private func capHitBanner(report: PhotoPrefetchBudgetReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                Text("STORAGE LIMIT REACHED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
            Text("\(report.photosRemaining) photo\(report.photosRemaining == 1 ? "" : "s") still to download. Raise your limit below to continue, or apply a smaller limit to delete oldest.")
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
    }

    // MARK: - Pending change card

    private var pendingBudgetLabel: String {
        if hasPendingChange {
            return "Pending: \(StorageProfiler.formatBytes(pendingBudgetBytes))"
        }
        return "Limit: \(StorageProfiler.formatBytes(pendingBudgetBytes))"
    }

    private var applyPendingCard: some View {
        let accent = wouldTriggerEviction ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: wouldTriggerEviction ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                    .foregroundColor(accent)
                Text(wouldTriggerEviction ? "REVIEW DELETION" : "PENDING CHANGE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(accent)
            }

            Text(applyCardBodyCopy)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: cancelPendingChange) {
                    Text("Cancel")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }

                Button(action: applyPendingChange) {
                    Text(wouldTriggerEviction ? "Apply & Delete" : "Apply")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
        .padding()
        .background(accent.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(accent, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private var applyCardBodyCopy: String {
        let newLimit = StorageProfiler.formatBytes(pendingBudgetBytes)

        if wouldTriggerEviction {
            let preview = evictionPreview
            if preview.count > 0 {
                let photoWord = preview.count == 1 ? "photo" : "photos"
                return "Reducing to \(newLimit) will delete \(preview.count) \(photoWord) (\(StorageProfiler.formatBytes(preview.bytesFreed))) from your oldest projects. Pinned photos are kept."
            }
            return "Reducing to \(newLimit) will trim photos from your oldest projects until usage fits."
        }

        if pendingBudgetBytes > Int64(committedBudgetMB * 1_048_576) {
            let headroom = pendingBudgetBytes - currentUsageBytes
            return "Raising to \(newLimit) gives OPS \(StorageProfiler.formatBytes(headroom)) of headroom. The next sync will download photos from your most recent projects to fill it (WiFi only by default)."
        }

        return "Set the limit to \(newLimit). Current usage fits — no photos will be deleted."
    }

    // MARK: - Actions

    private func cancelPendingChange() {
        budgetSliderMB = committedBudgetMB
    }

    private func applyPendingChange() {
        let newBytes = pendingBudgetBytes
        profiler.setBudget(newBytes)
        let resolvedBudget = profiler.budgetBytes

        if resolvedBudget < currentUsageBytes {
            let result = downloadManager.enforceCapacityPolicy(
                projectsWithPhotos: projectsWithPhotosPayload
            )
            print("[PhotoStorageBudgetCard] Apply+Delete: evicted \(result.deleted), freed \(StorageProfiler.formatBytes(result.bytesFreed))")
        } else {
            print("[PhotoStorageBudgetCard] Apply: budget set to \(StorageProfiler.formatBytes(resolvedBudget)); no eviction needed")
        }

        committedBudgetMB = Double(resolvedBudget) / 1_048_576.0
        budgetSliderMB = committedBudgetMB

        if !profiler.wouldExceedBudget(adding: 0) {
            capHitReport = nil
            resolveCapHitRailNotifications()
        }
    }

    private func resolveCapHitRailNotifications() {
        prefetchService.clearCapHitCooldown()
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"), !userId.isEmpty else {
            return
        }
        Task {
            do {
                try await NotificationRepository.shared.markAllAsReadByType(
                    type: "photo_storage_limit",
                    userId: userId
                )
                print("[PhotoStorageBudgetCard] Resolved photo_storage_limit rail notifications")
            } catch {
                print("[PhotoStorageBudgetCard] Failed to resolve rail notifications: \(error)")
            }
        }
    }
}
