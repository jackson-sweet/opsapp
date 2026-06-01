//
//  ProductExtensionDTOs.swift
//  OPS
//
//  DTOs for the configurable-Product layers: options, option values,
//  pricing modifiers, and recipe rows (product_materials).
//

import Foundation

struct ProductOptionDTO: Codable, Identifiable {
    let id: String
    let productId: String
    let name: String
    let kind: String          // 'select' | 'integer' | 'boolean'
    let affectsPrice: Bool
    let affectsRecipe: Bool
    let required: Bool
    let defaultValue: String?
    let optionDefaultSource: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case productId            = "product_id"
        case name
        case kind
        case affectsPrice         = "affects_price"
        case affectsRecipe        = "affects_recipe"
        case required
        case defaultValue         = "default_value"
        case optionDefaultSource  = "option_default_source"
        case sortOrder            = "sort_order"
    }

    func toModel() -> ProductOption {
        ProductOption(
            id: id, productId: productId, name: name,
            kind: ProductOptionKind(rawValue: kind) ?? .select,
            affectsPrice: affectsPrice, affectsRecipe: affectsRecipe,
            required: required, defaultValue: defaultValue,
            optionDefaultSource: optionDefaultSource, sortOrder: sortOrder
        )
    }
}

struct ProductOptionValueDTO: Codable, Identifiable {
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

    func toModel() -> ProductOptionValue {
        ProductOptionValue(id: id, optionId: optionId, value: value, sortOrder: sortOrder)
    }
}

struct ProductPricingModifierDTO: Codable, Identifiable {
    let id: String
    let productId: String
    let optionId: String
    let triggerValueId: String?
    let triggerIntMin: Int?
    let triggerIntMax: Int?
    let modifierKind: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case productId        = "product_id"
        case optionId         = "option_id"
        case triggerValueId   = "trigger_value_id"
        case triggerIntMin    = "trigger_int_min"
        case triggerIntMax    = "trigger_int_max"
        case modifierKind     = "modifier_kind"
        case amount
    }

    func toModel() -> ProductPricingModifier {
        ProductPricingModifier(
            id: id, productId: productId, optionId: optionId,
            triggerValueId: triggerValueId,
            triggerIntMin: triggerIntMin, triggerIntMax: triggerIntMax,
            modifierKind: PricingModifierKind(rawValue: modifierKind) ?? .addPerUnit,
            amount: amount
        )
    }
}

struct ProductMaterialDTO: Codable, Identifiable {
    let id: String
    let productId: String
    let catalogVariantId: String?
    let catalogItemId: String?
    let variantSelector: RawJSONColumn?
    let quantityPerUnit: Double
    let scaledByOptionId: String?
    let unitId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case productId          = "product_id"
        case catalogVariantId   = "catalog_variant_id"
        case catalogItemId      = "catalog_item_id"
        case variantSelector    = "variant_selector"
        case quantityPerUnit    = "quantity_per_unit"
        case scaledByOptionId   = "scaled_by_option_id"
        case unitId             = "unit_id"
        case notes
    }

    func toModel() -> ProductMaterial {
        ProductMaterial(
            id: id, productId: productId,
            catalogVariantId: catalogVariantId, catalogItemId: catalogItemId,
            variantSelectorJSON: variantSelector?.rawJSONString,
            quantityPerUnit: quantityPerUnit,
            scaledByOptionId: scaledByOptionId,
            unitId: unitId, notes: notes
        )
    }
}

// MARK: - Create / Update DTOs

struct CreateProductOptionDTO: Codable {
    let productId: String
    let name: String
    let kind: String
    let affectsPrice: Bool
    let affectsRecipe: Bool
    let required: Bool
    let defaultValue: String?
    let optionDefaultSource: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case productId            = "product_id"
        case name
        case kind
        case affectsPrice         = "affects_price"
        case affectsRecipe        = "affects_recipe"
        case required
        case defaultValue         = "default_value"
        case optionDefaultSource  = "option_default_source"
        case sortOrder            = "sort_order"
    }
}

struct UpdateProductOptionDTO: Codable {
    let name: String
    let kind: String
    let affectsPrice: Bool
    let affectsRecipe: Bool
    let required: Bool
    let defaultValue: String?
    let optionDefaultSource: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name
        case kind
        case affectsPrice         = "affects_price"
        case affectsRecipe        = "affects_recipe"
        case required
        case defaultValue         = "default_value"
        case optionDefaultSource  = "option_default_source"
        case sortOrder            = "sort_order"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(affectsPrice, forKey: .affectsPrice)
        try c.encode(affectsRecipe, forKey: .affectsRecipe)
        try c.encode(required, forKey: .required)
        try c.encode(defaultValue, forKey: .defaultValue)
        try c.encode(optionDefaultSource, forKey: .optionDefaultSource)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

struct CreateProductOptionValueDTO: Codable {
    let optionId: String
    let value: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case optionId   = "option_id"
        case value
        case sortOrder  = "sort_order"
    }
}

struct UpdateProductOptionValueDTO: Codable {
    let value: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case value
        case sortOrder = "sort_order"
    }
}

struct CreateProductPricingModifierDTO: Codable {
    let productId: String
    let optionId: String
    let triggerValueId: String?
    let triggerIntMin: Int?
    let triggerIntMax: Int?
    let modifierKind: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case productId       = "product_id"
        case optionId        = "option_id"
        case triggerValueId  = "trigger_value_id"
        case triggerIntMin   = "trigger_int_min"
        case triggerIntMax   = "trigger_int_max"
        case modifierKind    = "modifier_kind"
        case amount
    }
}

struct UpdateProductPricingModifierDTO: Codable {
    let optionId: String
    let triggerValueId: String?
    let triggerIntMin: Int?
    let triggerIntMax: Int?
    let modifierKind: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case optionId        = "option_id"
        case triggerValueId  = "trigger_value_id"
        case triggerIntMin   = "trigger_int_min"
        case triggerIntMax   = "trigger_int_max"
        case modifierKind    = "modifier_kind"
        case amount
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(optionId, forKey: .optionId)
        try c.encode(triggerValueId, forKey: .triggerValueId)
        try c.encode(triggerIntMin, forKey: .triggerIntMin)
        try c.encode(triggerIntMax, forKey: .triggerIntMax)
        try c.encode(modifierKind, forKey: .modifierKind)
        try c.encode(amount, forKey: .amount)
    }
}

struct CreateProductMaterialDTO: Codable {
    let productId: String
    let catalogVariantId: String?
    let catalogItemId: String?
    let variantSelector: RawJSONColumn?
    let quantityPerUnit: Double
    let scaledByOptionId: String?
    let unitId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case productId         = "product_id"
        case catalogVariantId  = "catalog_variant_id"
        case catalogItemId     = "catalog_item_id"
        case variantSelector   = "variant_selector"
        case quantityPerUnit   = "quantity_per_unit"
        case scaledByOptionId  = "scaled_by_option_id"
        case unitId            = "unit_id"
        case notes
    }
}

/// Sparse update for an existing product_materials row. Only mutable
/// fields are exposed — id, productId, catalogVariantId, catalogItemId,
/// and variantSelector are identity / pin shape and require a delete +
/// re-create rather than an update. Encoder writes only the fields the
/// caller set, so PostgREST sees a minimal patch.
struct UpdateProductMaterialDTO: Codable {
    var quantityPerUnit: Double?
    var scaledByOptionId: String?
    var unitId: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case quantityPerUnit   = "quantity_per_unit"
        case scaledByOptionId  = "scaled_by_option_id"
        case unitId            = "unit_id"
        case notes
    }
}
