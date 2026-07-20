//
//  MarkupStrokeStore.swift
//  OPS
//
//  Persists each author's editable PKDrawing stroke blob as an S3 object (via the
//  existing presign path) and resumes it cross-device. The blob's URL is the
//  layer's `strokeRef` — we never inline base64 in the layers jsonb (that would
//  bloat every get_photo_annotations_since pull). Mirrors the overlay PNG upload.
//

import Foundation
import PencilKit

enum MarkupStrokeStore {

    /// Upload an author's PKDrawing strokes as an octet-stream S3 object, returning
    /// the public URL to store as the layer's `strokeRef`.
    static func uploadStroke(
        _ drawing: PKDrawing,
        projectId: String,
        companyId: String
    ) async throws -> String {
        let data = drawing.dataRepresentation()
        let filename = "markup_\(Int(Date().timeIntervalSince1970 * 1000)).pkdrawing"
        let folder = "annotations/\(companyId)/\(projectId)/strokes"
        return try await PresignedURLUploadService.shared.uploadAsset(
            data,
            filename: filename,
            folder: folder,
            contentType: "application/octet-stream"
        )
    }

    /// Resume an author's own editable strokes from their `strokeRef`. Used only
    /// when the local canvas is empty (cross-device / reinstall), so no on-disk
    /// cache is warranted — the blob is small and the path is rare.
    static func loadDrawing(strokeRef: String) async -> PKDrawing? {
        let normalized = strokeRef.hasPrefix("//") ? "https:" + strokeRef : strokeRef
        guard let url = URL(string: normalized),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let drawing = try? PKDrawing(data: data) else { return nil }
        return drawing
    }
}
