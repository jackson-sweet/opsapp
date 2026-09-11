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
//  Order: projects closest to "happening now" first. Priority is distance
//  (in seconds) from today to the nearer of startDate/endDate — so the
//  project the user is on today leads, then work scheduled next week, then
//  recently finished work, then archives. Future-only far-out projects rank
//  by their start date's distance. Undated projects fall back to lastSyncedAt
//  with a fixed penalty so any dated project outranks them.
//
//  Previous scheme used max(startDate, endDate, lastSyncedAt) as a single
//  date. Because sync refreshes lastSyncedAt for every project on every
//  pass, that score collapsed — old and new projects landed at the same
//  "now" value, sort order became unstable, and the budget cap cut off
//  active work because archived jobs had already eaten the quota.
//
//  Cap-hit behaviour: when the next candidate photo would exceed the budget,
//  the service posts `.photoStorageBudgetExceeded` (Notification.Name) with a
//  `PhotoPrefetchBudgetReport` payload. The cap-hit handler (P4) presents the
//  user options: "Increase Limit" or "Delete Oldest". We never silently evict.
//

import Foundation
import SwiftData
import Network
import UIKit

extension Notification.Name {
    /// Posted when the photo prefetch service pauses because adding the next
    /// photo would exceed the user's storage budget.
    /// userInfo["report"] is a PhotoPrefetchBudgetReport.
    static let photoStorageBudgetExceeded = Notification.Name("photoStorageBudgetExceeded")
}

// MARK: - Cap-Hit Rail Notification

/// Seam for the photo-storage cap rail row. Conformed to by
/// `NotificationRepository` (the `sync_photo_storage_limit_notification` RPC);
/// tests substitute a spy.
protocol PhotoStorageLimitNotifying {
    /// Returns `created` or `kept`. The server resolves the actor itself and
    /// holds at most one unread row per device, so repeated reports from the
    /// same phone cannot stack.
    @discardableResult
    func syncPhotoStorageLimit(photosRemaining: Int, deviceName: String) async throws -> String
}

extension NotificationRepository: PhotoStorageLimitNotifying {}

/// Reports a cap hit to the rail and decides whether the local cooldown should
/// start. Lifted out of the service so the verdict handling is testable
/// without UserDefaults or a network.
enum PhotoStorageLimitRailDispatcher {

    /// `created` wrote a fresh row; `kept` means the server is already holding
    /// an unread notice for this device. Both mean the rail is telling the
    /// truth right now, so both start the cooldown — with the server owning
    /// at-most-one-unread-per-device, the client cooldown is a call-rate
    /// optimization, not the dedupe itself. A throw stamps nothing: the next
    /// sync must stay free to report the cap again.
    static func dispatch(
        photosRemaining: Int,
        deviceName: String,
        syncer: PhotoStorageLimitNotifying = NotificationRepository.shared,
        markPosted: () -> Void
    ) async {
        let verdict: String
        do {
            verdict = try await syncer.syncPhotoStorageLimit(
                photosRemaining: photosRemaining,
                deviceName: deviceName
            )
        } catch {
            print("[PhotoPrefetch] Failed to post rail notification: \(error)")
            return
        }

        guard verdict == "created" || verdict == "kept" else {
            print("[PhotoPrefetch] Rail notification returned '\(verdict)' — cooldown not started")
            return
        }

        markPosted()
        print("[PhotoPrefetch] Cap-hit rail notification \(verdict) (\(photosRemaining) photos)")
    }
}

/// Snapshot of budget state at the moment prefetch paused. Delivered via
/// NotificationCenter for the cap-hit UI to act on.
struct PhotoPrefetchBudgetReport {
    let currentUsageBytes: Int64
    let budgetBytes: Int64
    let photosRemaining: Int
    let estimatedRemainingBytes: Int64
}

struct PhotoPrefetchWarmupResult {
    let planned: Int
    let downloaded: Int
    let alreadyOnDevice: Int
    let skippedForBudget: Int
    let timedOut: Bool
    let duration: TimeInterval
}

@MainActor
final class PhotoPrefetchService: ObservableObject {
    static let shared = PhotoPrefetchService()

    // MARK: - Published State

    @Published private(set) var isPrefetching: Bool = false
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var lastRunDownloaded: Int = 0
    @Published private(set) var lastRunSkippedForBudget: Int = 0

    /// Handle to the in-flight prefetch task. Retained so logout (or any
    /// other teardown path) can cancel the pass and prevent downloads from
    /// completing under a signed-out user's directory.
    private var prefetchTask: Task<Void, Never>?
    private var prefetchTaskID: UUID?

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

        // ModelContext does not own its container. Capture it synchronously,
        // before the queued task or profiler await can outlive the caller.
        startPrefetch(container: modelContext.container, connectivity: connectivity)
    }

    private func startPrefetch(container: ModelContainer, connectivity: ConnectivityManager) {
        prefetchTask?.cancel()
        let id = UUID()
        prefetchTaskID = id
        isPrefetching = true
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.prefetchTaskID == id {
                    self.prefetchTask = nil
                    self.prefetchTaskID = nil
                    self.isPrefetching = false
                }
            }
            await self.runPrefetch(container: container, connectivity: connectivity)
        }
    }

    #if DEBUG
    private var beforeSnapshotForTesting: (() async -> Void)?
    static func isolatedForTesting() -> PhotoPrefetchService { PhotoPrefetchService() }
    /// Runs the real queued worker without network-admission timing in fixtures.
    func startPrefetchForTesting(
        context: ModelContext,
        connectivity: ConnectivityManager,
        beforeSnapshot: @escaping () async -> Void
    ) -> Task<Void, Never>? {
        beforeSnapshotForTesting = beforeSnapshot
        startPrefetch(container: context.container, connectivity: connectivity)
        return prefetchTask
    }
    #endif

    /// Cancel any in-flight prefetch pass. Call from the logout path so we
    /// don't keep pulling photos under a signed-out user. No-op if nothing
    /// is running.
    func cancelPrefetch() {
        guard let task = prefetchTask else { return }
        print("[PhotoPrefetch] Cancelling in-flight prefetch")
        task.cancel()
        prefetchTask = nil
        prefetchTaskID = nil
        isPrefetching = false
    }

    // MARK: - Prefetch Core

    private func runPrefetch(container: ModelContainer, connectivity: ConnectivityManager) async {
        guard !Task.isCancelled else { return }

        let profiler = StorageProfiler.shared
        let downloader = PhotoDownloadManager.shared

        let startUsage = await profiler.backgroundUsageBytes(reconcile: true)
        guard !Task.isCancelled else { return }
        #if DEBUG
        await beforeSnapshotForTesting?()
        guard !Task.isCancelled else { return }
        #endif
        let budget = profiler.budgetBytes
        print("[PhotoPrefetch] Starting pass — \(StorageProfiler.formatBytes(startUsage)) of \(StorageProfiler.formatBytes(budget)) used")

        let plan: PhotoPrefetchPlan
        do {
            plan = try await PhotoPrefetchProjectReader.plan(
                container: container, now: Date(),
                warmupProjectCap: firstLoadWarmupProjectCap, warmupPhotoCap: firstLoadWarmupPhotoCap
            )
        } catch {
            print("[PhotoPrefetch] Project snapshot failed: \(error)")
            return
        }
        let warmup = await runCriticalWarmup(
            urls: plan.warmupURLs, connectivity: connectivity,
            profiler: profiler, downloader: downloader
        )
        if warmup.planned > 0 {
            print("[PhotoPrefetch] First-load warmup — planned \(warmup.planned), downloaded \(warmup.downloaded), already \(warmup.alreadyOnDevice), budget \(warmup.skippedForBudget), timedOut=\(warmup.timedOut), \(String(format: "%.2f", warmup.duration))s")
        }

        var downloaded = 0
        var skippedForBudget = 0

        for (index, url) in plan.orderedURLs.enumerated() {
            if Task.isCancelled { break }
            guard isEnabled, shouldRunOnCurrentNetwork(connectivity) else { break }
            guard !(await Self.isOnDisk(url)) else { continue }
            let probedSize = await probeContentLength(urlString: url) ?? fallbackSizeEstimate
            if Task.isCancelled { break }
            guard let reservation = await PhotoCacheLedger.shared.reserveInBackground(bytes: probedSize, budget: profiler.budgetBytes) else {
                skippedForBudget += 1
                let remaining = await Self.missingCount(Array(plan.orderedURLs[index...]))
                let usage = await profiler.backgroundUsageBytes()
                postBudgetExceededNotification(currentUsage: usage, budget: budget, remaining: remaining,
                    estimatedRemaining: Int64(remaining) * fallbackSizeEstimate)
                break
            }
            if Task.isCancelled || !isEnabled || !shouldRunOnCurrentNetwork(connectivity) {
                PhotoCacheLedger.shared.release(reservation)
                break
            }
            let success = await downloader.downloadPhoto(url, cacheReservation: reservation)
            PhotoCacheLedger.shared.release(reservation)
            if success { downloaded += 1 }
        }

        guard !Task.isCancelled else { return }
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

    /// Initial Home photo warmup budget. This happens before the broader
    /// prefetch pass so the first visible jobs are not blocked behind a single
    /// old project with many photos.
    private let firstLoadWarmupDuration: TimeInterval = 8
    private let firstLoadWarmupProjectCap = 8
    private let firstLoadWarmupPhotoCap = 18

    // MARK: - Helpers

    private func runCriticalWarmup(
        urls: [String],
        connectivity: ConnectivityManager,
        profiler: StorageProfiler,
        downloader: PhotoDownloadManager
    ) async -> PhotoPrefetchWarmupResult {
        let startedAt = Date()

        var downloaded = 0
        var alreadyOnDevice = 0
        var skippedForBudget = 0
        var timedOut = false

        for url in urls {
            if Task.isCancelled { break }
            guard isEnabled, shouldRunOnCurrentNetwork(connectivity) else { break }

            let elapsed = Date().timeIntervalSince(startedAt)
            guard elapsed < firstLoadWarmupDuration else {
                timedOut = true
                break
            }

            guard !(await Self.isOnDisk(url)) else {
                alreadyOnDevice += 1
                continue
            }

            guard let reservation = await PhotoCacheLedger.shared.reserveInBackground(bytes: fallbackSizeEstimate, budget: profiler.budgetBytes) else {
                skippedForBudget += 1
                continue
            }
            if Task.isCancelled {
                PhotoCacheLedger.shared.release(reservation)
                break
            }

            let remaining = max(0.5, firstLoadWarmupDuration - elapsed)
            if await downloader.downloadPhoto(url, timeout: min(4, remaining), cacheReservation: reservation) {
                downloaded += 1
            }
            PhotoCacheLedger.shared.release(reservation)
        }

        return PhotoPrefetchWarmupResult(
            planned: urls.count,
            downloaded: downloaded,
            alreadyOnDevice: alreadyOnDevice,
            skippedForBudget: skippedForBudget,
            timedOut: timedOut,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

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

    private nonisolated static func isOnDisk(_ url: String) async -> Bool {
        ImageFileManager.shared.imageExists(localID: url)
    }

    private nonisolated static func missingCount(_ urls: [String]) async -> Int {
        urls.filter { !ImageFileManager.shared.imageExists(localID: $0) }.count
    }

    /// WiFi-only by default. Returns true if prefetch should proceed given the
    /// current connection. Cellular is permitted only when `allowCellular`
    /// is set by the user.
    private func shouldRunOnCurrentNetwork(_ connectivity: ConnectivityManager) -> Bool {
        guard connectivity.shouldAttemptSync else { return false }
        if allowCellular { return true }
        return connectivity.state.type == .wifi || connectivity.state.type == .wiredEthernet
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

    /// Clears the rail-notification cooldown timestamp. Called after the user
    /// resolves a cap-hit (via slider increase or Free Up Space) so the next
    /// legitimate cap-hit can post a new rail notification without waiting for
    /// the 24-hour window to expire.
    func clearCapHitCooldown() {
        UserDefaults.standard.removeObject(forKey: RailKey.lastPostedAt)
    }

    /// Clears the cooldown AND marks any outstanding `photo_storage_limit`
    /// rail notifications as read. Call this from any path that makes the
    /// cap-hit state no longer true: budget raised, photos cleared, free-up
    /// succeeded, etc. Safe to call even when there's nothing to resolve.
    func resolveCapHitRailNotifications() {
        clearCapHitCooldown()
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"), !userId.isEmpty else {
            return
        }
        Task {
            do {
                try await NotificationRepository.shared.markAllAsReadByType(
                    type: "photo_storage_limit",
                    userId: userId
                )
                print("[PhotoPrefetch] Resolved photo_storage_limit rail notifications")
            } catch {
                print("[PhotoPrefetch] Failed to resolve rail notifications: \(error)")
            }
        }
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

        // Name the device so the notification is actionable when read on the
        // web rail / another device — the storage cap is a per-device local
        // cache limit, and the user needs to know which one filled up (bug
        // d5da3d51). @MainActor class, so UIDevice.current is safe to read.
        // The server resolves the actor and their company from the session and
        // renders the copy from these two values.
        let deviceName = UIDevice.current.name

        await PhotoStorageLimitRailDispatcher.dispatch(
            photosRemaining: report.photosRemaining,
            deviceName: deviceName
        ) {
            UserDefaults.standard.set(Date(), forKey: RailKey.lastPostedAt)
        }
    }
}
