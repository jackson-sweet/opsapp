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

struct AcceptEstimateToJobResponseDTO: Codable, Equatable {
    let ok: Bool
    let estimateId: String
    let projectId: String?
    let actorUserId: String?
    let companyId: String
    let idempotencyKey: String
    let idempotentReplay: Bool
    let projectTaskResult: AcceptEstimateProjectTaskResultDTO?
    let bookingProjectionResult: AcceptEstimateBookingProjectionResultDTO?
    let mappingNotificationResult: AcceptEstimateMappingNotificationResultDTO?
    let inventoryMode: String?
    let warnings: [AcceptEstimateWarningDTO]
    let overruns: [AcceptEstimateOverrunDTO]
    let missingMappings: [AcceptEstimateMissingMappingDTO]
    let demandIds: [String]
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case estimateId = "estimate_id"
        case projectId = "project_id"
        case actorUserId = "actor_user_id"
        case companyId = "company_id"
        case idempotencyKey = "idempotency_key"
        case idempotentReplay = "idempotent_replay"
        case projectTaskResult = "project_task_result"
        case bookingProjectionResult = "booking_projection_result"
        case mappingNotificationResult = "mapping_notification_result"
        case inventoryMode = "inventory_mode"
        case warnings
        case overruns
        case missingMappings = "missing_mappings"
        case demandIds = "demand_ids"
        case acceptedAt = "accepted_at"
    }

    init(
        ok: Bool,
        estimateId: String,
        projectId: String?,
        actorUserId: String?,
        companyId: String,
        idempotencyKey: String,
        idempotentReplay: Bool,
        projectTaskResult: AcceptEstimateProjectTaskResultDTO?,
        bookingProjectionResult: AcceptEstimateBookingProjectionResultDTO?,
        mappingNotificationResult: AcceptEstimateMappingNotificationResultDTO?,
        inventoryMode: String?,
        warnings: [AcceptEstimateWarningDTO] = [],
        overruns: [AcceptEstimateOverrunDTO] = [],
        missingMappings: [AcceptEstimateMissingMappingDTO] = [],
        demandIds: [String] = [],
        acceptedAt: String?
    ) {
        self.ok = ok
        self.estimateId = estimateId
        self.projectId = projectId
        self.actorUserId = actorUserId
        self.companyId = companyId
        self.idempotencyKey = idempotencyKey
        self.idempotentReplay = idempotentReplay
        self.projectTaskResult = projectTaskResult
        self.bookingProjectionResult = bookingProjectionResult
        self.mappingNotificationResult = mappingNotificationResult
        self.inventoryMode = inventoryMode
        self.warnings = warnings
        self.overruns = overruns
        self.missingMappings = missingMappings
        self.demandIds = demandIds
        self.acceptedAt = acceptedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        estimateId = try container.decode(String.self, forKey: .estimateId)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        actorUserId = try container.decodeIfPresent(String.self, forKey: .actorUserId)
        companyId = try container.decode(String.self, forKey: .companyId)
        idempotencyKey = try container.decode(String.self, forKey: .idempotencyKey)
        idempotentReplay = try container.decodeIfPresent(Bool.self, forKey: .idempotentReplay) ?? false
        projectTaskResult = try container.decodeIfPresent(AcceptEstimateProjectTaskResultDTO.self, forKey: .projectTaskResult)
        bookingProjectionResult = try container.decodeIfPresent(AcceptEstimateBookingProjectionResultDTO.self, forKey: .bookingProjectionResult)
        mappingNotificationResult = try container.decodeIfPresent(AcceptEstimateMappingNotificationResultDTO.self, forKey: .mappingNotificationResult)
        inventoryMode = try container.decodeIfPresent(String.self, forKey: .inventoryMode)
        warnings = try container.decodeIfPresent([AcceptEstimateWarningDTO].self, forKey: .warnings) ?? []
        overruns = try container.decodeIfPresent([AcceptEstimateOverrunDTO].self, forKey: .overruns) ?? []
        missingMappings = try container.decodeIfPresent([AcceptEstimateMissingMappingDTO].self, forKey: .missingMappings) ?? []
        demandIds = try container.decodeIfPresent([String].self, forKey: .demandIds) ?? []
        acceptedAt = try container.decodeIfPresent(String.self, forKey: .acceptedAt)
    }
}

struct AcceptEstimateProjectTaskResultDTO: Codable, Equatable {
    let projectId: String?
    let taskIds: [String]

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case taskIds = "task_ids"
    }

    init(projectId: String?, taskIds: [String] = []) {
        self.projectId = projectId
        self.taskIds = taskIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        taskIds = try container.decodeIfPresent([String].self, forKey: .taskIds) ?? []
    }
}

struct AcceptEstimateBookingProjectionResultDTO: Codable, Equatable {
    let inventoryMode: String?
    let demandIds: [String]
    let warnings: [AcceptEstimateWarningDTO]
    let overruns: [AcceptEstimateOverrunDTO]
    let missingMappings: [AcceptEstimateMissingMappingDTO]

    enum CodingKeys: String, CodingKey {
        case inventoryMode = "inventory_mode"
        case demandIds = "demand_ids"
        case warnings
        case overruns
        case missingMappings = "missing_mappings"
    }

    init(
        inventoryMode: String?,
        demandIds: [String] = [],
        warnings: [AcceptEstimateWarningDTO] = [],
        overruns: [AcceptEstimateOverrunDTO] = [],
        missingMappings: [AcceptEstimateMissingMappingDTO] = []
    ) {
        self.inventoryMode = inventoryMode
        self.demandIds = demandIds
        self.warnings = warnings
        self.overruns = overruns
        self.missingMappings = missingMappings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inventoryMode = try container.decodeIfPresent(String.self, forKey: .inventoryMode)
        demandIds = try container.decodeIfPresent([String].self, forKey: .demandIds) ?? []
        warnings = try container.decodeIfPresent([AcceptEstimateWarningDTO].self, forKey: .warnings) ?? []
        overruns = try container.decodeIfPresent([AcceptEstimateOverrunDTO].self, forKey: .overruns) ?? []
        missingMappings = try container.decodeIfPresent([AcceptEstimateMissingMappingDTO].self, forKey: .missingMappings) ?? []
    }
}

struct AcceptEstimateMappingNotificationResultDTO: Codable, Equatable {
    let notificationPersistencePerformed: Bool
    let dedupeKeys: [String]
    let recipientCount: Int
    let insertedNotificationCount: Int
    let updatedNotificationCount: Int

    enum CodingKeys: String, CodingKey {
        case notificationPersistencePerformed = "notification_persistence_performed"
        case dedupeKeys = "dedupe_keys"
        case recipientCount = "recipient_count"
        case insertedNotificationCount = "inserted_notification_count"
        case updatedNotificationCount = "updated_notification_count"
    }

    init(
        notificationPersistencePerformed: Bool = false,
        dedupeKeys: [String] = [],
        recipientCount: Int = 0,
        insertedNotificationCount: Int = 0,
        updatedNotificationCount: Int = 0
    ) {
        self.notificationPersistencePerformed = notificationPersistencePerformed
        self.dedupeKeys = dedupeKeys
        self.recipientCount = recipientCount
        self.insertedNotificationCount = insertedNotificationCount
        self.updatedNotificationCount = updatedNotificationCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notificationPersistencePerformed = try container.decodeIfPresent(Bool.self, forKey: .notificationPersistencePerformed) ?? false
        dedupeKeys = try container.decodeIfPresent([String].self, forKey: .dedupeKeys) ?? []
        recipientCount = try container.decodeIfPresent(Int.self, forKey: .recipientCount) ?? 0
        insertedNotificationCount = try container.decodeIfPresent(Int.self, forKey: .insertedNotificationCount) ?? 0
        updatedNotificationCount = try container.decodeIfPresent(Int.self, forKey: .updatedNotificationCount) ?? 0
    }
}

struct AcceptEstimateWarningDTO: Codable, Equatable {
    let code: String?
    let message: String?
    let lineItemId: String?
    let productId: String?
    let productName: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case lineItemId = "line_item_id"
        case productId = "product_id"
        case productName = "product_name"
    }

    init(
        code: String?,
        message: String?,
        lineItemId: String? = nil,
        productId: String? = nil,
        productName: String? = nil
    ) {
        self.code = code
        self.message = message
        self.lineItemId = lineItemId
        self.productId = productId
        self.productName = productName
    }
}

struct AcceptEstimateOverrunDTO: Codable, Equatable {
    let demandKey: String?
    let lineItemId: String?
    let productId: String?
    let catalogVariantId: String?
    let requiredQuantity: Double?
    let availableQuantityAtBooking: Double?
    let projectedOverrunQuantity: Double?
    let availabilityBasis: String?

    enum CodingKeys: String, CodingKey {
        case demandKey = "demand_key"
        case lineItemId = "line_item_id"
        case productId = "product_id"
        case catalogVariantId = "catalog_variant_id"
        case requiredQuantity = "required_quantity"
        case availableQuantityAtBooking = "available_quantity_at_booking"
        case projectedOverrunQuantity = "projected_overrun_quantity"
        case availabilityBasis = "availability_basis"
    }

    init(
        demandKey: String? = nil,
        lineItemId: String? = nil,
        productId: String? = nil,
        catalogVariantId: String? = nil,
        requiredQuantity: Double? = nil,
        availableQuantityAtBooking: Double? = nil,
        projectedOverrunQuantity: Double? = nil,
        availabilityBasis: String? = nil
    ) {
        self.demandKey = demandKey
        self.lineItemId = lineItemId
        self.productId = productId
        self.catalogVariantId = catalogVariantId
        self.requiredQuantity = requiredQuantity
        self.availableQuantityAtBooking = availableQuantityAtBooking
        self.projectedOverrunQuantity = projectedOverrunQuantity
        self.availabilityBasis = availabilityBasis
    }
}

struct AcceptEstimateMissingMappingDTO: Codable, Equatable {
    let dedupeKey: String?
    let productId: String?
    let lineItemId: String?
    let productName: String?
    let lineName: String?

    enum CodingKeys: String, CodingKey {
        case dedupeKey = "dedupe_key"
        case productId = "product_id"
        case lineItemId = "line_item_id"
        case productName = "product_name"
        case lineName = "line_name"
    }

    init(
        dedupeKey: String?,
        productId: String? = nil,
        lineItemId: String? = nil,
        productName: String? = nil,
        lineName: String? = nil
    ) {
        self.dedupeKey = dedupeKey
        self.productId = productId
        self.lineItemId = lineItemId
        self.productName = productName
        self.lineName = lineName
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
