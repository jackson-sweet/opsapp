//
//  PhotoDownloadManager.swift
//  OPS
//

import SwiftUI
import Foundation

/// Manages photo download state, download queue, and auto-keep date policy.
/// Uses ImageFileManager for disk operations and UserDefaults for policy storage.
@MainActor
class PhotoDownloadManager: ObservableObject {
    static let shared = PhotoDownloadManager()

    // MARK: - Published State
    @Published var activeDownloads: [String: Double] = [:]  // url -> progress (0.0-1.0)
    @Published private(set) var cacheVersion: Int = 0  // Bumped on cache changes to trigger view refresh

    // MARK: - Pinned URLs (user-selected keep list)

    private let pinnedKey = "photoPinnedURLs"

    /// URLs that the user has explicitly pinned to keep on-device. Pins count
    /// toward the storage budget (see StorageProfiler) but are never auto-evicted
    /// by capacity cleanup — user chose them.
    @Published var pinnedURLs: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(pinnedURLs) {
                UserDefaults.standard.set(data, forKey: pinnedKey)
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: pinnedKey),
           let urls = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.pinnedURLs = urls
        }

        // One-time migration: remove defunct keys from the pre-capacity era.
        // Safe to call on every launch — UserDefaults.removeObject is idempotent.
        UserDefaults.standard.removeObject(forKey: "photoAutoKeepPolicy")
        UserDefaults.standard.removeObject(forKey: "photoKeepAllDownloaded")
    }

    // MARK: - Pin / Unpin

    /// Pin a photo URL so it stays on-device even after auto-keep policy cleanup
    func pin(_ url: String) {
        pinnedURLs.insert(url)
    }

    /// Unpin a photo URL, allowing it to be removed by auto-keep policy
    func unpin(_ url: String) {
        pinnedURLs.remove(url)
    }

    /// Check if a photo URL is pinned
    func isPinned(_ url: String) -> Bool {
        pinnedURLs.contains(url)
    }

    /// Pin multiple photo URLs at once
    func pinAll(_ urls: [String]) {
        pinnedURLs.formUnion(urls)
    }

    /// Download all photos that are not yet on-device (used for "keep all downloaded")
    func downloadAllPhotos(_ urls: [String]) async -> Int {
        var downloaded = 0
        for url in urls where !isOnDevice(url) {
            if await downloadPhoto(url) {
                downloaded += 1
            }
        }
        return downloaded
    }

    // MARK: - On-Device Detection

    /// Check if a photo URL has a cached file on disk (lightweight — checks file existence, not full image load)
    func isOnDevice(_ url: String) -> Bool {
        // Asset catalog images are always available
        if !url.contains("://") && !url.hasPrefix("//") {
            return true
        }
        // Local and remote: check if file exists on disk
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        return ImageFileManager.shared.imageExists(localID: url) ||
               ImageFileManager.shared.imageExists(localID: cacheKey)
    }

    /// Count on-device photos from a list of URLs
    func onDeviceCount(from urls: [String]) -> Int {
        urls.filter { isOnDevice($0) }.count
    }

    // MARK: - Download

    /// Download a single photo and cache to disk
    func downloadPhoto(_ url: String, timeout: TimeInterval? = nil) async -> Bool {
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        guard let imageURL = URL(string: cacheKey) else { return false }

        activeDownloads[url] = 0.0
        defer {
            activeDownloads.removeValue(forKey: url)
            cacheVersion += 1
        }

        do {
            var request = URLRequest(url: imageURL)
            if let timeout, timeout > 0 {
                request.timeoutInterval = timeout
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  UIImage(data: data) != nil else {
                return false
            }

            activeDownloads[url] = 1.0
            let saved = ImageFileManager.shared.saveImage(data: data, localID: cacheKey)
            if saved {
                if let image = UIImage(data: data) {
                    ImageCache.shared.set(image, forKey: cacheKey)
                }
            }
            return saved
        } catch {
            return false
        }
    }

    /// Download all photos for a project
    func downloadAllForProject(_ photos: [String]) async -> Int {
        var downloaded = 0
        for url in photos where !isOnDevice(url) {
            if await downloadPhoto(url) {
                downloaded += 1
            }
        }
        return downloaded
    }

    /// Delete local cache for a photo
    func removeFromDevice(_ url: String) -> Bool {
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        ImageCache.shared.remove(forKey: cacheKey)
        let result = ImageFileManager.shared.deleteImage(localID: cacheKey)
        cacheVersion += 1
        return result
    }

    /// Clear all cached remote photos and bump version to refresh views
    func clearAllCachedPhotos() {
        ImageFileManager.shared.clearRemoteImageCache()
        ImageCache.shared.clear()
        cacheVersion += 1
        // Clearing always leaves the user under budget — resolve any
        // outstanding cap-hit rail notifications so the user isn't left
        // staring at a persistent warning after they've already acted on it.
        PhotoPrefetchService.shared.resolveCapHitRailNotifications()
    }

    /// Dry-run of enforceCapacityPolicy against a hypothetical target budget.
    /// Used by the settings UI to show "Will delete N photos (~X MB)" before
    /// the user commits a budget reduction. Walks the same candidate ordering
    /// as the real eviction (pinned skipped, oldest-project-first) but makes
    /// no mutations.
    ///
    /// - Parameters:
    ///   - projectsWithPhotos: same tuple shape as enforceCapacityPolicy
    ///   - targetBudget: hypothetical budget in bytes to test against
    /// - Returns: `(count, bytesFreed)` — how many photos would evict and how
    ///   many bytes would be reclaimed. Zero/zero if the hypothetical budget
    ///   already covers current usage.
    func previewEviction(
        projectsWithPhotos: [(projectUpdatedAt: Date, photoURLs: [String])],
        targetBudget: Int64
    ) -> (count: Int, bytesFreed: Int64) {
        var currentUsage = StorageProfiler.shared.currentUsageBytes()
        guard currentUsage > targetBudget else { return (0, 0) }

        var candidates: [(projectDate: Date, url: String)] = []
        for project in projectsWithPhotos {
            for url in project.photoURLs where !pinnedURLs.contains(url) {
                candidates.append((project.projectUpdatedAt, url))
            }
        }
        candidates.sort { $0.projectDate < $1.projectDate }

        var count = 0
        var bytes: Int64 = 0
        for candidate in candidates {
            if currentUsage <= targetBudget { break }
            let cacheKey = candidate.url.hasPrefix("//") ? "https:" + candidate.url : candidate.url
            guard let fileSize = ImageFileManager.shared.imageFileSize(localID: cacheKey), fileSize > 0 else {
                continue  // File not on disk — not a real eviction candidate
            }
            count += 1
            bytes += fileSize
            currentUsage -= fileSize
        }
        return (count, bytes)
    }

    /// Capacity-based cleanup: evict photos from oldest-updated projects first
    /// until on-disk usage drops below `StorageProfiler.shared.budgetBytes`.
    ///
    /// - Pinned photos are SKIPPED (they still count toward budget but are never
    ///   auto-deleted — user chose to keep them).
    /// - Eviction is user-initiated only (via cap-hit notification action or
    ///   "Free Up Space" in settings). This method never runs automatically.
    /// - Oldest-project-first ordering: a project with 50 photos that hasn't
    ///   been touched in 6 months loses all 50 before a project touched last
    ///   week loses any.
    ///
    /// - Parameter projectsWithPhotos: caller supplies `(projectUpdatedAt, photoURLs)`
    ///   tuples for every project containing cached photos. The caller is
    ///   responsible for filtering to the user's permission scope.
    /// - Returns: `(deleted, bytesFreed)` — count of photo files removed and
    ///   total bytes reclaimed.
    @discardableResult
    func enforceCapacityPolicy(
        projectsWithPhotos: [(projectUpdatedAt: Date, photoURLs: [String])]
    ) -> (deleted: Int, bytesFreed: Int64) {
        let profiler = StorageProfiler.shared
        let budget = profiler.budgetBytes
        var currentUsage = profiler.currentUsageBytes()

        guard currentUsage > budget else {
            print("[PhotoDownloadManager] Capacity policy: under budget (\(StorageProfiler.formatBytes(currentUsage)) of \(StorageProfiler.formatBytes(budget))) — nothing to evict")
            return (0, 0)
        }

        // Flatten to (projectDate, url) pairs. Skip pinned URLs — they count
        // toward the budget but are never candidates for eviction.
        var candidates: [(projectDate: Date, url: String)] = []
        for project in projectsWithPhotos {
            for url in project.photoURLs where !pinnedURLs.contains(url) {
                candidates.append((project.projectUpdatedAt, url))
            }
        }

        // Oldest projects first.
        candidates.sort { $0.projectDate < $1.projectDate }

        var deleted = 0
        var bytesFreed: Int64 = 0

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for candidate in candidates {
            if currentUsage <= budget { break }

            let cacheKey = candidate.url.hasPrefix("//") ? "https:" + candidate.url : candidate.url
            // Skip candidates not actually on disk. Without this guard, missing/
            // zero-byte files still invoke removeFromDevice but contribute 0 to
            // bytesFreed, so the loop exhausts all candidates while
            // currentUsage never drops below budget.
            guard let fileSize = ImageFileManager.shared.imageFileSize(localID: cacheKey), fileSize > 0 else {
                continue
            }

            if removeFromDevice(candidate.url) {
                // Per-photo eviction log for test verification. Chronological
                // ordering (oldest project date first) should be visible in
                // the printed sequence.
                let dateStr = dateFormatter.string(from: candidate.projectDate)
                let urlTail = String(candidate.url.suffix(48))
                print("[PhotoDownloadManager] Evicted project-date=\(dateStr) url=…\(urlTail)")

                deleted += 1
                bytesFreed += fileSize
                currentUsage -= fileSize
            }
        }

        print("[PhotoDownloadManager] Capacity policy: evicted \(deleted) photo(s), freed \(StorageProfiler.formatBytes(bytesFreed)) — now at \(StorageProfiler.formatBytes(currentUsage)) of \(StorageProfiler.formatBytes(budget))")
        return (deleted, bytesFreed)
    }

    // MARK: - Storage Estimation (cached — call sparingly, not in computed properties)

    /// Estimate total on-device photo storage in bytes (lightweight — uses file attributes, not data loading)
    func estimateStorageBytes(urls: [String]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            let cacheKey = url.hasPrefix("//") ? "https:" + url : url
            if let size = ImageFileManager.shared.imageFileSize(localID: cacheKey) {
                total += size
            }
        }
        return total
    }

    /// Format bytes as human-readable string
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
