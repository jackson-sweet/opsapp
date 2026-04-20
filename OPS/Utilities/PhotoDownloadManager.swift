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

    // MARK: - Auto-Keep Policy
    enum KeepPolicy: String, CaseIterable {
        case oneMonth = "1 Month"
        case threeMonths = "3 Months"
        case sixMonths = "6 Months"
        case twelveMonths = "12 Months"
        case allTime = "All Time"
        case manual = "Manual Only"

        var monthCount: Int? {
            switch self {
            case .oneMonth: return 1
            case .threeMonths: return 3
            case .sixMonths: return 6
            case .twelveMonths: return 12
            case .allTime: return nil
            case .manual: return nil  // nil = never auto-delete (same as allTime)
            }
        }
    }

    private let policyKey = "photoAutoKeepPolicy"
    private let pinnedKey = "photoPinnedURLs"
    private let keepAllKey = "photoKeepAllDownloaded"

    @Published var keepPolicy: KeepPolicy = .threeMonths {
        didSet {
            UserDefaults.standard.set(keepPolicy.rawValue, forKey: policyKey)
        }
    }

    /// URLs that the user has explicitly pinned to keep on-device (survive auto-keep policy cleanup)
    @Published var pinnedURLs: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(pinnedURLs) {
                UserDefaults.standard.set(data, forKey: pinnedKey)
            }
        }
    }

    /// When true, all photos are downloaded and kept on-device regardless of policy
    @Published var keepAllDownloaded: Bool = false {
        didSet {
            UserDefaults.standard.set(keepAllDownloaded, forKey: keepAllKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: policyKey) ?? KeepPolicy.threeMonths.rawValue
        self.keepPolicy = KeepPolicy(rawValue: raw) ?? .threeMonths
        self.keepAllDownloaded = UserDefaults.standard.bool(forKey: keepAllKey)

        if let data = UserDefaults.standard.data(forKey: pinnedKey),
           let urls = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.pinnedURLs = urls
        }
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
    func downloadPhoto(_ url: String) async -> Bool {
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        guard let imageURL = URL(string: cacheKey) else { return false }

        activeDownloads[url] = 0.0
        defer {
            activeDownloads.removeValue(forKey: url)
            cacheVersion += 1
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: imageURL)
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
    }

    /// Enforce auto-keep policy: remove photos older than policy date.
    /// Respects pinned URLs and keepAllDownloaded setting.
    ///
    /// DEPRECATED (photo-storage-capacity migration): replaced by
    /// `enforceCapacityPolicy(projectsWithPhotos:)`. The capacity-based approach
    /// evicts by oldest project rather than fixed time cutoffs, and scales to
    /// device capacity. This method kept for callers-in-transition; will be
    /// removed once PhotoStorageManagementView is rewritten.
    func enforceKeepPolicy(allPhotoURLs: [(url: String, date: Date)]) {
        // Never enforce cleanup when keep-all is enabled
        guard !keepAllDownloaded else { return }
        guard let months = keepPolicy.monthCount, months > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()

        for item in allPhotoURLs where item.date < cutoff {
            // Skip pinned photos — user explicitly chose to keep them
            if pinnedURLs.contains(item.url) { continue }
            if !item.url.hasPrefix("local://") {
                _ = removeFromDevice(item.url)
            }
        }
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

        for candidate in candidates {
            if currentUsage <= budget { break }

            let cacheKey = candidate.url.hasPrefix("//") ? "https:" + candidate.url : candidate.url
            let fileSize = ImageFileManager.shared.imageFileSize(localID: cacheKey) ?? 0

            if removeFromDevice(candidate.url) {
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
