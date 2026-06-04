//
//  ProjectPhotoDTOs.swift
//  OPS
//
//  Data Transfer Objects for the project_photos Supabase table.
//
//  Read-only from the sync engine: ProjectPhoto rows are created server-side
//  by `ImageSyncManager.insertProjectPhotoRows`. Optional-heavy decoding keeps
//  a single malformed row from failing an entire sync batch.
//

import Foundation

struct ProjectPhotoDTO: Codable, Identifiable {
    let id: String
    let projectId: String
    let companyId: String
    let url: String
    let thumbnailURL: String?
    let renderedURL: String?
    let source: String?
    let siteVisitId: String?
    let uploadedBy: String?
    let caption: String?
    let isClientVisible: Bool?
    let takenAt: String?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId       = "project_id"
        case companyId       = "company_id"
        case url
        case thumbnailURL    = "thumbnail_url"
        case renderedURL     = "rendered_url"
        case source
        case siteVisitId     = "site_visit_id"
        case uploadedBy      = "uploaded_by"
        case caption
        case isClientVisible = "is_client_visible"
        case takenAt         = "taken_at"
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case deletedAt       = "deleted_at"
    }

    func toModel() -> ProjectPhoto {
        let photo = ProjectPhoto(
            id: id,
            projectId: projectId,
            companyId: companyId,
            url: url,
            thumbnailURL: thumbnailURL,
            renderedURL: renderedURL,
            source: source ?? "other",
            siteVisitId: siteVisitId,
            uploadedBy: uploadedBy ?? "",
            caption: caption,
            isClientVisible: isClientVisible ?? false,
            takenAt: takenAt.flatMap { SupabaseDate.parse($0) },
            createdAt: SupabaseDate.parse(createdAt ?? "") ?? Date()
        )
        photo.updatedAt = updatedAt.flatMap { SupabaseDate.parse($0) }
        photo.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return photo
    }
}
