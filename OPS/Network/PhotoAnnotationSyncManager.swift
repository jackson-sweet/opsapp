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

    // MARK: - Permanent-failure parking

    /// Parked annotation ids that already used their one retry this launch.
    private var parkedRetriedThisLaunch: Set<String> = []

    /// Reset retry-hygiene state after any successful server write of `annotation`.
    private func noteSyncSuccess(_ annotation: PhotoAnnotation) {
        annotation.syncFailureCount = 0
        annotation.syncParkedAt = nil
        parkedRetriedThisLaunch.remove(annotation.id)
    }

    /// Record a sweep failure. Only PERMANENT rejections count toward the
    /// park threshold — transient network noise must keep retrying freely.
    private func notePermanentFailure(_ annotation: PhotoAnnotation, kind: UploadErrorKind) {
        guard case .permanent = kind else { return }
        annotation.syncFailureCount = AnnotationRetryPolicy.nextFailureCount(after: annotation.syncFailureCount)
        guard annotation.syncParkedAt == nil,
              AnnotationRetryPolicy.shouldPark(failureCount: annotation.syncFailureCount) else { return }
        annotation.syncParkedAt = Date()
        DebugLogger.shared.log(
            "Annotation \(annotation.id) parked after \(annotation.syncFailureCount) permanent sync failures — retrying once per launch from here",
            level: .warning,
            category: "PhotoAnnotationSyncManager"
        )
    }

    // MARK: - Save Annotation

    /// Save the CURRENT USER'S OWN markup layer. Renders the PencilKit drawing to a
    /// transparent overlay PNG (peers' base) + uploads the editable stroke blob,
    /// then merges the layer into the shared anchor row SERVER-SIDE via
    /// upsert_markup_layer (per-author, atomic — never a wholesale overwrite that
    /// would drop a peer's layer). An empty drawing routes to an author-scoped
    /// clear. Upload/RPC failures queue the layer locally (needsSync) for the sweep.
    func saveAnnotation(
        drawing: PKDrawing,
        note: String,
        photoURL: String,
        imageSize: CGSize,
        projectId: String,
        companyId: String,
        authorId: String,
        authorName: String,
        existingAnnotationId: String?,
        modelContext: ModelContext
    ) async throws -> PhotoAnnotation {
        let pngData = renderDrawingToPNG(drawing: drawing, size: imageSize)

        // Empty drawing -> author-scoped clear (never clobbers a peer's layer).
        guard let pngData else {
            return try await applyAuthorScopedClear(
                existingAnnotationId: existingAnnotationId,
                photoURL: photoURL,
                projectId: projectId,
                companyId: companyId,
                authorId: authorId,
                authorName: authorName,
                modelContext: modelContext
            )
        }

        // Upload the overlay PNG (the peers' base) + the editable stroke blob.
        // Best effort — a failure leaves both nil and queues the layer locally.
        var overlayURL: String?
        var strokeRef: String?
        do {
            overlayURL = try await uploadAnnotationPNG(data: pngData, projectId: projectId, companyId: companyId)
            strokeRef = try? await MarkupStrokeStore.uploadStroke(drawing, projectId: projectId, companyId: companyId)
        } catch {
            await AutoBugReporter.shared.reportIfPermanent(
                error,
                screen: "PhotoAnnotationSyncManager.uploadAnnotationPNG",
                suspectedFile: "PhotoAnnotationSyncManager.swift",
                summary: "Annotation PNG S3 upload failed for project \(projectId): \(error.localizedDescription)",
                metadata: ["project_id": projectId, "company_id": companyId, "byte_count": pngData.count]
            )
            DebugLogger.shared.log("Annotation PNG upload failed, saving locally: \(error)",
                                   level: .warning, category: "PhotoAnnotationSyncManager")
        }

        let now = Date()
        let repository = PhotoAnnotationRepository(companyId: companyId)

        // Resolve / create the shared anchor row (first-creation requires network).
        let anchor = try await resolveAnchorRow(
            existingAnnotationId: existingAnnotationId, photoURL: photoURL,
            projectId: projectId, companyId: companyId, authorId: authorId,
            note: note, overlayURL: overlayURL, repository: repository, modelContext: modelContext
        )

        // Build this user's layer + change event.
        let priorOwn = anchor.ownLayer(userId: authorId)
        let zIndex = priorOwn?.zIndex ?? ((anchor.layers.map(\.zIndex).max() ?? -1) + 1)
        let layer = MarkupLayer(
            layerId: authorId, authorId: authorId, authorName: authorName,
            overlayUrl: overlayURL, strokeRef: strokeRef, visibleDefault: true,
            zIndex: zIndex, strokeCount: drawing.strokes.count,
            createdAt: priorOwn?.createdAt ?? now, updatedAt: now, clearedAt: nil
        )
        let event = MarkupChangeEvent(
            authorId: authorId, authorName: authorName,
            action: priorOwn == nil ? .added : .edited,
            strokeDelta: drawing.strokes.count, at: now
        )

        anchor.note = note
        anchor.localDrawingData = drawing.dataRepresentation()

        if overlayURL != nil {
            // Online: merge the layer server-side, then take the merged row.
            do {
                let dto = try await repository.upsertLayer(annotationId: anchor.id, layer: layer, changeEvent: event)
                applyServerRow(dto, to: anchor)
                // The RPC write landed — reset permanent-failure hygiene.
                noteSyncSuccess(anchor)
                if !ProjectPhotoAnnotationDeletePlanner.isLocalOnlyAnnotationID(anchor.id) {
                    try? await repository.updateNote(anchor.id, note: note)
                }
                anchor.needsSync = false
                anchor.lastSyncedAt = now
            } catch {
                mergeLocalLayer(layer, event: event, into: anchor)
                anchor.needsSync = true
                let kind = await AutoBugReporter.shared.reportIfPermanent(
                    error,
                    screen: "PhotoAnnotationSyncManager.upsertLayer",
                    suspectedFile: "PhotoAnnotationSyncManager.swift",
                    summary: "Markup layer upsert failed for \(anchor.id): \(error.localizedDescription)",
                    metadata: ["annotation_id": anchor.id, "project_id": projectId, "company_id": companyId]
                )
                notePermanentFailure(anchor, kind: kind)
            }
        } else {
            // Offline / upload failed: queue the layer locally for the sweep.
            mergeLocalLayer(layer, event: event, into: anchor)
            anchor.needsSync = true
        }

        try? modelContext.save()

        // Cache the own overlay by URL + refresh the gallery composite.
        if let url = overlayURL {
            _ = ImageFileManager.shared.saveImage(data: pngData, localID: MarkupOverlayCompositor.overlayCacheID(forURL: url))
        }
        ImageFileManager.shared.deleteCompositedImage(forURL: photoURL)
        await preCompositeAnnotations(projectId: projectId, modelContext: modelContext)

        return anchor
    }

    /// Return the shared anchor PhotoAnnotation for this photo, creating it (remote
    /// insert + local insert) when none exists. First-creation requires network —
    /// offline throws, matching the pre-collab behaviour (offline EDITS still queue).
    private func resolveAnchorRow(
        existingAnnotationId: String?, photoURL: String, projectId: String,
        companyId: String, authorId: String, note: String, overlayURL: String?,
        repository: PhotoAnnotationRepository, modelContext: ModelContext
    ) async throws -> PhotoAnnotation {
        if let id = existingAnnotationId {
            let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == id })
            if let existing = try? modelContext.fetch(descriptor).first { return existing }
        }
        let dto = UpsertPhotoAnnotationDTO(
            projectId: projectId, companyId: companyId, photoUrl: photoURL,
            annotationUrl: overlayURL, note: note, authorId: authorId
        )
        let created = try await repository.create(dto)
        let model = created.toModel()
        model.lastSyncedAt = Date()
        modelContext.insert(model)
        return model
    }

    /// Take the server's merged row wholesale after our own RPC write (authoritative).
    private func applyServerRow(_ dto: PhotoAnnotationDTO, to model: PhotoAnnotation) {
        model.layersData = dto.layersData
        model.changeLogData = dto.changeLogData
        model.annotationURL = dto.annotationUrl
        model.beforeSnapshotURL = dto.beforeSnapshotUrl
        model.afterSnapshotURL = dto.afterSnapshotUrl
        model.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
        model.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } ?? Date()
    }

    /// Merge the current user's layer into the LOCAL row (offline path): promote a
    /// legacy single overlay into its author's layer first (mirrors the RPC seed),
    /// replace/append the caller's layer, append the event, and recompute the
    /// legacy scalar + the author-scoped soft-delete state.
    private func mergeLocalLayer(_ layer: MarkupLayer, event: MarkupChangeEvent, into model: PhotoAnnotation) {
        var base = model.effectiveMarkupLayers()
        base.removeAll { $0.layerId == layer.layerId }
        base.append(layer)
        model.layers = base.sorted { $0.zIndex < $1.zIndex }

        var log = model.changeLog
        log.append(event)
        model.changeLog = log

        model.annotationURL = MarkupLayerMerge.primaryOverlay(model.layers)
        if MarkupLayerMerge.allCleared(model.layers) && model.dimensionsData == nil {
            model.deletedAt = Date()
        } else {
            model.deletedAt = nil
        }
        model.updatedAt = Date()
    }

    // MARK: - Author-scoped Clear (HARD CORRECTION 3)

    /// Handle a save whose drawing is empty (CLEAR then DONE). Clears ONLY the
    /// current user's layer via the RPC (sets their `clearedAt`); the whole row
    /// soft-deletes server-side only when that was the last active layer and no
    /// dimensioned capture remains. Opening a PEER's row and tapping DONE with no
    /// marks of your own is a no-op — it never deletes the peer's layer/row.
    private func applyAuthorScopedClear(
        existingAnnotationId: String?,
        photoURL: String,
        projectId: String,
        companyId: String,
        authorId: String,
        authorName: String,
        modelContext: ModelContext
    ) async throws -> PhotoAnnotation {
        let existing: PhotoAnnotation? = existingAnnotationId.flatMap { id in
            let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == id })
            return try? modelContext.fetch(descriptor).first
        }
        let layers = existing?.effectiveMarkupLayers() ?? []
        let action = AnnotationClearPlanner.plan(
            existingAnnotationId: existingAnnotationId,
            hasDimensions: existing?.dimensionsData != nil,
            layers: layers,
            currentUserId: authorId
        )

        func placeholder() -> PhotoAnnotation {
            PhotoAnnotation(projectId: projectId, companyId: companyId, photoURL: photoURL, authorId: authorId)
        }

        switch action {
        case .ignore, .preserveDimensioned:
            // Nothing of the current user's to clear (or a dimensioned row with no
            // own layer). Leave every layer — including peers' — untouched.
            return existing ?? placeholder()

        case .clearOwnLayer, .softDelete:
            guard let existing, let id = existingAnnotationId else { return placeholder() }
            let now = Date()
            let prior = existing.ownLayer(userId: authorId) ?? layers.first { $0.authorId == authorId }
            let cleared = MarkupLayer(
                layerId: authorId, authorId: authorId, authorName: authorName,
                overlayUrl: nil, strokeRef: nil, visibleDefault: true,
                zIndex: prior?.zIndex ?? 0, strokeCount: 0,
                createdAt: prior?.createdAt ?? now, updatedAt: now, clearedAt: now
            )
            let event = MarkupChangeEvent(authorId: authorId, authorName: authorName, action: .cleared, strokeDelta: nil, at: now)
            let repository = PhotoAnnotationRepository(companyId: companyId)

            if ProjectPhotoAnnotationDeletePlanner.isLocalOnlyAnnotationID(id) {
                mergeLocalLayer(cleared, event: event, into: existing)
                existing.localDrawingData = nil
                existing.needsSync = true
            } else {
                do {
                    let dto = try await repository.upsertLayer(annotationId: id, layer: cleared, changeEvent: event)
                    applyServerRow(dto, to: existing)
                    // The RPC write landed — reset permanent-failure hygiene.
                    noteSyncSuccess(existing)
                    existing.localDrawingData = nil
                    existing.needsSync = false
                    existing.lastSyncedAt = now
                } catch {
                    mergeLocalLayer(cleared, event: event, into: existing)
                    existing.localDrawingData = nil
                    existing.needsSync = true
                    let kind = await AutoBugReporter.shared.reportIfPermanent(
                        error,
                        screen: "PhotoAnnotationSyncManager.applyAuthorScopedClear",
                        suspectedFile: "PhotoAnnotationSyncManager.swift",
                        summary: "Cleared-layer upsert failed for \(id): \(error.localizedDescription)",
                        metadata: ["annotation_id": id, "project_id": projectId, "company_id": companyId]
                    )
                    notePermanentFailure(existing, kind: kind)
                }
            }
            try? modelContext.save()

            // Drop my cached overlay; if the whole row is now soft-deleted, revert
            // the display to the raw original, else re-composite the survivors.
            if let url = prior?.overlayUrl {
                _ = ImageFileManager.shared.deleteImage(localID: MarkupOverlayCompositor.overlayCacheID(forURL: url))
            }
            _ = ImageFileManager.shared.deleteImage(localID: "overlay_\(id)")
            ImageFileManager.shared.deleteCompositedImage(forURL: photoURL)

            if existing.deletedAt != nil {
                let cacheKey = photoURL.hasPrefix("//") ? "https:" + photoURL : photoURL
                if let raw = ImageFileManager.shared.loadImage(localID: cacheKey) {
                    ImageCache.shared.set(raw, forKey: cacheKey)
                } else {
                    ImageCache.shared.remove(forKey: cacheKey)
                }
                NotificationCenter.default.post(name: .annotationsComposited, object: nil)
            } else {
                await preCompositeAnnotations(projectId: projectId, modelContext: modelContext)
            }
            return existing
        }
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
            // annotation's last change is still valid, so skip the re-render —
            // just make sure the in-memory display cache is warm and nudge any
            // mounted thumbnail to re-read (see PhotoCompositeRenderer for why
            // a stale composite never survives the check). The probe itself is
            // a file-attributes read plus, on a lost cache entry, a JPEG decode;
            // both run on the renderer, off the main actor, because this loop is
            // driven from onAppear.
            let lastChange = annotation.updatedAt ?? annotation.createdAt
            switch await PhotoCompositeRenderer.shared.durableComposite(
                cacheKey: cacheKey, notOlderThan: lastChange
            ) {
            case .fresh(let warm):
                if let warm {
                    ImageCache.shared.set(warm, forKey: cacheKey)
                }
                NotificationCenter.default.post(name: .annotationsComposited, object: nil)
                continue
            case .stale:
                break
            }

            // Composite the photo + EVERY active layer's overlay (collaborative
            // markup) so a thumbnail shows all authors' marks — not just the legacy
            // single overlay. effectiveMarkupLayers() also covers pre-collab rows
            // (one synthesized layer from annotation_url), so this one path serves
            // both. Cached per-overlay by URL via the shared compositor.
            //
            // Read the layers here (SwiftData, main context) and hand VALUES to
            // the renderer — the base-image load, the flatten, the JPEG encode
            // and the durable write all happen off the main actor.
            let activeLayers = annotation.effectiveMarkupLayers()
                .filter { $0.isActive }
                .sorted { $0.zIndex < $1.zIndex }

            guard let composited = await PhotoCompositeRenderer.shared.render(
                plan: plan, layers: activeLayers
            ) else { continue }

            ImageCache.shared.set(composited, forKey: cacheKey)

            // Notify per photo, not once after the loop, and synchronously on
            // the line after the cache insert. Composites are full source
            // resolution (a 12MP photo ≈ 48 MB) and ImageCache is an NSCache
            // with a 50 MB cost limit, so inserting the next composite can evict
            // this one right away. Posting while this composite is the freshest
            // cache entry lets each mounted PhotoThumbnail capture its own image
            // into @State (via reloadFromCache) before the next iteration can
            // evict it. A single post after the loop would arrive once most
            // composites had already been evicted, leaving thumbnails showing
            // the raw photo.
            //
            // This ordering closes the window against THIS loop, not against the
            // process: photo downloads now warm ImageCache off the main actor
            // (PhotoDownloadManager.decodeAndStore), so a concurrent insert can
            // land between the set and the post. Benign — a thumbnail that finds
            // the cache entry already evicted falls back to the durable
            // composite on disk (ProjectPhotosGrid.reloadFromCache: in-memory
            // first, else loadCompositedImage), so the worst case is one extra
            // file read, not lost markup.
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

    // MARK: - Sync Pending

    /// Push annotations saved offline (needsSync). The current user's OWN layer is
    /// merged server-side via upsert_markup_layer — an un-uploaded edit is
    /// re-rendered + uploaded first; a cleared layer is pushed as-is so the RPC
    /// re-derives the soft-delete. Pre-collab queued rows (no own layer) keep the
    /// legacy delete / single-overlay paths.
    func syncPendingAnnotations(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.needsSync == true }
        )

        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }
        print("[ANNOTATION SYNC] Found \(pending.count) pending annotations to sync")

        let currentUserId = SupabaseService.shared.currentUserId

        for annotation in pending {
            // Park gate: rows the server has permanently rejected
            // `AnnotationRetryPolicy.parkThreshold` times get exactly one
            // retry per launch so a landed server-side fix self-heals the
            // fleet without hammering (and re-filing bugs) in between.
            switch AnnotationRetryPolicy.sweepDecision(
                parkedAt: annotation.syncParkedAt,
                alreadyRetriedThisLaunch: parkedRetriedThisLaunch.contains(annotation.id)
            ) {
            case .skip:
                continue
            case .attempt:
                if annotation.syncParkedAt != nil {
                    parkedRetriedThisLaunch.insert(annotation.id)
                }
            }

            // Local-only ids never reached the server (offline first-creation isn't
            // supported) — clear the flag so the queue doesn't spin on them.
            if ProjectPhotoAnnotationDeletePlanner.isLocalOnlyAnnotationID(annotation.id) {
                annotation.needsSync = false
                try? modelContext.save()
                continue
            }

            let repo = PhotoAnnotationRepository(companyId: annotation.companyId)
            let ownLayer = currentUserId.flatMap { uid in annotation.layers.first { $0.layerId == uid } }

            // NEW model — push the current user's own layer through the RPC.
            if let ownLayer {
                do {
                    let pushedLayer: MarkupLayer
                    let event: MarkupChangeEvent
                    if ownLayer.isActive, ownLayer.overlayUrl == nil, let drawingData = annotation.localDrawingData {
                        // Un-uploaded edit: re-render, upload overlay + stroke, rebuild.
                        let drawing = try PKDrawing(data: drawingData)
                        let size = CGSize(width: 1080, height: 1920)
                        guard let pngData = renderDrawingToPNG(drawing: drawing, size: size) else { continue }
                        let overlayURL = try await uploadAnnotationPNG(data: pngData, projectId: annotation.projectId, companyId: annotation.companyId)
                        let strokeRef = try? await MarkupStrokeStore.uploadStroke(drawing, projectId: annotation.projectId, companyId: annotation.companyId)
                        _ = ImageFileManager.shared.saveImage(data: pngData, localID: MarkupOverlayCompositor.overlayCacheID(forURL: overlayURL))
                        pushedLayer = MarkupLayer(
                            layerId: ownLayer.layerId, authorId: ownLayer.authorId, authorName: ownLayer.authorName,
                            overlayUrl: overlayURL, strokeRef: strokeRef, visibleDefault: ownLayer.visibleDefault,
                            zIndex: ownLayer.zIndex, strokeCount: drawing.strokes.count,
                            createdAt: ownLayer.createdAt, updatedAt: Date(), clearedAt: nil
                        )
                        event = MarkupChangeEvent(authorId: ownLayer.authorId, authorName: ownLayer.authorName, action: .edited, strokeDelta: drawing.strokes.count, at: Date())
                    } else {
                        // Cleared (or already-uploaded) layer — push as-is.
                        pushedLayer = ownLayer
                        event = MarkupChangeEvent(authorId: ownLayer.authorId, authorName: ownLayer.authorName, action: ownLayer.isCleared ? .cleared : .edited, strokeDelta: ownLayer.strokeCount, at: Date())
                    }
                    let dto = try await repo.upsertLayer(annotationId: annotation.id, layer: pushedLayer, changeEvent: event)
                    if !ProjectPhotoAnnotationDeletePlanner.isLocalOnlyAnnotationID(annotation.id) {
                        try? await repo.updateNote(annotation.id, note: annotation.note)
                    }
                    applyServerRow(dto, to: annotation)
                    // The RPC write landed — reset permanent-failure hygiene.
                    noteSyncSuccess(annotation)
                    annotation.needsSync = false
                    annotation.lastSyncedAt = Date()
                    try? modelContext.save()
                    await preCompositeAnnotations(projectId: annotation.projectId, modelContext: modelContext)
                } catch {
                    let kind = await AutoBugReporter.shared.reportIfPermanent(
                        error,
                        screen: "PhotoAnnotationSyncManager.syncPendingAnnotations",
                        suspectedFile: "PhotoAnnotationSyncManager.swift",
                        summary: "Annotation layer retry failed for \(annotation.id): \(error.localizedDescription)",
                        metadata: ["annotation_id": annotation.id, "project_id": annotation.projectId, "company_id": annotation.companyId]
                    )
                    notePermanentFailure(annotation, kind: kind)
                    try? modelContext.save()
                    DebugLogger.shared.log("Annotation layer sync retry failed for \(annotation.id): \(error)", level: .warning, category: "PhotoAnnotationSyncManager")
                }
                continue
            }

            // LEGACY fallback — pre-collab queued rows (no own layer).
            if annotation.deletedAt != nil {
                do {
                    try await repo.softDelete(annotation.id)
                    noteSyncSuccess(annotation)
                    annotation.needsSync = false
                    annotation.lastSyncedAt = Date()
                    try? modelContext.save()
                } catch {
                    let kind = await AutoBugReporter.shared.reportIfPermanent(
                        error,
                        screen: "PhotoAnnotationSyncManager.syncPendingAnnotations",
                        suspectedFile: "PhotoAnnotationSyncManager.swift",
                        summary: "Annotation delete retry failed for \(annotation.id): \(error.localizedDescription)",
                        metadata: ["annotation_id": annotation.id, "project_id": annotation.projectId, "company_id": annotation.companyId]
                    )
                    notePermanentFailure(annotation, kind: kind)
                    try? modelContext.save()
                    DebugLogger.shared.log("Annotation delete retry failed for \(annotation.id): \(error)", level: .warning, category: "PhotoAnnotationSyncManager")
                }
                continue
            }

            guard let drawingData = annotation.localDrawingData else { continue }
            do {
                let drawing = try PKDrawing(data: drawingData)
                let size = CGSize(width: 1080, height: 1920)
                guard let pngData = renderDrawingToPNG(drawing: drawing, size: size) else { continue }
                let annotationURL = try await uploadAnnotationPNG(data: pngData, projectId: annotation.projectId, companyId: annotation.companyId)
                try await repo.updateAnnotation(annotation.id, annotationUrl: annotationURL, note: annotation.note)

                // Update local
                noteSyncSuccess(annotation)
                annotation.annotationURL = annotationURL
                annotation.needsSync = false
                annotation.lastSyncedAt = Date()
                try? modelContext.save()
            } catch {
                // Auto-bug-reporting (May-12 follow-up): the retry loop
                // hammers the same row every sweep — auto-bug on permanent
                // so the dev team intervenes before the queue silently
                // bloats with poisoned annotations.
                let kind = await AutoBugReporter.shared.reportIfPermanent(
                    error,
                    screen: "PhotoAnnotationSyncManager.syncPendingAnnotations",
                    suspectedFile: "PhotoAnnotationSyncManager.swift",
                    summary: "Annotation retry failed for \(annotation.id): \(error.localizedDescription)",
                    metadata: ["annotation_id": annotation.id, "project_id": annotation.projectId, "company_id": annotation.companyId]
                )
                notePermanentFailure(annotation, kind: kind)
                try? modelContext.save()
                DebugLogger.shared.log("Annotation sync retry failed for \(annotation.id): \(error)", level: .warning, category: "PhotoAnnotationSyncManager")
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
    /// A PostgREST write matched zero rows: RLS filtered the target (dead
    /// identity, wrong company) or the row vanished server-side. PostgREST
    /// reports 2xx for these, so the repository detects the empty RETURNING
    /// set and throws this instead of letting the caller mark the row
    /// synced. Permanent — retrying the same session cannot succeed.
    case writeNotApplied(annotationId: String)

    var errorDescription: String? {
        switch self {
        case .uploadFailed: return "Failed to upload annotation"
        case .invalidURL: return "Invalid upload URL"
        case .writeNotApplied(let annotationId):
            return "Annotation write matched no rows (RLS-filtered) for \(annotationId)"
        }
    }
}

// MARK: - Permanent-failure retry policy

/// Pure retry/park decisions for the pending-annotation sweep, kept separate
/// so they are unit-testable without SwiftData or the network (same pattern
/// as AnnotationClearPlanner).
///
/// A write the server has permanently rejected (RLS, validation) must not be
/// hammered on every sweep forever — that is how bugs 452bab04/0415504f kept
/// re-firing the same dead soft-delete. After `parkThreshold` permanent
/// failures the row parks and gets exactly one retry per app launch: enough
/// to self-heal the moment a server-side fix lands, silent otherwise.
/// Transient failures never count toward parking.
enum AnnotationRetryPolicy {
    static let parkThreshold = 3

    enum SweepDecision: Equatable {
        case attempt
        case skip
    }

    static func sweepDecision(parkedAt: Date?, alreadyRetriedThisLaunch: Bool) -> SweepDecision {
        guard parkedAt != nil else { return .attempt }
        return alreadyRetriedThisLaunch ? .skip : .attempt
    }

    static func nextFailureCount(after count: Int) -> Int {
        count + 1
    }

    static func shouldPark(failureCount: Int) -> Bool {
        failureCount >= parkThreshold
    }
}

// MARK: - Cleared-drawing decision

/// Pure decision for what a cleared (empty) drawing save should do. Kept
/// separate from `saveAnnotation` so the branch logic is unit-testable without
/// SwiftData or the network.
enum AnnotationClearPlanner {
    enum Action: Equatable {
        /// No existing annotation / nothing of the current user's to clear.
        case ignore
        /// Dimensioned capture — preserve the row + its dimensions.
        case preserveDimensioned
        /// Pure PencilKit annotation — soft-delete the whole row.
        case softDelete
        /// Author-scoped — clear only the current user's layer; the row lives on
        /// because a peer still has an active layer (or it's dimensioned).
        case clearOwnLayer
    }

    /// Legacy single-author decision (no layers). Retained for the pre-collab
    /// callers + locked by AnnotationClearPlannerTests.
    static func plan(existingAnnotationId: String?, hasDimensions: Bool) -> Action {
        guard existingAnnotationId != nil else { return .ignore }
        return hasDimensions ? .preserveDimensioned : .softDelete
    }

    /// Collaborative decision (HARD CORRECTION 3). An empty save clears ONLY the
    /// current user's layer; the whole-row soft-delete fires only when the last
    /// active layer is the one being cleared AND there's no dimensioned capture
    /// to preserve. Opening a PEER's row and tapping DONE with no marks of your
    /// own resolves to `.ignore` — it must never delete the peer's layer/row.
    static func plan(
        existingAnnotationId: String?,
        hasDimensions: Bool,
        layers: [MarkupLayer],
        currentUserId: String
    ) -> Action {
        guard existingAnnotationId != nil else { return .ignore }
        let ownActive = layers.contains { $0.authorId == currentUserId && $0.isActive }
        if hasDimensions {
            return ownActive ? .clearOwnLayer : .preserveDimensioned
        }
        if !ownActive { return .ignore }
        let othersActive = layers.contains { $0.authorId != currentUserId && $0.isActive }
        return othersActive ? .clearOwnLayer : .softDelete
    }
}

// MARK: - Composite Renderer

/// The off-main half of annotation compositing: base-image resolve, overlay
/// resolve, flatten, JPEG encode and the durable write.
///
/// Why an actor and not a detached task. Two constraints have to hold at once:
///
///  1. None of this may run on the main actor. A full-resolution flatten plus a
///     bounded JPEG encode is tens of milliseconds each, and `preCompositeAnnotations`
///     runs from `onAppear` for every annotated photo on the project.
///  2. The durable write must stay serialized. Several mounted photo surfaces
///     call `preCompositeAnnotations` concurrently (details screen, photo grid,
///     comment viewer); before this move, main-actor isolation was what kept two
///     of them from writing the same composite file at the same time. An actor
///     preserves exactly that: every synchronous stretch — including each
///     `saveCompositedImage` — runs in isolation.
actor PhotoCompositeRenderer {
    static let shared = PhotoCompositeRenderer()

    /// Newest render token handed out per composite key. A render is current
    /// only while it holds the newest token for its key — see `beginRender`.
    private var currentGeneration: [String: Int] = [:]

    /// State of a photo's durable composite relative to its annotation.
    enum DurableComposite {
        /// A composite newer than the annotation's last change is on disk.
        /// `warm` carries the decoded image ONLY when the in-memory display
        /// cache had lost it — otherwise the cache entry already stands.
        case fresh(warm: UIImage?)
        /// No composite, or one older than the last annotation change.
        case stale
    }

    /// Freshness short-circuit. Re-rendering a camera-resolution composite is
    /// expensive and would thrash the budget evictor on every gallery
    /// open, so a durable composite newer than the annotation's last change is
    /// reused as-is. Local edits delete the composite up front (see
    /// `saveAnnotation`) and remote edits bump `updatedAt`, so a stale composite
    /// never survives this check.
    func durableComposite(cacheKey: String, notOlderThan lastChange: Date) -> DurableComposite {
        guard let modified = ImageFileManager.shared.compositedImageModificationDate(forURL: cacheKey),
              modified >= lastChange else { return .stale }
        guard ImageCache.shared.get(forKey: cacheKey) == nil else { return .fresh(warm: nil) }
        return .fresh(warm: ImageFileManager.shared.loadCompositedImage(forURL: cacheKey))
    }

    /// Claim `cacheKey` for a render and return the token that identifies it.
    /// Every later claim on the same key supersedes this one.
    func beginRender(for cacheKey: String) -> Int {
        let token = (currentGeneration[cacheKey] ?? 0) + 1
        currentGeneration[cacheKey] = token
        return token
    }

    /// What a durable-composite write did.
    enum PersistOutcome: Equatable {
        case written
        /// The key was still current; the disk write itself failed.
        case writeFailed
        /// A newer render claimed this key — these pixels are stale and must not
        /// be persisted OR published.
        case superseded
    }

    /// Write `jpeg` as the durable composite for `cacheKey` — but ONLY while
    /// `token` is still the newest claim on that key.
    ///
    /// This closes a lost-update race that outlives any single render: a render
    /// suspended on a base-image or overlay download can resume AFTER a later
    /// render (started because the annotation changed) has already persisted its
    /// result, and would then overwrite the fresh composite with pre-edit
    /// pixels. Because `saveCompositedImage` refreshes the file's mtime, that
    /// stale write would also pass `durableComposite`'s freshness check — the
    /// operator would keep seeing pre-edit markup until the next edit.
    ///
    /// The check and the write are one synchronous stretch on the actor, so no
    /// other render can interleave between them.
    @discardableResult
    func persistIfCurrent(jpeg: Data, cacheKey: String, token: Int) -> PersistOutcome {
        guard isCurrent(token: token, for: cacheKey) else { return .superseded }
        return ImageFileManager.shared.saveCompositedImage(jpeg, forURL: cacheKey)
            ? .written
            : .writeFailed
    }

    /// Flatten the photo + every supplied overlay, persist the result, and hand
    /// the image back for the caller to publish into the display cache. The
    /// caller owns the `ImageCache` insert so it can post `.annotationsComposited`
    /// on the very next line (see `preCompositeAnnotations`).
    ///
    /// Returns nil when a newer render for the same photo superseded this one:
    /// that render has already published fresher pixels, and handing these back
    /// would put pre-edit markup into the display cache.
    func render(plan: PhotoAnnotationCompositePlan, layers: [MarkupLayer]) async -> UIImage? {
        let token = beginRender(for: plan.cacheKey)

        guard let baseImage = await loadBaseImage(for: plan) else { return nil }

        var overlays: [UIImage] = []
        for layer in layers {
            if let image = await MarkupOverlayCompositor.loadOverlay(for: layer) {
                overlays.append(image)
            }
        }
        guard !overlays.isEmpty else { return nil }

        guard let composited = MarkupOverlayCompositor.composite(
            base: baseImage, overlays: overlays, size: baseImage.size
        ) else { return nil }

        // Persist the composite so ANY thumbnail can resolve markup the instant
        // it mounts — independent of NSCache eviction or mount timing. This is
        // the durability tier: the in-memory cache holds barely one
        // camera-resolution composite, so a thumbnail scrolled into view long
        // after the post fired would otherwise fall back to the raw photo. The
        // shared site-visit preparation policy caps the durable JPEG at 2,048 px
        // and 10 MiB, preventing a rendered markup file from becoming
        // permanently unsendable while preserving the untouched source photo.
        guard let jpeg = SiteVisitMediaImagePreparation.jpegData(for: composited) else {
            // No durable copy to write, but the in-memory publish is still only
            // valid if nothing newer has landed.
            return isCurrent(token: token, for: plan.cacheKey) ? composited : nil
        }

        switch persistIfCurrent(jpeg: jpeg, cacheKey: plan.cacheKey, token: token) {
        case .superseded:
            return nil
        case .written, .writeFailed:
            // A failed disk write costs durability, not correctness — the
            // display cache still gets the freshest pixels, as before.
            return composited
        }
    }

    /// True while `token` is still the newest claim on `cacheKey`.
    private func isCurrent(token: Int, for cacheKey: String) -> Bool {
        currentGeneration[cacheKey] == token
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
}
