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
    case package
}

/// User-facing product taxonomy. Replaces the legacy `kind` + `type` two-axis
/// confusion in the iOS forms with a single 4-way pick. The legacy columns
/// remain mirrored on save so old App Store builds and the web app continue
/// to work unchanged — see `derivedKind` / `derivedType` for the mapping.
enum ProductCategory: String, CaseIterable, Codable, Identifiable {
    case service
    case material
    case fee
    case bundle

    var id: String { rawValue }

    /// Reconstruct the user-facing category from the legacy two-field shape.
    /// Bundle wins over type — a package-kind product is a bundle regardless of type.
    static func from(type: LineItemType, kind: ProductKind) -> ProductCategory {
        if kind == .package { return .bundle }
        switch type {
        case .labor:    return .service
        case .material: return .material
        case .other:    return .fee
        }
    }

    /// Value to write to `products.kind`. Fee maps to `service` because the
    /// CHECK constraint accepts only `{service, material, package}` — keeping
    /// Fees out of `material` avoids accidental inclusion in inventory paths.
    var derivedKind: ProductKind {
        switch self {
        case .service, .fee: return .service
        case .material:      return .good
        case .bundle:        return .package
        }
    }

    /// Raw `kind` string written to Supabase. `ProductKind.good` is mapped to
    /// the database value `material` because that's what Supabase actually
    /// stores (the Swift enum case name is legacy).
    var derivedKindRaw: String {
        switch self {
        case .service, .fee: return "service"
        case .material:      return "material"
        case .bundle:        return "package"
        }
    }

    /// Value to write to `products.type` (the load-bearing classifier).
    var derivedType: LineItemType {
        switch self {
        case .service:  return .labor
        case .material: return .material
        case .fee:      return .other
        case .bundle:   return .other
        }
    }

    /// Sensible default for the `taxable` toggle when a user picks a category.
    /// Manual overrides should win; this is only the *initial* value.
    var defaultTaxable: Bool {
        switch self {
        case .service, .material, .bundle: return true
        case .fee:                         return false
        }
    }

    /// Display label for the segmented picker.
    var displayLabel: String {
        switch self {
        case .service:  return "SERVICE"
        case .material: return "GOOD"
        case .fee:      return "FEE"
        case .bundle:   return "BUNDLE"
        }
    }

    /// Nav-title variant — uses tradesman vocabulary where it differs from displayLabel.
    var navigationTitle: String {
        switch self {
        case .service:  return "SERVICE"
        case .material: return "PRODUCT"
        case .fee:      return "FEE"
        case .bundle:   return "BUNDLE"
        }
    }

    /// One-line subtitle shown under the picker so the operator can place
    /// the right product without thinking about the legacy taxonomy.
    var helpText: String {
        switch self {
        case .service:  return "Labor, time, or expertise"
        case .material: return "Physical product you sell"
        case .fee:      return "Permit, disposal, passthrough"
        case .bundle:   return "Services + goods sold as one package"
        }
    }

    /// SF Symbol matching this category for kind picker / row leading icon.
    var iconName: String {
        switch self {
        case .service:  return "wrench.adjustable"
        case .material: return "cube.box"
        case .fee:      return "doc.text"
        case .bundle:   return "square.stack.3d.up"
        }
    }
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
    var thumbnailUrl: String?       // Supabase Storage public URL into the `product-thumbnails` bucket (nullable)
    var categoryId: String?         // FK to catalog_categories.id; populated alongside legacy `category` for new writes
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
    var linkedCatalogItemId: String?  // FK to catalog_items.id; non-nil when a Material product is wired into the stock catalog. Auto-deduction on sale ships with the next stock release.
    var bundlePricingMode: String?    // 'auto' | 'override' | nil for non-bundles. Mirrors products.bundle_pricing_mode.
    var createdAt: Date

    /// Convenience accessor that derives the user-facing 4-way category from
    /// the legacy `kind` + `type` columns. Use this anywhere the form needs
    /// to hydrate from an existing Product. The name kept as `category3Way`
    /// for callsite stability — the underlying taxonomy is now 4-way.
    var category3Way: ProductCategory {
        ProductCategory.from(type: type, kind: kind)
    }

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
        bundlePricingMode: String? = nil,
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
        self.bundlePricingMode = bundlePricingMode
        self.createdAt = createdAt
    }
}
