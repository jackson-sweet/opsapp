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

    var dimensionsData: Data? {
        Self.encodeDimensionsData(from: dimensions)
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
        return annotation
    }

    private static func encodeDimensionsData(from dimensions: DimensionsJSONValue?) -> Data? {
        guard let dimensions else { return nil }
        return try? JSONEncoder().encode(dimensions)
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
