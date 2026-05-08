//
//  ProductDTOs.swift
//  OPS
//
//  DTOs for the Supabase `products` table. The wire-field bug from
//  earlier builds (unit_price / cost_price — columns that don't exist
//  in Supabase) is fixed here: we now correctly map base_price + default_price
//  + unit_cost. The base_price ↔ default_price mirror lives in a Postgres
//  trigger (see migration 02), so iOS only needs to read/write base_price.
//

import Foundation

struct ProductDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let description: String?
    let basePrice: Double                  // FIXED: was unit_price (column did not exist)
    let unitCost: Double?                  // FIXED: was cost_price
    let unit: String?
    let category: String?
    let sku: String?
    let kind: String?                      // 'service' | 'good'
    let pricingUnit: String?
    let type: String?                      // LineItemType raw — LABOR/MATERIAL/OTHER
    let isTaxable: Bool?
    let isActive: Bool
    let isFavorite: Bool
    let minimumCharge: Double?
    let minimumQuantity: Double?
    let showBomOnEstimate: Bool
    let showInStorefront: Bool
    let tieredPricing: RawJSONColumn?            // jsonb passthrough
    let taskTypeId: String?
    let taskTypeRef: String?
    let unitId: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId             = "company_id"
        case name
        case description
        case basePrice             = "base_price"
        case unitCost              = "unit_cost"
        case unit
        case category
        case sku
        case kind
        case pricingUnit           = "pricing_unit"
        case type
        case isTaxable             = "is_taxable"
        case isActive              = "is_active"
        case isFavorite            = "is_favorite"
        case minimumCharge         = "minimum_charge"
        case minimumQuantity       = "minimum_quantity"
        case showBomOnEstimate     = "show_bom_on_estimate"
        case showInStorefront      = "show_in_storefront"
        case tieredPricing         = "tiered_pricing"
        case taskTypeId            = "task_type_id"
        case taskTypeRef           = "task_type_ref"
        case unitId                = "unit_id"
        case createdAt             = "created_at"
        case updatedAt             = "updated_at"
    }

    func toModel() -> Product {
        let prod = Product(
            id: id,
            companyId: companyId,
            name: name,
            type: type.flatMap { LineItemType(rawValue: $0) } ?? .labor,
            kind: kind.flatMap { ProductKind(rawValue: $0) } ?? .service,
            basePrice: basePrice,
            pricingUnit: pricingUnit.flatMap { ProductPricingUnit(rawValue: $0) } ?? .each,
            taxable: isTaxable ?? true,
            isActive: isActive,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        prod.productDescription = description
        prod.unitCost = unitCost
        prod.unit = unit
        prod.category = category
        prod.sku = sku
        prod.isFavorite = isFavorite
        prod.minimumCharge = minimumCharge
        prod.minimumQuantity = minimumQuantity
        prod.showBomOnEstimate = showBomOnEstimate
        prod.showInStorefront = showInStorefront
        prod.tieredPricingJSON = tieredPricing?.rawJSONString
        prod.taskTypeId = taskTypeId
        prod.taskTypeRef = taskTypeRef
        prod.unitId = unitId
        return prod
    }
}

struct CreateProductDTO: Codable {
    let companyId: String
    let name: String
    let description: String?
    let basePrice: Double
    let unitCost: Double?
    let unit: String?
    let pricingUnit: String?
    let unitId: String?              // FK to catalog_units; column already exists server-side
    let category: String?
    let sku: String?
    let kind: String?
    let type: String?
    let isTaxable: Bool
    let taskTypeId: String?

    enum CodingKeys: String, CodingKey {
        case companyId    = "company_id"
        case name
        case description
        case basePrice    = "base_price"
        case unitCost     = "unit_cost"
        case unit
        case pricingUnit  = "pricing_unit"
        case unitId       = "unit_id"
        case category
        case sku
        case kind
        case type
        case isTaxable    = "is_taxable"
        case taskTypeId   = "task_type_id"
    }
}

struct UpdateProductDTO: Codable {
    var name: String?
    var description: String?
    var basePrice: Double?
    var unitCost: Double?
    var unit: String?
    var pricingUnit: String?
    var category: String?
    var sku: String?
    var kind: String?
    var type: String?
    var isTaxable: Bool?
    var isActive: Bool?
    var isFavorite: Bool?
    var minimumCharge: Double?
    var minimumQuantity: Double?
    var taskTypeId: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case basePrice         = "base_price"
        case unitCost          = "unit_cost"
        case unit
        case pricingUnit       = "pricing_unit"
        case category
        case sku
        case kind
        case type
        case isTaxable         = "is_taxable"
        case isActive          = "is_active"
        case isFavorite        = "is_favorite"
        case minimumCharge     = "minimum_charge"
        case minimumQuantity   = "minimum_quantity"
        case taskTypeId        = "task_type_id"
    }
}

/// Type-erased JSON value for `tiered_pricing` and other jsonb fields we want
/// to pass through without strong typing.
struct RawJSONColumn: Codable {
    let rawJSONString: String

    init(rawJSONString: String) {
        self.rawJSONString = rawJSONString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Preserve raw JSON by re-encoding through JSONSerialization.
        let value = try container.decode(RawJSONValue.self)
        let data = try JSONEncoder().encode(value)
        rawJSONString = String(data: data, encoding: .utf8) ?? "{}"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let data = rawJSONString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(RawJSONValue.self, from: data) {
            try container.encode(decoded)
        } else {
            try container.encode(RawJSONValue.object([:]))
        }
    }
}

private indirect enum RawJSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RawJSONValue])
    case object([String: RawJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([RawJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: RawJSONValue].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):    try c.encode(b)
        case .number(let n):  try c.encode(n)
        case .string(let s):  try c.encode(s)
        case .array(let a):   try c.encode(a)
        case .object(let o):  try c.encode(o)
        }
    }
}
