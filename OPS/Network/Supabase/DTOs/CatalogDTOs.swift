//
//  CatalogDTOs.swift
//  OPS
//
//  DTOs for catalog_* tables — read, create, update.
//

import Foundation

// MARK: - Read DTOs

struct CatalogCategoryDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let parentId: String?
    let sortOrder: Int
    let colorHex: String?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId                  = "company_id"
        case name
        case parentId                   = "parent_id"
        case sortOrder                  = "sort_order"
        case colorHex                   = "color_hex"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
        case createdAt                  = "created_at"
        case updatedAt                  = "updated_at"
        case deletedAt                  = "deleted_at"
    }

    func toModel() -> CatalogCategory {
        let cat = CatalogCategory(
            id: id, companyId: companyId, name: name,
            parentId: parentId, sortOrder: sortOrder,
            colorHex: colorHex,
            defaultWarningThreshold: defaultWarningThreshold,
            defaultCriticalThreshold: defaultCriticalThreshold
        )
        cat.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return cat
    }
}

struct CatalogItemDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let categoryId: String?
    let name: String
    let description: String?
    let defaultPrice: Double?
    let defaultUnitCost: Double?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?
    let defaultUnitId: String?
    let imageUrl: String?
    let notes: String?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId                  = "company_id"
        case categoryId                 = "category_id"
        case name
        case description
        case defaultPrice               = "default_price"
        case defaultUnitCost            = "default_unit_cost"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
        case defaultUnitId              = "default_unit_id"
        case imageUrl                   = "image_url"
        case notes                      = "notes"
        case isActive                   = "is_active"
        case createdAt                  = "created_at"
        case updatedAt                  = "updated_at"
        case deletedAt                  = "deleted_at"
    }

    func toModel() -> CatalogItem {
        let item = CatalogItem(
            id: id, companyId: companyId, name: name,
            categoryId: categoryId,
            defaultPrice: defaultPrice,
            defaultUnitCost: defaultUnitCost,
            defaultWarningThreshold: defaultWarningThreshold,
            defaultCriticalThreshold: defaultCriticalThreshold,
            defaultUnitId: defaultUnitId,
            isActive: isActive
        )
        item.itemDescription = description
        item.imageUrl = imageUrl
        item.notes = notes
        item.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return item
    }
}

struct CatalogVariantDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let catalogItemId: String
    let sku: String?
    let quantity: Double
    let priceOverride: Double?
    let unitCostOverride: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitId: String?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId          = "company_id"
        case catalogItemId      = "catalog_item_id"
        case sku
        case quantity
        case priceOverride      = "price_override"
        case unitCostOverride   = "unit_cost_override"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case unitId             = "unit_id"
        case isActive           = "is_active"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case deletedAt          = "deleted_at"
    }

    func toModel() -> CatalogVariant {
        let v = CatalogVariant(
            id: id, companyId: companyId, catalogItemId: catalogItemId,
            sku: sku, quantity: quantity,
            priceOverride: priceOverride, unitCostOverride: unitCostOverride,
            warningThreshold: warningThreshold, criticalThreshold: criticalThreshold,
            unitId: unitId, isActive: isActive
        )
        v.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return v
    }
}

struct CatalogOptionDTO: Codable, Identifiable {
    let id: String
    let catalogItemId: String
    let name: String
    let sortOrder: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case catalogItemId  = "catalog_item_id"
        case name
        case sortOrder      = "sort_order"
        case createdAt      = "created_at"
    }

    func toModel() -> CatalogOption {
        CatalogOption(id: id, catalogItemId: catalogItemId, name: name, sortOrder: sortOrder)
    }
}

struct CatalogOptionValueDTO: Codable, Identifiable {
    let id: String
    let optionId: String
    let value: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case optionId   = "option_id"
        case value
        case sortOrder  = "sort_order"
    }

    func toModel() -> CatalogOptionValue {
        CatalogOptionValue(id: id, optionId: optionId, value: value, sortOrder: sortOrder)
    }
}

struct CatalogVariantOptionValueDTO: Codable {
    let variantId: String
    let optionValueId: String

    enum CodingKeys: String, CodingKey {
        case variantId      = "variant_id"
        case optionValueId  = "option_value_id"
    }

    func toModel() -> CatalogVariantOptionValue {
        CatalogVariantOptionValue(variantId: variantId, optionValueId: optionValueId)
    }
}

struct CatalogTagDTO: Codable, Identifiable {
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

    func toModel() -> CatalogTag {
        let t = CatalogTag(id: id, companyId: companyId, name: name,
                            warningThreshold: warningThreshold, criticalThreshold: criticalThreshold)
        t.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return t
    }
}

struct CatalogItemTagDTO: Codable, Identifiable {
    let id: String
    let catalogItemId: String
    let tagId: String

    enum CodingKeys: String, CodingKey {
        case id
        case catalogItemId  = "catalog_item_id"
        case tagId          = "tag_id"
    }

    func toModel() -> CatalogItemTag {
        CatalogItemTag(id: id, catalogItemId: catalogItemId, tagId: tagId)
    }
}

struct CatalogUnitDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let display: String
    let abbreviation: String?
    let dimension: String
    let isDefault: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId      = "company_id"
        case display
        case abbreviation
        case dimension
        case isDefault      = "is_default"
        case sortOrder      = "sort_order"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
        case deletedAt      = "deleted_at"
    }

    func toModel() -> CatalogUnit {
        let u = CatalogUnit(id: id, companyId: companyId, display: display,
                            abbreviation: abbreviation, dimension: dimension,
                            isDefault: isDefault, sortOrder: sortOrder)
        u.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return u
    }
}

struct CatalogSnapshotDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let createdById: String?
    let isAutomatic: Bool
    let itemCount: Int
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId      = "company_id"
        case createdById    = "created_by_id"
        case isAutomatic    = "is_automatic"
        case itemCount      = "item_count"
        case notes
        case createdAt      = "created_at"
    }

    func toModel() -> CatalogSnapshot {
        CatalogSnapshot(
            id: id, companyId: companyId,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            createdById: createdById, isAutomatic: isAutomatic,
            itemCount: itemCount, notes: notes
        )
    }
}

struct CatalogSnapshotItemDTO: Codable, Identifiable {
    let id: String
    let snapshotId: String
    let originalVariantId: String?
    let familyName: String
    let variantLabel: String?
    let quantity: Double
    let unitDisplay: String?
    let sku: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case snapshotId        = "snapshot_id"
        case originalVariantId = "original_variant_id"
        case familyName        = "family_name"
        case variantLabel      = "variant_label"
        case quantity
        case unitDisplay       = "unit_display"
        case sku
        case description
    }

    func toModel() -> CatalogSnapshotItem {
        CatalogSnapshotItem(
            id: id, snapshotId: snapshotId,
            originalVariantId: originalVariantId,
            familyName: familyName, variantLabel: variantLabel,
            quantity: quantity, unitDisplay: unitDisplay,
            sku: sku, itemDescription: description
        )
    }
}

// MARK: - Create / Update DTOs (write paths)

struct CreateCatalogCategoryDTO: Codable {
    let companyId: String
    let name: String
    let parentId: String?
    let sortOrder: Int
    let colorHex: String?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case companyId                  = "company_id"
        case name
        case parentId                   = "parent_id"
        case sortOrder                  = "sort_order"
        case colorHex                   = "color_hex"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
    }
}

struct CreateCatalogItemDTO: Codable {
    let companyId: String
    let categoryId: String?
    let name: String
    let description: String?
    let defaultPrice: Double?
    let defaultUnitCost: Double?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?
    let defaultUnitId: String?

    enum CodingKeys: String, CodingKey {
        case companyId                  = "company_id"
        case categoryId                 = "category_id"
        case name
        case description
        case defaultPrice               = "default_price"
        case defaultUnitCost            = "default_unit_cost"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
        case defaultUnitId              = "default_unit_id"
    }
}

struct CreateCatalogVariantDTO: Codable {
    let companyId: String
    let catalogItemId: String
    let sku: String?
    let quantity: Double
    let priceOverride: Double?
    let unitCostOverride: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitId: String?

    enum CodingKeys: String, CodingKey {
        case companyId          = "company_id"
        case catalogItemId      = "catalog_item_id"
        case sku
        case quantity
        case priceOverride      = "price_override"
        case unitCostOverride   = "unit_cost_override"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case unitId             = "unit_id"
    }
}

struct UpdateCatalogVariantDTO: Codable {
    var sku: String?
    var quantity: Double?
    var priceOverride: Double?
    var unitCostOverride: Double?
    var warningThreshold: Double?
    var criticalThreshold: Double?
    var unitId: String?

    enum CodingKeys: String, CodingKey {
        case sku
        case quantity
        case priceOverride      = "price_override"
        case unitCostOverride   = "unit_cost_override"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case unitId             = "unit_id"
    }
}

// Additional Create/Update DTOs follow the same pattern. They are added on
// demand by callers (e.g., CatalogRepository) — most catalog write paths from
// iOS are quantity adjustments on variants, which use UpdateCatalogVariantDTO
// above. Authoring options/values/tags is read-only on iOS for now (web-only).

struct UpsertCatalogVariantOptionValueDTO: Codable {
    let variantId: String
    let optionValueId: String

    enum CodingKeys: String, CodingKey {
        case variantId      = "variant_id"
        case optionValueId  = "option_value_id"
    }
}

struct UpdateCatalogCategoryDTO: Codable {
    var name: String?
    var parentId: String?
    var sortOrder: Int?
    var colorHex: String?
    var defaultWarningThreshold: Double?
    var defaultCriticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case parentId                   = "parent_id"
        case sortOrder                  = "sort_order"
        case colorHex                   = "color_hex"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
    }

    // Custom encode skips nil values so a partial update doesn't clobber
    // unrelated columns. Default `Codable` synthesis would emit JSON null
    // for nil optionals, which PostgREST treats as "set this column to
    // NULL" — exactly the behavior we want to avoid for partial updates.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(defaultWarningThreshold, forKey: .defaultWarningThreshold)
        try c.encodeIfPresent(defaultCriticalThreshold, forKey: .defaultCriticalThreshold)
    }
}

struct CreateCatalogTagDTO: Codable {
    let companyId: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case companyId  = "company_id"
        case name
    }
}

struct UpdateCatalogTagDTO: Codable {
    var name: String?

    enum CodingKeys: String, CodingKey {
        case name
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
    }
}

struct CreateCatalogUnitDTO: Codable {
    let companyId: String
    let display: String
    let abbreviation: String?
    let dimension: String
    let isDefault: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case display
        case abbreviation
        case dimension
        case isDefault      = "is_default"
        case sortOrder      = "sort_order"
    }
}

struct UpdateCatalogUnitDTO: Codable {
    var display: String?
    var abbreviation: String?
    var dimension: String?
    var isDefault: Bool?
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case display
        case abbreviation
        case dimension
        case isDefault      = "is_default"
        case sortOrder      = "sort_order"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(display, forKey: .display)
        try c.encodeIfPresent(abbreviation, forKey: .abbreviation)
        try c.encodeIfPresent(dimension, forKey: .dimension)
        try c.encodeIfPresent(isDefault, forKey: .isDefault)
        try c.encodeIfPresent(sortOrder, forKey: .sortOrder)
    }
}

struct CreateCatalogSnapshotDTO: Codable {
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

struct CreateCatalogSnapshotItemDTO: Codable {
    let snapshotId: String
    let originalVariantId: String?
    let familyName: String
    let variantLabel: String?
    let quantity: Double
    let unitDisplay: String?
    let sku: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case snapshotId        = "snapshot_id"
        case originalVariantId = "original_variant_id"
        case familyName        = "family_name"
        case variantLabel      = "variant_label"
        case quantity
        case unitDisplay       = "unit_display"
        case sku
        case description
    }
}
