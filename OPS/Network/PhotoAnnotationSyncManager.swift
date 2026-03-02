//
//  PhotoAnnotationSyncManager.swift
//  OPS
//
//  Handles rendering PKDrawing to PNG, uploading to S3,
//  and syncing annotation records with Supabase.
//

import SwiftUI
import SwiftData
import PencilKit
import Supabase

@MainActor
class PhotoAnnotationSyncManager {
    static let shared = PhotoAnnotationSyncManager()
    private init() {}

    // MARK: - Save Annotation

    /// Render the drawing to a transparent PNG, upload to S3, and save the record.
    /// Falls back to storing drawing data locally for offline sync.
    func saveAnnotation(
        drawing: PKDrawing,
        note: String,
        photoURL: String,
        imageSize: CGSize,
        projectId: String,
        companyId: String,
        authorId: String,
        existingAnnotationId: String?,
        modelContext: ModelContext
    ) async throws -> PhotoAnnotation {
        // Render drawing to transparent PNG
        let pngData = renderDrawingToPNG(drawing: drawing, size: imageSize)

        // Try to upload to S3
        var annotationURL: String? = nil
        if let pngData = pngData {
            do {
                annotationURL = try await uploadAnnotationPNG(
                    data: pngData,
                    projectId: projectId,
                    companyId: companyId
                )
            } catch {
                print("[ANNOTATION SYNC] S3 upload failed, saving locally: \(error)")
            }
        }

        let repository = PhotoAnnotationRepository(companyId: companyId)

        if let existingId = existingAnnotationId {
            // Update existing annotation
            try await repository.updateAnnotation(existingId, annotationUrl: annotationURL, note: note)

            // Update local model
            let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == existingId })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.annotationURL = annotationURL
                existing.note = note
                existing.updatedAt = Date()
                existing.localDrawingData = drawing.dataRepresentation()
                existing.lastSyncedAt = Date()
                existing.needsSync = annotationURL == nil
                try? modelContext.save()
                return existing
            }
        }

        // Create new annotation
        let dto = UpsertPhotoAnnotationDTO(
            projectId: projectId,
            companyId: companyId,
            photoUrl: photoURL,
            annotationUrl: annotationURL,
            note: note,
            authorId: authorId
        )

        let created = try await repository.create(dto)
        let model = created.toModel()
        model.localDrawingData = drawing.dataRepresentation()
        model.lastSyncedAt = Date()
        model.needsSync = annotationURL == nil
        modelContext.insert(model)
        try? modelContext.save()
        return model
    }

    // MARK: - Render Drawing

    private func renderDrawingToPNG(drawing: PKDrawing, size: CGSize) -> Data? {
        guard !drawing.strokes.isEmpty else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            // Transparent background
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            // Render the drawing
            let drawingImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: UIScreen.main.scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: size))
        }

        return image.pngData()
    }

    // MARK: - S3 Upload

    private func uploadAnnotationPNG(data: Data, projectId: String, companyId: String) async throws -> String {
        let session = try await SupabaseService.shared.client.auth.session
        let idToken = session.accessToken

        let timestamp = Date().timeIntervalSince1970
        let filename = "annotation_\(timestamp).png"
        let folder = "annotations/\(companyId)/\(projectId)"

        // Step 1: Get presigned URL
        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/uploads/presign")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = [
            "filename": filename,
            "contentType": "image/png",
            "folder": folder
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (presignData, presignResponse) = try await URLSession.shared.data(for: request)
        guard let httpResponse = presignResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AnnotationSyncError.presignFailed
        }

        let presigned = try JSONDecoder().decode(PresignedURLUploadService.PresignedURLResponse.self, from: presignData)

        // Step 2: Upload PNG to S3
        guard let uploadURL = URL(string: presigned.uploadUrl) else {
            throw AnnotationSyncError.invalidURL
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("image/png", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        uploadRequest.httpBody = data

        let (_, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        guard let uploadHttpResponse = uploadResponse as? HTTPURLResponse,
              (200...299).contains(uploadHttpResponse.statusCode) else {
            throw AnnotationSyncError.s3UploadFailed
        }

        print("[ANNOTATION SYNC] PNG uploaded to S3: \(presigned.publicUrl)")
        return presigned.publicUrl
    }

    // MARK: - Sync Pending

    /// Upload any annotations that were saved locally (offline) and now need to be synced
    func syncPendingAnnotations(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.needsSync == true && $0.deletedAt == nil }
        )

        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }
        print("[ANNOTATION SYNC] Found \(pending.count) pending annotations to sync")

        for annotation in pending {
            guard let drawingData = annotation.localDrawingData else { continue }

            do {
                let drawing = try PKDrawing(data: drawingData)
                // Use a reasonable default size for rendering
                let size = CGSize(width: 1080, height: 1920)
                guard let pngData = renderDrawingToPNG(drawing: drawing, size: size) else { continue }

                let annotationURL = try await uploadAnnotationPNG(
                    data: pngData,
                    projectId: annotation.projectId,
                    companyId: annotation.companyId
                )

                // Update remote
                let repo = PhotoAnnotationRepository(companyId: annotation.companyId)
                try await repo.updateAnnotation(annotation.id, annotationUrl: annotationURL, note: annotation.note)

                // Update local
                annotation.annotationURL = annotationURL
                annotation.needsSync = false
                annotation.lastSyncedAt = Date()
                try? modelContext.save()
            } catch {
                print("[ANNOTATION SYNC] Failed to sync annotation \(annotation.id): \(error)")
            }
        }
    }
}

// MARK: - Errors

enum AnnotationSyncError: Error, LocalizedError {
    case presignFailed
    case invalidURL
    case s3UploadFailed

    var errorDescription: String? {
        switch self {
        case .presignFailed: return "Failed to get upload URL"
        case .invalidURL: return "Invalid upload URL"
        case .s3UploadFailed: return "Failed to upload annotation"
        }
    }
}
