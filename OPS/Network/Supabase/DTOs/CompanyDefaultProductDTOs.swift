//
//  CompanyDefaultProductDTOs.swift
//  OPS
//

import Foundation

struct CompanyDefaultProductDTO: Codable {
    let companyId: String
    let componentType: String   // 'railing' | 'deck_board' | 'stair_set' | 'gate' | 'post_set'
    let productId: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case componentType  = "component_type"
        case productId      = "product_id"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }

    func toModel() -> CompanyDefaultProduct {
        CompanyDefaultProduct(
            companyId: companyId,
            componentType: DesignComponentType(rawValue: componentType) ?? .railing,
            productId: productId,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
    }
}

struct UpsertCompanyDefaultProductDTO: Codable {
    let companyId: String
    let componentType: String
    let productId: String

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case componentType  = "component_type"
        case productId      = "product_id"
    }
}
