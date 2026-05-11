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
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case bundleProductId = "bundle_product_id"
        case childProductId  = "child_product_id"
        case quantity
        case displayOrder    = "display_order"
    }
}

struct UpdateProductBundleItemDTO: Codable {
    var quantity: Double?
    var displayOrder: Int?

    enum CodingKeys: String, CodingKey {
        case quantity
        case displayOrder = "display_order"
    }
}
