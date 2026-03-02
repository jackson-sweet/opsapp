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
    let annotationUrl: String?
    let note: String?
    let authorId: String
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId     = "project_id"
        case companyId     = "company_id"
        case photoUrl      = "photo_url"
        case annotationUrl = "annotation_url"
        case note
        case authorId      = "author_id"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
        case deletedAt     = "deleted_at"
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
        annotation.annotationURL = annotationUrl
        annotation.note = note ?? ""
        if let updatedAt = updatedAt {
            annotation.updatedAt = SupabaseDate.parse(updatedAt)
        }
        if let deletedAt = deletedAt {
            annotation.deletedAt = SupabaseDate.parse(deletedAt)
        }
        return annotation
    }
}

struct UpsertPhotoAnnotationDTO: Codable {
    let projectId: String
    let companyId: String
    let photoUrl: String
    let annotationUrl: String?
    let note: String
    let authorId: String

    enum CodingKeys: String, CodingKey {
        case projectId     = "project_id"
        case companyId     = "company_id"
        case photoUrl      = "photo_url"
        case annotationUrl = "annotation_url"
        case note
        case authorId      = "author_id"
    }
}
