//
//  SiteVisitProjectHandoff.swift
//  OPS
//
//  Applies a reviewed site-visit packet to a newly created project locally.
//

import Foundation
import SwiftData

enum SiteVisitProjectHandoff {
    static func apply(
        payload: SiteVisitProjectPayload,
        artifacts: [SiteVisitCaptureArtifact],
        projectId: String,
        companyId: String,
        userId: String?,
        modelContext: ModelContext
    ) {
        let included = artifacts
            .filter { $0.isActive && $0.includedInProjectReview }
            .sorted { $0.capturedAt < $1.capturedAt }

        insertProjectPhotos(
            from: included,
            payload: payload,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext
        )
        insertDimensionedPhotoAnnotations(
            from: included,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext
        )
        insertProjectNotes(
            from: included,
            payload: payload,
            projectId: projectId,
            companyId: companyId,
            userId: userId,
            modelContext: modelContext
        )
        attachDeckDesigns(
            payload.deckDesignIds,
            projectId: projectId,
            modelContext: modelContext
        )

        try? modelContext.save()
    }

    private static func insertProjectPhotos(
        from artifacts: [SiteVisitCaptureArtifact],
        payload: SiteVisitProjectPayload,
        projectId: String,
        companyId: String,
        userId: String?,
        modelContext: ModelContext
    ) {
        for artifact in artifacts where artifact.pipesToProjectPhotos {
            guard let url = projectPhotoSourceURL(for: artifact) else { continue }
            let photo = ProjectPhoto(
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
        modelContext: ModelContext
    ) {
        let noteLines = artifacts
            .filter { $0.pipesToProjectNotes || $0.pipesToProjectMeasurements }
            .compactMap { artifact -> String? in
                guard let body = artifact.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !body.isEmpty else { return nil }
                switch artifact.kind {
                case .measurement, .dimensionedPhoto:
                    return "MEASURE :: \(body)"
                case .note, .transcript:
                    return body
                case .photo, .annotatedPhoto, .deckDesign:
                    return nil
                }
            }

        let packetLines = noteLines + payload.checklistLines
        guard !packetLines.isEmpty else { return }
        let note = ProjectNote(
            projectId: projectId,
            companyId: companyId,
            authorId: userId ?? "",
            content: "SITE VISIT PACKET\n\n" + packetLines.joined(separator: "\n\n"),
            createdAt: Date()
        )
        note.needsSync = true
        modelContext.insert(note)
    }

    private static func attachDeckDesigns(
        _ deckDesignIds: [String],
        projectId: String,
        modelContext: ModelContext
    ) {
        for deckDesignId in deckDesignIds {
            let descriptor = FetchDescriptor<DeckDesign>(
                predicate: #Predicate<DeckDesign> { design in
                    design.id == deckDesignId
                }
            )
            guard let design = try? modelContext.fetch(descriptor).first else { continue }
            design.projectId = projectId
            design.markForSync()
        }
    }
}
