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

    // MARK: - Cache
    //
    // Populated once on appear (and after Apply) by `refreshCache()` which
    // runs expensive directory walks + eviction candidate builds off the
    // main thread. Every body evaluation reads from these @State values so
    // SwiftUI can re-render the slider at 60 fps without stalling on
    // FileManager work that used to re-run on every frame.

    @State private var cachedUsageBytes: Int64 = 0
    @State private var cachedBudgetBytes: Int64 = 0
    @State private var cachedMaxBudget: Int64 = 0
    @State private var cachedDeviceFree: Int64?
    /// Sorted oldest-project-first. Each entry already carries its on-disk
    /// file size so eviction preview is an in-memory O(n) sum — no FileManager
    /// calls per slider frame.
    @State private var cachedCandidates: [EvictionCandidate] = []
    @State private var isLoadingCache = true

    struct EvictionCandidate {
        let projectDate: Date
        let url: String
        let fileSize: Int64
    }

    // MARK: - Derived

    private var profiler: StorageProfiler { .shared }

    private var currentUsageBytes: Int64 { cachedUsageBytes }
    private var budgetBytes: Int64 { cachedBudgetBytes }

    private var usagePercent: Double {
        let budget = Double(budgetBytes)
        guard budget > 0 else { return 0 }
        return min(1.0, Double(currentUsageBytes) / budget)
    }

    private var isOverBudget: Bool { currentUsageBytes > budgetBytes }

    private var sliderMin: Double { Double(StorageProfiler.minBudget) / 1_048_576.0 }
    private var sliderMax: Double {
        let maxBudget = cachedMaxBudget > 0 ? cachedMaxBudget : StorageProfiler.minBudget
        return Double(maxBudget) / 1_048_576.0
    }

    private var pendingBudgetBytes: Int64 { Int64(budgetSliderMB * 1_048_576) }

    private var hasPendingChange: Bool {
        abs(budgetSliderMB - committedBudgetMB) >= 1.0
    }

    private var wouldTriggerEviction: Bool { pendingBudgetBytes < currentUsageBytes }

    /// Counts how many of the pre-sorted, pre-sized candidates would need to
    /// evict to reach the slider's target budget. Pure in-memory walk —
    /// cheap enough to run on every body evaluation (slider drags etc.).
    private var evictionPreview: (count: Int, bytesFreed: Int64) {
        guard pendingBudgetBytes < cachedUsageBytes else { return (0, 0) }
        let toFree = cachedUsageBytes - pendingBudgetBytes
        var count = 0
        var freed: Int64 = 0
        for c in cachedCandidates {
            if freed >= toFree { break }
            count += 1
            freed += c.fileSize
        }
        return (count, freed)
    }

    /// Rebuilds the per-project payload shape that `enforceCapacityPolicy`
    /// expects. Uses the already-cached candidates so we don't re-walk disk.
    private var projectsWithPhotosPayload: [(projectUpdatedAt: Date, photoURLs: [String])] {
        var grouped: [Date: [String]] = [:]
        for c in cachedCandidates {
            grouped[c.projectDate, default: []].append(c.url)
        }
        return grouped.map { (projectUpdatedAt: $0.key, photoURLs: $0.value) }
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
                // Seed cached budget from UserDefaults (nonisolated, instant)
                // so the slider can position itself before the async cache
                // refresh finishes.
                let storedBudget = profiler.budgetBytes
                cachedBudgetBytes = storedBudget
                let initial = Double(storedBudget) / 1_048_576.0
                budgetSliderMB = initial
                committedBudgetMB = initial
                didLoadInitialBudget = true
            }
        }
        .task {
            await refreshCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: .photoStorageBudgetExceeded)) { notification in
            if let report = notification.userInfo?["report"] as? PhotoPrefetchBudgetReport {
                capHitReport = report
            }
        }
    }

    // MARK: - Cache Refresh

    /// Populates the heavy @State caches without blocking main. The directory
    /// walks and per-photo file-size probes run on a detached task; only the
    /// SwiftData fetch (needed for project recency ordering) hops back to
    /// main. When this finishes the UI flips from "Calculating…" to real
    /// numbers and the slider/preview become fully interactive.
    private func refreshCache() async {
        isLoadingCache = true

        // SwiftData fetch must be on main actor. Fast for ~hundreds of rows.
        let projectPayloads: [(date: Date, urls: [String])] = await MainActor.run {
            guard let ctx = dataController.modelContext else { return [] }
            let companyId = dataController.currentUser?.companyId ?? ""
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.companyId == companyId }
            )
            let projects = ((try? ctx.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
            return projects.compactMap { project -> (date: Date, urls: [String])? in
                let urls = project.getProjectImages()
                    .filter { $0.contains("://") || $0.hasPrefix("//") }
                guard !urls.isEmpty else { return nil }
                let score = max(
                    project.startDate ?? .distantPast,
                    project.endDate ?? .distantPast,
                    project.lastSyncedAt ?? .distantPast
                )
                return (date: score, urls: urls)
            }
        }

        let pinned = await MainActor.run { downloadManager.pinnedURLs }

        // All heavy filesystem work happens off main. StorageProfiler's
        // usage/budget methods are `nonisolated` so they're safe here.
        let result = await Task.detached {
            let usage = StorageProfiler.shared.currentUsageBytes()
            let free = StorageProfiler.shared.currentDeviceFreeBytes()
            let maxBudget = StorageProfiler.shared.maxAllowedBudget()

            var candidates: [EvictionCandidate] = []
            for project in projectPayloads {
                for url in project.urls where !pinned.contains(url) {
                    let cacheKey = url.hasPrefix("//") ? "https:" + url : url
                    guard let size = ImageFileManager.shared.imageFileSize(localID: cacheKey),
                          size > 0 else { continue }
                    candidates.append(EvictionCandidate(
                        projectDate: project.date,
                        url: url,
                        fileSize: size
                    ))
                }
            }
            candidates.sort { $0.projectDate < $1.projectDate }
            return (usage: usage, free: free, maxBudget: maxBudget, candidates: candidates)
        }.value

        cachedUsageBytes = result.usage
        cachedDeviceFree = result.free
        cachedMaxBudget = result.maxBudget
        cachedCandidates = result.candidates
        cachedBudgetBytes = profiler.budgetBytes
        isLoadingCache = false
        print("[PhotoStorageBudgetCard] Cache refreshed — usage=\(StorageProfiler.formatBytes(result.usage)), candidates=\(result.candidates.count)")
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
            prefetchService.resolveCapHitRailNotifications()
        }

        // Refresh the cache after mutation so usage / candidates reflect the
        // post-eviction state without a full view rebuild.
        Task { await refreshCache() }
    }
}
