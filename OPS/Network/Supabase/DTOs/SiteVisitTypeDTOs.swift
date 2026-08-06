//
//  SiteVisitTypeDTOs.swift
//  OPS
//
//  Supabase wire contract for company-wide site-visit checklist templates.
//

import Foundation

struct SiteVisitTypeDTO: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let companyId: String
    let slug: String
    let name: String
    let descriptionText: String?
    let isSystemTemplate: Bool
    let isDefault: Bool
    let sortOrder: Int
    let fields: [SiteVisitTypeFieldDefinition]
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, fields
        case companyId = "company_id"
        case descriptionText = "description_text"
        case isSystemTemplate = "is_system_template"
        case isDefault = "is_default"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

extension SiteVisitTypeDTO {
    func toModel() -> SiteVisitType {
        let model = SiteVisitType(
            id: id.lowercased(),
            companyId: companyId.lowercased(),
            slug: slug,
            name: name,
            descriptionText: descriptionText,
            isSystemTemplate: isSystemTemplate,
            isDefault: isDefault,
            sortOrder: sortOrder,
            fields: fields,
            createdAt: createdAt.flatMap(SupabaseDate.parse) ?? Date()
        )
        model.updatedAt = updatedAt.flatMap(SupabaseDate.parse)
        model.deletedAt = deletedAt.flatMap(SupabaseDate.parse)
        model.needsSync = false
        model.lastSyncedAt = Date()
        return model
    }
}
