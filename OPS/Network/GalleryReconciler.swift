//
//  GalleryReconciler.swift
//  OPS
//
//  Pure reconciliation of batch-upload outcomes against a project's gallery URL
//  list. Replaces the positional `s3Results[index]` ↔ `uploads[index]` mapping
//  in `ImageSyncManager.syncImagesForProject`, which silently misaligned (and
//  permanently stranded `local://` URLs) the moment the old uploader skipped an
//  image. With outcomes now aligned 1:1 to their source local URL, this maps
//  each result back by IDENTITY — a successful upload swaps its own `local://`
//  placeholder for the returned S3 URL; a failed one keeps its placeholder and
//  stays queued.
//

import Foundation

enum GalleryReconciler {

    /// The result of draining a batch of queued (`local://`) uploads.
    struct DrainResult: Equatable {
        /// `currentImageURLs` with each *successfully* uploaded local URL swapped
        /// for its remote S3 URL, in place. Failed/unknown local URLs are left
        /// untouched so the carousel keeps rendering the on-disk copy.
        var updatedImageURLs: [String]
        /// Local URLs whose upload succeeded — caller marks these synced and
        /// removes them from the pending-upload queue.
        var syncedLocalURLs: [String]
        /// Remote URLs newly landed on S3 — caller inserts `project_photos` rows.
        var newRemoteURLs: [String]
        /// Local URLs whose upload failed — caller keeps these queued for the
        /// next retry pass.
        var failedLocalURLs: [String]
    }

    /// Reconcile by identity (never by position). `results` pairs each drained
    /// pending upload's `local://` URL with the outcome of re-uploading it.
    static func reconcileDrain(
        currentImageURLs: [String],
        results: [(localURL: String, outcome: ProjectImageUploadOutcome)]
    ) -> DrainResult {
        var updated = currentImageURLs
        var synced: [String] = []
        var newRemote: [String] = []
        var failed: [String] = []

        for (localURL, outcome) in results {
            if let remoteURL = outcome.url {
                // Success — swap THIS local URL for its own remote URL, found by
                // identity (never by position). A local URL absent from the
                // gallery is still recorded as synced so the queue clears.
                if let idx = updated.firstIndex(of: localURL) {
                    updated[idx] = remoteURL
                }
                synced.append(localURL)
                newRemote.append(remoteURL)
            } else {
                // Failure — leave the local placeholder in place and keep queued.
                failed.append(localURL)
            }
        }

        return DrainResult(
            updatedImageURLs: updated,
            syncedLocalURLs: synced,
            newRemoteURLs: newRemote,
            failedLocalURLs: failed
        )
    }
}
