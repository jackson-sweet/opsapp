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

enum SiteVisitMediaSyncError: Error, Equatable, LocalizedError {
    case localFileMissing(String)
    case invalidRemoteURL(String)

    var errorDescription: String? {
        switch self {
        case .localFileMissing(let source):
            return "Site-visit media file is missing: \(source)"
        case .invalidRemoteURL(let value):
            return "Site-visit upload returned an invalid URL: \(value)"
        }
    }
}

struct SiteVisitMediaSyncManager {
    typealias LoadedAsset = (data: Data, contentType: String)
    typealias Loader = (String) throws -> LoadedAsset
    typealias Uploader = (
        _ siteVisitId: String,
        _ artifactId: String,
        _ variant: SiteVisitArtifactVariant,
        _ data: Data,
        _ contentType: String
    ) async throws -> String

    private let uploader: Uploader
    private let loader: Loader

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
        loader: @escaping Loader = Self.loadAsset
    ) {
        self.uploader = uploader
        self.loader = loader
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

            let asset = try loader(source)
            let remoteURL = try await uploader(
                artifact.siteVisitId.lowercased(),
                artifact.id.lowercased(),
                variant,
                asset.data,
                asset.contentType
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
            existing.dependsOnId = mediaOperation.id.uuidString.lowercased()
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

    private func setSourceURL(
        _ value: String,
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
            throw SiteVisitMediaSyncError.localFileMissing(source)
        }
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
