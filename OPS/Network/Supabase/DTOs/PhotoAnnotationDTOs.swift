//
//  PhotoAnnotationDTOs.swift
//  OPS
//
//  Data Transfer Objects for project_photo_annotations Supabase table.
//

import Foundation

struct PhotoAnnotationDTO: Codable, Identifiable {
    let id: String
    let projectId: String
    let companyId: String
    let photoUrl: String
    let renderedPhotoUrl: String?
    let annotationUrl: String?
    let note: String?
    let authorId: String
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?
    let dimensions: DimensionsJSONValue?
    // Collaborative markup (spec 2026-06-23). Passthrough JSON so a malformed
    // jsonb element can never fail the whole inbound annotation decode; the model
    // accessor decodes resiliently at read time.
    let layers: DimensionsJSONValue?
    let changeLog: DimensionsJSONValue?
    let beforeSnapshotUrl: String?
    let afterSnapshotUrl: String?

    var dimensionsData: Data? {
        Self.encodeJSONValue(dimensions)
    }
    var layersData: Data? {
        Self.encodeJSONValue(layers)
    }
    var changeLogData: Data? {
        Self.encodeJSONValue(changeLog)
    }
    /// Resiliently-decoded markup layers from the server row (for the inbound union merge).
    var layersModel: [MarkupLayer] {
        MarkupCoding.decodeArray(layersData)
    }
    var changeLogModel: [MarkupChangeEvent] {
        MarkupCoding.decodeArray(changeLogData)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId     = "project_id"
        case companyId     = "company_id"
        case photoUrl      = "photo_url"
        case renderedPhotoUrl = "rendered_photo_url"
        case annotationUrl = "annotation_url"
        case note
        case authorId      = "author_id"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
        case deletedAt     = "deleted_at"
        case dimensions
        case layers
        case changeLog          = "change_log"
        case beforeSnapshotUrl  = "before_snapshot_url"
        case afterSnapshotUrl   = "after_snapshot_url"
    }

    func toModel() -> PhotoAnnotation {
        let annotation = PhotoAnnotation(
            id: id,
            projectId: projectId,
            companyId: companyId,
            photoURL: photoUrl,
            authorId: authorId,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        annotation.renderedPhotoURL = renderedPhotoUrl
        annotation.annotationURL = annotationUrl
        annotation.note = note ?? ""
        if let updatedAt = updatedAt {
            annotation.updatedAt = SupabaseDate.parse(updatedAt)
        }
        if let deletedAt = deletedAt {
            annotation.deletedAt = SupabaseDate.parse(deletedAt)
        }
        annotation.dimensionsData = dimensionsData
        annotation.layersData = layersData
        annotation.changeLogData = changeLogData
        annotation.beforeSnapshotURL = beforeSnapshotUrl
        annotation.afterSnapshotURL = afterSnapshotUrl
        // hiddenAuthorIds is local-only (per-viewer) — never populated from sync.
        return annotation
    }

    private static func encodeJSONValue(_ value: DimensionsJSONValue?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }
}

struct UpsertPhotoAnnotationDTO: Codable {
    let projectId: String
    let companyId: String
    let photoUrl: String
    let renderedPhotoUrl: String?
    let annotationUrl: String?
    let note: String
    let authorId: String
    let dimensions: DimensionsJSONValue? = nil

    init(
        projectId: String,
        companyId: String,
        photoUrl: String,
        renderedPhotoUrl: String? = nil,
        annotationUrl: String?,
        note: String,
        authorId: String
    ) {
        self.projectId = projectId
        self.companyId = companyId
        self.photoUrl = photoUrl
        self.renderedPhotoUrl = renderedPhotoUrl
        self.annotationUrl = annotationUrl
        self.note = note
        self.authorId = authorId
    }

    enum CodingKeys: String, CodingKey {
        case projectId     = "project_id"
        case companyId     = "company_id"
        case photoUrl      = "photo_url"
        case renderedPhotoUrl = "rendered_photo_url"
        case annotationUrl = "annotation_url"
        case note
        case authorId      = "author_id"
        case dimensions
    }
}
