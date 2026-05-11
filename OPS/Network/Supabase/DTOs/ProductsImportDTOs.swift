//
//  ProductsImportDTOs.swift
//  OPS
//
//  DTOs for the products_import_validate / products_import_apply RPCs.
//  See: OPS/Migrations/2026-05-08-products-import-rpc.sql for the
//  authoritative payload + result schemas.
//
//  One array in the payload — `products`. Each row carries a 0-based
//  `row_index`; the server returns a row_index → uuid mapping after
//  INSERT under `created_product_ids`.
//
//  Sibling: CatalogImportDTOs.swift (catalog families+variants import).
//

import Foundation

// MARK: - Payload (request)

struct ProductsImportPayload: Encodable {
    let products: [ProductsImportProduct]
}

struct ProductsImportProduct: Encodable {
    let rowIndex: Int
    let name: String
    let description: String?
    let basePrice: Double
    let unitCost: Double?
    let categoryId: String?
    let unitId: String?
    /// Legacy free-text category, written alongside `categoryId` for
    /// read-fallback compatibility on older clients.
    let category: String?
    /// Legacy free-text unit display, written alongside `unitId`.
    let unit: String?
    /// Legacy enum value (free text on the wire). NOT NULL on the
    /// server; defaults to 'each' if omitted.
    let pricingUnit: String?
    let sku: String?
    /// 'service' | 'good'. NOT NULL on the server; defaults to 'service'
    /// if omitted.
    let kind: String?
    /// LineItemType raw — 'LABOR' | 'MATERIAL' | 'OTHER'. NOT NULL on
    /// the server; defaults to 'LABOR' if omitted.
    let type: String?
    let isTaxable: Bool?

    enum CodingKeys: String, CodingKey {
        case rowIndex      = "row_index"
        case name
        case description
        case basePrice     = "base_price"
        case unitCost      = "unit_cost"
        case categoryId    = "category_id"
        case unitId        = "unit_id"
        case category
        case unit
        case pricingUnit   = "pricing_unit"
        case sku
        case kind
        case type
        case isTaxable     = "is_taxable"
    }
}

// MARK: - Result (response)

struct ProductsImportResult: Decodable {
    let success: Bool
    /// Map of `row_index` (as a string key, since plpgsql jsonb keys are
    /// text) → newly inserted products uuid. Present on success only.
    let createdProductIds: [String: String]?
    let totals: ProductsImportTotals?
    let errors: [ProductsImportError]?

    enum CodingKeys: String, CodingKey {
        case success
        case createdProductIds = "created_product_ids"
        case totals
        case errors
    }
}

struct ProductsImportTotals: Decodable {
    let products: Int
}

struct ProductsImportError: Decodable, Identifiable, Hashable {
    /// Synthesized — not returned by the server. `scope:row:field` is
    /// stable enough to identify a row in a SwiftUI ForEach.
    var id: String { "\(scope):\(rowIndex):\(field)" }

    /// "product" | "payload" | "mapping" (mapping is client-only)
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
