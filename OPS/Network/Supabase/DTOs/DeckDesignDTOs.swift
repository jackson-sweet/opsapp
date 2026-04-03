//
//  DeckDesignDTOs.swift
//  OPS
//
//  Data Transfer Objects for deck_designs Supabase table.
//

import Foundation

struct SupabaseDeckDesignDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let projectId: String?
    let title: String
    let drawingData: DeckDrawingData   // JSONB — decoded directly as Codable struct
    let thumbnailUrl: String?
    let version: Int
    let createdBy: String?
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId    = "company_id"
        case projectId    = "project_id"
        case title
        case drawingData  = "drawing_data"
        case thumbnailUrl = "thumbnail_url"
        case version
        case createdBy    = "created_by"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case deletedAt    = "deleted_at"
    }

    func toModel() -> DeckDesign {
        let model = DeckDesign(
            id: id,
            companyId: companyId,
            projectId: projectId,
            title: title,
            drawingDataJSON: drawingData.toJSON(),
            createdBy: createdBy
        )
        model.thumbnailURL = thumbnailUrl
        model.version = version
        model.createdAt = SupabaseDate.parse(createdAt) ?? Date()
        if let updatedAt = updatedAt {
            model.updatedAt = SupabaseDate.parse(updatedAt)
        }
        if let deletedAt = deletedAt {
            model.deletedAt = SupabaseDate.parse(deletedAt)
        }
        return model
    }

    static func fromModel(_ model: DeckDesign) -> SupabaseDeckDesignDTO {
        SupabaseDeckDesignDTO(
            id: model.id,
            companyId: model.companyId,
            projectId: model.projectId,
            title: model.title,
            drawingData: model.drawingData,
            thumbnailUrl: model.thumbnailURL,
            version: model.version,
            createdBy: model.createdBy,
            createdAt: ISO8601DateFormatter().string(from: model.createdAt),
            updatedAt: model.updatedAt.map { ISO8601DateFormatter().string(from: $0) },
            deletedAt: model.deletedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }
}
