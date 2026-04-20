//
//  PhotoPrefetchService.swift
//  OPS
//
//  Background-fetches project photos so they're available offline without the
//  user having to manually open each photo first.
//
//  Trigger: called by SyncEngine after every successful full or delta sync.
//  Respects:
//   - The user's permission scope (we only iterate locally-synced projects,
//     which are already scope-filtered by the sync layer)
//   - The photo storage budget (never auto-evicts — pauses and notifies instead)
//   - The network (WiFi-only by default; cellular opt-in via UserDefaults)
//   - The user's pinned-photo selection (pins skip the download path only in
//     that they're guaranteed not to be evicted; pins themselves still count
//     toward budget)
//
//  Order: projects with the most-recent activity first. Activity score is the
//  max of (startDate, endDate, lastSyncedAt) — this surfaces projects the
//  user is actively working on before archived work.
//
//  Cap-hit behaviour: when the next candidate photo would exceed the budget,
//  the service posts `.photoStorageBudgetExceeded` (Notification.Name) with a
//  `PhotoPrefetchBudgetReport` payload. The cap-hit handler (P4) presents the
//  user options: "Increase Limit" or "Delete Oldest". We never silently evict.
//

import Foundation
import SwiftData
import Network

extension Notification.Name {
    /// Posted when the photo prefetch service pauses because adding the next
    /// photo would exceed the user's storage budget.
    /// userInfo["report"] is a PhotoPrefetchBudgetReport.
    static let photoStorageBudgetExceeded = Notification.Name("photoStorageBudgetExceeded")
}

/// Snapshot of budget state at the moment prefetch paused. Delivered via
/// NotificationCenter for the cap-hit UI to act on.
struct PhotoPrefetchBudgetReport {
    let currentUsageBytes: Int64
    let budgetBytes: Int64
    let photosRemaining: Int
    let estimatedRemainingBytes: Int64
}

@MainActor
final class PhotoPrefetchService: ObservableObject {
    static let shared = PhotoPrefetchService()

    // MARK: - Published State

    @Published private(set) var isPrefetching: Bool = false
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var lastRunDownloaded: Int = 0
    @Published private(set) var lastRunSkippedForBudget: Int = 0

    // MARK: - UserDefaults Keys

    private enum Key {
        static let allowCellular = "photoPrefetch.allowCellular"
        static let enabled = "photoPrefetch.enabled"
    }

    // MARK: - Preferences

    /// Master toggle. Default true. User-facing switch in Settings (P4).
    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.enabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.enabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.enabled) }
    }

    /// When true, prefetch runs on cellular too. Default false (WiFi-only).
    var allowCellular: Bool {
        get { UserDefaults.standard.bool(forKey: Key.allowCellular) }
        set { UserDefaults.standard.set(newValue, forKey: Key.allowCellular) }
    }

    private init() {}

    // MARK: - Public Entry Point

    /// Kick off a prefetch pass. Idempotent — returns immediately if a pass is
    /// already in flight. Fire-and-forget: safe to call from any sync
    /// completion hook; failures are logged, not thrown.
    func prefetchIfAppropriate(modelContext: ModelContext, connectivity: ConnectivityManager) {
        guard !isPrefetching else {
            print("[PhotoPrefetch] Already running — skipping")
            return
        }

        guard isEnabled else {
            print("[PhotoPrefetch] Disabled in settings — skipping")
            return
        }

        guard shouldRunOnCurrentNetwork(connectivity) else {
            print("[PhotoPrefetch] Network not suitable (cellular with allowCellular=false, or offline) — skipping")
            return
        }

        Task { [weak self] in
            await self?.runPrefetch(modelContext: modelContext, connectivity: connectivity)
        }
    }

    // MARK: - Prefetch Core

    private func runPrefetch(modelContext: ModelContext, connectivity: ConnectivityManager) async {
        isPrefetching = true
        defer { isPrefetching = false }

        let profiler = StorageProfiler.shared
        let downloader = PhotoDownloadManager.shared

        let startUsage = profiler.currentUsageBytes()
        let budget = profiler.budgetBytes
        print("[PhotoPrefetch] Starting pass — \(StorageProfiler.formatBytes(startUsage)) of \(StorageProfiler.formatBytes(budget)) used")

        // Pull all local projects — sync layer has already scope-filtered, so
        // this list reflects the user's permission scope.
        let projects: [Project]
        do {
            projects = try modelContext.fetch(FetchDescriptor<Project>())
        } catch {
            print("[PhotoPrefetch] Fetch projects failed: \(error)")
            return
        }

        // Sort projects by activity recency (most recent first). Activity score
        // = max(startDate, endDate, lastSyncedAt). A project with a scheduled
        // start next week wins over one that synced last month with no dates.
        let ordered = projects
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                activityScore(for: lhs) > activityScore(for: rhs)
            }

        var downloaded = 0
        var skippedForBudget = 0

        for project in ordered {
            // Cooperative cancellation: bail if prefetch was disabled or the
            // network flipped mid-pass.
            if Task.isCancelled { break }
            guard isEnabled, shouldRunOnCurrentNetwork(connectivity) else {
                print("[PhotoPrefetch] Conditions changed mid-pass — stopping")
                break
            }

            let photoURLs = project.getProjectImages()
            guard !photoURLs.isEmpty else { continue }

            for url in photoURLs {
                // Skip asset catalog / non-http URLs — they're local-only anyway
                guard url.contains("://") || url.hasPrefix("//") else { continue }
                // Skip if already on disk
                guard !downloader.isOnDevice(url) else { continue }

                // Budget check. We don't know the target photo size until we
                // fetch it; use a conservative estimate (2.5 MB per photo —
                // typical JPEG from a modern phone camera at default quality).
                let estimate: Int64 = 2_500_000
                if profiler.wouldExceedBudget(adding: estimate) {
                    skippedForBudget += 1
                    // Count remaining photos across all projects for the cap-hit report
                    let remaining = countRemainingPhotos(from: ordered, startingFrom: project, skippingUpTo: url)
                    postBudgetExceededNotification(
                        currentUsage: profiler.currentUsageBytes(),
                        budget: budget,
                        remaining: remaining,
                        estimatedRemaining: Int64(remaining) * estimate
                    )
                    lastRunDownloaded = downloaded
                    lastRunSkippedForBudget = skippedForBudget
                    lastRunAt = Date()
                    print("[PhotoPrefetch] Paused at budget — downloaded \(downloaded), skipped \(skippedForBudget) remaining")
                    return
                }

                let success = await downloader.downloadPhoto(url)
                if success { downloaded += 1 }
            }
        }

        lastRunDownloaded = downloaded
        lastRunSkippedForBudget = skippedForBudget
        lastRunAt = Date()
        print("[PhotoPrefetch] Pass complete — downloaded \(downloaded), skipped \(skippedForBudget) (budget)")
    }

    // MARK: - Helpers

    /// Composite recency score for project ordering. Projects that the user is
    /// actively working on (scheduled today, ending tomorrow) should rank above
    /// projects that last saw server activity but are otherwise dormant.
    private func activityScore(for project: Project) -> Date {
        var best = Date.distantPast
        if let d = project.startDate, d > best { best = d }
        if let d = project.endDate, d > best { best = d }
        if let d = project.lastSyncedAt, d > best { best = d }
        return best
    }

    /// WiFi-only by default. Returns true if prefetch should proceed given the
    /// current connection. Cellular is permitted only when `allowCellular`
    /// is set by the user.
    private func shouldRunOnCurrentNetwork(_ connectivity: ConnectivityManager) -> Bool {
        guard connectivity.shouldAttemptSync else { return false }
        if allowCellular { return true }
        return connectivity.state.type == .wifi || connectivity.state.type == .wiredEthernet
    }

    /// Counts the photos across `projects` from `startingFrom` onward that
    /// aren't yet on disk. Used to populate the cap-hit report.
    private func countRemainingPhotos(
        from projects: [Project],
        startingFrom current: Project,
        skippingUpTo url: String
    ) -> Int {
        guard let startIdx = projects.firstIndex(where: { $0.id == current.id }) else { return 0 }
        let downloader = PhotoDownloadManager.shared
        var count = 0
        var seenStartURL = false

        for project in projects[startIdx...] {
            for candidate in project.getProjectImages() {
                if project.id == current.id && !seenStartURL {
                    if candidate == url { seenStartURL = true }
                    else { continue }
                }
                guard candidate.contains("://") || candidate.hasPrefix("//") else { continue }
                if !downloader.isOnDevice(candidate) { count += 1 }
            }
        }
        return count
    }

    private func postBudgetExceededNotification(
        currentUsage: Int64,
        budget: Int64,
        remaining: Int,
        estimatedRemaining: Int64
    ) {
        let report = PhotoPrefetchBudgetReport(
            currentUsageBytes: currentUsage,
            budgetBytes: budget,
            photosRemaining: remaining,
            estimatedRemainingBytes: estimatedRemaining
        )
        NotificationCenter.default.post(
            name: .photoStorageBudgetExceeded,
            object: nil,
            userInfo: ["report": report]
        )
    }
}

