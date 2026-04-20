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

                // Probe the photo's actual size via HEAD before committing the
                // download. S3 / ops-web presigned URLs both return Content-Length
                // on HEAD. Fall back to a 2.5 MB estimate if HEAD fails so the
                // prefetch still progresses — we just use the less-accurate value
                // for the budget check.
                let probedSize = await probeContentLength(urlString: url) ?? fallbackSizeEstimate

                if profiler.wouldExceedBudget(adding: probedSize) {
                    skippedForBudget += 1
                    let remaining = countRemainingPhotos(from: ordered, startingFrom: project, skippingUpTo: url)
                    postBudgetExceededNotification(
                        currentUsage: profiler.currentUsageBytes(),
                        budget: budget,
                        remaining: remaining,
                        estimatedRemaining: Int64(remaining) * fallbackSizeEstimate
                    )
                    lastRunDownloaded = downloaded
                    lastRunSkippedForBudget = skippedForBudget
                    lastRunAt = Date()
                    print("[PhotoPrefetch] Paused at budget — downloaded \(downloaded), next photo would need \(StorageProfiler.formatBytes(probedSize))")
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

    // MARK: - Constants

    /// Fallback size when HEAD can't tell us the real Content-Length. Typical
    /// JPEG from a modern phone camera at default quality settings.
    private let fallbackSizeEstimate: Int64 = 2_500_000

    /// Timeout for the HEAD request used to probe photo size. Short so a bad
    /// network doesn't delay prefetch materially; on timeout we use the fallback
    /// estimate and proceed.
    private let headProbeTimeout: TimeInterval = 5

    // MARK: - Helpers

    /// Issues a HEAD request against `urlString` and returns the Content-Length,
    /// if the server provides one. Returns nil on error / timeout / missing header.
    /// Cheap (~10-50 ms on WiFi) and caches nothing — called once per photo during prefetch.
    private func probeContentLength(urlString: String) async -> Int64? {
        let normalized = urlString.hasPrefix("//") ? "https:" + urlString : urlString
        guard let url = URL(string: normalized) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = headProbeTimeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            // Try Content-Length first (standard); fall back to expectedContentLength
            // which URLSession computes from the same header.
            if let lengthString = http.value(forHTTPHeaderField: "Content-Length"),
               let length = Int64(lengthString), length > 0 {
                return length
            }
            if http.expectedContentLength > 0 {
                return http.expectedContentLength
            }
            return nil
        } catch {
            return nil
        }
    }

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
        // Local event for views/banners to observe (used by PhotoStorageManagementView).
        NotificationCenter.default.post(
            name: .photoStorageBudgetExceeded,
            object: nil,
            userInfo: ["report": report]
        )

        // Persist the event to the in-app notification rail so the user sees
        // it even without opening Photo Storage settings. Cooldown-gated so
        // we don't spam the rail on every sync when budget stays full.
        Task { [report] in
            await postCapHitRailNotification(report: report)
        }
    }

    // MARK: - Rail Notification Integration

    /// Cooldown between rail notifications so repeated cap-hits don't spam the
    /// rail. A single rail entry stays until the user addresses it.
    private static let railNotificationCooldown: TimeInterval = 24 * 60 * 60  // 24 hours

    private enum RailKey {
        static let lastPostedAt = "photoStorage.lastCapHitRailPostAt"
    }

    /// Inserts a persistent cap-hit notification into the Supabase notifications
    /// table so it appears in the in-app notification rail. De-duped via a
    /// 24-hour cooldown — if we posted one recently, we skip.
    private func postCapHitRailNotification(report: PhotoPrefetchBudgetReport) async {
        // Cooldown: don't flood the rail if sync keeps hitting cap
        if let lastPost = UserDefaults.standard.object(forKey: RailKey.lastPostedAt) as? Date {
            let elapsed = Date().timeIntervalSince(lastPost)
            if elapsed < Self.railNotificationCooldown {
                print("[PhotoPrefetch] Skipping rail notification — last posted \(Int(elapsed / 3600))h ago")
                return
            }
        }

        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"), !userId.isEmpty else {
            print("[PhotoPrefetch] Skipping rail notification — no currentUserId")
            return
        }
        guard let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId"), !companyId.isEmpty else {
            print("[PhotoPrefetch] Skipping rail notification — no currentUserCompanyId")
            return
        }

        let photos = report.photosRemaining
        let photoPhrase = photos == 1 ? "1 photo" : "\(photos) photos"
        let title = "Photo storage limit reached"
        let body = "\(photoPhrase) couldn't download. Open Settings → Photo Storage to raise your limit or free up space."

        let dto = NotificationRepository.CreateNotificationDTO(
            userId: userId,
            companyId: companyId,
            type: "photo_storage_limit",
            title: title,
            body: body,
            deepLinkType: "photoStorage",
            persistent: true,
            actionLabel: "Manage Storage"
        )

        do {
            try await NotificationRepository.shared.createNotification(dto)
            UserDefaults.standard.set(Date(), forKey: RailKey.lastPostedAt)
            print("[PhotoPrefetch] Posted cap-hit rail notification (\(photoPhrase))")
        } catch {
            print("[PhotoPrefetch] Failed to post rail notification: \(error)")
        }
    }
}

