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
// FirebaseAuthService used for token retrieval (Firebase Auth migration)

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

                // Cache overlay PNG locally for instant compositing on next load
                if let pngData = pngData {
                    _ = ImageFileManager.shared.saveImage(data: pngData, localID: "overlay_\(existingId)")
                }

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

        // Cache overlay PNG locally for instant compositing on next load
        if let pngData = pngData {
            _ = ImageFileManager.shared.saveImage(data: pngData, localID: "overlay_\(created.id)")
        }

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

    // MARK: - Upload

    /// Upload annotation PNG via multipart form data to /api/uploads/presign.
    /// The API uploads directly to Supabase Storage and returns `{ url, publicUrl }`.
    private func uploadAnnotationPNG(data: Data, projectId: String, companyId: String) async throws -> String {
        let idToken = try await FirebaseAuthService.shared.getIDToken()

        let timestamp = Date().timeIntervalSince1970
        let filename = "annotation_\(timestamp).png"
        let folder = "annotations/\(companyId)/\(projectId)"

        let boundary = "Boundary-\(UUID().uuidString)"
        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/uploads/presign")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        // Build multipart body
        var body = Data()

        // folder field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"folder\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(folder)\r\n".data(using: .utf8)!)

        // file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: responseData, encoding: .utf8) ?? "no body"
            print("[ANNOTATION SYNC] Upload failed (\(statusCode)): \(responseBody)")
            throw AnnotationSyncError.uploadFailed
        }

        let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        let publicUrl = result.publicUrl ?? result.url ?? ""

        guard !publicUrl.isEmpty else {
            throw AnnotationSyncError.invalidURL
        }

        print("[ANNOTATION SYNC] PNG uploaded: \(publicUrl)")
        return publicUrl
    }

    /// Response from /api/uploads/presign (multipart upload)
    private struct UploadResponse: Codable {
        let url: String?
        let publicUrl: String?
    }

    // MARK: - Pre-Composite Into Cache

    /// Composite all annotations for a project into the in-memory image cache.
    /// Uses locally-cached overlay PNGs when available (instant), falls back to download.
    /// Call from ProjectDetailsView.onAppear so gallery thumbnails show annotations,
    /// and from PhotoCommentViewer.onAppear for the full-screen viewer.
    func preCompositeAnnotations(projectId: String, modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.projectId == projectId && $0.deletedAt == nil
            }
        )
        guard let annotations = try? modelContext.fetch(descriptor), !annotations.isEmpty else { return }

        var didComposite = false
        for annotation in annotations {
            guard let urlString = annotation.annotationURL,
                  let overlayURL = URL(string: urlString) else { continue }

            let photoURL = annotation.photoURL
            let cacheKey = photoURL.hasPrefix("//") ? "https:" + photoURL : photoURL

            // Load base image from file system (original, un-composited)
            // Also check ImageCache as fallback (thumbnails may have loaded it)
            guard let baseImage = ImageFileManager.shared.loadImage(localID: photoURL)
                    ?? ImageFileManager.shared.loadImage(localID: cacheKey)
                    ?? ImageCache.shared.get(forKey: cacheKey) else { continue }

            // Load overlay from local cache or download
            let overlayKey = "overlay_\(annotation.id)"
            var overlayImage: UIImage?

            if let cached = ImageFileManager.shared.loadImage(localID: overlayKey) {
                overlayImage = cached
            } else {
                if let (data, _) = try? await URLSession.shared.data(from: overlayURL),
                   let downloaded = UIImage(data: data) {
                    overlayImage = downloaded
                    if let pngData = downloaded.pngData() {
                        _ = ImageFileManager.shared.saveImage(data: pngData, localID: overlayKey)
                    }
                }
            }

            guard let overlay = overlayImage else { continue }

            let originalSize = baseImage.size
            let renderer = UIGraphicsImageRenderer(size: originalSize)
            let composited = renderer.image { _ in
                baseImage.draw(in: CGRect(origin: .zero, size: originalSize))
                overlay.draw(in: CGRect(origin: .zero, size: originalSize))
            }

            ImageCache.shared.set(composited, forKey: cacheKey)
            didComposite = true
        }

        if didComposite {
            NotificationCenter.default.post(name: .annotationsComposited, object: nil)
        }
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

// MARK: - Notification

extension Notification.Name {
    static let annotationsComposited = Notification.Name("annotationsComposited")
}

// MARK: - Errors

enum AnnotationSyncError: Error, LocalizedError {
    case uploadFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .uploadFailed: return "Failed to upload annotation"
        case .invalidURL: return "Invalid upload URL"
        }
    }
}
