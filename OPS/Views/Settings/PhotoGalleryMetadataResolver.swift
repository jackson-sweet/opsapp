//
//  PhotoGalleryMetadataResolver.swift
//  OPS
//
//  Joins canonical project_photos metadata to legacy gallery URLs without
//  conflating the photo uploader with the author of a note or markup layer.
//

import Foundation

struct PhotoGalleryResolvedMetadata: Equatable {
    let uploaderId: String?
    let date: Date?
    let note: String?
}

struct PhotoGalleryMetadataResolver {
    private struct Key: Hashable {
        let projectId: String
        let companyId: String
        let url: String
    }

    private struct PhotoSnapshot {
        let uploaderId: String?
        let date: Date
        let recency: Date
    }

    private struct AnnotationSnapshot {
        let note: String?
        let createdAt: Date
        let recency: Date
    }

    private let photosByKey: [Key: PhotoSnapshot]
    private let annotationsByKey: [Key: AnnotationSnapshot]

    init(projectPhotos: [ProjectPhoto], annotations: [PhotoAnnotation]) {
        var photoIndex: [Key: PhotoSnapshot] = [:]
        for photo in projectPhotos where photo.isGalleryEligible {
            let key = Key(
                projectId: photo.projectId,
                companyId: photo.companyId,
                url: GalleryPhotoURLIdentity.canonical(photo.url)
            )
            let snapshot = PhotoSnapshot(
                uploaderId: ProjectPhotoUploaderIdentity.canonicalUserID(photo.uploadedBy),
                date: photo.takenAt ?? photo.createdAt,
                recency: photo.updatedAt ?? photo.createdAt
            )
            if let current = photoIndex[key], current.recency > snapshot.recency {
                continue
            }
            photoIndex[key] = snapshot
        }
        photosByKey = photoIndex

        var annotationIndex: [Key: AnnotationSnapshot] = [:]
        for annotation in annotations where annotation.deletedAt == nil {
            let key = Key(
                projectId: annotation.projectId,
                companyId: annotation.companyId,
                url: GalleryPhotoURLIdentity.canonical(annotation.photoURL)
            )
            let trimmedNote = annotation.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let snapshot = AnnotationSnapshot(
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                createdAt: annotation.createdAt,
                recency: annotation.updatedAt ?? annotation.createdAt
            )
            if let current = annotationIndex[key], current.recency > snapshot.recency {
                continue
            }
            annotationIndex[key] = snapshot
        }
        annotationsByKey = annotationIndex
    }

    func metadata(
        projectId: String,
        companyId: String,
        url: String,
        legacyFallbackDate: Date?
    ) -> PhotoGalleryResolvedMetadata {
        let key = Key(
            projectId: projectId,
            companyId: companyId,
            url: GalleryPhotoURLIdentity.canonical(url)
        )
        let photo = photosByKey[key]
        let annotation = annotationsByKey[key]
        let date = photo?.date
            ?? GalleryOrdering.timestamp(fromURL: url)
            ?? annotation?.createdAt
            ?? legacyFallbackDate

        return PhotoGalleryResolvedMetadata(
            uploaderId: photo?.uploaderId,
            date: date,
            note: annotation?.note
        )
    }

    static func matchesUploader(_ uploaderId: String?, selectedIds: Set<String>) -> Bool {
        guard !selectedIds.isEmpty else { return true }
        guard let uploaderId = ProjectPhotoUploaderIdentity.canonicalUserID(uploaderId) else {
            return false
        }
        let canonicalSelection = Set(selectedIds.compactMap(ProjectPhotoUploaderIdentity.canonicalUserID))
        return canonicalSelection.contains(uploaderId)
    }
}
