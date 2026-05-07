//
//  Product.swift
//  OPS
//
//  Service/product catalog item — Supabase-backed.
//  Configurable Products carry options, pricing modifiers, and recipe rows
//  via separate models (ProductOption, ProductPricingModifier, ProductMaterial).
//

import SwiftData
import Foundation

enum ProductPricingUnit: String, CaseIterable, Codable {
    case each
    case flatRate = "flat_rate"
    case linearFoot = "linear_foot"
    case sqft
    case hour
    case day
}

enum ProductKind: String, CaseIterable, Codable {
    case service
    case good
}

@Model
class Product: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var productDescription: String?
    var type: LineItemType
    var kind: ProductKind
    var basePrice: Double
    var unitCost: Double?
    var pricingUnit: ProductPricingUnit
    var unit: String?               // legacy free-text unit; iOS reads `pricingUnit` for new behavior
    var category: String?           // legacy free-text category on Product (separate from catalog_categories)
    var sku: String?
    var taxable: Bool
    var isActive: Bool
    var isFavorite: Bool
    var minimumCharge: Double?
    var minimumQuantity: Double?
    var showBomOnEstimate: Bool
    var showInStorefront: Bool
    var tieredPricingJSON: String?  // raw jsonb stored as JSON string for the rare power-user case
    var taskTypeId: String?
    var taskTypeRef: String?
    var unitId: String?             // FK to catalog_units (was nullable text before; now uuid)
    var createdAt: Date

    // Computed margin
    var marginPercent: Double? {
        guard let cost = unitCost, cost > 0, basePrice > 0 else { return nil }
        return ((basePrice - cost) / basePrice) * 100
    }

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        type: LineItemType = .labor,
        kind: ProductKind = .service,
        basePrice: Double = 0,
        pricingUnit: ProductPricingUnit = .each,
        taxable: Bool = true,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.type = type
        self.kind = kind
        self.basePrice = basePrice
        self.pricingUnit = pricingUnit
        self.taxable = taxable
        self.isActive = isActive
        self.isFavorite = false
        self.showBomOnEstimate = false
        self.showInStorefront = false
        self.createdAt = createdAt
    }
}
