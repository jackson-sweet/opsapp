//
//  CatalogSetupWorkflow.swift
//  OPS
//
//  Draft-side helpers for the field setup flow. These types stay UI-agnostic
//  so matrix generation, duplicate checks, and stock-unit quantity mirroring
//  can be tested without launching SwiftUI.
//

import Foundation

struct CatalogSetupSaveIssue: Codable, Equatable {
    var code: String
    var path: String
    var message: String

    init(code: String, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}

struct CatalogSetupSaveResponse: Codable, Equatable {
    var ok: Bool
    var mode: String?
    var companyId: String?
    var idempotencyKey: String?
    var requestHash: String?
    var warnings: [CatalogSetupSaveIssue]
    var blockers: [CatalogSetupSaveIssue]
    var idMap: [String: String]
    var counts: [String: Int]
    var deletedCounts: [String: Int]
    var validatedCounts: [String: Int]
    var savedAt: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case mode
        case companyId = "company_id"
        case idempotencyKey = "idempotency_key"
        case requestHash = "request_hash"
        case warnings
        case blockers
        case idMap = "id_map"
        case counts
        case deletedCounts = "deleted_counts"
        case validatedCounts = "validated_counts"
        case savedAt = "saved_at"
    }

    init(
        ok: Bool,
        mode: String? = nil,
        companyId: String? = nil,
        idempotencyKey: String? = nil,
        requestHash: String? = nil,
        warnings: [CatalogSetupSaveIssue] = [],
        blockers: [CatalogSetupSaveIssue] = [],
        idMap: [String: String] = [:],
        counts: [String: Int] = [:],
        deletedCounts: [String: Int] = [:],
        validatedCounts: [String: Int] = [:],
        savedAt: String? = nil
    ) {
        self.ok = ok
        self.mode = mode
        self.companyId = companyId
        self.idempotencyKey = idempotencyKey
        self.requestHash = requestHash
        self.warnings = warnings
        self.blockers = blockers
        self.idMap = idMap
        self.counts = counts
        self.deletedCounts = deletedCounts
        self.validatedCounts = validatedCounts
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        companyId = try container.decodeIfPresent(String.self, forKey: .companyId)
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
        requestHash = try container.decodeIfPresent(String.self, forKey: .requestHash)
        warnings = try container.decodeIfPresent([CatalogSetupSaveIssue].self, forKey: .warnings) ?? []
        blockers = try container.decodeIfPresent([CatalogSetupSaveIssue].self, forKey: .blockers) ?? []
        idMap = try container.decodeIfPresent([String: String].self, forKey: .idMap) ?? [:]
        counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        deletedCounts = try container.decodeIfPresent([String: Int].self, forKey: .deletedCounts) ?? [:]
        validatedCounts = try container.decodeIfPresent([String: Int].self, forKey: .validatedCounts) ?? [:]
        savedAt = try container.decodeIfPresent(String.self, forKey: .savedAt)
    }
}

struct CatalogSetupDeletedIds: Codable, Equatable {
    var catalogItems: [String]
    var catalogOptions: [String]
    var catalogOptionValues: [String]
    var catalogVariants: [String]
    var catalogVariantOptionValues: [String]
    var catalogStockUnits: [String]
    var products: [String]
    var productOptions: [String]
    var productOptionValues: [String]
    var productPricingModifiers: [String]
    var productMaterials: [String]
    var productBundleItems: [String]
    var catalogProductOptionMappings: [String]

    enum CodingKeys: String, CodingKey {
        case catalogItems = "catalog_items"
        case catalogOptions = "catalog_options"
        case catalogOptionValues = "catalog_option_values"
        case catalogVariants = "catalog_variants"
        case catalogVariantOptionValues = "catalog_variant_option_values"
        case catalogStockUnits = "catalog_stock_units"
        case products
        case productOptions = "product_options"
        case productOptionValues = "product_option_values"
        case productPricingModifiers = "product_pricing_modifiers"
        case productMaterials = "product_materials"
        case productBundleItems = "product_bundle_items"
        case catalogProductOptionMappings = "catalog_product_option_mappings"
    }

    init(
        catalogItems: [String] = [],
        catalogOptions: [String] = [],
        catalogOptionValues: [String] = [],
        catalogVariants: [String] = [],
        catalogVariantOptionValues: [String] = [],
        catalogStockUnits: [String] = [],
        products: [String] = [],
        productOptions: [String] = [],
        productOptionValues: [String] = [],
        productPricingModifiers: [String] = [],
        productMaterials: [String] = [],
        productBundleItems: [String] = [],
        catalogProductOptionMappings: [String] = []
    ) {
        self.catalogItems = catalogItems
        self.catalogOptions = catalogOptions
        self.catalogOptionValues = catalogOptionValues
        self.catalogVariants = catalogVariants
        self.catalogVariantOptionValues = catalogVariantOptionValues
        self.catalogStockUnits = catalogStockUnits
        self.products = products
        self.productOptions = productOptions
        self.productOptionValues = productOptionValues
        self.productPricingModifiers = productPricingModifiers
        self.productMaterials = productMaterials
        self.productBundleItems = productBundleItems
        self.catalogProductOptionMappings = catalogProductOptionMappings
    }

    var isEmpty: Bool {
        catalogItems.isEmpty &&
        catalogOptions.isEmpty &&
        catalogOptionValues.isEmpty &&
        catalogVariants.isEmpty &&
        catalogVariantOptionValues.isEmpty &&
        catalogStockUnits.isEmpty &&
        products.isEmpty &&
        productOptions.isEmpty &&
        productOptionValues.isEmpty &&
        productPricingModifiers.isEmpty &&
        productMaterials.isEmpty &&
        productBundleItems.isEmpty &&
        catalogProductOptionMappings.isEmpty
    }

    mutating func appendUnique(_ id: String?, to keyPath: WritableKeyPath<CatalogSetupDeletedIds, [String]>) {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return }
        if !self[keyPath: keyPath].contains(id) {
            self[keyPath: keyPath].append(id)
        }
    }

    mutating func merge(_ other: CatalogSetupDeletedIds) {
        for id in other.catalogItems { appendUnique(id, to: \.catalogItems) }
        for id in other.catalogOptions { appendUnique(id, to: \.catalogOptions) }
        for id in other.catalogOptionValues { appendUnique(id, to: \.catalogOptionValues) }
        for id in other.catalogVariants { appendUnique(id, to: \.catalogVariants) }
        for id in other.catalogVariantOptionValues { appendUnique(id, to: \.catalogVariantOptionValues) }
        for id in other.catalogStockUnits { appendUnique(id, to: \.catalogStockUnits) }
        for id in other.products { appendUnique(id, to: \.products) }
        for id in other.productOptions { appendUnique(id, to: \.productOptions) }
        for id in other.productOptionValues { appendUnique(id, to: \.productOptionValues) }
        for id in other.productPricingModifiers { appendUnique(id, to: \.productPricingModifiers) }
        for id in other.productMaterials { appendUnique(id, to: \.productMaterials) }
        for id in other.productBundleItems { appendUnique(id, to: \.productBundleItems) }
        for id in other.catalogProductOptionMappings { appendUnique(id, to: \.catalogProductOptionMappings) }
    }

    func merged(with other: CatalogSetupDeletedIds) -> CatalogSetupDeletedIds {
        var next = self
        next.merge(other)
        return next
    }
}

enum CatalogStockUnitLifecycleEventType: String, Codable, CaseIterable, Hashable {
    case receive
    case consume
    case scrap
    case offcutCreate = "offcut_create"
    case adjust
    case reserve
    case release
    case restore
    case delete
}

struct CatalogSetupStockUnitEventDraft: Identifiable, Hashable, Codable {
    var id: String
    var eventType: CatalogStockUnitLifecycleEventType
    var relatedStockUnitClientId: String?
    var relatedStockUnitServerId: String?
    var fromStatus: CatalogStockUnitStatus?
    var toStatus: CatalogStockUnitStatus?
    var quantityDelta: Double?
    var remainingLengthDelta: Double?
    var marker: String?
    var notes: String
    var metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        eventType: CatalogStockUnitLifecycleEventType,
        relatedStockUnitClientId: String? = nil,
        relatedStockUnitServerId: String? = nil,
        fromStatus: CatalogStockUnitStatus? = nil,
        toStatus: CatalogStockUnitStatus? = nil,
        quantityDelta: Double? = nil,
        remainingLengthDelta: Double? = nil,
        marker: String? = "ios_catalog_setup_lifecycle",
        notes: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.eventType = eventType
        self.relatedStockUnitClientId = relatedStockUnitClientId
        self.relatedStockUnitServerId = relatedStockUnitServerId
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.quantityDelta = quantityDelta
        self.remainingLengthDelta = remainingLengthDelta
        self.marker = marker
        self.notes = notes
        self.metadata = metadata
    }
}

struct CatalogSetupSavePayload: Codable, Equatable {
    var mode: String
    var draftId: String
    var clientSchemaVersion: Int
    var family: Family
    var catalogOptions: [CatalogOption]
    var variants: [Variant]
    var stockUnits: [StockUnit]
    var stockUnitEvents: [StockUnitEvent] = []
    var products: [ProductPayload]
    var productMaterials: [ProductMaterial]
    var deletedIds: CatalogSetupDeletedIds
    var clientMetadata: ClientMetadata

    enum CodingKeys: String, CodingKey {
        case mode
        case draftId = "draft_id"
        case clientSchemaVersion = "client_schema_version"
        case family
        case catalogOptions = "catalog_options"
        case variants
        case stockUnits = "stock_units"
        case stockUnitEvents = "stock_unit_events"
        case products
        case productMaterials = "product_materials"
        case deletedIds = "deleted_ids"
        case clientMetadata = "client_metadata"
    }

    struct ClientMetadata: Codable, Equatable {
        var source: String
        var appVersion: String?

        enum CodingKeys: String, CodingKey {
            case source
            case appVersion = "app_version"
        }

        init(source: String = "ios", appVersion: String? = nil) {
            self.source = source
            self.appVersion = appVersion
        }
    }

    struct Family: Codable, Equatable {
        var id: String?
        var clientId: String
        var name: String
        var categoryId: String?
        var unitId: String?
        var description: String?
        var imageUrl: String?
        var defaultWarningThreshold: Double?
        var defaultCriticalThreshold: Double?
        var metadata: [String: String]

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case name
            case categoryId = "category_id"
            case unitId = "unit_id"
            case description
            case imageUrl = "image_url"
            case defaultWarningThreshold = "default_warning_threshold"
            case defaultCriticalThreshold = "default_critical_threshold"
            case metadata
        }
    }

    struct CatalogOption: Codable, Equatable {
        var id: String?
        var clientId: String
        var name: String
        var sortOrder: Int
        var affectsStockIdentity: Bool
        var affectsPrice: Bool
        var affectsRecipe: Bool
        var shownOnEstimate: Bool
        var values: [CatalogOptionValue]

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case name
            case sortOrder = "sort_order"
            case affectsStockIdentity = "affects_stock_identity"
            case affectsPrice = "affects_price"
            case affectsRecipe = "affects_recipe"
            case shownOnEstimate = "shown_on_estimate"
            case values
        }
    }

    struct CatalogOptionValue: Codable, Equatable {
        var id: String?
        var clientId: String
        var label: String
        var sortOrder: Int
        var metadata: [String: String]

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case label
            case sortOrder = "sort_order"
            case metadata
        }
    }

    struct Variant: Codable, Equatable {
        var id: String?
        var clientId: String
        var name: String
        var sku: String?
        var price: Double?
        var quantity: Double
        var optionValueClientIds: [String]
        var excluded: Bool
        var warningThreshold: Double?
        var criticalThreshold: Double?
        var unitId: String?

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case name
            case sku
            case price
            case quantity
            case optionValueClientIds = "option_value_client_ids"
            case excluded
            case warningThreshold = "warning_threshold"
            case criticalThreshold = "critical_threshold"
            case unitId = "unit_id"
        }
    }

    struct StockUnit: Codable, Equatable {
        var id: String?
        var clientId: String
        var variantClientId: String?
        var catalogVariantId: String?
        var relatedCatalogStockUnitClientId: String? = nil
        var relatedCatalogStockUnitId: String? = nil
        var unitKind: String
        var label: String?
        var lotCode: String?
        var widthValue: Double?
        var widthUnit: String?
        var originalLengthValue: Double?
        var remainingLengthValue: Double?
        var lengthUnit: String?
        var quantityValue: Double
        var location: String?
        var status: String
        var notes: String?

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case variantClientId = "variant_client_id"
            case catalogVariantId = "catalog_variant_id"
            case relatedCatalogStockUnitClientId = "related_catalog_stock_unit_client_id"
            case relatedCatalogStockUnitId = "related_catalog_stock_unit_id"
            case unitKind = "unit_kind"
            case label
            case lotCode = "lot_code"
            case widthValue = "width_value"
            case widthUnit = "width_unit"
            case originalLengthValue = "original_length_value"
            case remainingLengthValue = "remaining_length_value"
            case lengthUnit = "length_unit"
            case quantityValue = "quantity_value"
            case location
            case status
            case notes
        }
    }

    struct StockUnitEvent: Codable, Equatable {
        var eventId: String
        var stockUnitClientId: String
        var catalogStockUnitId: String?
        var variantClientId: String?
        var catalogVariantId: String?
        var relatedCatalogStockUnitClientId: String?
        var relatedCatalogStockUnitId: String?
        var eventType: String
        var fromStatus: String?
        var toStatus: String?
        var quantityDelta: Double?
        var remainingLengthDelta: Double?
        var payload: [String: String]
        var marker: String?
        var notes: String?

        enum CodingKeys: String, CodingKey {
            case eventId = "event_id"
            case stockUnitClientId = "stock_unit_client_id"
            case catalogStockUnitId = "catalog_stock_unit_id"
            case variantClientId = "variant_client_id"
            case catalogVariantId = "catalog_variant_id"
            case relatedCatalogStockUnitClientId = "related_catalog_stock_unit_client_id"
            case relatedCatalogStockUnitId = "related_catalog_stock_unit_id"
            case eventType = "event_type"
            case fromStatus = "from_status"
            case toStatus = "to_status"
            case quantityDelta = "quantity_delta"
            case remainingLengthDelta = "remaining_length_delta"
            case payload
            case marker
            case notes
        }
    }

    struct ProductPayload: Codable, Equatable {
        var id: String?
        var clientId: String
        var kind: String
        var type: String
        var name: String
        var description: String? = nil
        var basePrice: Double = 0
        var unit: String? = nil
        var category: String? = nil
        var isTaxable: Bool = true
        var isActive: Bool = true
        var unitId: String? = nil
        var sku: String? = nil
        var isFavorite: Bool = false
        var minimumCharge: Double? = nil
        var minimumQuantity: Double? = nil
        var showBomOnEstimate: Bool = false
        var showInStorefront: Bool = false
        var tieredPricing: RawJSONColumn? = nil
        var categoryId: String? = nil
        var thumbnailUrl: String? = nil
        var pricingUnit: String
        var linkedCatalogItemClientId: String?
        var linkedCatalogItemId: String?
        var bundlePricingMode: String? = nil
        var options: [ProductOptionPayload]
        var pricingModifiers: [ProductPricingModifier]
        var productMaterials: [ProductMaterial]
        var catalogOptionMappings: [CatalogProductOptionMapping]
        var bundleItems: [ProductBundleItemPayload]

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case kind
            case type
            case name
            case description
            case basePrice = "base_price"
            case unit
            case category
            case isTaxable = "is_taxable"
            case isActive = "is_active"
            case unitId = "unit_id"
            case sku
            case isFavorite = "is_favorite"
            case minimumCharge = "minimum_charge"
            case minimumQuantity = "minimum_quantity"
            case showBomOnEstimate = "show_bom_on_estimate"
            case showInStorefront = "show_in_storefront"
            case tieredPricing = "tiered_pricing"
            case categoryId = "category_id"
            case thumbnailUrl = "thumbnail_url"
            case pricingUnit = "pricing_unit"
            case linkedCatalogItemClientId = "linked_catalog_item_client_id"
            case linkedCatalogItemId = "linked_catalog_item_id"
            case bundlePricingMode = "bundle_pricing_mode"
            case options
            case pricingModifiers = "pricing_modifiers"
            case productMaterials = "product_materials"
            case catalogOptionMappings = "catalog_option_mappings"
            case bundleItems = "bundle_items"
        }
    }

    struct ProductOptionPayload: Codable, Equatable {
        var id: String?
        var clientId: String
        var name: String
        var kind: String
        var required: Bool
        var affectsPrice: Bool
        var affectsRecipe: Bool
        var defaultValue: String? = nil
        var optionDefaultSource: String? = nil
        var sortOrder: Int
        var values: [ProductOptionValuePayload]

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case name
            case kind
            case required
            case affectsPrice = "affects_price"
            case affectsRecipe = "affects_recipe"
            case defaultValue = "default_value"
            case optionDefaultSource = "option_default_source"
            case sortOrder = "sort_order"
            case values
        }
    }

    struct ProductOptionValuePayload: Codable, Equatable {
        var id: String?
        var clientId: String
        var label: String
        var sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case label
            case sortOrder = "sort_order"
        }
    }

    struct ProductPricingModifier: Codable, Equatable {
        var id: String?
        var clientId: String
        var optionClientId: String?
        var optionId: String?
        var optionValueClientId: String?
        var triggerValueId: String?
        var triggerIntMin: Int? = nil
        var triggerIntMax: Int? = nil
        var modifierKind: String
        var amount: Double

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case optionClientId = "option_client_id"
            case optionId = "option_id"
            case optionValueClientId = "option_value_client_id"
            case triggerValueId = "trigger_value_id"
            case triggerIntMin = "trigger_int_min"
            case triggerIntMax = "trigger_int_max"
            case modifierKind = "modifier_kind"
            case amount
        }
    }

    struct ProductMaterial: Codable, Equatable {
        var id: String?
        var clientId: String
        var productClientId: String?
        var productId: String?
        var catalogVariantClientId: String?
        var catalogVariantId: String?
        var catalogItemClientId: String?
        var catalogItemId: String?
        var variantSelector: RawJSONColumn? = nil
        var quantityPerUnit: Double
        var scaledByOptionId: String?
        var unitId: String?
        var notes: String?

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case productClientId = "product_client_id"
            case productId = "product_id"
            case catalogVariantClientId = "catalog_variant_client_id"
            case catalogVariantId = "catalog_variant_id"
            case catalogItemClientId = "catalog_item_client_id"
            case catalogItemId = "catalog_item_id"
            case variantSelector = "variant_selector"
            case quantityPerUnit = "quantity_per_unit"
            case scaledByOptionId = "scaled_by_option_id"
            case unitId = "unit_id"
            case notes
        }
    }

    struct CatalogProductOptionMapping: Codable, Equatable {
        var id: String?
        var clientId: String
        var mappingKind: String
        var catalogOptionClientId: String?
        var catalogOptionId: String?
        var catalogOptionValueClientId: String?
        var catalogOptionValueId: String?
        var productOptionClientId: String?
        var productOptionId: String?
        var productOptionValueClientId: String?
        var productOptionValueId: String?

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case mappingKind = "mapping_kind"
            case catalogOptionClientId = "catalog_option_client_id"
            case catalogOptionId = "catalog_option_id"
            case catalogOptionValueClientId = "catalog_option_value_client_id"
            case catalogOptionValueId = "catalog_option_value_id"
            case productOptionClientId = "product_option_client_id"
            case productOptionId = "product_option_id"
            case productOptionValueClientId = "product_option_value_client_id"
            case productOptionValueId = "product_option_value_id"
        }
    }

    struct ProductBundleItemPayload: Codable, Equatable {
        var id: String?
        var clientId: String
        var childProductId: String
        var quantity: Double
        var relationshipKind: String?
        var hasPricing: Bool
        var suggestionReason: String?
        var compatibilitySelector: RawJSONColumn?
        var displayOrder: Int

        enum CodingKeys: String, CodingKey {
            case id
            case clientId = "client_id"
            case childProductId = "child_product_id"
            case quantity
            case relationshipKind = "relationship_kind"
            case hasPricing = "has_pricing"
            case suggestionReason = "suggestion_reason"
            case compatibilitySelector = "compatibility_selector"
            case displayOrder = "display_order"
        }
    }

    static func minimalTestPayload(draftId: String, familyName: String) -> CatalogSetupSavePayload {
        CatalogSetupSavePayload(
            mode: "create",
            draftId: draftId,
            clientSchemaVersion: 1,
            family: Family(
                id: nil,
                clientId: "family:\(draftId)",
                name: familyName,
                categoryId: nil,
                unitId: nil,
                description: nil,
                imageUrl: nil,
                defaultWarningThreshold: nil,
                defaultCriticalThreshold: nil,
                metadata: [:]
            ),
            catalogOptions: [],
            variants: [],
            stockUnits: [],
            stockUnitEvents: [],
            products: [],
            productMaterials: [],
            deletedIds: CatalogSetupDeletedIds(),
            clientMetadata: ClientMetadata()
        )
    }
}

struct CatalogSetupSaveAttempt: Codable, Equatable {
    var idempotencyKey: String
    var payloadFingerprint: String

    static func resolve(
        payload: CatalogSetupSavePayload,
        existingAttempt: CatalogSetupSaveAttempt?,
        makeKey: () -> String = { "ios-catalog-setup-\(UUID().uuidString)" }
    ) throws -> CatalogSetupSaveAttempt {
        let fingerprint = try payload.catalogSetupFingerprint()
        if let existingAttempt, existingAttempt.payloadFingerprint == fingerprint {
            return existingAttempt
        }
        return CatalogSetupSaveAttempt(
            idempotencyKey: makeKey(),
            payloadFingerprint: fingerprint
        )
    }
}

struct CatalogSetupDraftContext: Codable, Equatable, Hashable {
    var companyId: String
    var userId: String
    var scope: String?

    init(companyId: String, userId: String, scope: String? = nil) {
        self.companyId = companyId
        self.userId = userId
        self.scope = scope
    }

    static func make(companyId: String?, userId: String?, editFamilyId: String? = nil) -> CatalogSetupDraftContext? {
        let companyId = companyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userId = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !companyId.isEmpty, !userId.isEmpty else { return nil }
        let editFamilyId = editFamilyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CatalogSetupDraftContext(
            companyId: companyId,
            userId: userId,
            scope: editFamilyId.isEmpty ? nil : "family:\(editFamilyId)"
        )
    }
}

struct CatalogSetupDraftSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var context: CatalogSetupDraftContext
    var updatedAt: Date
    var draftId: String
    var editFamilyId: String?
    var selectedStep: String
    var familyName: String
    var familyDescription: String
    var familyImageUrl: String
    var selectedCategoryId: String?
    var selectedUnitId: String?
    var defaultWarningText: String
    var defaultCriticalText: String
    var attributes: [CatalogSetupAttributeDraft]
    var invalidCombinations: [CatalogSetupInvalidCombination]
    var invalidSelectionByAttributeId: [String: String]
    var setupVariants: [CatalogSetupVariantDraft]
    var generatedMatrixOnce: Bool
    var selectedProductId: String?
    var productOptionSelectionByAttributeId: [String: String]
    var productValueSelectionByCatalogValueId: [String: String]
    var deletedIds: CatalogSetupDeletedIds?
    var activeSaveAttempt: CatalogSetupSaveAttempt?
    var rpcWarnings: [CatalogSetupSaveIssue]
    var rpcBlockers: [CatalogSetupSaveIssue]
    var saveErrorMessage: String?

    init(
        schemaVersion: Int = CatalogSetupDraftSnapshot.currentSchemaVersion,
        context: CatalogSetupDraftContext,
        updatedAt: Date = Date(),
        draftId: String,
        editFamilyId: String? = nil,
        selectedStep: String,
        familyName: String,
        familyDescription: String,
        familyImageUrl: String,
        selectedCategoryId: String?,
        selectedUnitId: String?,
        defaultWarningText: String,
        defaultCriticalText: String,
        attributes: [CatalogSetupAttributeDraft],
        invalidCombinations: [CatalogSetupInvalidCombination],
        invalidSelectionByAttributeId: [String: String],
        setupVariants: [CatalogSetupVariantDraft],
        generatedMatrixOnce: Bool,
        selectedProductId: String?,
        productOptionSelectionByAttributeId: [String: String],
        productValueSelectionByCatalogValueId: [String: String],
        deletedIds: CatalogSetupDeletedIds? = nil,
        activeSaveAttempt: CatalogSetupSaveAttempt?,
        rpcWarnings: [CatalogSetupSaveIssue],
        rpcBlockers: [CatalogSetupSaveIssue],
        saveErrorMessage: String?
    ) {
        self.schemaVersion = schemaVersion
        self.context = context
        self.updatedAt = updatedAt
        self.draftId = draftId
        self.editFamilyId = editFamilyId
        self.selectedStep = selectedStep
        self.familyName = familyName
        self.familyDescription = familyDescription
        self.familyImageUrl = familyImageUrl
        self.selectedCategoryId = selectedCategoryId
        self.selectedUnitId = selectedUnitId
        self.defaultWarningText = defaultWarningText
        self.defaultCriticalText = defaultCriticalText
        self.attributes = attributes
        self.invalidCombinations = invalidCombinations
        self.invalidSelectionByAttributeId = invalidSelectionByAttributeId
        self.setupVariants = setupVariants
        self.generatedMatrixOnce = generatedMatrixOnce
        self.selectedProductId = selectedProductId
        self.productOptionSelectionByAttributeId = productOptionSelectionByAttributeId
        self.productValueSelectionByCatalogValueId = productValueSelectionByCatalogValueId
        self.deletedIds = deletedIds
        self.activeSaveAttempt = activeSaveAttempt
        self.rpcWarnings = rpcWarnings
        self.rpcBlockers = rpcBlockers
        self.saveErrorMessage = saveErrorMessage
    }
}

final class CatalogSetupDraftStore {
    static let shared = CatalogSetupDraftStore()

    private let fileManager: FileManager
    private let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("CatalogSetupDrafts", isDirectory: true)
    }

    func save(_ snapshot: CatalogSetupDraftSnapshot) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(for: snapshot.context), options: .atomic)
    }

    func load(context: CatalogSetupDraftContext) throws -> CatalogSetupDraftSnapshot? {
        let url = fileURL(for: context)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CatalogSetupDraftSnapshot.self, from: data)
        guard snapshot.schemaVersion == CatalogSetupDraftSnapshot.currentSchemaVersion,
              snapshot.context == context
        else { return nil }
        return snapshot
    }

    func clear(context: CatalogSetupDraftContext) throws {
        let url = fileURL(for: context)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for context: CatalogSetupDraftContext) -> URL {
        var path = "\(safePathComponent(context.companyId))__\(safePathComponent(context.userId))"
        if let scope = context.scope?.trimmingCharacters(in: .whitespacesAndNewlines), !scope.isEmpty {
            path += "__\(safePathComponent(scope))"
        }
        return rootURL.appendingPathComponent("\(path).json", isDirectory: false)
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let components = value.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return components.joined()
    }
}

struct CatalogSetupSaveResolution: Equatable {
    var shouldClearDraft: Bool
    var warnings: [CatalogSetupSaveIssue]
    var blockers: [CatalogSetupSaveIssue]
    var userFacingMessage: String?
}

struct CatalogSetupAttributeValueDraft: Identifiable, Hashable, Codable {
    var id: String
    var serverId: String?
    var value: String

    init(id: String = UUID().uuidString, serverId: String? = nil, value: String = "") {
        self.id = id
        self.serverId = serverId
        self.value = value
    }
}

struct CatalogSetupAttributeDraft: Identifiable, Hashable, Codable {
    var id: String
    var serverId: String?
    var name: String
    var values: [CatalogSetupAttributeValueDraft]

    init(
        id: String = UUID().uuidString,
        serverId: String? = nil,
        name: String = "",
        values: [CatalogSetupAttributeValueDraft] = []
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.values = values
    }
}

struct CatalogSetupInvalidCombination: Identifiable, Hashable, Codable {
    var id: String
    var valueIds: Set<String>

    init(id: String = UUID().uuidString, valueIds: Set<String>) {
        self.id = id
        self.valueIds = valueIds
    }
}

struct CatalogSetupStockUnitDraft: Identifiable, Hashable, Codable {
    var id: String
    var serverId: String?
    var relatedStockUnitClientId: String?
    var relatedStockUnitServerId: String?
    var unitKind: CatalogStockUnitKind
    var label: String
    var lotCode: String
    var widthValue: Double?
    var widthUnit: String
    var originalLengthValue: Double?
    var remainingLengthValue: Double?
    var lengthUnit: String
    var quantityValue: Double
    var location: String
    var status: CatalogStockUnitStatus
    var notes: String
    var lifecycleEvents: [CatalogSetupStockUnitEventDraft]

    enum CodingKeys: String, CodingKey {
        case id
        case serverId
        case relatedStockUnitClientId
        case relatedStockUnitServerId
        case unitKind
        case label
        case lotCode
        case widthValue
        case widthUnit
        case originalLengthValue
        case remainingLengthValue
        case lengthUnit
        case quantityValue
        case location
        case status
        case notes
        case lifecycleEvents
    }

    init(
        id: String = UUID().uuidString,
        serverId: String? = nil,
        relatedStockUnitClientId: String? = nil,
        relatedStockUnitServerId: String? = nil,
        unitKind: CatalogStockUnitKind = .roll,
        label: String = "",
        lotCode: String = "",
        widthValue: Double? = nil,
        widthUnit: String = "ft",
        originalLengthValue: Double? = nil,
        remainingLengthValue: Double? = nil,
        lengthUnit: String = "ft",
        quantityValue: Double = 1,
        location: String = "",
        status: CatalogStockUnitStatus = .full,
        notes: String = "",
        lifecycleEvents: [CatalogSetupStockUnitEventDraft] = []
    ) {
        self.id = id
        self.serverId = serverId
        self.relatedStockUnitClientId = relatedStockUnitClientId
        self.relatedStockUnitServerId = relatedStockUnitServerId
        self.unitKind = unitKind
        self.label = label
        self.lotCode = lotCode
        self.widthValue = widthValue
        self.widthUnit = widthUnit
        self.originalLengthValue = originalLengthValue
        self.remainingLengthValue = remainingLengthValue
        self.lengthUnit = lengthUnit
        self.quantityValue = quantityValue
        self.location = location
        self.status = status
        self.notes = notes
        self.lifecycleEvents = lifecycleEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        serverId = try container.decodeIfPresent(String.self, forKey: .serverId)
        relatedStockUnitClientId = try container.decodeIfPresent(String.self, forKey: .relatedStockUnitClientId)
        relatedStockUnitServerId = try container.decodeIfPresent(String.self, forKey: .relatedStockUnitServerId)
        unitKind = try container.decode(CatalogStockUnitKind.self, forKey: .unitKind)
        label = try container.decode(String.self, forKey: .label)
        lotCode = try container.decode(String.self, forKey: .lotCode)
        widthValue = try container.decodeIfPresent(Double.self, forKey: .widthValue)
        widthUnit = try container.decode(String.self, forKey: .widthUnit)
        originalLengthValue = try container.decodeIfPresent(Double.self, forKey: .originalLengthValue)
        remainingLengthValue = try container.decodeIfPresent(Double.self, forKey: .remainingLengthValue)
        lengthUnit = try container.decode(String.self, forKey: .lengthUnit)
        quantityValue = try container.decode(Double.self, forKey: .quantityValue)
        location = try container.decode(String.self, forKey: .location)
        status = try container.decode(CatalogStockUnitStatus.self, forKey: .status)
        notes = try container.decode(String.self, forKey: .notes)
        lifecycleEvents = try container.decodeIfPresent([CatalogSetupStockUnitEventDraft].self, forKey: .lifecycleEvents) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(serverId, forKey: .serverId)
        try container.encodeIfPresent(relatedStockUnitClientId, forKey: .relatedStockUnitClientId)
        try container.encodeIfPresent(relatedStockUnitServerId, forKey: .relatedStockUnitServerId)
        try container.encode(unitKind, forKey: .unitKind)
        try container.encode(label, forKey: .label)
        try container.encode(lotCode, forKey: .lotCode)
        try container.encodeIfPresent(widthValue, forKey: .widthValue)
        try container.encode(widthUnit, forKey: .widthUnit)
        try container.encodeIfPresent(originalLengthValue, forKey: .originalLengthValue)
        try container.encodeIfPresent(remainingLengthValue, forKey: .remainingLengthValue)
        try container.encode(lengthUnit, forKey: .lengthUnit)
        try container.encode(quantityValue, forKey: .quantityValue)
        try container.encode(location, forKey: .location)
        try container.encode(status, forKey: .status)
        try container.encode(notes, forKey: .notes)
        try container.encode(lifecycleEvents, forKey: .lifecycleEvents)
    }
}

struct CatalogSetupVariantDraft: Identifiable, Hashable, Codable {
    var id: String
    var serverId: String?
    var optionValueIdsByAttributeId: [String: String]
    var optionValueIds: Set<String>
    var sku: String
    var warningThresholdText: String
    var criticalThresholdText: String
    var unitId: String?
    var imageUrl: String
    var stockUnits: [CatalogSetupStockUnitDraft]
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        serverId: String? = nil,
        optionValueIdsByAttributeId: [String: String] = [:],
        optionValueIds: Set<String>,
        sku: String = "",
        warningThresholdText: String = "",
        criticalThresholdText: String = "",
        unitId: String? = nil,
        imageUrl: String = "",
        stockUnits: [CatalogSetupStockUnitDraft] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.serverId = serverId
        self.optionValueIdsByAttributeId = optionValueIdsByAttributeId
        self.optionValueIds = optionValueIds
        self.sku = sku
        self.warningThresholdText = warningThresholdText
        self.criticalThresholdText = criticalThresholdText
        self.unitId = unitId
        self.imageUrl = imageUrl
        self.stockUnits = stockUnits
        self.isEnabled = isEnabled
    }
}

enum CatalogSetupCommitPreflightError: LocalizedError, Equatable {
    case catalogStockUnitsUnavailable
    case invalidProductOptionMappings([CatalogProductOptionMappingViolation])

    var errorDescription: String? {
        switch self {
        case .catalogStockUnitsUnavailable:
            return "Stock-unit schema is unavailable. Commit blocked before any catalog rows are created."
        case .invalidProductOptionMappings:
            return "Product option mapping is invalid. Clear stale values before commit."
        }
    }
}

/// Thrown when a guided-flow commit encounters a stock unit with a non-positive quantity.
///
/// The advanced flow uses the lenient `max(0, quantityValue)` coercion in
/// `makeSavePayload`; the guided flow routes through `validateStockQuantities`
/// first and surfaces this error to the user before any payload is built.
enum CatalogSetupStockValidationError: LocalizedError, Equatable {
    case nonPositiveStockQuantity(stockUnitClientId: String)

    var errorDescription: String? {
        switch self {
        case .nonPositiveStockQuantity(let id):
            return "Stock unit \(id) must have a quantity greater than zero before it can be built."
        }
    }
}

enum CatalogSetupWorkflow {
    static func generateVariantDrafts(
        attributes: [CatalogSetupAttributeDraft],
        invalidCombinations: [CatalogSetupInvalidCombination]
    ) -> [CatalogSetupVariantDraft] {
        let activeAttributes = attributes
            .map { attribute in
                CatalogSetupAttributeDraft(
                    id: attribute.id,
                    name: attribute.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    values: attribute.values.filter {
                        !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                )
            }
            .filter { !$0.name.isEmpty && !$0.values.isEmpty }

        guard !activeAttributes.isEmpty else {
            return []
        }

        var combinations: [[String: String]] = [[:]]
        for attribute in activeAttributes {
            combinations = combinations.flatMap { partial in
                attribute.values.map { value in
                    var next = partial
                    next[attribute.id] = value.id
                    return next
                }
            }
        }

        return combinations.compactMap { selection in
            let valueIds = Set(selection.values)
            let isInvalid = invalidCombinations.contains { invalid in
                !invalid.valueIds.isEmpty && valueIds.isSuperset(of: invalid.valueIds)
            }
            guard !isInvalid else { return nil }

            return CatalogSetupVariantDraft(
                id: signature(for: valueIds),
                optionValueIdsByAttributeId: selection,
                optionValueIds: valueIds
            )
        }
        .sorted { lhs, rhs in
            lhs.id < rhs.id
        }
    }

    // MARK: - Guided-flow stock quantity guard

    /// Validates that every enabled variant's stock units have a strictly positive
    /// quantity before building a guided-flow save payload.
    ///
    /// The advanced flow uses the lenient `max(0, quantityValue)` coercion in
    /// `makeSavePayload` for back-compat; the guided flow calls this first so the
    /// user sees a clear error rather than silently saving a zero-quantity unit.
    ///
    /// - Parameter variants: The variant drafts to inspect. Disabled variants
    ///   (`isEnabled == false`) are skipped entirely.
    /// - Throws: `CatalogSetupStockValidationError.nonPositiveStockQuantity` for
    ///   the first offending stock unit encountered.
    static func validateStockQuantities(variants: [CatalogSetupVariantDraft]) throws {
        for variant in variants where variant.isEnabled {
            for stockUnit in variant.stockUnits where stockUnit.quantityValue <= 0 {
                throw CatalogSetupStockValidationError.nonPositiveStockQuantity(
                    stockUnitClientId: stockUnit.id
                )
            }
        }
    }

    // MARK: - Variant identity validation

    static func validate(
        variants: [CatalogSetupVariantDraft],
        companyId: String,
        catalogItemId: String,
        existingVariants: [CatalogVariant],
        existingOptionValues: [CatalogVariantOptionValue]
    ) -> CatalogVariantIdentityValidationResult {
        let identities = variants
            .filter(\.isEnabled)
            .map {
                CatalogVariantDraftIdentity(
                    id: $0.serverId ?? $0.id,
                    companyId: companyId,
                    catalogItemId: catalogItemId,
                    sku: trimmedOptional($0.sku),
                    optionValueIds: $0.optionValueIds
                )
            }

        return CatalogVariantIdentityValidator.validate(
            drafts: identities,
            existingVariants: existingVariants,
            existingOptionValues: existingOptionValues
        )
    }

    static func mirroredQuantity(for stockUnits: [CatalogSetupStockUnitDraft]) -> Double {
        stockUnitAggregate(for: stockUnits).effectiveQuantity
    }

    static func mirroredQuantityLabel(for stockUnits: [CatalogSetupStockUnitDraft]) -> String {
        let aggregate = stockUnitAggregate(for: stockUnits)
        let quantity = aggregate.effectiveQuantity.formatted(.number.precision(.fractionLength(0...2)))
        let basis = aggregate.effectiveQuantityBasis
        switch basis {
        case let value where value.hasPrefix("AREA · "):
            return "\(quantity) \(String(value.dropFirst("AREA · ".count)))"
        case let value where value.hasPrefix("LENGTH · "):
            return "\(quantity) \(String(value.dropFirst("LENGTH · ".count)))"
        default:
            return quantity
        }
    }

    static func mirroredQuantityBasis(for stockUnits: [CatalogSetupStockUnitDraft]) -> String {
        stockUnitAggregate(for: stockUnits).effectiveQuantityBasis
    }

    static func setProductOptionSelection(
        attributeId: String,
        selectedProductOptionId: String,
        attributes: [CatalogSetupAttributeDraft],
        productOptionSelectionByAttributeId: inout [String: String],
        productValueSelectionByCatalogValueId: inout [String: String]
    ) {
        let previousSelection = productOptionSelectionByAttributeId[attributeId]
        let nextSelection = selectedProductOptionId.trimmingCharacters(in: .whitespacesAndNewlines)

        if nextSelection.isEmpty {
            productOptionSelectionByAttributeId.removeValue(forKey: attributeId)
        } else {
            productOptionSelectionByAttributeId[attributeId] = nextSelection
        }

        guard previousSelection != productOptionSelectionByAttributeId[attributeId],
              let attribute = attributes.first(where: { $0.id == attributeId })
        else { return }

        for value in attribute.values {
            productValueSelectionByCatalogValueId.removeValue(forKey: value.id)
        }
    }

    static func sanitizeProductOptionMappingSelections(
        attributes: [CatalogSetupAttributeDraft],
        productOptions: [ProductOption],
        productOptionValues: [ProductOptionValue],
        productOptionSelectionByAttributeId: inout [String: String],
        productValueSelectionByCatalogValueId: inout [String: String]
    ) {
        let attributeIds = Set(attributes.map(\.id))
        let catalogValueIdsByAttributeId = Dictionary(
            uniqueKeysWithValues: attributes.map { attribute in
                (attribute.id, Set(attribute.values.map(\.id)))
            }
        )
        let catalogValueIds = Set(catalogValueIdsByAttributeId.values.flatMap { $0 })
        let selectableProductOptionsById = Dictionary(
            uniqueKeysWithValues: productOptions
                .filter { $0.kind == .select }
                .map { ($0.id, $0) }
        )
        let productOptionValuesById = Dictionary(
            uniqueKeysWithValues: productOptionValues.map { ($0.id, $0) }
        )

        for attributeId in Array(productOptionSelectionByAttributeId.keys) where !attributeIds.contains(attributeId) {
            productOptionSelectionByAttributeId.removeValue(forKey: attributeId)
        }
        for catalogValueId in Array(productValueSelectionByCatalogValueId.keys) where !catalogValueIds.contains(catalogValueId) {
            productValueSelectionByCatalogValueId.removeValue(forKey: catalogValueId)
        }

        for attribute in attributes {
            guard let productOptionId = trimmedOptional(productOptionSelectionByAttributeId[attribute.id] ?? ""),
                  selectableProductOptionsById[productOptionId] != nil
            else {
                productOptionSelectionByAttributeId.removeValue(forKey: attribute.id)
                for catalogValueId in catalogValueIdsByAttributeId[attribute.id] ?? [] {
                    productValueSelectionByCatalogValueId.removeValue(forKey: catalogValueId)
                }
                continue
            }

            for value in attribute.values {
                guard let productValueId = trimmedOptional(productValueSelectionByCatalogValueId[value.id] ?? "") else {
                    continue
                }
                guard let productValue = productOptionValuesById[productValueId],
                      productValue.optionId == productOptionId
                else {
                    productValueSelectionByCatalogValueId.removeValue(forKey: value.id)
                    continue
                }
            }
        }
    }

    static func validateProductOptionMappingDraft(
        companyId: String,
        productId: String,
        attributes: [CatalogSetupAttributeDraft],
        productOptionSelectionByAttributeId: [String: String],
        productValueSelectionByCatalogValueId: [String: String],
        productOptions: [ProductOption],
        productOptionValues: [ProductOptionValue]
    ) -> [CatalogProductOptionMappingViolation] {
        let catalogItemId = "__catalog_setup_draft__"
        let catalogOptions = attributes.map {
            CatalogOption(id: $0.id, catalogItemId: catalogItemId, name: $0.name)
        }
        let catalogValues = attributes.flatMap { attribute in
            attribute.values.map {
                CatalogOptionValue(id: $0.id, optionId: attribute.id, value: $0.value)
            }
        }

        var mappings: [CatalogProductOptionMapping] = []
        for attribute in attributes {
            guard let productOptionId = productOptionSelectionByAttributeId[attribute.id],
                  !productOptionId.isEmpty
            else { continue }

            mappings.append(CatalogProductOptionMapping(
                id: "\(attribute.id)::axis",
                companyId: companyId,
                productId: productId,
                catalogItemId: catalogItemId,
                catalogOptionId: attribute.id,
                productOptionId: productOptionId,
                mappingKind: .axis
            ))

            for value in attribute.values {
                guard let productValueId = productValueSelectionByCatalogValueId[value.id],
                      !productValueId.isEmpty
                else { continue }

                mappings.append(CatalogProductOptionMapping(
                    id: "\(attribute.id)::\(value.id)",
                    companyId: companyId,
                    productId: productId,
                    catalogItemId: catalogItemId,
                    catalogOptionId: attribute.id,
                    productOptionId: productOptionId,
                    catalogOptionValueId: value.id,
                    productOptionValueId: productValueId,
                    mappingKind: .value
                ))
            }
        }

        return CatalogProductOptionMappingValidator.validate(
            mappings: mappings,
            catalogOptions: catalogOptions,
            catalogOptionValues: catalogValues,
            productOptions: productOptions,
            productOptionValues: productOptionValues
        )
    }

    static func preflightCommit(
        variants: [CatalogSetupVariantDraft],
        capabilities: CatalogSchemaCapabilities
    ) throws {
        let hasStockUnits = variants
            .filter(\.isEnabled)
            .contains { !$0.stockUnits.isEmpty }

        if hasStockUnits && !capabilities.catalogStockUnits {
            throw CatalogSetupCommitPreflightError.catalogStockUnitsUnavailable
        }
    }

    static func makeSavePayload(
        mode: String = "create",
        draftId: String,
        existingFamilyId: String? = nil,
        familyName: String,
        familyDescription: String,
        familyImageUrl: String,
        selectedCategoryId: String?,
        selectedUnitId: String?,
        defaultWarningThreshold: Double?,
        defaultCriticalThreshold: Double?,
        attributes: [CatalogSetupAttributeDraft],
        variants: [CatalogSetupVariantDraft],
        selectedProduct: Product?,
        productOptionSelectionByAttributeId: [String: String],
        productValueSelectionByCatalogValueId: [String: String],
        productOptions: [ProductOption],
        productOptionValues: [ProductOptionValue],
        catalogProductOptionMappings: [CatalogProductOptionMapping] = [],
        productPricingModifiers: [ProductPricingModifier] = [],
        productMaterials: [ProductMaterial] = [],
        productBundleItems: [ProductBundleItem] = [],
        capabilities: CatalogSchemaCapabilities = CatalogSchemaCapabilityGate.current,
        deletedIds: CatalogSetupDeletedIds = CatalogSetupDeletedIds(),
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    ) -> CatalogSetupSavePayload {
        let normalizedMode = mode == "update" ? "edit" : mode
        let familyClientId = existingFamilyId.map { "family:\($0)" } ?? "family:\(draftId)"
        let activeAttributes = normalizedAttributes(attributes)
        let enabledVariants = variants.filter(\.isEnabled)
        let catalogOptions = activeAttributes.enumerated().map { optionIndex, attribute in
            CatalogSetupSavePayload.CatalogOption(
                id: attribute.serverId,
                clientId: attribute.id,
                name: attribute.name,
                sortOrder: optionIndex,
                affectsStockIdentity: true,
                affectsPrice: true,
                affectsRecipe: true,
                shownOnEstimate: true,
                values: attribute.values.enumerated().map { valueIndex, value in
                    CatalogSetupSavePayload.CatalogOptionValue(
                        id: value.serverId,
                        clientId: value.id,
                        label: value.value,
                        sortOrder: valueIndex,
                        metadata: [:]
                    )
                }
            )
        }

        let valueLabelsById = Dictionary(
            uniqueKeysWithValues: activeAttributes.flatMap { attribute in
                attribute.values.map { ($0.id, $0.value) }
            }
        )

        let variantPayloads = enabledVariants.map { variant in
            let valueIds = orderedOptionValueClientIds(for: variant, attributes: activeAttributes)
            let name = valueIds.compactMap { valueLabelsById[$0] }.joined(separator: " - ")
            return CatalogSetupSavePayload.Variant(
                id: variant.serverId,
                clientId: variant.id,
                name: name.isEmpty ? variant.id : name,
                sku: trimmedOptional(variant.sku),
                price: nil,
                quantity: mirroredQuantity(for: variant.stockUnits),
                optionValueClientIds: valueIds,
                excluded: false,
                warningThreshold: parsedDouble(variant.warningThresholdText),
                criticalThreshold: parsedDouble(variant.criticalThresholdText),
                unitId: variant.unitId ?? selectedUnitId
            )
        }

        let stockUnitPayloads = enabledVariants.flatMap { variant in
            variant.stockUnits.map { stockUnit in
                CatalogSetupSavePayload.StockUnit(
                    id: stockUnit.serverId,
                    clientId: stockUnit.id,
                    variantClientId: variant.id,
                    catalogVariantId: variant.serverId,
                    relatedCatalogStockUnitClientId: stockUnit.relatedStockUnitClientId,
                    relatedCatalogStockUnitId: stockUnit.relatedStockUnitServerId,
                    unitKind: stockUnit.unitKind.rawValue,
                    label: trimmedOptional(stockUnit.label),
                    lotCode: trimmedOptional(stockUnit.lotCode),
                    widthValue: stockUnit.widthValue,
                    widthUnit: trimmedOptional(stockUnit.widthUnit),
                    originalLengthValue: stockUnit.originalLengthValue,
                    remainingLengthValue: stockUnit.remainingLengthValue,
                    lengthUnit: trimmedOptional(stockUnit.lengthUnit),
                    quantityValue: max(0, stockUnit.quantityValue),
                    location: trimmedOptional(stockUnit.location),
                    status: stockUnit.status.rawValue,
                    notes: trimmedOptional(stockUnit.notes)
                )
            }
        }
        let stockUnitEventPayloads = stockUnitEventPayloads(for: enabledVariants)

        let productPayloads: [CatalogSetupSavePayload.ProductPayload]
        if let selectedProduct {
            let mappings = productMappingsPayload(
                attributes: activeAttributes,
                productOptionSelectionByAttributeId: productOptionSelectionByAttributeId,
                productValueSelectionByCatalogValueId: productValueSelectionByCatalogValueId,
                productOptions: productOptions,
                productOptionValues: productOptionValues,
                existingMappings: catalogProductOptionMappings
            )
            let pricingModifierPayloads = productPricingModifierPayloads(
                product: selectedProduct,
                productPricingModifiers: productPricingModifiers
            )
            let productMaterialPayloads = productMaterialPayloads(
                product: selectedProduct,
                existingFamilyId: existingFamilyId,
                variants: enabledVariants,
                productMaterials: productMaterials
            )
            productPayloads = [
                CatalogSetupSavePayload.ProductPayload(
                    id: selectedProduct.id,
                    clientId: "product:\(selectedProduct.id)",
                    kind: selectedProduct.category3Way.derivedKindRaw,
                    type: selectedProduct.type.rawValue,
                    name: selectedProduct.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: trimmedOptional(selectedProduct.productDescription),
                    basePrice: selectedProduct.basePrice,
                    unit: trimmedOptional(selectedProduct.unit),
                    category: trimmedOptional(selectedProduct.category),
                    isTaxable: selectedProduct.taxable,
                    isActive: selectedProduct.isActive,
                    unitId: selectedProduct.unitId,
                    sku: trimmedOptional(selectedProduct.sku),
                    isFavorite: selectedProduct.isFavorite,
                    minimumCharge: selectedProduct.minimumCharge,
                    minimumQuantity: selectedProduct.minimumQuantity,
                    showBomOnEstimate: selectedProduct.showBomOnEstimate,
                    showInStorefront: selectedProduct.showInStorefront,
                    tieredPricing: selectedProduct.tieredPricingJSON.map { RawJSONColumn(rawJSONString: $0) },
                    categoryId: selectedProduct.categoryId,
                    thumbnailUrl: trimmedOptional(selectedProduct.thumbnailUrl),
                    pricingUnit: selectedProduct.pricingUnit.rawValue,
                    linkedCatalogItemClientId: familyClientId,
                    linkedCatalogItemId: nil,
                    bundlePricingMode: trimmedOptional(selectedProduct.bundlePricingMode),
                    options: productOptionPayloads(
                        product: selectedProduct,
                        productOptions: productOptions,
                        productOptionValues: productOptionValues
                    ),
                    pricingModifiers: pricingModifierPayloads,
                    productMaterials: productMaterialPayloads,
                    catalogOptionMappings: mappings,
                    bundleItems: productBundleItemPayloads(
                        product: selectedProduct,
                        productBundleItems: productBundleItems,
                        capabilities: capabilities
                    )
                )
            ]
        } else {
            productPayloads = []
        }

        return CatalogSetupSavePayload(
            mode: normalizedMode,
            draftId: draftId,
            clientSchemaVersion: 1,
            family: CatalogSetupSavePayload.Family(
                id: existingFamilyId,
                clientId: familyClientId,
                name: familyName.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryId: selectedCategoryId,
                unitId: selectedUnitId,
                description: trimmedOptional(familyDescription),
                imageUrl: trimmedOptional(familyImageUrl),
                defaultWarningThreshold: defaultWarningThreshold,
                defaultCriticalThreshold: defaultCriticalThreshold,
                metadata: [:]
            ),
            catalogOptions: catalogOptions,
            variants: variantPayloads,
            stockUnits: stockUnitPayloads,
            stockUnitEvents: stockUnitEventPayloads,
            products: productPayloads,
            productMaterials: [],
            deletedIds: deletedIds,
            clientMetadata: CatalogSetupSavePayload.ClientMetadata(appVersion: appVersion)
        )
    }

    static func resolveSaveResponse(_ response: CatalogSetupSaveResponse) -> CatalogSetupSaveResolution {
        CatalogSetupSaveResolution(
            shouldClearDraft: response.ok,
            warnings: response.warnings,
            blockers: response.blockers,
            userFacingMessage: response.ok ? nil : response.blockers.first?.message ?? response.warnings.first?.message
        )
    }

    static func resolvedProductId(
        for product: CatalogSetupSavePayload.ProductPayload,
        response: CatalogSetupSaveResponse
    ) -> String? {
        if let mappedId = response.idMap[product.clientId]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mappedId.isEmpty {
            return mappedId
        }
        return trimmedOptional(product.id ?? "")
    }

    static func signature(for optionValueIds: Set<String>) -> String {
        optionValueIds.sorted().joined(separator: "::")
    }

    static func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        return trimmedOptional(value)
    }

    private static func serverUUID(_ value: String) -> String? {
        UUID(uuidString: value) == nil ? nil : value
    }

    static func parsedDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    private static func stockUnitAggregate(for stockUnits: [CatalogSetupStockUnitDraft]) -> CatalogStockUnitVariantAggregate {
        var aggregate = CatalogStockUnitVariantAggregate()
        for unit in stockUnits where unit.status.countsAsAvailable {
            aggregate.addAvailableMeasurement(
                unitKind: unit.unitKind,
                quantityValue: unit.quantityValue,
                remainingLengthValue: unit.remainingLengthValue,
                lengthUnit: unit.lengthUnit,
                widthValue: unit.widthValue,
                widthUnit: unit.widthUnit
            )
        }
        return aggregate
    }

    private static func stockUnitEventPayloads(
        for variants: [CatalogSetupVariantDraft]
    ) -> [CatalogSetupSavePayload.StockUnitEvent] {
        variants.flatMap { variant in
            variant.stockUnits.flatMap { stockUnit in
                effectiveLifecycleEvents(for: stockUnit).map { event in
                    let relatedClientId = event.relatedStockUnitClientId ?? stockUnit.relatedStockUnitClientId
                    let relatedServerId = event.relatedStockUnitServerId ?? stockUnit.relatedStockUnitServerId
                    var payload = event.metadata
                    payload["draft_event_id"] = event.id
                    payload["operator_action"] = event.eventType.rawValue

                    return CatalogSetupSavePayload.StockUnitEvent(
                        eventId: event.id,
                        stockUnitClientId: stockUnit.id,
                        catalogStockUnitId: stockUnit.serverId,
                        variantClientId: variant.id,
                        catalogVariantId: variant.serverId,
                        relatedCatalogStockUnitClientId: relatedClientId,
                        relatedCatalogStockUnitId: relatedServerId,
                        eventType: event.eventType.rawValue,
                        fromStatus: event.fromStatus?.rawValue,
                        toStatus: event.toStatus?.rawValue,
                        quantityDelta: event.quantityDelta,
                        remainingLengthDelta: event.remainingLengthDelta,
                        payload: payload,
                        marker: trimmedOptional(event.marker),
                        notes: trimmedOptional(event.notes)
                    )
                }
            }
        }
    }

    private static func effectiveLifecycleEvents(
        for stockUnit: CatalogSetupStockUnitDraft
    ) -> [CatalogSetupStockUnitEventDraft] {
        var events = stockUnit.lifecycleEvents
        let existingTypes = Set(events.map(\.eventType))
        let hasRelatedSource = trimmedOptional(stockUnit.relatedStockUnitClientId) != nil ||
            trimmedOptional(stockUnit.relatedStockUnitServerId) != nil

        if stockUnit.serverId == nil,
           stockUnit.unitKind == .offcut,
           hasRelatedSource,
           !existingTypes.contains(.offcutCreate) {
            events.append(CatalogSetupStockUnitEventDraft(
                eventType: .offcutCreate,
                relatedStockUnitClientId: stockUnit.relatedStockUnitClientId,
                relatedStockUnitServerId: stockUnit.relatedStockUnitServerId,
                fromStatus: nil,
                toStatus: stockUnit.status,
                quantityDelta: max(0, stockUnit.quantityValue),
                remainingLengthDelta: stockUnit.remainingLengthValue,
                metadata: ["source": "ios_catalog_setup"]
            ))
        } else if stockUnit.serverId == nil,
                  !existingTypes.contains(.receive),
                  !existingTypes.contains(.offcutCreate) {
            events.append(CatalogSetupStockUnitEventDraft(
                eventType: .receive,
                fromStatus: nil,
                toStatus: stockUnit.status,
                quantityDelta: max(0, stockUnit.quantityValue),
                remainingLengthDelta: stockUnit.remainingLengthValue,
                metadata: ["source": "ios_catalog_setup"]
            ))
        }

        return events
    }

    private static func normalizedAttributes(_ attributes: [CatalogSetupAttributeDraft]) -> [CatalogSetupAttributeDraft] {
        attributes.compactMap { attribute in
            let name = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let values = attribute.values.compactMap { value -> CatalogSetupAttributeValueDraft? in
                let trimmed = value.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return CatalogSetupAttributeValueDraft(id: value.id, serverId: value.serverId, value: trimmed)
            }
            guard !name.isEmpty, !values.isEmpty else { return nil }
            return CatalogSetupAttributeDraft(
                id: attribute.id,
                serverId: attribute.serverId,
                name: name,
                values: values
            )
        }
    }

    private static func orderedOptionValueClientIds(
        for variant: CatalogSetupVariantDraft,
        attributes: [CatalogSetupAttributeDraft]
    ) -> [String] {
        var orderedIds: [String] = []
        var emittedIds = Set<String>()

        for attribute in attributes {
            guard let valueId = variant.optionValueIdsByAttributeId[attribute.id],
                  variant.optionValueIds.contains(valueId),
                  !emittedIds.contains(valueId)
            else {
                continue
            }
            orderedIds.append(valueId)
            emittedIds.insert(valueId)
        }

        let remainingIds = variant.optionValueIds
            .filter { !emittedIds.contains($0) }
            .sorted()
        return orderedIds + remainingIds
    }

    private static func productMappingsPayload(
        attributes: [CatalogSetupAttributeDraft],
        productOptionSelectionByAttributeId: [String: String],
        productValueSelectionByCatalogValueId: [String: String],
        productOptions: [ProductOption],
        productOptionValues: [ProductOptionValue],
        existingMappings: [CatalogProductOptionMapping]
    ) -> [CatalogSetupSavePayload.CatalogProductOptionMapping] {
        var mappings: [CatalogSetupSavePayload.CatalogProductOptionMapping] = []
        let selectableProductOptionsById = Dictionary(
            uniqueKeysWithValues: productOptions
                .filter { $0.kind == .select }
                .map { ($0.id, $0) }
        )
        let productOptionValuesById = Dictionary(
            uniqueKeysWithValues: productOptionValues.map { ($0.id, $0) }
        )

        for attribute in attributes {
            guard let productOptionId = trimmedOptional(productOptionSelectionByAttributeId[attribute.id] ?? ""),
                  selectableProductOptionsById[productOptionId] != nil
            else {
                continue
            }
            let existingAxisMapping = existingMappings.first { mapping in
                mapping.deletedAt == nil &&
                mapping.mappingKind == .axis &&
                mapping.catalogOptionId == (attribute.serverId ?? attribute.id) &&
                mapping.productOptionId == productOptionId
            }

            mappings.append(CatalogSetupSavePayload.CatalogProductOptionMapping(
                id: existingAxisMapping?.id,
                clientId: existingAxisMapping?.id ?? "mapping:\(attribute.id):axis",
                mappingKind: CatalogProductOptionMappingKind.axis.rawValue,
                catalogOptionClientId: attribute.id,
                catalogOptionId: attribute.serverId,
                catalogOptionValueClientId: nil,
                catalogOptionValueId: nil,
                productOptionClientId: nil,
                productOptionId: productOptionId,
                productOptionValueClientId: nil,
                productOptionValueId: nil
            ))

            for value in attribute.values {
                guard let productValueId = trimmedOptional(productValueSelectionByCatalogValueId[value.id] ?? ""),
                      let productValue = productOptionValuesById[productValueId],
                      productValue.optionId == productOptionId
                else {
                    continue
                }
                let existingValueMapping = existingMappings.first { mapping in
                    mapping.deletedAt == nil &&
                    mapping.mappingKind == .value &&
                    mapping.catalogOptionId == (attribute.serverId ?? attribute.id) &&
                    mapping.catalogOptionValueId == (value.serverId ?? value.id) &&
                    mapping.productOptionId == productOptionId &&
                    mapping.productOptionValueId == productValueId
                }
                mappings.append(CatalogSetupSavePayload.CatalogProductOptionMapping(
                    id: existingValueMapping?.id,
                    clientId: existingValueMapping?.id ?? "mapping:\(attribute.id):\(value.id)",
                    mappingKind: CatalogProductOptionMappingKind.value.rawValue,
                    catalogOptionClientId: attribute.id,
                    catalogOptionId: attribute.serverId,
                    catalogOptionValueClientId: value.id,
                    catalogOptionValueId: value.serverId,
                    productOptionClientId: nil,
                    productOptionId: productOptionId,
                    productOptionValueClientId: "product-option-value:\(productValue.id)",
                    productOptionValueId: serverUUID(productValueId)
                ))
            }
        }
        return mappings
    }

    private static func productPricingModifierPayloads(
        product: Product,
        productPricingModifiers: [ProductPricingModifier]
    ) -> [CatalogSetupSavePayload.ProductPricingModifier] {
        productPricingModifiers
            .filter { $0.productId == product.id }
            .map { modifier in
                CatalogSetupSavePayload.ProductPricingModifier(
                    id: modifier.id,
                    clientId: "product-pricing-modifier:\(modifier.id)",
                    optionClientId: nil,
                    optionId: modifier.optionId,
                    optionValueClientId: nil,
                    triggerValueId: modifier.triggerValueId,
                    triggerIntMin: modifier.triggerIntMin,
                    triggerIntMax: modifier.triggerIntMax,
                    modifierKind: modifier.modifierKind.rawValue,
                    amount: modifier.amount
                )
            }
    }

    private static func productMaterialPayloads(
        product: Product,
        existingFamilyId: String?,
        variants: [CatalogSetupVariantDraft],
        productMaterials: [ProductMaterial]
    ) -> [CatalogSetupSavePayload.ProductMaterial] {
        let existingVariantIds = Set(variants.compactMap(\.serverId))
        return productMaterials
            .filter { material in
                material.productId == product.id &&
                (
                    material.catalogItemId == existingFamilyId ||
                    material.catalogVariantId.map { existingVariantIds.contains($0) } == true
                )
            }
            .map { material in
                CatalogSetupSavePayload.ProductMaterial(
                    id: material.id,
                    clientId: "product-material:\(material.id)",
                    productClientId: nil,
                    productId: material.productId,
                    catalogVariantClientId: nil,
                    catalogVariantId: material.catalogVariantId,
                    catalogItemClientId: nil,
                    catalogItemId: material.catalogItemId,
                    variantSelector: material.variantSelectorJSON.map { RawJSONColumn(rawJSONString: $0) },
                    quantityPerUnit: material.quantityPerUnit,
                    scaledByOptionId: material.scaledByOptionId,
                    unitId: material.unitId,
                    notes: material.notes
                )
            }
    }

    private static func productBundleItemPayloads(
        product: Product,
        productBundleItems: [ProductBundleItem],
        capabilities: CatalogSchemaCapabilities
    ) -> [CatalogSetupSavePayload.ProductBundleItemPayload] {
        let activeRows = productBundleItems
            .filter { $0.bundleProductId == product.id && $0.deletedAt == nil }
        let groupedRows = ProductBundleCompositionGrouping.group(activeRows)
        let canSendRelationshipFields = capabilities.productBundleRelationshipFields
        let rows = canSendRelationshipFields
            ? groupedRows.required + groupedRows.suggested
            : groupedRows.required

        return rows.map { item in
            CatalogSetupSavePayload.ProductBundleItemPayload(
                id: item.id,
                clientId: "product-bundle-item:\(item.id)",
                childProductId: item.childProductId,
                quantity: item.quantity,
                relationshipKind: canSendRelationshipFields ? item.relationshipKind.rawValue : nil,
                hasPricing: true,
                suggestionReason: canSendRelationshipFields ? item.suggestionReason : nil,
                compatibilitySelector: canSendRelationshipFields
                    ? item.compatibilitySelectorJSON.map { RawJSONColumn(rawJSONString: $0) }
                    : nil,
                displayOrder: item.displayOrder
            )
        }
    }

    private static func productOptionPayloads(
        product: Product,
        productOptions: [ProductOption],
        productOptionValues: [ProductOptionValue]
    ) -> [CatalogSetupSavePayload.ProductOptionPayload] {
        productOptions
            .filter { $0.productId == product.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .map { option in
                CatalogSetupSavePayload.ProductOptionPayload(
                    id: option.id,
                    clientId: "product-option:\(option.id)",
                    name: option.name,
                    kind: option.kind.rawValue,
                    required: option.required,
                    affectsPrice: option.affectsPrice,
                    affectsRecipe: option.affectsRecipe,
                    defaultValue: trimmedOptional(option.defaultValue),
                    optionDefaultSource: trimmedOptional(option.optionDefaultSource),
                    sortOrder: option.sortOrder,
                    values: productOptionValues
                        .filter { $0.optionId == option.id }
                        .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
                        .map { value in
                            CatalogSetupSavePayload.ProductOptionValuePayload(
                                id: value.id,
                                clientId: "product-option-value:\(value.id)",
                                label: value.value,
                                sortOrder: value.sortOrder
                            )
                        }
                )
            }
    }
}

private extension CatalogSetupSavePayload {
    func catalogSetupFingerprint() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self).base64EncodedString()
    }
}
