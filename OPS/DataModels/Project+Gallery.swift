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

// MARK: - Gallery Ordering

/// Stable identity for photo URLs that are equivalent throughout the app.
/// Legacy project CSVs may store a protocol-relative URL while the canonical
/// `project_photos` row stores the same resource with an HTTPS scheme.
enum GalleryPhotoURLIdentity {
    static func canonical(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
    }
}

/// Newest-first ordering for the project photo gallery (bug e7ef2c88 — new
/// photos were inserting mid-list). A photo's sort date is resolved, in order:
///   1. the synced `project_photos` row date (`takenAt ?? createdAt`), when present
///   2. the timestamp embedded in the upload filename
///   3. `.distantPast` — legacy/migrated URLs with no signal sink to the tail
///      in their original CSV order (a stable sort preserves it)
enum GalleryOrdering {

    /// Extract the capture timestamp encoded in an OPS upload filename.
    /// Recognised shapes (the last path component, percent-decoded):
    ///   - web:            `<epochMillis>-<rand>.jpg`      (13-digit integer)
    ///   - project upload: `<street>_IMG_<epochSeconds>_<i>.jpg`
    ///   - note upload:     `note_<epochSeconds>_<i>.jpg`
    ///   - offline local:   `local_project_<pid>_<epochSeconds>_<i>.jpg`
    /// `epochSeconds` may carry a fractional part (`timeIntervalSince1970`).
    static func timestamp(fromURL url: String) -> Date? {
        guard !url.isEmpty else { return nil }
        let lastComponent = (url as NSString).lastPathComponent.removingPercentEncoding
            ?? (url as NSString).lastPathComponent

        // web millis: leading 13-digit block before a hyphen
        if let dash = lastComponent.firstIndex(of: "-") {
            let head = String(lastComponent[..<dash])
            if head.count == 13, let millis = Double(head) {
                return Date(timeIntervalSince1970: millis / 1000.0)
            }
        }

        // `_IMG_<seconds>_`, `note_<seconds>_`, `local_project_..._<seconds>_`
        // all share a trailing `_<epochSeconds>_<index>.<ext>`; the epoch is the
        // second-to-last underscore-delimited token that parses as a Double > 10^8.
        let stem = (lastComponent as NSString).deletingPathExtension
        let tokens = stem.components(separatedBy: "_")
        for token in tokens.reversed() {
            if let value = Double(token), value > 100_000_000 {
                return Date(timeIntervalSince1970: value)
            }
        }
        return nil
    }

    /// Merge the legacy CSV URLs with the synced-photo dates into one
    /// newest-first, deduplicated list. Empty strings drop. Stable: equal dates
    /// (and the undated tail) keep their incoming CSV-then-synced order.
    static func orderedNewestFirst(
        csvURLs: [String],
        syncedPhotoDates: [(url: String, date: Date)],
        excludedURLIdentities: Set<String> = []
    ) -> [String] {
        let excludedIdentities = Set(excludedURLIdentities.map(GalleryPhotoURLIdentity.canonical))
        let rowDateByURL = Dictionary(
            syncedPhotoDates.compactMap { entry -> (String, Date)? in
                let identity = GalleryPhotoURLIdentity.canonical(entry.url)
                guard !identity.isEmpty, !excludedIdentities.contains(identity) else { return nil }
                return (identity, entry.date)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Preserve first-seen order across CSV then synced-only URLs; dedupe by
        // canonical identity while retaining the first display URL.
        var order: [String] = []
        var seen = Set<String>()
        for rawURL in csvURLs {
            let displayURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = GalleryPhotoURLIdentity.canonical(displayURL)
            guard !identity.isEmpty,
                  !excludedIdentities.contains(identity),
                  seen.insert(identity).inserted else { continue }
            order.append(displayURL)
        }
        for entry in syncedPhotoDates {
            let displayURL = entry.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = GalleryPhotoURLIdentity.canonical(displayURL)
            guard !identity.isEmpty,
                  !excludedIdentities.contains(identity),
                  seen.insert(identity).inserted else { continue }
            order.append(displayURL)
        }

        func sortDate(for url: String) -> Date {
            rowDateByURL[GalleryPhotoURLIdentity.canonical(url)]
                ?? timestamp(fromURL: url)
                ?? .distantPast
        }

        // enumerated() index as the tiebreaker keeps the sort stable across the
        // undated tail and any equal timestamps.
        return order.enumerated()
            .sorted { lhs, rhs in
                let dl = sortDate(for: lhs.element)
                let dr = sortDate(for: rhs.element)
                if dl != dr { return dl > dr }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }
}

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

    /// Merge inputs derived from every canonical row, including tombstones.
    /// An ineligible row suppresses a stale legacy CSV alias unless another
    /// active real-photo row still owns the same canonical URL identity.
    func galleryMergeState() -> ProjectPhotoGalleryMergeState {
        let rows = Array(self)
        let eligible = rows.filter { $0.isGalleryEligible }
        let eligibleIdentities = Set(eligible.map { GalleryPhotoURLIdentity.canonical($0.url) })
        let excludedIdentities = Set(
            rows.filter { !$0.isGalleryEligible }
                .map { GalleryPhotoURLIdentity.canonical($0.url) }
                .filter { !$0.isEmpty }
        ).subtracting(eligibleIdentities)

        return ProjectPhotoGalleryMergeState(
            eligibleDates: eligible.map { ($0.url, $0.takenAt ?? $0.createdAt) },
            excludedURLIdentities: excludedIdentities
        )
    }
}

struct ProjectPhotoGalleryMergeState {
    let eligibleDates: [(url: String, date: Date)]
    let excludedURLIdentities: Set<String>
}

extension Project {
    /// Newest-first gallery list: already-fetched synced `ProjectPhoto` rows
    /// unioned with the legacy CSV, ordered by capture date (bug e7ef2c88).
    /// Deduped by URL; empty strings and non-gallery / soft-deleted rows dropped.
    func mergedGalleryImageURLs(syncedPhotos: [ProjectPhoto]) -> [String] {
        let state = syncedPhotos.galleryMergeState()
        return GalleryOrdering.orderedNewestFirst(
            csvURLs: getProjectImages(),
            syncedPhotoDates: state.eligibleDates,
            excludedURLIdentities: state.excludedURLIdentities
        )
    }

    /// Convenience overload that fetches live `ProjectPhoto` rows for this
    /// project from `context`, then merges newest-first. Tombstones are fetched
    /// intentionally so a failed legacy CSV delete cannot resurrect a photo.
    /// Used where a reactive `@Query` isn't available — the cold-start fallback
    /// carousel and the full-screen viewer's one-shot present.
    func mergedGalleryImageURLs(using context: ModelContext) -> [String] {
        let pid = id
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate { $0.projectId == pid }
        )
        let photos = (try? context.fetch(descriptor)) ?? []
        return mergedGalleryImageURLs(syncedPhotos: photos)
    }
}
