//
//  ImageFileManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import UIKit
import Foundation
import CryptoKit

/// Helper for managing image storage in the file system instead of UserDefaults
class ImageFileManager {
    static let shared = ImageFileManager()
    
    private init() {
        // Create directory if it doesn't exist
        createDirectoryIfNeeded()
    }
    
    // Get the documents directory
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // Get the images directory
    private var imagesDirectory: URL {
        documentsDirectory.appendingPathComponent("ProjectImages", isDirectory: true)
    }
    
    // Create the images directory if it doesn't exist
    private func createDirectoryIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            do {
                try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            } catch {
            }
        }
    }
    
    /// Normalize a URL to ensure consistent caching regardless of protocol prefix
    private func normalizeURL(_ url: String) -> String {
        // Handle // prefix by adding https:
        if url.hasPrefix("//") {
            return "https:" + url
        }
        return url
    }

    /// Encode a remote URL to make it safe for use as a file name
    private func encodeRemoteURL(_ url: String) -> String {
        // Normalize URL first for consistent hashing
        let normalizedURL = normalizeURL(url)

        // Use SHA256 hash to create a unique, fixed-length identifier
        let data = normalizedURL.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        // Extract the filename from the URL if possible to make debugging easier
        var filenameSuffix = ""
        if let urlComponents = URL(string: normalizedURL),
           let filename = urlComponents.lastPathComponent.split(separator: ".").first {
            // Take last 20 characters of the filename
            filenameSuffix = "_" + String(filename.suffix(20))
        }

        // Return a combination of hash prefix and filename for uniqueness and debuggability
        return "remote_\(hashString.prefix(32))\(filenameSuffix)"
    }
    
    /// Get the file URL for a local image identifier
    func getFileURL(for localID: String) -> URL? {
        // Handle remote URLs
        if localID.hasPrefix("http") || localID.hasPrefix("//") {
            let encodedID = encodeRemoteURL(localID)
            return imagesDirectory.appendingPathComponent(encodedID)
        }

        // Handle already-encoded remote URLs (e.g., "remote_xxxxx") plus the two
        // derived caches that live beside them as opaque, pre-encoded filenames:
        //   overlay_<annotationId>          — transparent PNG markup overlay
        //   composited_remote_<hash><tail>  — flattened photo+markup display image
        // These previously fell through to the `nil` return below, so every
        // saveImage / loadImage with such a key was a silent no-op (overlays
        // re-downloaded on every composite; composites had nowhere durable to
        // live). Treating them as direct filenames closes both gaps.
        if localID.hasPrefix("remote_")
            || localID.hasPrefix("overlay_")
            || localID.hasPrefix("composited_") {
            return imagesDirectory.appendingPathComponent(localID)
        }

        // Extract filename from localID (format: "local://project_images/filename.jpg")
        guard localID.hasPrefix("local://project_images/") else {
            return nil
        }

        let components = localID.components(separatedBy: "/")
        guard let filename = components.last else {
            return nil
        }

        return imagesDirectory.appendingPathComponent(filename)
    }
    
    /// Lightweight file existence check (no image decode)
    func imageExists(localID: String) -> Bool {
        guard let fileURL = getFileURL(for: localID) else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Save image data to file system
    ///
    /// For remote-image caches (URLs / pre-encoded `remote_` keys) this enforces
    /// the photo storage budget by evicting the oldest cached remote images,
    /// skipping pinned ones, until the incoming write fits. Local upload-pending
    /// images (`local://project_images/...`) bypass the budget — they can't be
    /// re-fetched from the cloud and are the user's only copy until upload.
    func saveImage(data: Data, localID: String, reservation: UUID? = nil, allowEviction: Bool = true) -> Bool {
        guard let fileURL = getFileURL(for: localID) else { return false }
        let saved = PhotoCacheLedger.shared.write(
            data: data, to: fileURL,
            budget: isRemoteCacheKey(localID) ? StorageProfiler.budgetSnapshot() : nil,
            reservation: reservation, allowEviction: allowEviction,
            pinnedFilenames: loadPinnedRemoteFilenames()
        )
        if saved { notifyThumbnailChange(localID) }
        return saved
    }

    private func notifyThumbnailChange(_ localID: String) {
        NotificationCenter.default.post(name: .photoThumbnailSourceChanged, object: nil,
                                        userInfo: ["sourceURL": localID])
    }

    /// True if `localID` represents a remote (server-side) photo that's been
    /// downloaded into the local cache, OR a flattened markup composite derived
    /// from one. Both are subject to the photo storage budget. Local
    /// upload-pending images and the tiny `overlay_` PNGs are not — overlays are
    /// the only local copy of pending markup and re-downloading them defeats the
    /// instant-composite cache.
    private func isRemoteCacheKey(_ localID: String) -> Bool {
        localID.hasPrefix("http") || localID.hasPrefix("//")
            || localID.hasPrefix("remote_") || localID.hasPrefix("composited_remote_")
    }

    /// Pinned URLs serialised by PhotoDownloadManager. Stored as a Set<String>
    /// of remote URLs; we hash them to the on-disk filename so callers can ask
    /// "is the file currently on disk pinned by the user?". Direct UserDefaults
    /// read keeps ImageFileManager free of an actor dependency on
    /// PhotoDownloadManager (which is @MainActor).
    private func loadPinnedRemoteFilenames() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: "photoPinnedURLs"),
              let urls = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        var filenames = Set<String>()
        for url in urls {
            let normalized = url.hasPrefix("//") ? "https:" + url : url
            let remoteName = encodeRemoteURL(normalized)
            filenames.insert(remoteName)
            // A pinned photo's flattened markup composite is pinned too — keep
            // the annotated version available offline alongside the original.
            filenames.insert("composited_" + remoteName)
        }
        return filenames
    }

    /// Walks `imagesDirectory` for cached remote photos (`remote_*` files),
    /// oldest-mtime first, and deletes them until on-disk usage plus
    /// `bytesNeeded` fits under `budget`. Skips pinned files. Idempotent —
    /// returns immediately when there is already enough headroom.
    ///
    /// Why this lives here, not in PhotoDownloadManager: PhotoDownloadManager is
    /// @MainActor, and the file-system walk + delete needs to run nonisolated
    /// alongside `saveImage` so any save path (sync, gallery viewer, comment
    /// viewer, etc.) gets the same enforcement without an actor hop.
    @discardableResult
    func evictRemoteImagesIfNeeded(bytesNeeded: Int64, budget: Int64) -> Int64 {
        PhotoCacheLedger.shared.evict(bytesNeeded: bytesNeeded, budget: budget, pinned: loadPinnedRemoteFilenames())
    }

    /// Load image data from file system
    func loadImage(localID: String) -> UIImage? {
        // For remote URLs, we still need to handle them, but check file system first
        // instead of UserDefaults, since we now save them to disk
        if localID.hasPrefix("http") || localID.hasPrefix("//") {
            let encodedID = encodeRemoteURL(localID)
            
            // Try to load from file system first
            if let fileURL = getFileURL(for: encodedID),
               FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    return UIImage(data: data)
                } catch {
                }
            }
            
            // For backward compatibility - check UserDefaults as fallback
            if let cachedData = UserDefaults.standard.data(forKey: localID) {
                // Migrate to file system for future use
                if saveImage(data: cachedData, localID: encodedID) {
                    UserDefaults.standard.removeObject(forKey: localID)
                }
                
                return UIImage(data: cachedData)
            }
        }
        
        // Otherwise load from file system
        guard let fileURL = getFileURL(for: localID) else {
            return nil
        }
        
        // Check if file exists in file system
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                return UIImage(data: data)
            } catch {
                return nil
            }
        }
        
        // Migration: Try loading from UserDefaults if not in file system
        if let base64String = UserDefaults.standard.string(forKey: localID),
           let data = Data(base64Encoded: base64String) {
            
            // Save to file system for future use
            if saveImage(data: data, localID: localID) {
                UserDefaults.standard.removeObject(forKey: localID)
            }
            
            return UIImage(data: data)
        }
        
        return nil
    }
    
    /// Delete image from file system
    func deleteImage(localID: String) -> Bool {
        guard let fileURL = getFileURL(for: localID) else {
            return false
        }
        
        // Also remove from UserDefaults if it exists there (for migration)
        UserDefaults.standard.removeObject(forKey: localID)
        
        let removed = PhotoCacheLedger.shared.remove(fileURL)
        if removed { notifyThumbnailChange(localID) }
        return removed
    }

    /// Get the file size in bytes without loading data into memory
    func imageFileSize(localID: String) -> Int64? {
        guard let fileURL = getFileURL(for: localID) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
    }

    /// Last-modified timestamp of a cached file, without decoding it. Used by
    /// the compositor's freshness check (composite mtime vs annotation
    /// `updatedAt`) to skip re-rendering unchanged markup.
    func imageModificationDate(localID: String) -> Date? {
        guard let fileURL = getFileURL(for: localID) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return date
    }

    // MARK: - Composited Markup Cache (durable annotation overlay)
    //
    // A composite is the source photo with its PencilKit markup flattened on
    // top, persisted so any thumbnail can resolve markup the instant it mounts —
    // independent of the volatile in-memory `ImageCache` (a 50 MB NSCache that
    // holds barely one full-resolution composite). The on-disk composite is a
    // SEPARATE asset from the raw original (distinct `composited_` filename), so
    // the two coexist: readers resolve composite-first, raw-second; base-image
    // loaders and the annotation editor always read the raw. Keyed by the photo
    // URL via `encodeRemoteURL`, so a photo's composite shares the raw's hash
    // identity (pin-mapping + eviction skip work without reversing the hash).

    /// On-disk localID for a photo's flattened markup composite.
    /// `encodeRemoteURL` normalises (`//` → `https:`) and hashes, so every
    /// reader/writer that passes the source URL addresses the same file.
    func compositedLocalID(forURL url: String) -> String {
        (url.hasPrefix("local://") ? "composited_local_" : "composited_") + encodeRemoteURL(url)
    }

    /// Read-through compatibility for local composites written before local
    /// pending composites received their protected cache namespace.
    func compositedReadLocalID(forURL url: String) -> String {
        let preferred = compositedLocalID(forURL: url)
        if url.hasPrefix("local://"), !imageExists(localID: preferred) {
            return "composited_" + encodeRemoteURL(url)
        }
        return preferred
    }

    /// Persist a flattened photo+markup composite for `url`. Budget-enforced
    /// (the `composited_` key is a remote-cache key), so a large composite can
    /// evict older reclaimable images to stay under the user's quota.
    @discardableResult
    func saveCompositedImage(_ data: Data, forURL url: String) -> Bool {
        let saved = saveImage(data: data, localID: compositedLocalID(forURL: url))
        if saved { notifyThumbnailChange(url) }
        return saved
    }

    /// Load the durable markup composite for `url`, if one is on disk.
    func loadCompositedImage(forURL url: String) -> UIImage? {
        loadImage(localID: compositedReadLocalID(forURL: url))
    }

    /// Lightweight existence check for a photo's composite (no decode).
    func compositedImageExists(forURL url: String) -> Bool {
        imageExists(localID: compositedReadLocalID(forURL: url))
    }

    /// Composite file size in bytes, or nil if absent.
    func compositedImageFileSize(forURL url: String) -> Int64? {
        imageFileSize(localID: compositedReadLocalID(forURL: url))
    }

    /// Composite last-modified timestamp, or nil if absent. Drives the
    /// compositor's "skip if the composite is newer than the annotation" check.
    func compositedImageModificationDate(forURL url: String) -> Date? {
        imageModificationDate(localID: compositedReadLocalID(forURL: url))
    }

    /// Remove a photo's durable composite (invalidation on edit / soft-delete /
    /// raw eviction). Returns true if the file is gone afterward.
    @discardableResult
    func deleteCompositedImage(forURL url: String) -> Bool {
        let readID = compositedReadLocalID(forURL: url)
        let writeID = compositedLocalID(forURL: url)
        let removedRead = deleteImage(localID: readID)
        let removed = readID == writeID ? removedRead : deleteImage(localID: writeID) && removedRead
        if removed { notifyThumbnailChange(url) }
        return removed
    }

    /// Get the raw data for an image
    func getImageData(localID: String) -> Data? {
        guard let fileURL = getFileURL(for: localID) else {
            return nil
        }
        
        // Check if file exists in file system
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                return try Data(contentsOf: fileURL)
            } catch {
                return nil
            }
        }
        
        // Migration: Try loading from UserDefaults if not in file system
        if let base64String = UserDefaults.standard.string(forKey: localID),
           let data = Data(base64Encoded: base64String) {
            return data
        }
        
        return nil
    }
    
    /// Migrate an existing UserDefaults-stored image to the file system
    func migrateFromUserDefaults(localID: String) -> Bool {
        if let base64String = UserDefaults.standard.string(forKey: localID),
           let data = Data(base64Encoded: base64String) {
            
            let success = saveImage(data: data, localID: localID)
            
            if success {
                // Remove from UserDefaults to free up space
                UserDefaults.standard.removeObject(forKey: localID)
            }
            
            return success
        }
        
        return false
    }
    
    /// Migrate all images from UserDefaults to file system
    func migrateAllImages() {
        // Get all keys from UserDefaults
        let userDefaults = UserDefaults.standard
        let dict = userDefaults.dictionaryRepresentation()
        
        var migratedCount = 0
        var failedCount = 0
        
        for (key, value) in dict {
            // Handle local project image keys
            if key.hasPrefix("local://project_images/") {
                let success = migrateFromUserDefaults(localID: key)
                if success {
                    migratedCount += 1
                } else {
                    failedCount += 1
                }
            }
            // Handle remote URLs (http or https)
            else if (key.hasPrefix("http") || key.hasPrefix("//")) && value is Data {
                if let imageData = userDefaults.data(forKey: key) {
                    let _ = encodeRemoteURL(key)
                    let success = saveImage(data: imageData, localID: key)
                    if success {
                        // Remove from UserDefaults to free up space
                        userDefaults.removeObject(forKey: key)
                        migratedCount += 1
                    } else {
                        failedCount += 1
                    }
                }
            }
        }
        
    }
    
    /// Clear all cached remote images (useful for fixing cache issues)
    func clearRemoteImageCache() {
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
            
            var deletedCount = 0
            for file in files {
                let name = file.lastPathComponent
                // Sweep both raw remote originals and their derived composites —
                // a composite without its raw is just orphaned bytes.
                if name.hasPrefix("remote_") || name.hasPrefix("composited_remote_") {
                    _ = PhotoCacheLedger.shared.remove(file)
                    deletedCount += 1
                }
            }
            notifyThumbnailChange("*")
        } catch {
        }
    }
}