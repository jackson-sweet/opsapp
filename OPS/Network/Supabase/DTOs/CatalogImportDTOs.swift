//
//  CatalogImportDTOs.swift
//  OPS
//
//  DTOs for the catalog_import_validate / catalog_import_apply RPCs.
//  See: OPS/Migrations/2026-05-08-catalog-import-rpc.sql for the
//  authoritative payload + result schemas.
//
//  Two arrays in the payload — `families` and `variants`. Each row
//  carries a 0-based `row_index`; variants reference families through
//  `family_row_index`. The server resolves the index → uuid mapping
//  after INSERT and returns it in `created_family_ids`.
//

import Foundation

// MARK: - Payload (request)

struct CatalogImportPayload: Encodable {
    let families: [CatalogImportFamily]
    let variants: [CatalogImportVariant]
}

struct CatalogImportFamily: Encodable {
    let rowIndex: Int
    let name: String
    let description: String?
    let categoryId: String?
    let defaultUnitId: String?
    let defaultPrice: Double?
    let defaultUnitCost: Double?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case rowIndex                   = "row_index"
        case name
        case description
        case categoryId                 = "category_id"
        case defaultUnitId              = "default_unit_id"
        case defaultPrice               = "default_price"
        case defaultUnitCost            = "default_unit_cost"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
    }
}

struct CatalogImportVariant: Encodable {
    let rowIndex: Int
    let familyRowIndex: Int
    let sku: String?
    let quantity: Double
    let priceOverride: Double?
    let unitCostOverride: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitId: String?

    enum CodingKeys: String, CodingKey {
        case rowIndex           = "row_index"
        case familyRowIndex     = "family_row_index"
        case sku
        case quantity
        case priceOverride      = "price_override"
        case unitCostOverride   = "unit_cost_override"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case unitId             = "unit_id"
    }
}

// MARK: - Result (response)

struct CatalogImportResult: Decodable {
    let success: Bool
    /// Map of `row_index` (as a string key, since plpgsql jsonb keys are
    /// text) → newly inserted catalog_items uuid. Present on success only.
    let createdFamilyIds: [String: String]?
    /// Same shape but for catalog_variants.
    let createdVariantIds: [String: String]?
    let totals: CatalogImportTotals?
    let errors: [CatalogImportError]?

    enum CodingKeys: String, CodingKey {
        case success
        case createdFamilyIds   = "created_family_ids"
        case createdVariantIds  = "created_variant_ids"
        case totals
        case errors
    }
}

struct CatalogImportTotals: Decodable {
    let families: Int
    let variants: Int
}

struct CatalogImportError: Decodable, Identifiable, Hashable {
    /// Synthesized — not returned by the server. `scope:row:field` is
    /// stable enough to identify a row in a SwiftUI ForEach.
    var id: String { "\(scope):\(rowIndex):\(field)" }

    /// "family" | "variant" | "payload"
    let scope: String
    /// 0-based index inside the originating array. -1 for payload-scope.
    let rowIndex: Int
    let field: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case scope
        case rowIndex   = "row_index"
        case field
        case reason
    }
}
