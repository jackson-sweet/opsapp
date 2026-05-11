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
    let title: String?
    let status: String
    let subtotal: Double
    let taxRate: Double?
    let taxAmount: Double?
    let discountType: String?
    let discountValue: Double?
    let discountAmount: Double?
    let total: Double
    let notes: String?
    let expirationDate: String?
    let version: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
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
        case discountType    = "discount_type"
        case discountValue   = "discount_value"
        case discountAmount  = "discount_amount"
        case total
        case notes
        case expirationDate  = "expiration_date"
        case version
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case deletedAt       = "deleted_at"
        case lineItems       = "line_items"
    }

    func toModel() -> Estimate {
        let est = Estimate(
            id: id,
            companyId: companyId,
            status: EstimateStatus(rawValue: status) ?? .draft,
            taxRate: taxRate ?? 0,
            discountPercent: discountType == "percent" ? (discountValue ?? 0) : 0,
            version: version,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        est.estimateNumber = estimateNumber ?? ""
        est.title = title ?? ""
        est.subtotal = subtotal
        est.taxAmount = taxAmount ?? 0
        est.total = total
        est.opportunityId = opportunityId
        est.projectId = projectId
        est.clientId = clientId
        est.internalNotes = notes
        if let ed = expirationDate { est.validUntil = SupabaseDate.parse(ed) }
        if let da = deletedAt { est.deletedAt = SupabaseDate.parse(da) }
        return est
    }
}

struct EstimateLineItemDTO: Codable, Identifiable {
    let id: String
    let estimateId: String?
    let productId: String?
    let name: String?
    let description: String?
    let quantity: Double
    let unitPrice: Double
    let unit: String?
    let lineTotal: Double?
    let sortOrder: Int
    let isOptional: Bool?
    let taskTypeId: String?
    let type: String?
    let category: String?
    let parentLineItemId: String?
    let configuredOptions: RawJSONColumn?
    let resolvedUnitPrice: Double?
    let resolvedOptionsLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case estimateId  = "estimate_id"
        case productId   = "product_id"
        case name
        case description
        case quantity
        case unitPrice   = "unit_price"
        case unit
        case lineTotal   = "line_total"
        case sortOrder   = "sort_order"
        case isOptional  = "is_optional"
        case taskTypeId  = "task_type_id"
        case type
        case category
        case parentLineItemId    = "parent_line_item_id"
        case configuredOptions   = "configured_options"
        case resolvedUnitPrice   = "resolved_unit_price"
        case resolvedOptionsLabel = "resolved_options_label"
    }

    func toModel() -> EstimateLineItem {
        let displayName = name ?? description ?? ""
        let item = EstimateLineItem(
            id: id,
            estimateId: estimateId ?? "",
            name: displayName,
            type: type.flatMap { LineItemType(rawValue: $0) } ?? .labor,
            quantity: quantity,
            unitPrice: unitPrice,
            displayOrder: sortOrder
        )
        item.productId = productId
        item.unit = unit
        item.optional = isOptional ?? false
        item.lineTotal = lineTotal ?? (quantity * unitPrice)
        item.taskTypeId = taskTypeId
        item.parentLineItemId = parentLineItemId
        item.configuredOptionsJSON = configuredOptions?.rawJSONString
        item.resolvedUnitPrice = resolvedUnitPrice
        item.resolvedOptionsLabel = resolvedOptionsLabel
        return item
    }
}

struct CreateEstimateDTO: Codable {
    let companyId: String
    let opportunityId: String?
    let projectId: String?
    let clientId: String?
    let title: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case companyId     = "company_id"
        case opportunityId = "opportunity_id"
        case projectId     = "project_id"
        case clientId      = "client_id"
        case title
        case notes
    }

    init(companyId: String, opportunityId: String? = nil, projectId: String? = nil, clientId: String? = nil, title: String, notes: String? = nil) {
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.projectId = projectId
        self.clientId = clientId
        self.title = title
        self.notes = notes
    }
}

struct CreateLineItemDTO: Codable {
    let estimateId: String
    let productId: String?
    let name: String?
    let description: String
    let quantity: Double
    let unitPrice: Double
    let unit: String?
    let sortOrder: Int
    let isOptional: Bool?
    let taskTypeId: String?
    let type: String?
    let category: String?
    let parentLineItemId: String?
    let configuredOptions: RawJSONColumn?
    let resolvedUnitPrice: Double?
    let resolvedOptionsLabel: String?

    enum CodingKeys: String, CodingKey {
        case estimateId  = "estimate_id"
        case productId   = "product_id"
        case name
        case description
        case quantity
        case unitPrice   = "unit_price"
        case unit
        case sortOrder   = "sort_order"
        case isOptional  = "is_optional"
        case taskTypeId  = "task_type_id"
        case type
        case category
        case parentLineItemId    = "parent_line_item_id"
        case configuredOptions   = "configured_options"
        case resolvedUnitPrice   = "resolved_unit_price"
        case resolvedOptionsLabel = "resolved_options_label"
    }

    init(
        estimateId: String,
        productId: String?,
        name: String?,
        description: String,
        quantity: Double,
        unitPrice: Double,
        unit: String?,
        sortOrder: Int,
        isOptional: Bool?,
        taskTypeId: String?,
        type: String?,
        category: String?,
        parentLineItemId: String?,
        configuredOptions: RawJSONColumn? = nil,
        resolvedUnitPrice: Double? = nil,
        resolvedOptionsLabel: String? = nil
    ) {
        self.estimateId = estimateId
        self.productId = productId
        self.name = name
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.unit = unit
        self.sortOrder = sortOrder
        self.isOptional = isOptional
        self.taskTypeId = taskTypeId
        self.type = type
        self.category = category
        self.parentLineItemId = parentLineItemId
        self.configuredOptions = configuredOptions
        self.resolvedUnitPrice = resolvedUnitPrice
        self.resolvedOptionsLabel = resolvedOptionsLabel
    }
}

struct UpdateLineItemDTO: Codable {
    var description: String?
    var quantity: Double?
    var unitPrice: Double?
    var sortOrder: Int?
    var isOptional: Bool?
    var parentLineItemId: String?
    var configuredOptions: RawJSONColumn?
    var resolvedUnitPrice: Double?
    var resolvedOptionsLabel: String?

    enum CodingKeys: String, CodingKey {
        case description
        case quantity
        case unitPrice  = "unit_price"
        case sortOrder  = "sort_order"
        case isOptional = "is_optional"
        case parentLineItemId    = "parent_line_item_id"
        case configuredOptions   = "configured_options"
        case resolvedUnitPrice   = "resolved_unit_price"
        case resolvedOptionsLabel = "resolved_options_label"
    }
}
