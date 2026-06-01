//
//  CatalogProductOptionMappingDTOs.swift
//  OPS
//

import Foundation

struct CatalogProductOptionMappingDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let productId: String
    let catalogItemId: String
    let catalogOptionId: String
    let productOptionId: String
    let catalogOptionValueId: String?
    let productOptionValueId: String?
    let mappingKind: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId              = "company_id"
        case productId              = "product_id"
        case catalogItemId          = "catalog_item_id"
        case catalogOptionId        = "catalog_option_id"
        case productOptionId        = "product_option_id"
        case catalogOptionValueId   = "catalog_option_value_id"
        case productOptionValueId   = "product_option_value_id"
        case mappingKind            = "mapping_kind"
        case createdAt              = "created_at"
        case updatedAt              = "updated_at"
        case deletedAt              = "deleted_at"
    }

    func toModel() -> CatalogProductOptionMapping {
        let model = CatalogProductOptionMapping(
            id: id,
            companyId: companyId,
            productId: productId,
            catalogItemId: catalogItemId,
            catalogOptionId: catalogOptionId,
            productOptionId: productOptionId,
            catalogOptionValueId: catalogOptionValueId,
            productOptionValueId: productOptionValueId,
            mappingKind: CatalogProductOptionMappingKind(rawValue: mappingKind) ?? .axis,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        model.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return model
    }
}

struct CreateCatalogProductOptionMappingDTO: Codable {
    let id: String
    let companyId: String
    let productId: String
    let catalogItemId: String
    let catalogOptionId: String
    let productOptionId: String
    let catalogOptionValueId: String?
    let productOptionValueId: String?
    let mappingKind: CatalogProductOptionMappingKind

    enum CodingKeys: String, CodingKey {
        case id
        case companyId              = "company_id"
        case productId              = "product_id"
        case catalogItemId          = "catalog_item_id"
        case catalogOptionId        = "catalog_option_id"
        case productOptionId        = "product_option_id"
        case catalogOptionValueId   = "catalog_option_value_id"
        case productOptionValueId   = "product_option_value_id"
        case mappingKind            = "mapping_kind"
    }
}

struct UpdateCatalogProductOptionMappingDTO: Codable {
    var catalogOptionValueId: String?
    var productOptionValueId: String?
    var mappingKind: CatalogProductOptionMappingKind?

    enum CodingKeys: String, CodingKey {
        case catalogOptionValueId   = "catalog_option_value_id"
        case productOptionValueId   = "product_option_value_id"
        case mappingKind            = "mapping_kind"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(catalogOptionValueId, forKey: .catalogOptionValueId)
        try c.encodeIfPresent(productOptionValueId, forKey: .productOptionValueId)
        try c.encodeIfPresent(mappingKind, forKey: .mappingKind)
    }
}
