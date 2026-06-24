//
//  Project+Gallery.swift
//  OPS
//
//  Single source of truth for the project photo gallery list.
//
//  The carousel and the full-screen viewer must render the SAME ordered URL
//  array so a tapped index opens the right photo. Both go through these
//  helpers, which merge the canonical synced `project_photos` store with the
//  legacy `projects.project_images` CSV — deduped by URL, soft-deleted photos
//  excluded. This is the read side of the project-photos sync fix: before
//  `project_photos` became a synced entity, a teammate's device only had the
//  uploader-written CSV, so a crew member's photo showed in comments but never
//  in the gallery.
//

import Foundation
import SwiftData

extension ProjectPhoto {
    /// `project_photos.source` values that are NOT real gallery photos and must
    /// never appear in the project photo carousel. Deck-builder 3D render
    /// snapshots (`deck_design`) live under a separate `deck_designs/` S3 prefix
    /// that isn't web-readable, so merging them into the gallery rendered them
    /// as blank tiles. They belong in the Deck tab, not the photo strip.
    static let nonGallerySources: Set<String> = ["deck_design"]

    /// True when this row is a real, displayable gallery photo.
    var isGalleryEligible: Bool {
        deletedAt == nil && !ProjectPhoto.nonGallerySources.contains(source)
    }
}

extension Sequence where Element == ProjectPhoto {
    /// URLs of the gallery-eligible photos, in sequence order. Filters out
    /// non-photo sources (e.g. deck renders) so they don't pollute the carousel.
    func galleryURLs() -> [String] {
        filter { $0.isGalleryEligible }.map { $0.url }
    }
}

extension Project {
    /// Merge already-fetched synced photo URLs with the legacy CSV. Legacy
    /// order first (preserves the uploader's existing ordering), then any
    /// synced-only URLs in the order supplied (callers sort by `createdAt`).
    /// Deduped by URL; empty strings dropped. Callers must pre-filter
    /// soft-deleted rows.
    func mergedGalleryImageURLs(syncedPhotoURLs: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for url in getProjectImages() where !url.isEmpty && seen.insert(url).inserted {
            merged.append(url)
        }
        for url in syncedPhotoURLs where !url.isEmpty && seen.insert(url).inserted {
            merged.append(url)
        }
        return merged
    }

    /// Convenience overload that fetches live `ProjectPhoto` rows for this
    /// project (excluding soft-deleted) from `context`, then merges. Used where
    /// a reactive `@Query` isn't available — the cold-start fallback carousel
    /// and the full-screen viewer's one-shot present.
    func mergedGalleryImageURLs(using context: ModelContext) -> [String] {
        let pid = id
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let urls = (try? context.fetch(descriptor))?.galleryURLs() ?? []
        return mergedGalleryImageURLs(syncedPhotoURLs: urls)
    }
}
