//
//  InventoryDTOs.swift
//  OPS
//
//  Data Transfer Objects for Inventory Supabase tables.
//

import Foundation

// MARK: - Read DTOs

struct InventoryUnitReadDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let display: String
    let isDefault: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId    = "company_id"
        case display
        case isDefault    = "is_default"
        case sortOrder    = "sort_order"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
        case deletedAt    = "deleted_at"
    }

    func toModel() -> InventoryUnit {
        let unit = InventoryUnit(
            id: id,
            display: display,
            companyId: companyId,
            isDefault: isDefault,
            sortOrder: sortOrder
        )
        unit.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return unit
    }
}

struct InventoryTagReadDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId          = "company_id"
        case name
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case deletedAt          = "deleted_at"
    }

    func toModel() -> InventoryTag {
        let tag = InventoryTag(
            id: id,
            name: name,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            companyId: companyId
        )
        tag.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return tag
    }
}

struct InventoryItemReadDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let description: String?
    let quantity: Double
    let unitId: String?
    let sku: String?
    let notes: String?
    let imageUrl: String?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId          = "company_id"
        case name
        case description
        case quantity
        case unitId             = "unit_id"
        case sku
        case notes
        case imageUrl           = "image_url"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case deletedAt          = "deleted_at"
    }

    func toModel() -> InventoryItem {
        let item = InventoryItem(
            id: id,
            name: name,
            quantity: quantity,
            companyId: companyId,
            unitId: unitId,
            itemDescription: description,
            sku: sku,
            notes: notes,
            imageUrl: imageUrl,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )
        item.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return item
    }
}

struct InventoryItemTagReadDTO: Codable, Identifiable {
    let id: String
    let itemId: String
    let tagId: String

    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
        case tagId  = "tag_id"
    }
}

struct InventorySnapshotReadDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let createdById: String?
    let isAutomatic: Bool
    let itemCount: Int
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId    = "company_id"
        case createdById  = "created_by_id"
        case isAutomatic  = "is_automatic"
        case itemCount    = "item_count"
        case notes
        case createdAt    = "created_at"
    }

    func toModel() -> InventorySnapshot {
        return InventorySnapshot(
            id: id,
            companyId: companyId,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            createdById: createdById,
            isAutomatic: isAutomatic,
            itemCount: itemCount,
            notes: notes
        )
    }
}

struct InventorySnapshotItemReadDTO: Codable, Identifiable {
    let id: String
    let snapshotId: String
    let originalItemId: String?
    let name: String
    let quantity: Double
    let unitDisplay: String?
    let sku: String?
    let tagsString: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case snapshotId     = "snapshot_id"
        case originalItemId = "original_item_id"
        case name
        case quantity
        case unitDisplay    = "unit_display"
        case sku
        case tagsString     = "tags_string"
        case description
    }

    func toModel() -> InventorySnapshotItem {
        return InventorySnapshotItem(
            id: id,
            snapshotId: snapshotId,
            originalItemId: originalItemId ?? "",
            name: name,
            quantity: quantity,
            unitDisplay: unitDisplay,
            sku: sku,
            tagsString: tagsString ?? "",
            itemDescription: description
        )
    }
}

// MARK: - Create DTOs

struct CreateInventoryUnitDTO: Codable {
    let companyId: String
    let display: String
    let isDefault: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case companyId  = "company_id"
        case display
        case isDefault  = "is_default"
        case sortOrder  = "sort_order"
    }
}

struct CreateInventoryTagDTO: Codable {
    let companyId: String
    let name: String
    let warningThreshold: Double?
    let criticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case companyId          = "company_id"
        case name
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
    }
}

struct CreateInventoryItemDTO: Codable {
    let companyId: String
    let name: String
    let description: String?
    let quantity: Double
    let unitId: String?
    let sku: String?
    let notes: String?
    let imageUrl: String?
    let warningThreshold: Double?
    let criticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case companyId          = "company_id"
        case name
        case description
        case quantity
        case unitId             = "unit_id"
        case sku
        case notes
        case imageUrl           = "image_url"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
    }
}

struct CreateInventorySnapshotDTO: Codable {
    let companyId: String
    let createdById: String?
    let isAutomatic: Bool
    let itemCount: Int
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case companyId    = "company_id"
        case createdById  = "created_by_id"
        case isAutomatic  = "is_automatic"
        case itemCount    = "item_count"
        case notes
    }
}

struct CreateInventorySnapshotItemDTO: Codable {
    let snapshotId: String
    let originalItemId: String?
    let name: String
    let quantity: Double
    let unitDisplay: String?
    let sku: String?
    let tagsString: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case snapshotId     = "snapshot_id"
        case originalItemId = "original_item_id"
        case name
        case quantity
        case unitDisplay    = "unit_display"
        case sku
        case tagsString     = "tags_string"
        case description
    }
}

// MARK: - Update DTOs

struct UpdateInventoryItemDTO: Codable {
    var name: String?
    var description: String?
    var quantity: Double?
    var unitId: String?
    var sku: String?
    var notes: String?
    var imageUrl: String?
    var warningThreshold: Double?
    var criticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case quantity
        case unitId             = "unit_id"
        case sku
        case notes
        case imageUrl           = "image_url"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
    }
}

struct UpdateInventoryTagDTO: Codable {
    var name: String?
    var warningThreshold: Double?
    var criticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
    }
}

struct UpdateInventoryUnitDTO: Codable {
    var display: String?
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case display
        case sortOrder = "sort_order"
    }
}
