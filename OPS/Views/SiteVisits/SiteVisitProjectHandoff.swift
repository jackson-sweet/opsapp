//
//  SiteVisitProjectHandoff.swift
//  OPS
//
//  Applies a reviewed site-visit packet to a newly created project locally.
//

import Foundation
import SwiftData

// Applies on the main actor because it mutates the shared SwiftData context and
// its durable outbound queue in one save. Only called from SwiftUI View code
// (lead conversion), which is already MainActor.
@MainActor
enum SiteVisitProjectHandoff {
    /// `syncEngine` / `imageSync` default to the DataController's instances;
    /// they exist as parameters so tests can drive the durable-sync seams
    /// without constructing a DataController.
    static func apply(
        payload: SiteVisitProjectPayload,
        artifacts: [SiteVisitCaptureArtifact],
        projectId: String,
        companyId: String,
        userId: String?,
        modelContext: ModelContext,
        dataController: DataController? = nil,
        syncEngine: SyncEngine? = nil,
        imageSync: ImageSyncManager? = nil
    ) {
        let resolvedSyncEngine = syncEngine ?? dataController?.syncEngine
        let resolvedImageSync = imageSync ?? dataController?.imageSyncManager

        let included = artifacts
            .filter { $0.isActive && $0.includedInProjectReview }
            .sorted { $0.capturedAt < $1.capturedAt }

        var queuedDurableOperation = insertProjectPhotos(
            from: included,
            payload: payload,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext,
            imageSync: resolvedImageSync
        )
        queuedDurableOperation = insertDimensionedPhotoAnnotations(
            from: included,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext
        ) || queuedDurableOperation
        queuedDurableOperation = insertProjectNotes(
            from: artifacts,
            payload: payload,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext
        ) || queuedDurableOperation
        queuedDurableOperation = attachDeckDesigns(
            payload.deckDesignIds,
            projectId: projectId,
            modelContext: modelContext
        ) || queuedDurableOperation

        do {
            // Gallery rows, notes, deck links, annotations, and their outbound
            // commands commit together. A crash can no longer strand one side
            // of the handoff without the operation that delivers it.
            try modelContext.save()
            if queuedDurableOperation {
                resolvedSyncEngine?.notifyDurableOperationQueued(pullAfterPush: true)
            }
        } catch {
            DebugLogger.shared.log(
                "Site-visit project handoff could not commit: \(error)",
                level: .error,
                category: "SiteVisitProjectHandoff"
            )
        }
    }

    private static func insertProjectPhotos(
        from artifacts: [SiteVisitCaptureArtifact],
        payload: SiteVisitProjectPayload,
        projectId: String,
        companyId: String,
        userId: String?,
        modelContext: ModelContext,
        imageSync: ImageSyncManager?
    ) -> Bool {
        let existingRows = (try? modelContext.fetch(FetchDescriptor<ProjectPhoto>())) ?? []
        let canonicalVisitId = canonicalLocalVisitID(payload.siteVisitId)
        var knownRows = existingRows.filter {
            $0.companyId == companyId
                && $0.projectId == projectId
                && $0.deletedAt == nil
        }
        var queuedOperation = false

        for artifact in artifacts where artifact.pipesToProjectPhotos {
            guard let url = projectPhotoSourceURL(for: artifact) else { continue }
            let photo: ProjectPhoto
            if let existing = knownRows.first(where: {
                canonicalLocalVisitID($0.siteVisitId ?? "") == canonicalVisitId
                    && $0.url == url
            }) {
                photo = existing
            } else {
                photo = ProjectPhoto(
                    // Lowercased at creation: Postgres echoes UUIDs lowercase,
                    // so the insert echo must merge into this exact local row.
                    id: UUID().uuidString.lowercased(),
                    projectId: projectId,
                    companyId: companyId,
                    url: url,
                    thumbnailURL: artifact.thumbnailURL,
                    renderedURL: artifact.renderedAssetURL,
                    source: "site_visit",
                    siteVisitId: canonicalVisitId,
                    uploadedBy: userId ?? "",
                    caption: artifact.title,
                    takenAt: artifact.capturedAt,
                    createdAt: artifact.capturedAt
                )
                photo.needsSync = true
                modelContext.insert(photo)
                knownRows.append(photo)
            }

            if isRemoteURL(url) {
                // The visit-media upload already owns the S3 object. Reuse it
                // verbatim and queue only the project_photos row; copying bytes
                // creates duplicate objects and duplicate gallery tiles.
                queuedOperation = ensureOperation(
                    entityType: .projectPhoto,
                    entityId: photo.id,
                    operationType: "create",
                    payload: projectPhotoCreatePayload(photo),
                    modelContext: modelContext
                ) || queuedOperation
            } else if artifact.kind != .dimensionedPhoto, url.hasPrefix("local://") {
                // A genuinely local capture still rides the existing durable
                // upload queue. That drain creates the server row with this
                // row's stable id and site-visit provenance.
                imageSync?.enqueueExistingLocalImage(
                    localURL: url,
                    projectId: projectId,
                    companyId: companyId
                )
            }
        }
        return queuedOperation
    }

    private static func projectPhotoSourceURL(for artifact: SiteVisitCaptureArtifact) -> String? {
        if artifact.kind == .dimensionedPhoto {
            return artifact.localAssetURL ?? artifact.renderedAssetURL
        }
        return artifact.renderedAssetURL ?? artifact.localAssetURL
    }

    private static func insertDimensionedPhotoAnnotations(
        from artifacts: [SiteVisitCaptureArtifact],
        projectId: String,
        companyId: String,
        userId: String?,
        modelContext: ModelContext
    ) -> Bool {
        let existing = (try? modelContext.fetch(FetchDescriptor<PhotoAnnotation>())) ?? []
        var knownAnnotations = existing.filter {
            $0.companyId == companyId
                && $0.projectId == projectId
                && $0.deletedAt == nil
        }
        var queuedOperation = false

        for artifact in artifacts where artifact.kind == .dimensionedPhoto {
            guard let photoURL = artifact.localAssetURL ?? artifact.renderedAssetURL,
                  let dimensionsJSON = artifact.dimensionsJSON,
                  let dimensionsData = dimensionsJSON.data(using: .utf8),
                  let dimensions = try? DimensionsData.jsonDecoder.decode(
                    DimensionsData.self,
                    from: dimensionsData
                  ) else { continue }

            let annotation: PhotoAnnotation
            if let existing = knownAnnotations.first(where: { $0.photoURL == photoURL }) {
                annotation = existing
            } else {
                annotation = PhotoAnnotation(
                    id: UUID().uuidString.lowercased(),
                    projectId: projectId,
                    companyId: companyId,
                    photoURL: photoURL,
                    authorId: userId ?? "",
                    createdAt: artifact.capturedAt
                )
                annotation.renderedPhotoURL = artifact.renderedAssetURL
                annotation.note = artifact.body ?? ""
                annotation.dimensions = dimensions
                annotation.localDepthMapPath = localFilePath(from: dimensions.depthAssetUrl)
                annotation.localSidecarPath = localFilePath(from: dimensions.sidecarMetadataUrl)
                annotation.localCaptureFinishedAt = artifact.capturedAt
                annotation.needsSync = true
                modelContext.insert(annotation)
                knownAnnotations.append(annotation)
            }

            if isRemoteURL(photoURL) {
                queuedOperation = ensureOperation(
                    entityType: .photoAnnotation,
                    entityId: annotation.id,
                    operationType: "create",
                    payload: photoAnnotationCreatePayload(annotation, dimensions: dimensions),
                    modelContext: modelContext
                ) || queuedOperation
            }
        }
        return queuedOperation
    }

    private static func localFilePath(from urlString: String?) -> String? {
        guard let urlString,
              let url = URL(string: urlString),
              url.isFileURL else { return nil }
        return url.path
    }

    private static func insertProjectNotes(
        from artifacts: [SiteVisitCaptureArtifact],
        payload: SiteVisitProjectPayload,
        projectId: String,
        companyId: String,
        userId: String?,
        modelContext: ModelContext
    ) -> Bool {
        // Bug 7649fd48 — the packet is now a structured system note. `content`
        // keeps the legacy plain-text packet (web / older builds); the rich iOS
        // feed card + sheet render from `content_metadata`.
        guard let packet = SiteVisitPacketNote.build(artifacts: artifacts, payload: payload) else { return false }

        let existingNotes = (try? modelContext.fetch(FetchDescriptor<ProjectNote>())) ?? []
        let canonicalVisitId = canonicalLocalVisitID(payload.siteVisitId)
        if let existing = existingNotes.first(where: {
            $0.companyId == companyId
                && $0.projectId == projectId
                && $0.deletedAt == nil
                && $0.eventKind == "site_visit"
                && packetVisitID(from: $0.contentMetadataJSON) == canonicalVisitId
        }) {
            return ensureOperation(
                entityType: .projectNote,
                entityId: existing.id,
                operationType: "create",
                payload: projectNoteCreatePayload(existing),
                modelContext: modelContext
            )
        }

        let note = ProjectNote(
            projectId: projectId,
            companyId: companyId,
            authorId: userId ?? "",
            content: packet.content,
            createdAt: Date()
        )
        note.eventKind = "site_visit"
        note.contentMetadataJSON = packet.metadataJSON
        note.needsSync = true
        modelContext.insert(note)
        return ensureOperation(
            entityType: .projectNote,
            entityId: note.id,
            operationType: "create",
            payload: projectNoteCreatePayload(note),
            modelContext: modelContext
        )
    }

    private static func attachDeckDesigns(
        _ deckDesignIds: [String],
        projectId: String,
        modelContext: ModelContext
    ) -> Bool {
        let canonicalProjectId = DeckDesign.canonicalUUIDString(projectId)
        var queuedOperation = false
        for deckDesignId in deckDesignIds {
            let descriptor = FetchDescriptor<DeckDesign>(
                predicate: #Predicate<DeckDesign> { design in
                    design.id == deckDesignId
                }
            )
            guard let design = try? modelContext.fetch(descriptor).first else { continue }
            let requiresDelivery = !design.isAttached(toProjectId: canonicalProjectId) || design.needsSync
            if !design.isAttached(toProjectId: canonicalProjectId) {
                design.projectId = canonicalProjectId
                design.markForSync()
            }
            guard requiresDelivery else { continue }

            // Queue directly in the same transaction. If this is an old
            // partially applied handoff (link set, operation absent), this also
            // repairs it. A fully synced design needs no redundant update.
            queuedOperation = ensureOperation(
                entityType: .deckDesign,
                entityId: design.id,
                operationType: "update",
                payload: [
                    "project_id": canonicalProjectId,
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ],
                modelContext: modelContext
            ) || queuedOperation
        }
        return queuedOperation
    }

    private static func canonicalLocalVisitID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func canonicalServerVisitID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))?
            .uuidString
            .lowercased()
    }

    private static func isRemoteURL(_ raw: String) -> Bool {
        SiteVisitMediaSyncManager.isRemoteURL(raw)
    }

    private static func projectPhotoCreatePayload(_ photo: ProjectPhoto) -> [String: Any] {
        var payload: [String: Any] = [
            "project_id": photo.projectId,
            "company_id": photo.companyId,
            "url": photo.url,
            "source": photo.source,
            "is_client_visible": photo.isClientVisible,
            "taken_at": ISO8601DateFormatter().string(from: photo.takenAt ?? photo.createdAt),
            "created_at": ISO8601DateFormatter().string(from: photo.createdAt)
        ]
        if let visitId = canonicalServerVisitID(photo.siteVisitId) {
            payload["site_visit_id"] = visitId
        }
        if let uploader = ProjectPhotoUploaderIdentity.canonicalUserID(photo.uploadedBy) {
            payload["uploaded_by"] = uploader
        }
        if let caption = photo.caption { payload["caption"] = caption }
        if let rendered = photo.renderedURL, isRemoteURL(rendered) {
            payload["rendered_url"] = rendered
        }
        if let thumbnail = photo.thumbnailURL, isRemoteURL(thumbnail) {
            payload["thumbnail_url"] = thumbnail
        }
        return payload
    }

    private static func photoAnnotationCreatePayload(
        _ annotation: PhotoAnnotation,
        dimensions: DimensionsData
    ) -> [String: Any] {
        var serverDimensions = dimensions
        if let depth = serverDimensions.depthAssetUrl, !isRemoteURL(depth) {
            serverDimensions.depthAssetUrl = nil
        }
        if let sidecar = serverDimensions.sidecarMetadataUrl, !isRemoteURL(sidecar) {
            serverDimensions.sidecarMetadataUrl = nil
        }

        var payload: [String: Any] = [
            "project_id": annotation.projectId,
            "company_id": annotation.companyId,
            "photo_url": annotation.photoURL,
            "note": annotation.note,
            "author_id": annotation.authorId,
            "created_at": ISO8601DateFormatter().string(from: annotation.createdAt)
        ]
        if let rendered = annotation.renderedPhotoURL, isRemoteURL(rendered) {
            payload["rendered_photo_url"] = rendered
        }
        if let data = try? DimensionsData.jsonEncoder.encode(serverDimensions),
           let object = try? JSONSerialization.jsonObject(with: data) {
            payload["dimensions"] = object
        }
        return payload
    }

    private static func projectNoteCreatePayload(_ note: ProjectNote) -> [String: Any] {
        var payload: [String: Any] = [
            "id": note.id,
            "project_id": note.projectId,
            "company_id": note.companyId,
            "author_id": note.authorId,
            "content": note.content
        ]
        if let eventKind = note.eventKind { payload["event_kind"] = eventKind }
        if let metadataJSON = note.contentMetadataJSON,
           let data = metadataJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            payload["content_metadata"] = object
        }
        return payload
    }

    private static func packetVisitID(from metadataJSON: String?) -> String? {
        guard let metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let visitId = object["site_visit_id"] as? String else { return nil }
        return canonicalLocalVisitID(visitId)
    }

    @discardableResult
    private static func ensureOperation(
        entityType: SyncEntityType,
        entityId: String,
        operationType: String,
        payload: [String: Any],
        modelContext: ModelContext
    ) -> Bool {
        let canonicalEntityId = entityId.lowercased()
        let operations = (try? modelContext.fetch(FetchDescriptor<SyncOperation>())) ?? []
        if operations.contains(where: {
            $0.entityType == entityType.rawValue
                && $0.entityId.lowercased() == canonicalEntityId
                && $0.operationType == operationType
        }) {
            return false
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else {
            return false
        }
        modelContext.insert(
            SyncOperation(
                entityType: entityType.rawValue,
                entityId: canonicalEntityId,
                operationType: operationType,
                payload: encoded,
                changedFields: Array(payload.keys),
                priority: 1
            )
        )
        return true
    }

    // MARK: - Convert-time payload derivation (staging-store loss recovery)

    /// Rebuild the handoff payload from persisted rows when the in-memory
    /// staging store didn't survive to conversion (app kill between visit
    /// review and convert, or a conversion started without the review flow).
    /// Artifacts and checklist answers are SwiftData rows keyed by visit /
    /// opportunity, so everything the staged payload carried is derivable.
    ///
    /// Visit discovery is two-way: visits bound to the opportunity AND visits
    /// whose artifacts carry the opportunity binding (covers a visit row that
    /// lost its link, and pre-bind captures on a visit that gained one).
    static func derivePayload(
        opportunityId: String,
        opportunityAddress: String?,
        modelContext: ModelContext
    ) -> (payload: SiteVisitProjectPayload, artifacts: [SiteVisitCaptureArtifact])? {
        let visitDescriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> { $0.opportunityId == opportunityId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let visits = (try? modelContext.fetch(visitDescriptor)) ?? []

        let boundArtifactDescriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { $0.opportunityId == opportunityId }
        )
        let boundArtifacts = (try? modelContext.fetch(boundArtifactDescriptor)) ?? []

        var visitIds: [String] = visits.map(\.id)
        for artifact in boundArtifacts where !visitIds.contains(artifact.siteVisitId) {
            visitIds.append(artifact.siteVisitId)
        }
        guard !visitIds.isEmpty else { return nil }

        let ids = visitIds
        let artifactDescriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { ids.contains($0.siteVisitId) },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]
        )
        let artifacts = (try? modelContext.fetch(artifactDescriptor)) ?? []

        let answerDescriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate<SiteVisitChecklistAnswer> { ids.contains($0.siteVisitId) }
        )
        let answers = (try? modelContext.fetch(answerDescriptor)) ?? []

        // No evidence, no packet — conversion must not synthesize an empty one.
        let hasEvidence = artifacts.contains { $0.isActive && $0.includedInProjectReview }
            || answers.contains { $0.isActive && $0.isAnswered }
        guard hasEvidence else { return nil }

        let primaryVisitId = artifacts.last(where: { $0.isActive })?.siteVisitId ?? ids[ids.count - 1]
        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: primaryVisitId,
            opportunityId: opportunityId,
            address: opportunityAddress,
            artifacts: artifacts,
            checklistAnswers: answers
        )
        return (payload, artifacts)
    }
}
