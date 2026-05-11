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

        // Handle already-encoded remote URLs (e.g., "remote_xxxxx")
        if localID.hasPrefix("remote_") {
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
    func saveImage(data: Data, localID: String) -> Bool {
        guard let fileURL = getFileURL(for: localID) else {
            return false
        }

        if isRemoteCacheKey(localID) {
            let budget = StorageProfiler.shared.budgetBytes
            evictRemoteImagesIfNeeded(bytesNeeded: Int64(data.count), budget: budget)
        }

        do {
            try data.write(to: fileURL)
            return true
        } catch {
            return false
        }
    }

    /// True if `localID` represents a remote (server-side) photo that's been
    /// downloaded into the local cache. These are subject to the photo storage
    /// budget; local upload-pending images are not.
    private func isRemoteCacheKey(_ localID: String) -> Bool {
        localID.hasPrefix("http") || localID.hasPrefix("//") || localID.hasPrefix("remote_")
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
            filenames.insert(encodeRemoteURL(normalized))
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
        let fm = FileManager.default
        let currentUsage = StorageProfiler.shared.currentUsageBytes()
        guard currentUsage + bytesNeeded > budget else { return 0 }

        guard let enumerator = fm.enumerator(
            at: imagesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return 0 }

        let pinned = loadPinnedRemoteFilenames()

        struct Candidate {
            let url: URL
            let modified: Date
            let size: Int64
        }

        var candidates: [Candidate] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("remote_"), !pinned.contains(name) else { continue }
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey]
            ) else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            let size = Int64(values.totalFileAllocatedSize ?? 0)
            guard size > 0 else { continue }
            candidates.append(Candidate(url: fileURL, modified: modified, size: size))
        }

        candidates.sort { $0.modified < $1.modified }

        var freed: Int64 = 0
        var projectedUsage = currentUsage
        for candidate in candidates {
            if projectedUsage + bytesNeeded <= budget { break }
            do {
                try fm.removeItem(at: candidate.url)
                projectedUsage -= candidate.size
                freed += candidate.size
            } catch {
                continue
            }
        }

        if freed > 0 {
            print("[ImageFileManager] Budget evict: freed \(freed) bytes across \(candidates.count) candidate(s) to make room for \(bytesNeeded) byte write")
        }
        return freed
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
                _ = saveImage(data: cachedData, localID: encodedID)
                
                // Remove from UserDefaults to free up space
                UserDefaults.standard.removeObject(forKey: localID)
                
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
            let _ = saveImage(data: data, localID: localID)
            
            // Remove from UserDefaults to free up space
            UserDefaults.standard.removeObject(forKey: localID)
            
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
        
        // Check if file exists before deleting
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                return true
            } catch {
                return false
            }
        }
        
        return true // Return true if file didn't exist
    }
    
    /// Get the file size in bytes without loading data into memory
    func imageFileSize(localID: String) -> Int64? {
        guard let fileURL = getFileURL(for: localID) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
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
                if file.lastPathComponent.hasPrefix("remote_") {
                    try fileManager.removeItem(at: file)
                    deletedCount += 1
                }
            }
            
        } catch {
        }
    }
}