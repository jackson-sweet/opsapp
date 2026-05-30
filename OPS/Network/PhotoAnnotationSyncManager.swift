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

struct PhotoAnnotationRenderGeometry {
    static func renderSize(displayedCanvasSize: CGSize, sourceImageSize: CGSize) -> CGSize {
        if displayedCanvasSize.width > 0, displayedCanvasSize.height > 0 {
            return displayedCanvasSize
        }
        if sourceImageSize.width > 0, sourceImageSize.height > 0 {
            return sourceImageSize
        }
        return .zero
    }
}

struct PhotoAnnotationCompositePlan {
    let cacheKey: String
    let baseLocalIDs: [String]
    let baseRemoteURL: URL?
    let overlayRemoteURL: URL

    init?(photoURL: String, annotationURL: String?) {
        guard let annotationURL,
              let overlayURL = Self.normalizedURL(from: annotationURL) else { return nil }

        self.cacheKey = Self.normalizedCacheKey(photoURL)
        self.baseLocalIDs = Array([photoURL, cacheKey].reduce(into: [String]()) { result, value in
            guard !value.isEmpty, !result.contains(value) else { return }
            result.append(value)
        })
        self.baseRemoteURL = Self.normalizedURL(from: photoURL)
        self.overlayRemoteURL = overlayURL
    }

    func overlayLocalID(annotationId: String) -> String {
        "overlay_\(annotationId)"
    }

    private static func normalizedCacheKey(_ value: String) -> String {
        value.hasPrefix("//") ? "https:" + value : value
    }

    private static func normalizedURL(from value: String) -> URL? {
        let normalized = normalizedCacheKey(value)
        return URL(string: normalized)
    }
}

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
                // Auto-bug-reporting (May-12 follow-up): a permanent 4xx
                // on the presigned-URL flow means the user's annotation
                // will queue locally forever and never reach S3. We need
                // to know. Transient errors fall through to the local-save
                // fallback below — needsSync stays true so the cross-session
                // sweeper can pick it up later.
                await AutoBugReporter.shared.reportIfPermanent(
                    error,
                    screen: "PhotoAnnotationSyncManager.uploadAnnotationPNG",
                    suspectedFile: "PhotoAnnotationSyncManager.swift",
                    summary: "Annotation PNG S3 upload failed for project \(projectId): \(error.localizedDescription)",
                    metadata: [
                        "project_id": projectId,
                        "company_id": companyId,
                        "byte_count": pngData.count
                    ]
                )
                DebugLogger.shared.log(
                    "Annotation PNG upload failed, saving locally: \(error)",
                    level: .warning,
                    category: "PhotoAnnotationSyncManager"
                )
            }
        }

        let repository = PhotoAnnotationRepository(companyId: companyId)

        if let existingId = existingAnnotationId {
            if let annotationURL {
                try await repository.updateAnnotation(existingId, annotationUrl: annotationURL, note: note)
            }

            // Update local model
            let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == existingId })
            if let existing = try? modelContext.fetch(descriptor).first {
                if let annotationURL {
                    existing.annotationURL = annotationURL
                }
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

                if annotationURL != nil {
                    await preCompositeAnnotations(projectId: projectId, modelContext: modelContext)
                }

                return existing
            }

            let model = PhotoAnnotation(
                id: existingId,
                projectId: projectId,
                companyId: companyId,
                photoURL: photoURL,
                authorId: authorId
            )
            model.annotationURL = annotationURL
            model.note = note
            model.updatedAt = Date()
            model.localDrawingData = drawing.dataRepresentation()
            model.lastSyncedAt = Date()
            model.needsSync = annotationURL == nil
            modelContext.insert(model)
            try? modelContext.save()

            if let pngData = pngData {
                _ = ImageFileManager.shared.saveImage(data: pngData, localID: "overlay_\(existingId)")
            }

            if annotationURL != nil {
                await preCompositeAnnotations(projectId: projectId, modelContext: modelContext)
            }

            return model
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

        if annotationURL != nil {
            await preCompositeAnnotations(projectId: projectId, modelContext: modelContext)
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
            guard let plan = PhotoAnnotationCompositePlan(
                photoURL: annotation.photoURL,
                annotationURL: annotation.annotationURL
            ) else { continue }

            // Load the original, un-composited image. A remote device may
            // receive the annotation row before it has ever opened the source
            // image, so cache misses must fall through to the source URL.
            guard let baseImage = await loadBaseImage(for: plan) else { continue }

            // Load overlay from local cache or download
            let overlayKey = plan.overlayLocalID(annotationId: annotation.id)
            var overlayImage: UIImage?

            if let cached = ImageFileManager.shared.loadImage(localID: overlayKey) {
                overlayImage = cached
            } else {
                if let (data, _) = try? await URLSession.shared.data(from: plan.overlayRemoteURL),
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

            ImageCache.shared.set(composited, forKey: plan.cacheKey)
            didComposite = true
        }

        if didComposite {
            NotificationCenter.default.post(name: .annotationsComposited, object: nil)
        }
    }

    private func loadBaseImage(for plan: PhotoAnnotationCompositePlan) async -> UIImage? {
        for localID in plan.baseLocalIDs {
            if let image = ImageFileManager.shared.loadImage(localID: localID) {
                return image
            }
        }

        if let cached = ImageCache.shared.get(forKey: plan.cacheKey) {
            return cached
        }

        guard let baseURL = plan.baseRemoteURL,
              let (data, _) = try? await URLSession.shared.data(from: baseURL),
              let downloaded = UIImage(data: data) else { return nil }

        _ = ImageFileManager.shared.saveImage(data: data, localID: plan.cacheKey)
        ImageCache.shared.set(downloaded, forKey: plan.cacheKey)
        return downloaded
    }

    // MARK: - Sync Pending

    /// Upload any annotations that were saved locally (offline) and now need to be synced
    func syncPendingAnnotations(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.needsSync == true }
        )

        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }
        print("[ANNOTATION SYNC] Found \(pending.count) pending annotations to sync")

        for annotation in pending {
            if annotation.deletedAt != nil {
                if ProjectPhotoAnnotationDeletePlanner.isLocalOnlyAnnotationID(annotation.id) {
                    annotation.needsSync = false
                    try? modelContext.save()
                    continue
                }

                do {
                    let repo = PhotoAnnotationRepository(companyId: annotation.companyId)
                    try await repo.softDelete(annotation.id)

                    annotation.needsSync = false
                    annotation.lastSyncedAt = Date()
                    try? modelContext.save()
                } catch {
                    await AutoBugReporter.shared.reportIfPermanent(
                        error,
                        screen: "PhotoAnnotationSyncManager.syncPendingAnnotations",
                        suspectedFile: "PhotoAnnotationSyncManager.swift",
                        summary: "Annotation delete retry failed for \(annotation.id): \(error.localizedDescription)",
                        metadata: [
                            "annotation_id": annotation.id,
                            "project_id": annotation.projectId,
                            "company_id": annotation.companyId
                        ]
                    )
                    DebugLogger.shared.log(
                        "Annotation delete retry failed for \(annotation.id): \(error)",
                        level: .warning,
                        category: "PhotoAnnotationSyncManager"
                    )
                }
                continue
            }

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
                // Auto-bug-reporting (May-12 follow-up): the retry loop
                // hammers the same row every sweep — auto-bug on permanent
                // so the dev team intervenes before the queue silently
                // bloats with poisoned annotations.
                await AutoBugReporter.shared.reportIfPermanent(
                    error,
                    screen: "PhotoAnnotationSyncManager.syncPendingAnnotations",
                    suspectedFile: "PhotoAnnotationSyncManager.swift",
                    summary: "Annotation retry failed for \(annotation.id): \(error.localizedDescription)",
                    metadata: [
                        "annotation_id": annotation.id,
                        "project_id": annotation.projectId,
                        "company_id": annotation.companyId
                    ]
                )
                DebugLogger.shared.log(
                    "Annotation sync retry failed for \(annotation.id): \(error)",
                    level: .warning,
                    category: "PhotoAnnotationSyncManager"
                )
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
