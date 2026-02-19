//
//  ProductDTOs.swift
//  OPS
//
//  Data Transfer Objects for Product/Service catalog Supabase table.
//

import Foundation

struct ProductDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let description: String?
    let unitPrice: Double
    let costPrice: Double?
    let unit: String?
    let type: String?
    let taxable: Bool?
    let taskTypeId: String?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId   = "company_id"
        case name
        case description
        case unitPrice   = "unit_price"
        case costPrice   = "cost_price"
        case unit
        case type
        case taxable
        case taskTypeId  = "task_type_id"
        case isActive    = "is_active"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }

    func toModel() -> Product {
        let prod = Product(
            id: id,
            companyId: companyId,
            name: name,
            type: type.flatMap { LineItemType(rawValue: $0) } ?? .labor,
            defaultPrice: unitPrice,
            isActive: isActive,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        prod.productDescription = description
        prod.taxable = taxable ?? true
        prod.unitCost = costPrice
        prod.unit = unit
        prod.taskTypeId = taskTypeId
        return prod
    }
}

struct CreateProductDTO: Codable {
    let companyId: String
    let name: String
    let description: String?
    let unitPrice: Double
    let costPrice: Double?
    let unit: String?
    let type: String?
    let taxable: Bool

    enum CodingKeys: String, CodingKey {
        case companyId   = "company_id"
        case name
        case description
        case unitPrice   = "unit_price"
        case costPrice   = "cost_price"
        case unit
        case type
        case taxable
    }
}

struct UpdateProductDTO: Codable {
    var name: String?
    var description: String?
    var unitPrice: Double?
    var costPrice: Double?
    var unit: String?
    var type: String?
    var taxable: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case unitPrice  = "unit_price"
        case costPrice  = "cost_price"
        case unit
        case type
        case taxable
    }
}
