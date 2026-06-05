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
                    // Invalidate the now-stale durable composite so preComposite
                    // regenerates it from the freshly-uploaded overlay rather
                    // than serving the pre-edit markup from disk.
                    ImageFileManager.shared.deleteCompositedImage(forURL: photoURL)
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
                ImageFileManager.shared.deleteCompositedImage(forURL: photoURL)
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
            ImageFileManager.shared.deleteCompositedImage(forURL: photoURL)
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
    /// from ProjectPhotosGrid.task so the full-screen grid re-composites after any
    /// ImageCache eviction, and from PhotoCommentViewer.onAppear for the viewer.
    /// Posts `.annotationsComposited` once per composited photo (see the loop).
    func preCompositeAnnotations(projectId: String, modelContext: ModelContext) async {
        // Active markup annotations for this project (non-deleted).
        let activeDescriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.projectId == projectId && $0.deletedAt == nil
            }
        )
        let annotations = (try? modelContext.fetch(activeDescriptor)) ?? []

        // Cache keys that legitimately carry markup right now — used to spare a
        // photo's composite during the deleted-row reconciliation below when the
        // same photo also still has a live annotation.
        var activeCompositeKeys = Set<String>()

        for annotation in annotations {
            guard let plan = PhotoAnnotationCompositePlan(
                photoURL: annotation.photoURL,
                annotationURL: annotation.annotationURL
            ) else { continue }
            let cacheKey = plan.cacheKey
            activeCompositeKeys.insert(cacheKey)

            // Freshness short-circuit: a durable composite newer than the
            // annotation's last change is still valid. Re-rendering a full-
            // resolution composite is expensive (≈48 MB) and would thrash the
            // budget evictor on every gallery open, so skip it — just make sure
            // the in-memory display cache is warm and nudge any mounted
            // thumbnail to re-read. Local edits delete the composite up front
            // (see saveAnnotation) and remote edits bump `updatedAt`, so a stale
            // composite never survives this check.
            let lastChange = annotation.updatedAt ?? annotation.createdAt
            if let compositeMTime = ImageFileManager.shared.compositedImageModificationDate(forURL: cacheKey),
               compositeMTime >= lastChange {
                if ImageCache.shared.get(forKey: cacheKey) == nil,
                   let durable = ImageFileManager.shared.loadCompositedImage(forURL: cacheKey) {
                    ImageCache.shared.set(durable, forKey: cacheKey)
                }
                NotificationCenter.default.post(name: .annotationsComposited, object: nil)
                continue
            }

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

            ImageCache.shared.set(composited, forKey: cacheKey)

            // Persist the composite so ANY thumbnail can resolve markup the
            // instant it mounts — independent of NSCache eviction or mount
            // timing. This is the durability tier: the in-memory cache holds
            // barely one full-resolution composite, so a thumbnail scrolled into
            // view long after the post fired would otherwise fall back to the
            // raw photo. JPEG (opaque, quality 0.9) keeps the file ~5-6× smaller
            // than a lossless PNG of the same 12 MP frame, which matters because
            // every composite counts against the photo storage budget.
            if let jpeg = composited.jpegData(compressionQuality: 0.9) {
                _ = ImageFileManager.shared.saveCompositedImage(jpeg, forURL: cacheKey)
            }

            // Notify per photo, not once after the loop. Composites are full
            // source resolution (a 12MP photo ≈ 48 MB) and ImageCache is an
            // NSCache with a 50 MB cost limit, so inserting the next composite
            // can evict this one right away. Posting now — synchronously, while
            // this composite is the freshest cache entry — lets each mounted
            // PhotoThumbnail capture its own image into @State (via
            // reloadFromCache) before the next iteration can evict it. A single
            // post after the loop would arrive once most composites had already
            // been evicted, leaving thumbnails showing the raw photo.
            NotificationCenter.default.post(name: .annotationsComposited, object: nil)
        }

        // Reconcile soft-deleted markup: drop durable composites for photos
        // whose annotations are all deleted. Driven by SwiftData `deletedAt`, so
        // it converges for every delete path — gallery long-press, sync merge,
        // realtime — without hooking each one.
        invalidateDeletedComposites(
            projectId: projectId,
            activeCompositeKeys: activeCompositeKeys,
            modelContext: modelContext
        )
    }

    /// Remove durable composites for annotations that have been soft-deleted and
    /// have no surviving markup sibling on the same photo. Reverts the in-memory
    /// display to the raw original (when cached) so a mounted thumbnail listening
    /// for `.annotationsComposited` drops the now-deleted markup instead of
    /// keeping its stale captured copy.
    private func invalidateDeletedComposites(
        projectId: String,
        activeCompositeKeys: Set<String>,
        modelContext: ModelContext
    ) {
        let deletedDescriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.projectId == projectId && $0.deletedAt != nil
            }
        )
        guard let deleted = try? modelContext.fetch(deletedDescriptor), !deleted.isEmpty else { return }

        var invalidated = false
        for annotation in deleted {
            let cacheKey = annotation.photoURL.hasPrefix("//")
                ? "https:" + annotation.photoURL
                : annotation.photoURL
            guard !activeCompositeKeys.contains(cacheKey) else { continue }
            guard ImageFileManager.shared.compositedImageExists(forURL: cacheKey) else { continue }

            _ = ImageFileManager.shared.deleteCompositedImage(forURL: cacheKey)
            if let raw = ImageFileManager.shared.loadImage(localID: cacheKey) {
                ImageCache.shared.set(raw, forKey: cacheKey)
            } else {
                ImageCache.shared.remove(forKey: cacheKey)
            }
            invalidated = true
        }

        if invalidated {
            NotificationCenter.default.post(name: .annotationsComposited, object: nil)
        }
    }

    /// Resolve the RAW, un-composited base for `plan`. Sources are raw-only: the
    /// url-keyed disk original, else a fresh download saved under that same key.
    /// The in-memory `ImageCache[cacheKey]` is deliberately NOT consulted — that
    /// slot holds the flattened composite for display, and reusing it as a base
    /// would draw the new overlay over already-composited pixels (doubled
    /// markup). Durable composites make raw eviction (composite surviving) more
    /// likely, so this raw-only guarantee matters.
    private func loadBaseImage(for plan: PhotoAnnotationCompositePlan) async -> UIImage? {
        for localID in plan.baseLocalIDs {
            if let image = ImageFileManager.shared.loadImage(localID: localID) {
                return image
            }
        }

        guard let baseURL = plan.baseRemoteURL,
              let (data, _) = try? await URLSession.shared.data(from: baseURL),
              let downloaded = UIImage(data: data) else { return nil }

        _ = ImageFileManager.shared.saveImage(data: data, localID: plan.cacheKey)
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
