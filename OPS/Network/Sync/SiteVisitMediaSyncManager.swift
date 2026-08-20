//
//  SiteVisitMediaSyncManager.swift
//  OPS
//
//  Restart-safe upload progress for pre-project site-visit artifacts. Every
//  successful variant is persisted before the next upload begins; the durable
//  media SyncOperation, not an in-memory task, remains authoritative.
//

import Foundation
import SwiftData
import UIKit

enum SiteVisitMediaSyncError: Error, Equatable, LocalizedError {
    /// The bytes are gone. A local capture's file is the ONLY copy until it
    /// uploads, so an absent file can never become present again — terminal.
    case localFileMissing(String)
    /// The file IS on disk but could not be read on this attempt (iOS Data
    /// Protection while the device is locked during a background drain,
    /// transient I/O). Never terminal: retiring on this would throw away the
    /// pointer to a photo that is perfectly fine.
    case localFileUnreadable(String)
    case invalidRemoteURL(String)
    case uploadPreparationFailed

    var errorDescription: String? {
        switch self {
        case .localFileMissing(let source):
            return "Site-visit media file is missing: \(source)"
        case .localFileUnreadable(let source):
            return "Site-visit media file could not be read: \(source)"
        case .invalidRemoteURL(let value):
            return "Site-visit upload returned an invalid URL: \(value)"
        case .uploadPreparationFailed:
            return "Couldn't prepare this site visit photo for upload. The original remains on this phone."
        }
    }
}

/// One byte-and-dimension policy for durable site-visit media. The server's
/// typed presign route rejects files above 10 MiB, while annotation composites
/// can inherit a camera's full 12 MP+ canvas. Existing safe assets pass through
/// untouched; only over-limit files are decoded, capped, and re-encoded.
enum SiteVisitMediaImagePreparation {
    static let maximumUploadBytes = 10 * 1_024 * 1_024
    static let maximumPixelDimension: CGFloat = 2_048

    static func prepare(
        data: Data,
        contentType: String
    ) throws -> (data: Data, contentType: String) {
        guard data.count > maximumUploadBytes else {
            return (data, contentType)
        }
        guard let image = UIImage(data: data),
              let jpeg = jpegData(for: image) else {
            throw SiteVisitMediaSyncError.uploadPreparationFailed
        }
        return (jpeg, "image/jpeg")
    }

    /// Produces a durable/upload-safe JPEG for newly rendered composites as
    /// well as legacy over-limit files. The dimension cap does the heavy work;
    /// the quality ladder is a hard final guard against pathological images.
    static func jpegData(for image: UIImage) -> Data? {
        let dimensionLadder: [CGFloat] = [2_048, 1_536, 1_280, 1_024]
        for dimension in dimensionLadder {
            let resized = resizeToFit(image, maximumDimension: dimension)
            let pixelCount = resized.size.width * resized.size.height
            let startingQuality: CGFloat
            if pixelCount > 4_000_000 {
                startingQuality = 0.5
            } else if pixelCount > 2_000_000 {
                startingQuality = 0.6
            } else if pixelCount > 1_000_000 {
                startingQuality = 0.7
            } else {
                startingQuality = 0.8
            }
            for quality in [startingQuality, 0.5, 0.4, 0.3] {
                guard let candidate = resized.jpegData(compressionQuality: quality) else {
                    continue
                }
                if candidate.count <= maximumUploadBytes {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func resizeToFit(
        _ image: UIImage,
        maximumDimension: CGFloat
    ) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > maximumDimension else { return image }
        let scale = maximumDimension / longestEdge
        let size = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Runs raster decoding and encoding on its own serial executor, never on the
/// MainActor that owns SwiftData and the sync UI.
actor SiteVisitMediaUploadPreparer {
    static let shared = SiteVisitMediaUploadPreparer()

    func prepare(
        data: Data,
        contentType: String
    ) async throws -> (data: Data, contentType: String) {
        try autoreleasepool {
            try SiteVisitMediaImagePreparation.prepare(
                data: data,
                contentType: contentType
            )
        }
    }
}

struct SiteVisitMediaSyncManager {
    typealias LoadedAsset = (data: Data, contentType: String)
    typealias Loader = (String) throws -> LoadedAsset
    typealias Preparer = (LoadedAsset) async throws -> LoadedAsset
    typealias Uploader = (
        _ siteVisitId: String,
        _ artifactId: String,
        _ variant: SiteVisitArtifactVariant,
        _ data: Data,
        _ contentType: String
    ) async throws -> String

    private let uploader: Uploader
    private let loader: Loader
    private let preparer: Preparer

    init(
        uploader: @escaping Uploader = { siteVisitId, artifactId, variant, data, contentType in
            try await PresignedURLUploadService.shared.uploadSiteVisitArtifact(
                data,
                siteVisitId: siteVisitId,
                artifactId: artifactId,
                variant: variant,
                contentType: contentType
            )
        },
        loader: @escaping Loader = Self.loadAsset,
        preparer: @escaping Preparer = { asset in
            try await SiteVisitMediaUploadPreparer.shared.prepare(
                data: asset.data,
                contentType: asset.contentType
            )
        }
    ) {
        self.uploader = uploader
        self.loader = loader
        self.preparer = preparer
    }

    func uploadPendingMedia(
        artifactId: String,
        mediaOperation: SyncOperation,
        context: ModelContext
    ) async throws {
        // Predicate-scoped, fetchLimit 1: this runs once per media operation
        // inside the same drain that crashed on a whole-table fetch registering
        // every artifact in the actor's context (bug 3eef6ad7).
        let exact = artifactId
        let canonicalId = artifactId.lowercased()
        let upper = artifactId.uppercased()
        var descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate {
                $0.id == exact || $0.id == canonicalId || $0.id == upper
            }
        )
        descriptor.fetchLimit = 1
        guard let artifact = try context.fetch(descriptor).first,
              artifact.deletedAt == nil else {
            // The capture was removed after this operation was queued. The
            // corresponding CRUD tombstone owns the server outcome; media is a
            // safe no-op.
            return
        }

        for variant in SiteVisitArtifactVariant.allCases {
            guard let source = sourceURL(for: variant, artifact: artifact),
                  !Self.isRemoteURL(source) else {
                continue
            }

            let asset: LoadedAsset
            do {
                asset = try loader(source)
            } catch let error as SiteVisitMediaSyncError {
                guard case .localFileMissing = error else { throw error }
                // The bytes are gone and the local file was the only copy, so
                // no future drain can ever succeed. Clearing the dead pointer
                // makes this row match what the server and every other device
                // already hold (a null asset URL) and stops the operation being
                // re-queued and re-parked forever. The artifact, its visit,
                // notes and checklist answers all survive untouched.
                try context.transaction {
                    guard sourceURL(for: variant, artifact: artifact) == source else {
                        return
                    }
                    setSourceURL(nil, for: variant, artifact: artifact)
                    artifact.updatedAt = Date()
                    artifact.needsSync = true
                    try queueArtifactURLUpsert(
                        artifact,
                        dependsOn: mediaOperation,
                        context: context
                    )
                }
                continue
            }
            let prepared = try await preparer(asset)
            let remoteURL = try await uploader(
                artifact.siteVisitId.lowercased(),
                artifact.id.lowercased(),
                variant,
                prepared.data,
                prepared.contentType
            )
            guard Self.isRemoteURL(remoteURL) else {
                throw SiteVisitMediaSyncError.invalidRemoteURL(remoteURL)
            }

            try context.transaction {
                // A user can replace a capture while its previous bytes are in
                // flight. Never overwrite that newer local source with the old
                // upload response; its newly queued media op will carry it.
                guard sourceURL(for: variant, artifact: artifact) == source else {
                    return
                }
                setSourceURL(remoteURL, for: variant, artifact: artifact)
                artifact.updatedAt = Date()
                artifact.needsSync = true
                try queueArtifactURLUpsert(
                    artifact,
                    dependsOn: mediaOperation,
                    context: context
                )
            }
        }
    }

    private func queueArtifactURLUpsert(
        _ artifact: SiteVisitCaptureArtifact,
        dependsOn mediaOperation: SyncOperation,
        context: ModelContext
    ) throws {
        let specification = SiteVisitSyncOperation.artifact(artifact)
        let allOperations = try context.fetch(FetchDescriptor<SyncOperation>())
        let unresolved: Set<String> = ["pending", "inProgress", "failed"]
        let existing = allOperations
            .filter {
                $0.entityType == SyncEntityType.siteVisitArtifact.rawValue
                    && $0.entityId.lowercased() == artifact.id.lowercased()
                    && $0.operationType != SiteVisitSyncOperation.mediaOperationType
                    && $0.operationType != SiteVisitSyncOperation.completionOperationType
                    && unresolved.contains($0.status)
            }
            .sorted(by: Self.operationOrder)
            .last(where: { $0.status != "inProgress" })

        let payload = try JSONEncoder().encode(specification.payload)
        if let existing {
            if existing.operationType != "create" {
                existing.operationType = specification.operationType
            }
            existing.payload = payload
            existing.changedFields = specification.changedFields.joined(separator: ",")
            existing.priority = min(existing.priority, specification.priority)
            // The media operation already depends on this CRUD operation when
            // the coordinator queued them together, so pointing it back here
            // would close a ring and strand both forever (the 2026-08-19
            // device wedge, reached by a second route).
            existing.dependsOnId = SiteVisitOutboundSync.dependencyWithoutCycle(
                mediaOperation.id.uuidString.lowercased(),
                for: existing,
                in: allOperations
            )
            existing.status = "pending"
            existing.retryCount = 0
            existing.lastAttemptedAt = nil
            existing.completedAt = nil
            existing.lastError = nil
            return
        }

        context.insert(
            SyncOperation(
                entityType: specification.entityType.rawValue,
                entityId: specification.entityId,
                operationType: specification.operationType,
                payload: payload,
                changedFields: specification.changedFields,
                priority: specification.priority,
                dependsOnId: mediaOperation.id.uuidString.lowercased()
            )
        )
    }

    private func sourceURL(
        for variant: SiteVisitArtifactVariant,
        artifact: SiteVisitCaptureArtifact
    ) -> String? {
        switch variant {
        case .original:
            return artifact.localAssetURL
        case .rendered:
            return artifact.renderedAssetURL
        case .thumbnail:
            return artifact.thumbnailURL
        }
    }

    /// Optional so the same writer both records an upload result and clears a
    /// pointer whose bytes are permanently gone.
    private func setSourceURL(
        _ value: String?,
        for variant: SiteVisitArtifactVariant,
        artifact: SiteVisitCaptureArtifact
    ) {
        switch variant {
        case .original:
            artifact.localAssetURL = value
        case .rendered:
            artifact.renderedAssetURL = value
        case .thumbnail:
            artifact.thumbnailURL = value
        }
    }

    static func isRemoteURL(_ raw: String) -> Bool {
        guard let scheme = URLComponents(string: raw)?.scheme?.lowercased() else {
            return false
        }
        return scheme == "https" || scheme == "http"
    }

    private static func loadAsset(_ source: String) throws -> LoadedAsset {
        let fileURL: URL?
        if source.hasPrefix("file://") {
            fileURL = URL(string: source)
        } else if source.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: source)
        } else {
            fileURL = ImageFileManager.shared.getFileURL(for: source)
        }
        // An unresolvable key and an absent file are the same fact: no bytes.
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SiteVisitMediaSyncError.localFileMissing(source)
        }
        do {
            return (
                try Data(contentsOf: fileURL),
                contentType(forExtension: fileURL.pathExtension)
            )
        } catch {
            // The file IS on disk — this read failed for some other reason, so
            // a later drain can still succeed. Never treat this as terminal.
            throw SiteVisitMediaSyncError.localFileUnreadable(source)
        }
    }

    /// Test seam for the absent/unreadable split. Production callers reach
    /// `loadAsset` through the injected `loader`.
    static func loadAssetForTesting(_ source: String) throws -> LoadedAsset {
        try loadAsset(source)
    }

    private static func contentType(forExtension raw: String) -> String {
        switch raw.lowercased() {
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }

    private static func operationOrder(
        _ lhs: SyncOperation,
        _ rhs: SyncOperation
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
