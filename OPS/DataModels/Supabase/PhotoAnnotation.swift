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
