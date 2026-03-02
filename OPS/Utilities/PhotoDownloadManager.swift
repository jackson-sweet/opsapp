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

    @Published var keepPolicy: KeepPolicy = .threeMonths {
        didSet {
            UserDefaults.standard.set(keepPolicy.rawValue, forKey: policyKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: policyKey) ?? KeepPolicy.threeMonths.rawValue
        self.keepPolicy = KeepPolicy(rawValue: raw) ?? .threeMonths
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

    /// Enforce auto-keep policy: remove photos older than policy date
    func enforceKeepPolicy(allPhotoURLs: [(url: String, date: Date)]) {
        guard let months = keepPolicy.monthCount, months > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()

        for item in allPhotoURLs where item.date < cutoff {
            if !item.url.hasPrefix("local://") {
                _ = removeFromDevice(item.url)
            }
        }
    }

    // MARK: - Storage Estimation (cached — call sparingly, not in computed properties)

    /// Estimate total on-device photo storage in bytes
    func estimateStorageBytes(urls: [String]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            let cacheKey = url.hasPrefix("//") ? "https:" + url : url
            if let data = ImageFileManager.shared.getImageData(localID: cacheKey) {
                total += Int64(data.count)
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
