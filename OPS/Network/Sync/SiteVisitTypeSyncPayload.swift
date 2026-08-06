//
//  SiteVisitTypeSyncPayload.swift
//  OPS
//
//  Exact server-column payload shared by seed and settings mutations.
//

import Foundation

enum SiteVisitTypeSyncPayload {
    static func make(_ type: SiteVisitType) throws -> [String: Any] {
        let fieldsData = try JSONEncoder().encode(type.fields)
        let fields = try JSONSerialization.jsonObject(with: fieldsData)
        let formatter = ISO8601DateFormatter()

        var payload: [String: Any] = [
            "id": type.id.lowercased(),
            "company_id": type.companyId.lowercased(),
            "slug": type.slug,
            "name": type.name,
            "is_system_template": type.isSystemTemplate,
            "is_default": type.isDefault,
            "sort_order": type.sortOrder,
            "fields": fields,
            "created_at": formatter.string(from: type.createdAt)
        ]
        if let descriptionText = type.descriptionText {
            payload["description_text"] = descriptionText
        } else {
            payload["description_text"] = NSNull()
        }
        if let deletedAt = type.deletedAt {
            payload["deleted_at"] = formatter.string(from: deletedAt)
        } else {
            payload["deleted_at"] = NSNull()
        }
        return payload
    }
}
