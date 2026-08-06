//
//  SiteVisitTypeServerMerge.swift
//  OPS
//
//  One merge rule shared by full pull, delta pull, and realtime.
//

import Foundation
import SwiftData

enum SiteVisitTypeServerMerge {
    static let mutableFields: Set<String> = [
        "slug",
        "name",
        "description_text",
        "is_system_template",
        "is_default",
        "sort_order",
        "fields",
        "deleted_at"
    ]

    @discardableResult
    static func merge(
        dto: SiteVisitTypeDTO,
        accepting acceptedFields: Set<String>,
        hasPendingLocalOperation: Bool,
        context: ModelContext
    ) throws -> Bool {
        let id = dto.id.lowercased()
        let companyId = dto.companyId.lowercased()
        guard !id.isEmpty, !companyId.isEmpty else { return false }

        let descriptor = FetchDescriptor<SiteVisitType>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            guard existing.companyId.lowercased() == companyId else { return false }

            if acceptedFields.contains("slug") { existing.slug = dto.slug }
            if acceptedFields.contains("name") { existing.name = dto.name }
            if acceptedFields.contains("description_text") {
                existing.descriptionText = dto.descriptionText
            }
            if acceptedFields.contains("is_system_template") {
                existing.isSystemTemplate = dto.isSystemTemplate
            }
            if acceptedFields.contains("is_default") {
                existing.isDefault = dto.isDefault
            }
            if acceptedFields.contains("sort_order") {
                existing.sortOrder = dto.sortOrder
            }
            if acceptedFields.contains("fields") { existing.fields = dto.fields }
            if acceptedFields.contains("deleted_at") {
                existing.deletedAt = dto.deletedAt.flatMap(SupabaseDate.parse)
            }
            existing.updatedAt = dto.updatedAt.flatMap(SupabaseDate.parse)
            existing.lastSyncedAt = Date()
            existing.needsSync = hasPendingLocalOperation
        } else {
            guard !hasPendingLocalOperation else { return false }
            context.insert(dto.toModel())
        }

        return true
    }
}
