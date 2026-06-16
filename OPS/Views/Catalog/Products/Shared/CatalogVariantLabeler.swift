//
//  CatalogVariantLabeler.swift
//  OPS
//
//  One canonical human label for a CatalogVariant, composed from its option
//  values (e.g. "Top rail · Black · 60mil"). Replaces the divergent per-sheet
//  copies — the guided-setup material picker, the product recipe picker, and the
//  stock list should all read a variant the same way. Falls back to
//  "family · SKU", then the bare family name.
//

import Foundation

enum CatalogVariantLabeler {

    /// Compose "family · value · value" in family option sort order. The label
    /// is the option-value combo (what a tradesperson actually distinguishes by),
    /// never the raw SKU — falling back to SKU only when a variant has no options.
    static func label(for variant: CatalogVariant,
                      families: [CatalogItem],
                      options: [CatalogOption],
                      optionValues: [CatalogOptionValue],
                      variantOptionValues: [CatalogVariantOptionValue]) -> String {
        let familyName = families.first { $0.id == variant.catalogItemId }?.name ?? "Item"

        let familyOptions = options
            .filter { $0.catalogItemId == variant.catalogItemId }
            .sorted { $0.sortOrder < $1.sortOrder }
        let myValueIds = Set(variantOptionValues
            .filter { $0.variantId == variant.id }
            .map(\.optionValueId))
        let valuesById = Dictionary(uniqueKeysWithValues: optionValues.map { ($0.id, $0) })

        var parts: [String] = []
        for option in familyOptions {
            if let value = myValueIds.compactMap({ valuesById[$0] }).first(where: { $0.optionId == option.id }) {
                parts.append(value.value)
            }
        }
        if !parts.isEmpty { return "\(familyName) · \(parts.joined(separator: " · "))" }
        if let sku = variant.sku, !sku.isEmpty { return "\(familyName) · \(sku)" }
        return familyName
    }
}
