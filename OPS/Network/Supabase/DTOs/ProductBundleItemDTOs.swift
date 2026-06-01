//
//  ProductBundleItemDTOs.swift
//  OPS
//
//  Read/Create/Update DTOs for public.product_bundle_items. Backs the
//  bundle composition sheets — each row maps a bundle Product (kind=.package)
//  to a child Product with a per-row quantity + display order.
//

import Foundation

struct ProductBundleItemDTO: Codable {
    let id: String
    let companyId: String
    let bundleProductId: String
    let childProductId: String
    let quantity: Double
    let relationshipKind: String?
    let suggestionReason: String?
    let compatibilitySelector: RawJSONColumn?
    let displayOrder: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId        = "company_id"
        case bundleProductId  = "bundle_product_id"
        case childProductId   = "child_product_id"
        case quantity
        case relationshipKind = "relationship_kind"
        case suggestionReason = "suggestion_reason"
        case compatibilitySelector = "compatibility_selector"
        case displayOrder     = "display_order"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case deletedAt        = "deleted_at"
    }

    func toModel() -> ProductBundleItem {
        let item = ProductBundleItem(
            id: id,
            companyId: companyId,
            bundleProductId: bundleProductId,
            childProductId: childProductId,
            quantity: quantity,
            relationshipKind: relationshipKind.flatMap { ProductBundleRelationshipKind(rawValue: $0) } ?? .required,
            suggestionReason: suggestionReason,
            compatibilitySelectorJSON: compatibilitySelector?.rawJSONString,
            displayOrder: displayOrder,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        item.updatedAt = SupabaseDate.parse(updatedAt) ?? item.createdAt
        item.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return item
    }
}

struct CreateProductBundleItemDTO: Codable {
    let id: String
    let companyId: String
    let bundleProductId: String
    let childProductId: String
    let quantity: Double
    let relationshipKind: ProductBundleRelationshipKind
    let suggestionReason: String?
    let compatibilitySelector: RawJSONColumn?
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case bundleProductId = "bundle_product_id"
        case childProductId  = "child_product_id"
        case quantity
        case relationshipKind = "relationship_kind"
        case suggestionReason = "suggestion_reason"
        case compatibilitySelector = "compatibility_selector"
        case displayOrder    = "display_order"
    }

    init(
        id: String,
        companyId: String,
        bundleProductId: String,
        childProductId: String,
        quantity: Double,
        relationshipKind: ProductBundleRelationshipKind = .required,
        suggestionReason: String? = nil,
        compatibilitySelector: RawJSONColumn? = nil,
        displayOrder: Int
    ) {
        self.id = id
        self.companyId = companyId
        self.bundleProductId = bundleProductId
        self.childProductId = childProductId
        self.quantity = quantity
        self.relationshipKind = relationshipKind
        self.suggestionReason = suggestionReason
        self.compatibilitySelector = compatibilitySelector
        self.displayOrder = displayOrder
    }

    var canDegradeToLegacyRequiredRow: Bool {
        relationshipKind == .required &&
            suggestionReason == nil &&
            compatibilitySelector == nil
    }
}

struct UpdateProductBundleItemDTO: Codable {
    var quantity: Double?
    var relationshipKind: ProductBundleRelationshipKind?
    var suggestionReason: String?
    var compatibilitySelector: RawJSONColumn?
    var displayOrder: Int?

    enum CodingKeys: String, CodingKey {
        case quantity
        case relationshipKind = "relationship_kind"
        case suggestionReason = "suggestion_reason"
        case compatibilitySelector = "compatibility_selector"
        case displayOrder = "display_order"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(quantity, forKey: .quantity)
        try c.encodeIfPresent(relationshipKind, forKey: .relationshipKind)
        try c.encodeIfPresent(suggestionReason, forKey: .suggestionReason)
        try c.encodeIfPresent(compatibilitySelector, forKey: .compatibilitySelector)
        try c.encodeIfPresent(displayOrder, forKey: .displayOrder)
    }

    var includesRelationshipMetadata: Bool {
        relationshipKind != nil ||
            suggestionReason != nil ||
            compatibilitySelector != nil
    }
}
