//
//  ProductRichnessRepository.swift
//  OPS
//
//  Fetches/persists the optional Product configurability layers:
//  product_options, product_option_values, product_pricing_modifiers,
//  product_materials.
//

import Foundation
import Supabase

class ProductRichnessRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Options

    func fetchOptionsForCompany() async throws -> [ProductOptionDTO] {
        struct Joined: Codable {
            let id: String
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
        }
        let rows: [Joined] = try await client.from("product_options")
            .select("id, product_id, name, kind, affects_price, affects_recipe, required, default_value, option_default_source, sort_order, products!inner(company_id)")
            .eq("products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductOptionDTO(
                id: $0.id, productId: $0.productId, name: $0.name, kind: $0.kind,
                affectsPrice: $0.affectsPrice, affectsRecipe: $0.affectsRecipe,
                required: $0.required, defaultValue: $0.defaultValue,
                optionDefaultSource: $0.optionDefaultSource, sortOrder: $0.sortOrder
            )
        }
    }

    // MARK: - Option values

    func fetchOptionValuesForCompany() async throws -> [ProductOptionValueDTO] {
        struct Joined: Codable {
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
        }
        let rows: [Joined] = try await client.from("product_option_values")
            .select("id, option_id, value, sort_order, product_options!inner(products!inner(company_id))")
            .eq("product_options.products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductOptionValueDTO(id: $0.id, optionId: $0.optionId, value: $0.value, sortOrder: $0.sortOrder)
        }
    }

    // MARK: - Pricing modifiers

    func fetchPricingModifiersForCompany() async throws -> [ProductPricingModifierDTO] {
        struct Joined: Codable {
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
        }
        let rows: [Joined] = try await client.from("product_pricing_modifiers")
            .select("id, product_id, option_id, trigger_value_id, trigger_int_min, trigger_int_max, modifier_kind, amount, products!inner(company_id)")
            .eq("products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductPricingModifierDTO(
                id: $0.id, productId: $0.productId, optionId: $0.optionId,
                triggerValueId: $0.triggerValueId,
                triggerIntMin: $0.triggerIntMin, triggerIntMax: $0.triggerIntMax,
                modifierKind: $0.modifierKind, amount: $0.amount
            )
        }
    }

    // MARK: - Recipe rows (product_materials)

    func fetchMaterialsForCompany() async throws -> [ProductMaterialDTO] {
        struct Joined: Codable {
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
        let rows: [Joined] = try await client.from("product_materials")
            .select("id, product_id, catalog_variant_id, catalog_item_id, variant_selector, quantity_per_unit, scaled_by_option_id, unit_id, notes, products!inner(company_id)")
            .eq("products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductMaterialDTO(
                id: $0.id, productId: $0.productId,
                catalogVariantId: $0.catalogVariantId, catalogItemId: $0.catalogItemId,
                variantSelector: $0.variantSelector,
                quantityPerUnit: $0.quantityPerUnit,
                scaledByOptionId: $0.scaledByOptionId,
                unitId: $0.unitId, notes: $0.notes
            )
        }
    }
}
