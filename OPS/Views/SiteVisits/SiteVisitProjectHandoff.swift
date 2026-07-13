//
//  SiteVisitProjectHandoff.swift
//  OPS
//
//  Applies a reviewed site-visit packet to a newly created project locally.
//

import Foundation
import SwiftData

// Applies on the main actor — it mutates the shared SwiftData context and routes
// the packet note through the main-actor-isolated DataController sync queue. Only
// ever called from SwiftUI View code (lead conversion), which is already MainActor.
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

        insertProjectPhotos(
            from: included,
            payload: payload,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext,
            imageSync: resolvedImageSync
        )
        insertDimensionedPhotoAnnotations(
            from: included,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext
        )
        insertProjectNotes(
            from: artifacts,
            payload: payload,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext,
            dataController: dataController
        )
        attachDeckDesigns(
            payload.deckDesignIds,
            projectId: projectId,
            modelContext: modelContext,
            syncEngine: resolvedSyncEngine
        )

        try? modelContext.save()
    }

    private static func insertProjectPhotos(
        from artifacts: [SiteVisitCaptureArtifact],
        payload: SiteVisitProjectPayload,
        projectId: String,
        companyId: String,
        userId: String?,
        modelContext: ModelContext,
        imageSync: ImageSyncManager?
    ) {
        for artifact in artifacts where artifact.pipesToProjectPhotos {
            guard let url = projectPhotoSourceURL(for: artifact) else { continue }
            let photo = ProjectPhoto(
                // Lowercased at creation: the drain sends this id in the server
                // insert, and Postgres echoes uuids lowercase — an UPPERCASE
                // local id would miss the echo and duplicate the row.
                id: UUID().uuidString.lowercased(),
                projectId: projectId,
                companyId: companyId,
                url: url,
                renderedURL: artifact.renderedAssetURL,
                source: "site_visit",
                siteVisitId: payload.siteVisitId,
                uploadedBy: userId ?? "",
                caption: artifact.title,
                takenAt: artifact.capturedAt,
                createdAt: artifact.capturedAt
            )
            photo.needsSync = true
            modelContext.insert(photo)

            // The row alone is phone-local: the sync engine treats ProjectPhoto
            // as read-only, so the bytes must ride the durable image-upload
            // queue (bug: every pre-fix conversion stranded its photos on the
            // capturing phone). Dimensioned captures are excluded — their
            // PhotoAnnotation pending sweep uploads the HEIC + rendered
            // deliverable, inserts the project_photos row, and heals this row
            // itself; queueing them here too would double-upload/double-tile.
            if artifact.kind != .dimensionedPhoto, url.hasPrefix("local://") {
                imageSync?.enqueueExistingLocalImage(
                    localURL: url,
                    projectId: projectId,
                    companyId: companyId
                )
            }
        }
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
    ) {
        for artifact in artifacts where artifact.kind == .dimensionedPhoto {
            guard let photoURL = artifact.localAssetURL ?? artifact.renderedAssetURL,
                  let dimensionsJSON = artifact.dimensionsJSON,
                  let dimensionsData = dimensionsJSON.data(using: .utf8),
                  let dimensions = try? DimensionsData.jsonDecoder.decode(
                    DimensionsData.self,
                    from: dimensionsData
                  ) else { continue }

            let annotation = PhotoAnnotation(
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
        }
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
        modelContext: ModelContext,
        dataController: DataController?
    ) {
        // Bug 7649fd48 — the packet is now a structured system note. `content`
        // keeps the legacy plain-text packet (web / older builds); the rich iOS
        // feed card + sheet render from `content_metadata`.
        guard let packet = SiteVisitPacketNote.build(artifacts: artifacts, payload: payload) else { return }

        let note = ProjectNote(
            projectId: projectId,
            companyId: companyId,
            authorId: userId ?? "",
            content: packet.content,
            createdAt: Date()
        )
        note.eventKind = "site_visit"
        note.contentMetadataJSON = packet.metadataJSON

        // Route through the durable sync queue so the packet ACTUALLY reaches
        // the server. The previous direct insert set needsSync but recorded no
        // outbound op, and project notes have no needsSync sweep — so every
        // packet was stranded on the capturing device (zero ever synced).
        if let dataController = dataController {
            dataController.createProjectNote(note: note)
        } else {
            note.needsSync = true
            modelContext.insert(note)
        }
    }

    private static func attachDeckDesigns(
        _ deckDesignIds: [String],
        projectId: String,
        modelContext: ModelContext,
        syncEngine: SyncEngine?
    ) {
        let canonicalProjectId = DeckDesign.canonicalUUIDString(projectId)
        for deckDesignId in deckDesignIds {
            let descriptor = FetchDescriptor<DeckDesign>(
                predicate: #Predicate<DeckDesign> { design in
                    design.id == deckDesignId
                }
            )
            guard let design = try? modelContext.fetch(descriptor).first else { continue }
            design.projectId = canonicalProjectId
            design.markForSync()

            // markForSync alone is a flag no sweep ever drained for decks —
            // the pre-fix handoff stopped here and the link never left the
            // phone (deck stayed project_id NULL on the server for everyone
            // else). Record the durable outbound op that actually ships it.
            syncEngine?.recordOperation(
                entityType: .deckDesign,
                entityId: design.id,
                operationType: "update",
                changedFields: [
                    "project_id": canonicalProjectId,
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ],
                priority: 1
            )
        }
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
