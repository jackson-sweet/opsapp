//
//  SiteVisitParkedMediaReconciler.swift
//  OPS
//
//  A media upload that parked because its local bytes were missing can never be
//  revived by the normal path: parked work never auto-retries (by design), and
//  the orphan sweep counts `parked` as unresolved so it will not replace it. So
//  a photo whose file is genuinely gone would nag in PENDING WORK forever, and
//  a photo that was only *temporarily* unreadable (Data Protection during a
//  locked-device drain, which older builds could not tell apart from a deleted
//  file) would stay written off even though its bytes are still on disk.
//
//  This sweep re-reads the filesystem and settles both cases honestly:
//    * bytes absent  → clear the dead pointer, resolve the operation
//    * bytes present → hand the operation back for another upload attempt
//
//  It never guesses: every decision comes from a live existence check, and it
//  only touches operations parked with our own missing-media error so work
//  parked for any other reason is left exactly as it is.
//

import Foundation
import SwiftData

enum SiteVisitParkedMediaReconciler {
    /// Injectable existence check so the sweep is testable without a filesystem.
    typealias FileProbe = (String) -> Bool

    /// The marker written by `SiteVisitMediaSyncError.localFileMissing`. Only
    /// operations carrying it are candidates — anything else parked for a
    /// different reason stays parked.
    static let missingMediaMarker = "Site-visit media file is missing"

    static func defaultProbe(_ source: String) -> Bool {
        let url: URL?
        if source.hasPrefix("file://") {
            url = URL(string: source)
        } else if source.hasPrefix("/") {
            url = URL(fileURLWithPath: source)
        } else {
            url = ImageFileManager.shared.getFileURL(for: source)
        }
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Settles every parked site-visit media operation. Returns how many were
    /// resolved (completed or handed back for retry).
    @discardableResult
    static func reconcile(
        in context: ModelContext,
        fileExists: FileProbe = defaultProbe
    ) -> Int {
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "parked" }
        )
        guard let parked = try? context.fetch(descriptor), !parked.isEmpty else {
            return 0
        }

        var resolved = 0
        for operation in parked
        where operation.operationType == SiteVisitSyncOperation.mediaOperationType
            && (operation.lastError?.contains(missingMediaMarker) ?? false) {

            guard let artifact = artifact(for: operation.entityId, in: context),
                  artifact.deletedAt == nil else {
                // The capture is gone; its tombstone owns the server outcome.
                complete(operation)
                resolved += 1
                continue
            }

            var clearedAny = false
            var uploadableRemains = false
            for variant in SiteVisitArtifactVariant.allCases {
                guard let source = sourceURL(for: variant, artifact: artifact),
                      !SiteVisitMediaSyncManager.isRemoteURL(source) else { continue }
                if fileExists(source) {
                    uploadableRemains = true
                } else {
                    setSourceURL(nil, for: variant, artifact: artifact)
                    clearedAny = true
                }
            }

            if clearedAny {
                artifact.updatedAt = Date()
                artifact.needsSync = true
            }

            if uploadableRemains {
                // Real bytes are still here — this deserves another attempt.
                operation.status = "pending"
                operation.retryCount = 0
                operation.lastAttemptedAt = nil
                operation.lastError = nil
            } else {
                complete(operation)
            }
            resolved += 1
        }

        if resolved > 0 {
            do {
                try context.save()
            } catch {
                print("[SiteVisitParkedMediaReconciler] save failed: \(error)")
                return 0
            }
            print("[SiteVisitParkedMediaReconciler] Settled \(resolved) parked media operation(s)")
        }
        return resolved
    }

    // MARK: - Helpers

    private static func complete(_ operation: SyncOperation) {
        operation.status = "completed"
        operation.completedAt = Date()
        operation.lastError = nil
    }

    private static func artifact(
        for entityId: String,
        in context: ModelContext
    ) -> SiteVisitCaptureArtifact? {
        let exact = entityId
        let lower = entityId.lowercased()
        let upper = entityId.uppercased()
        var descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func sourceURL(
        for variant: SiteVisitArtifactVariant,
        artifact: SiteVisitCaptureArtifact
    ) -> String? {
        switch variant {
        case .original:  return artifact.localAssetURL
        case .rendered:  return artifact.renderedAssetURL
        case .thumbnail: return artifact.thumbnailURL
        }
    }

    private static func setSourceURL(
        _ value: String?,
        for variant: SiteVisitArtifactVariant,
        artifact: SiteVisitCaptureArtifact
    ) {
        switch variant {
        case .original:  artifact.localAssetURL = value
        case .rendered:  artifact.renderedAssetURL = value
        case .thumbnail: artifact.thumbnailURL = value
        }
    }
}
