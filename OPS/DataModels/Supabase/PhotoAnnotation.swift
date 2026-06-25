//
//  PhotoAnnotation.swift
//  OPS
//
//  Drawing overlay and text note for a project photo — Supabase-backed
//

import SwiftData
import Foundation

@Model
class PhotoAnnotation: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var photoURL: String
    var annotationURL: String?
    var note: String
    var authorId: String
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    /// Synced to `project_photo_annotations.rendered_photo_url`.
    /// Derived 2048-long-edge PNG deliverable with burned-in dimensions;
    /// `photoURL` remains the source HEIC/photo URL.
    var renderedPhotoURL: String?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Local-only: PKDrawing data for offline editing
    var localDrawingData: Data?

    // MARK: - Collaborative markup layers (spec 2026-06-23)
    // Additive nullable — safe under the iOS sync constraint. Each author owns a
    // layer; peers' overlays composite as a non-editable base under the current
    // user's canvas (the #1 fix: a peer's marks are visible, not overwritten).

    /// Synced to `project_photo_annotations.layers` jsonb. Codable encoding of
    /// `[MarkupLayer]`. NULL for legacy single-overlay annotations until lazily
    /// migrated on next edit.
    var layersData: Data?

    /// Synced to `project_photo_annotations.change_log` jsonb. Codable encoding
    /// of `[MarkupChangeEvent]` (append-only per-author history).
    var changeLogData: Data?

    /// Synced to `project_photo_annotations.before_snapshot_url` — most-recent
    /// markup event's baked BEFORE composite. DEFERRED (null until snapshots ship).
    var beforeSnapshotURL: String?

    /// Synced to `project_photo_annotations.after_snapshot_url` — most-recent
    /// markup event's baked AFTER composite. DEFERRED (null until snapshots ship).
    var afterSnapshotURL: String?

    /// Local-only: author ids the current viewer has hidden via the change-log
    /// eye toggle. A per-viewer preference — NEVER synced (must not touch peers).
    var hiddenAuthorIdsData: Data?

    // MARK: - LiDAR Dimensioned Capture (spec 2026-05-10)
    // All four fields are additive nullable — safe under the iOS sync constraint.

    /// Synced to Supabase `project_photo_annotations.dimensions` jsonb column.
    /// Codable encoding of `DimensionsData`. NULL for legacy PencilKit-only annotations.
    var dimensionsData: Data?

    /// Local-only: file path to the cached FP32 depth map. Never synced.
    /// The depth itself uploads to S3; the URL is recorded inside `dimensionsData.depthAssetUrl`.
    var localDepthMapPath: String?

    /// Local-only: file path to the cached sidecar metadata JSON. Never synced.
    var localSidecarPath: String?

    /// Local-only: when the LiDAR capture finished. Used to dedupe in-flight uploads.
    var localCaptureFinishedAt: Date?

    init(
        id: String = UUID().uuidString,
        projectId: String,
        companyId: String,
        photoURL: String,
        authorId: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.companyId = companyId
        self.photoURL = photoURL
        self.note = ""
        self.authorId = authorId
        self.createdAt = createdAt
    }
}

// MARK: - Typed dimensions accessor

extension PhotoAnnotation {
    /// Typed read/write access to `dimensionsData`. Uses `DimensionsData.jsonEncoder`/`jsonDecoder`
    /// which apply snake_case key conversion to match the Supabase jsonb shape.
    var dimensions: DimensionsData? {
        get {
            guard let data = dimensionsData else { return nil }
            return try? DimensionsData.jsonDecoder.decode(DimensionsData.self, from: data)
        }
        set {
            guard let newValue else {
                dimensionsData = nil
                return
            }
            dimensionsData = try? DimensionsData.jsonEncoder.encode(newValue)
        }
    }
}

// MARK: - Typed markup-layer accessors (collaborative markup, spec 2026-06-23)

extension PhotoAnnotation {
    /// Author-scoped markup layers. Empty when this is a legacy single-overlay or
    /// dimensioned-only annotation. Resilient decode: a single malformed layer
    /// never nukes the rest of the row's markup.
    var layers: [MarkupLayer] {
        get { MarkupCoding.decodeArray(layersData) }
        set { layersData = MarkupCoding.encodeArray(newValue) }
    }

    /// Append-only per-author change history.
    var changeLog: [MarkupChangeEvent] {
        get { MarkupCoding.decodeArray(changeLogData) }
        set { changeLogData = MarkupCoding.encodeArray(newValue) }
    }

    /// Author ids the current viewer has hidden via the change-log eye toggle.
    /// Local-only, per-viewer — NEVER synced.
    var hiddenAuthorIds: Set<String> {
        get {
            guard let data = hiddenAuthorIdsData else { return [] }
            return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
        }
        set {
            hiddenAuthorIdsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    /// The caller's own layer (layerId == their user id), if any.
    func ownLayer(userId: String) -> MarkupLayer? {
        layers.first { $0.layerId == userId }
    }

    /// Every OTHER author's layer that is still active (not cleared) and not
    /// hidden by the current viewer — the set composited as the editor base.
    func visiblePeerLayers(userId: String) -> [MarkupLayer] {
        layers
            .filter { $0.layerId != userId && $0.isActive && !hiddenAuthorIds.contains($0.authorId) }
            .sorted { $0.zIndex < $1.zIndex }
    }

    /// Distinct authors that currently have an active layer (drives the change-log
    /// sheet + the toolbar author-count badge).
    func activeAuthorLayers() -> [MarkupLayer] {
        layers.filter { $0.isActive }.sorted { $0.zIndex < $1.zIndex }
    }

    /// Real layers, or a single SYNTHESIZED layer for a legacy `annotation_url`-only
    /// row (so a legacy overlay is treated as its original author's layer for
    /// display, peer compositing, and author-scoped clear). The RPC's server-side
    /// legacy-seed persists this shape the first time any layer is written.
    func effectiveMarkupLayers() -> [MarkupLayer] {
        if !layers.isEmpty { return layers }
        guard let url = annotationURL,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [MarkupLayer(
            layerId: authorId,
            authorId: authorId,
            authorName: "",
            overlayUrl: url,
            strokeRef: nil,
            visibleDefault: true,
            zIndex: 0,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt
        )]
    }
}
