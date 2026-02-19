//
//  EstimateDTOs.swift
//  OPS
//
//  Data Transfer Objects for Estimate Supabase tables.
//

import Foundation

struct EstimateDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let estimateNumber: String?
    let opportunityId: String?
    let projectId: String?
    let clientId: String?
    let title: String
    let status: String
    let subtotal: Double
    let taxRate: Double?
    let taxAmount: Double?
    let discountPercent: Double?
    let discountAmount: Double?
    let total: Double
    let notes: String?
    let validUntil: String?
    let version: Int
    let createdAt: String
    let updatedAt: String
    let lineItems: [EstimateLineItemDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case estimateNumber  = "estimate_number"
        case opportunityId   = "opportunity_id"
        case projectId       = "project_id"
        case clientId        = "client_id"
        case title
        case status
        case subtotal
        case taxRate         = "tax_rate"
        case taxAmount       = "tax_amount"
        case discountPercent = "discount_percent"
        case discountAmount  = "discount_amount"
        case total
        case notes
        case validUntil      = "valid_until"
        case version
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case lineItems       = "estimate_line_items"
    }

    func toModel() -> Estimate {
        let est = Estimate(
            id: id,
            companyId: companyId,
            status: EstimateStatus(rawValue: status) ?? .draft,
            taxRate: taxRate ?? 0,
            discountPercent: discountPercent ?? 0,
            version: version,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        est.estimateNumber = estimateNumber ?? ""
        est.title = title
        est.subtotal = subtotal
        est.taxAmount = taxAmount ?? 0
        est.total = total
        est.opportunityId = opportunityId
        est.projectId = projectId
        est.clientId = clientId
        est.internalNotes = notes
        if let vu = validUntil { est.validUntil = SupabaseDate.parse(vu) }
        return est
    }
}

struct EstimateLineItemDTO: Codable, Identifiable {
    let id: String
    let estimateId: String
    let productId: String?
    let description: String
    let quantity: Double
    let unitPrice: Double
    let unit: String?
    let total: Double
    let sortOrder: Int
    let isOptional: Bool?
    let taskTypeId: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId  = "estimate_id"
        case productId   = "product_id"
        case description
        case quantity
        case unitPrice   = "unit_price"
        case unit
        case total
        case sortOrder   = "sort_order"
        case isOptional  = "is_optional"
        case taskTypeId  = "task_type_id"
        case type
    }

    func toModel() -> EstimateLineItem {
        let item = EstimateLineItem(
            id: id,
            estimateId: estimateId,
            name: description,
            type: type.flatMap { LineItemType(rawValue: $0) } ?? .labor,
            quantity: quantity,
            unitPrice: unitPrice,
            displayOrder: sortOrder
        )
        item.productId = productId
        item.unit = unit
        item.optional = isOptional ?? false
        item.lineTotal = total
        item.taskTypeId = taskTypeId
        return item
    }
}

struct CreateEstimateDTO: Codable {
    let companyId: String
    let opportunityId: String?
    let clientId: String?
    let title: String

    enum CodingKeys: String, CodingKey {
        case companyId     = "company_id"
        case opportunityId = "opportunity_id"
        case clientId      = "client_id"
        case title
    }
}

struct CreateLineItemDTO: Codable {
    let estimateId: String
    let productId: String?
    let description: String
    let quantity: Double
    let unitPrice: Double
    let sortOrder: Int
    let isOptional: Bool?
    let taskTypeId: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case estimateId  = "estimate_id"
        case productId   = "product_id"
        case description
        case quantity
        case unitPrice   = "unit_price"
        case sortOrder   = "sort_order"
        case isOptional  = "is_optional"
        case taskTypeId  = "task_type_id"
        case type
    }
}

struct UpdateLineItemDTO: Codable {
    var description: String?
    var quantity: Double?
    var unitPrice: Double?
    var sortOrder: Int?
    var isOptional: Bool?

    enum CodingKeys: String, CodingKey {
        case description
        case quantity
        case unitPrice  = "unit_price"
        case sortOrder  = "sort_order"
        case isOptional = "is_optional"
    }
}
