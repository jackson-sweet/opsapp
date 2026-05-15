//
//  PhotoProcessor.swift
//  OPS
//
//  Manages the full photo lifecycle: local save, thumbnail generation,
//  adaptive upload via presigned URLs, and synced-photo cleanup.
//  Replaces ImageSyncManager and PhotoAnnotationSyncManager.
//

import UIKit
import SwiftData
import Foundation
import Network

@MainActor
final class PhotoProcessor {

    // MARK: - Dependencies

    private let uploadService = PresignedURLUploadService.shared

    // MARK: - Constants

    private static let maxDimension: CGFloat = 2048
    private static let thumbnailSize: CGFloat = 200
    private static let maxConcurrentWiFi = 3

    // MARK: - Photo Saving

    /// Saves a photo locally (full-size compressed JPEG + thumbnail) and creates
    /// a `LocalPhoto` record. Returns the newly-created record.
    func savePhoto(
        image: UIImage,
        entityType: String,
        entityId: String,
        companyId: String,
        context: ModelContext
    ) -> LocalPhoto {
        // Resize if needed
        let resized = resizeImage(image, maxDimension: Self.maxDimension)

        // Adaptive compression quality
        let quality = adaptiveCompressionQuality(for: resized)
        let imageData = resized.jpegData(compressionQuality: quality) ?? Data()

        // Generate unique filenames
        let photoId = UUID().uuidString
        let filename = "\(photoId).jpg"
        let thumbFilename = "\(photoId)_thumb.jpg"

        // Ensure directories exist
        let dir = photoDirectory()
        let thumbDir = thumbnailDirectory()

        // Write full-size image
        let fullURL = dir.appendingPathComponent(filename)
        try? imageData.write(to: fullURL)

        // Generate and write thumbnail
        let thumbnail = generateThumbnail(resized, size: Self.thumbnailSize)
        let thumbData = thumbnail?.jpegData(compressionQuality: 0.7)
        let thumbURL = thumbDir.appendingPathComponent(thumbFilename)
        if let thumbData {
            try? thumbData.write(to: thumbURL)
        }

        // Relative paths (from Documents/)
        let relativePath = "photos/\(filename)"
        let relativeThumbPath = "thumbnails/\(thumbFilename)"

        // Dimensions
        let width = Int(resized.size.width)
        let height = Int(resized.size.height)

        // Create SwiftData record
        let photo = LocalPhoto(
            id: photoId,
            companyId: companyId,
            entityType: entityType,
            entityId: entityId,
            localPath: relativePath,
            fileSize: Int64(imageData.count),
            mimeType: "image/jpeg",
            width: width,
            height: height,
            capturedAt: Date()
        )
        photo.thumbnailPath = relativeThumbPath
        photo.status = "local"
        photo.needsSync = true

        context.insert(photo)
        try? context.save()

        return photo
    }

    // MARK: - Upload Queue Processing

    /// Fetches all LocalPhoto records needing upload and processes them
    /// with adaptive concurrency based on connectivity quality.
    func processUploadQueue(context: ModelContext, connectivity: ConnectivityManager) async {
        guard connectivity.shouldUploadPhotos else {
            return
        }

        // Fetch photos that need uploading (excludes permanently_failed by status match)
        let photosToUpload: [LocalPhoto]
        do {
            let descriptor = FetchDescriptor<LocalPhoto>(
                predicate: #Predicate<LocalPhoto> {
                    $0.status == "local" || $0.status == "failed"
                }
            )
            photosToUpload = try context.fetch(descriptor)
        } catch {
            print("[PhotoProcessor] Failed to fetch upload queue: \(error)")
            return
        }

        guard !photosToUpload.isEmpty else { return }

        // Determine concurrency based on connection quality
        let isWiFi = connectivity.state.type == .wifi
        let quality = connectivity.state.quality

        let maxConcurrent: Int
        if isWiFi && (quality == .excellent || quality == .good) {
            maxConcurrent = Self.maxConcurrentWiFi
        } else {
            // Cellular or poor quality: sequential
            maxConcurrent = 1
        }

        // Process in batches respecting concurrency limit
        let batches = stride(from: 0, to: photosToUpload.count, by: maxConcurrent)

        for batchStart in batches {
            // Re-check connectivity before each batch
            guard connectivity.shouldUploadPhotos else {
                print("[PhotoProcessor] Connectivity dropped, pausing upload queue")
                return
            }

            let batchEnd = min(batchStart + maxConcurrent, photosToUpload.count)
            let batchSlice = Array(photosToUpload[batchStart..<batchEnd])

            // Apply retry cap and mark eligible photos as uploading
            var batch: [LocalPhoto] = []
            for photo in batchSlice {
                if photo.uploadRetryCount >= 20 {
                    photo.status = "permanently_failed"
                    print("[PHOTO_SYNC] Photo \(photo.id) permanently failed after 20 retries")
                    continue
                }
                photo.uploadRetryCount += 1
                photo.status = "uploading"
                photo.uploadProgress = 0
                batch.append(photo)
            }
            try? context.save()

            // Upload concurrently within batch
            await withTaskGroup(of: Void.self) { group in
                for photo in batch {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.processOneUpload(photo, context: context)
                    }
                }
            }

            try? context.save()
        }

        // Check disk usage after processing the batch
        let diskUsage = localPhotoDiskUsage()
        if diskUsage > 524_288_000 { // 500MB
            print("[PhotoProcessor] Disk usage warning: \(diskUsage / 1_048_576)MB exceeds 500MB threshold")
            NotificationCenter.default.post(name: .photoDiskUsageHigh, object: nil, userInfo: [
                "diskUsageBytes": diskUsage
            ])
        }
    }

    /// Uploads a single photo, updating its status on success or failure.
    ///
    /// Retry semantics (May-12 auto-bug-reporting follow-up):
    ///
    ///   * IN-SESSION: exponential backoff 1s / 5s / 15s / 60s, cap 4 attempts.
    ///     Each retry classifies the most recent error. Permanent errors
    ///     break the loop immediately (no point hammering an RLS reject).
    ///     The cap is the longest the user reasonably waits while watching
    ///     a single photo upload.
    ///
    ///   * CROSS-SESSION: the `uploadRetryCount >= 20` threshold in
    ///     `processUploadQueue` stays. A photo can rack up dozens of
    ///     "session ended before signal returned" retries across days of
    ///     bad coverage without being a bug — that's normal trades-life.
    ///
    /// Auto-bug fires when (a) any permanent error hits, or (b) the
    /// in-session cap is exhausted with a non-pure-transient cause (the
    /// latter signals "something is wrong beyond bad signal").
    private func processOneUpload(_ photo: LocalPhoto, context: ModelContext) async {
        let backoffSeconds: [TimeInterval] = [1, 5, 15, 60]
        var lastError: Error?
        var lastKind: UploadErrorKind?

        for attempt in 0..<backoffSeconds.count {
            do {
                let publicURL = try await uploadPhoto(photo)
                photo.uploadedURL = publicURL
                photo.status = "uploaded"
                photo.uploadProgress = 1.0
                photo.needsSync = false
                photo.lastSyncedAt = Date()
                return
            } catch {
                lastError = error
                let kind = UploadErrorClassifier.classify(error)
                lastKind = kind

                // Permanent errors short-circuit the loop — retry won't help.
                if case .permanent(let code, let reason) = kind {
                    await AutoBugReporter.shared.report(
                        screen: "PhotoProcessor.processOneUpload",
                        suspectedFile: "PhotoProcessor.swift",
                        errorCode: code,
                        summary: "Photo upload permanent failure for \(photo.id): \(reason)",
                        metadata: [
                            "photo_id": photo.id,
                            "entity_type": photo.entityType,
                            "entity_id": photo.entityId,
                            "company_id": photo.companyId,
                            "in_session_attempt": attempt + 1,
                            "cross_session_retry_count": photo.uploadRetryCount
                        ]
                    )
                    break
                }

                // Transient / unknown — sleep before next attempt unless
                // this was the final cap-exhaust pass.
                if attempt < backoffSeconds.count - 1 {
                    let ns = UInt64(backoffSeconds[attempt] * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                }
            }
        }

        // Upload didn't succeed in-session. Mark failed so the cross-session
        // retry loop in processUploadQueue picks it up next time. The
        // uploadRetryCount on the LocalPhoto bumps once per processUploadQueue
        // pass, not once per in-session attempt — so 4 in-session retries
        // count as 1 cross-session attempt against the 20 cap.
        photo.status = "failed"
        photo.uploadProgress = 0

        // Auto-bug only if the cap-exhaust cause is NOT a pure transient
        // (e.g. unknown error or repeated 5xx with no recovery). Pure
        // transient = "the user is offline / has bad signal" which is
        // normal in the field; the cross-session retry handles it.
        if let kind = lastKind, let error = lastError {
            await AutoBugReporter.shared.reportRetryExhausted(
                kind: kind,
                attempts: backoffSeconds.count,
                screen: "PhotoProcessor.processOneUpload",
                suspectedFile: "PhotoProcessor.swift",
                summary: "Photo upload retry-exhausted for \(photo.id): \(error.localizedDescription)",
                metadata: [
                    "photo_id": photo.id,
                    "entity_type": photo.entityType,
                    "entity_id": photo.entityId,
                    "company_id": photo.companyId,
                    "cross_session_retry_count": photo.uploadRetryCount
                ]
            )
            DebugLogger.shared.log(
                "PhotoProcessor in-session retries exhausted for \(photo.id): \(error)",
                level: .warning,
                category: "PhotoProcessor"
            )
        }
    }

    // MARK: - Single Photo Upload

    /// Reads the local file from disk and uploads it via the presigned URL service.
    /// Returns the public URL of the uploaded image.
    private func uploadPhoto(_ photo: LocalPhoto) async throws -> String {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let fileURL = documentsDir.appendingPathComponent(photo.localPath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UploadError.invalidURL
        }

        let imageData = try Data(contentsOf: fileURL)

        // Build folder: photos/{companyId}/{entityType}/{entityId}
        let folder = "photos/\(photo.companyId)/\(photo.entityType)/\(photo.entityId)"
        let timestamp = Date().timeIntervalSince1970
        let filename = "\(photo.id)_\(timestamp).jpg"

        let publicURL = try await uploadService.uploadImageData(
            imageData,
            filename: filename,
            folder: folder
        )
        return publicURL
    }

    // MARK: - Cleanup

    /// Deletes the full-size file for uploaded photos older than the given date.
    /// Keeps the thumbnail and SwiftData record (URL reference is still needed).
    func cleanupSyncedPhotos(olderThan date: Date, context: ModelContext) {
        let photosToClean: [LocalPhoto]
        do {
            let descriptor = FetchDescriptor<LocalPhoto>(
                predicate: #Predicate<LocalPhoto> {
                    $0.status == "uploaded" && $0.createdAt < date
                }
            )
            photosToClean = try context.fetch(descriptor)
        } catch {
            print("[PhotoProcessor] Failed to fetch photos for cleanup: \(error)")
            return
        }

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let fm = FileManager.default

        for photo in photosToClean {
            let fullPath = documentsDir.appendingPathComponent(photo.localPath)
            if fm.fileExists(atPath: fullPath.path) {
                try? fm.removeItem(at: fullPath)
            }
        }
    }

    // MARK: - Disk Usage

    /// Returns the total disk space (in bytes) consumed by all files in the
    /// app's Documents/photos/ directory. Includes full-size images only
    /// (thumbnails are stored separately in Documents/thumbnails/).
    func localPhotoDiskUsage() -> Int64 {
        let photosDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos")
        guard let enumerator = FileManager.default.enumerator(
            at: photosDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    // MARK: - Image Processing Utilities

    /// Compresses (resizes) the image so its longest edge is at most `maxDimension`,
    /// preserving aspect ratio. Returns the original if already within bounds.
    private func compressImage(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let resized = resizeImage(image, maxDimension: maxDimension)
        let quality = adaptiveCompressionQuality(for: resized)
        return resized.jpegData(compressionQuality: quality)
    }

    /// Resizes the image so its longest edge is at most `maxDimension`,
    /// preserving aspect ratio. Returns the original image if already within bounds.
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            return image
        }

        let aspectRatio = image.size.width / image.size.height
        let newSize: CGSize

        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()

        return resized
    }

    /// Generates a square thumbnail of the given size from the source image.
    private func generateThumbnail(_ image: UIImage, size: CGFloat) -> UIImage? {
        let targetSize = CGSize(width: size, height: size)

        // Center-crop to square
        let shortest = min(image.size.width, image.size.height)
        let cropOrigin = CGPoint(
            x: (image.size.width - shortest) / 2,
            y: (image.size.height - shortest) / 2
        )
        let cropRect = CGRect(origin: cropOrigin, size: CGSize(width: shortest, height: shortest))

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return nil
        }

        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: targetSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return thumbnail
    }

    /// Adaptive JPEG quality based on pixel count.
    /// Larger images get more compression to keep file sizes manageable.
    private func adaptiveCompressionQuality(for image: UIImage) -> CGFloat {
        let pixelCount = image.size.width * image.size.height
        if pixelCount > 4_000_000 {        // > 4MP
            return 0.5
        } else if pixelCount > 2_000_000 { // > 2MP
            return 0.6
        } else if pixelCount > 1_000_000 { // > 1MP
            return 0.7
        } else {
            return 0.8
        }
    }

    // MARK: - Directory Helpers

    /// Returns (and creates if necessary) the app's Documents/photos/ directory.
    private func photoDirectory() -> URL {
        let dir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("photos")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Returns (and creates if necessary) the app's Documents/thumbnails/ directory.
    private func thumbnailDirectory() -> URL {
        let dir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("thumbnails")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
