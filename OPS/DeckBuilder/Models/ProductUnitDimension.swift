//
//  ProductUnitDimension.swift
//  OPS
//
//  Three-tier resolution of a Product's unit dimension (length / area /
//  other). Used by MaterialPickerSheet to filter the picker, and by
//  AssignmentWheelView to populate its slot list with the right kind of
//  catalog product per selection context. Centralised here because the
//  three-path fallback chain (catalog_units join → ProductPricingUnit
//  enum → legacy `unit` text) is non-trivial and we want both call sites
//  to behave identically. Bug ee787f29.
//

import Foundation

enum ProductUnitDimension {
    case length
    case area
    case other
}

enum ProductUnitResolver {
    /// Resolves a Product's true dimension via catalog_units.dimension when
    /// possible, then ProductPricingUnit, then legacy free-text. The catalog
    /// path is authoritative — both iOS and ops-web populate Product.unitId
    /// when creating products. The pricing-unit path catches iOS-created
    /// products that wrote the enum but somehow lost the FK. The text path
    /// is the last-resort hammer for products that predate the catalog rollout.
    static func dimension(
        of product: Product,
        catalogUnits: [CatalogUnit]
    ) -> ProductUnitDimension {
        if let uid = product.unitId, !uid.isEmpty,
           let unit = catalogUnits.first(where: { $0.id == uid && $0.deletedAt == nil }) {
            switch unit.dimension.lowercased() {
            case "length": return .length
            case "area":   return .area
            default:       return .other
            }
        }
        switch product.pricingUnit {
        case .linearFoot: return .length
        case .sqft:       return .area
        default:          break
        }
        if let raw = product.unit?.lowercased().trimmingCharacters(in: .whitespaces) {
            let lengthPatterns: [String] = [
                "linear", "lin ft", "lf", "linear meter", "lm", "linear_ft"
            ]
            let areaPatterns: [String] = [
                "sq ft", "sqft", "sq_ft", "square foot", "square_foot", "sf",
                "sq meter", "square meter", "sm", "m²", "ft²"
            ]
            if lengthPatterns.contains(where: { raw.contains($0) }) { return .length }
            if areaPatterns.contains(where: { raw.contains($0) }) { return .area }
        }
        return .other
    }
}
