// OPS/OPS/DeckBuilder/Engine/VinylCatalogSelection.swift
//
// Shared catalog-selection helpers for vinyl ordering: the persisted-
// selection restore rule, variant display names, and the product/variant
// choice tree. Extracted verbatim from VinylOrderSheet so the bulk order
// wizard and the single-project sheet resolve colors identically. Pure —
// callers pass the catalog query results as arrays.

import Foundation

struct VinylCatalogProductChoice: Identifiable {
    let item: CatalogItem
    let variants: [CatalogVariant]

    var id: String { item.id }
}

enum VinylCatalogSelection {

    /// Pure resolution of the persisted vinyl selection against the live
    /// catalog, so a deactivated product/variant is dropped instead of silently
    /// restored. Static + primitive-typed for unit coverage.
    static func restoredSelection(
        configItemId: String?,
        configVariantId: String?,
        configColor: String?,
        availableItemIds: Set<String>,
        variantIdsByItem: [String: Set<String>]
    ) -> (itemId: String?, variantId: String?, color: String?) {
        let trimmedColor = configColor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = (trimmedColor?.isEmpty ?? true) ? nil : trimmedColor

        guard let itemId = configItemId, availableItemIds.contains(itemId) else {
            // No product (or a vanished one): keep the colour as free text so
            // the operator's note survives.
            return (nil, nil, color)
        }
        guard let variantId = configVariantId,
              variantIdsByItem[itemId]?.contains(variantId) == true else {
            // Product stands but the persisted variant is gone — force an
            // explicit re-pick rather than ordering a dead variant.
            return (itemId, nil, nil)
        }
        return (itemId, variantId, color)
    }

    static func variantDisplayName(
        _ variant: CatalogVariant,
        optionValues: [CatalogOptionValue],
        variantOptionValues: [CatalogVariantOptionValue]
    ) -> String {
        let optionValueIds = variantOptionValues
            .filter { $0.variantId == variant.id }
            .map(\.optionValueId)
        let optionValues = optionValues
            .filter { optionValueIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.value.localizedStandardCompare(rhs.value) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map(\.value)

        if !optionValues.isEmpty {
            return optionValues.joined(separator: " / ")
        }
        if let sku = variant.sku?.trimmingCharacters(in: .whitespacesAndNewlines), !sku.isEmpty {
            return sku
        }
        return "VARIANT"
    }

    static func productChoices(
        companyId: String,
        items: [CatalogItem],
        variants: [CatalogVariant],
        optionValues: [CatalogOptionValue],
        variantOptionValues: [CatalogVariantOptionValue]
    ) -> [VinylCatalogProductChoice] {
        let activeVariantsByItem = Dictionary(grouping: variants.filter { variant in
            variant.companyId == companyId
                && variant.isActive
                && variant.deletedAt == nil
        }, by: \.catalogItemId)

        return items
            .filter { item in
                item.companyId == companyId
                    && item.isActive
                    && item.deletedAt == nil
                    && !(activeVariantsByItem[item.id] ?? []).isEmpty
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { item in
                VinylCatalogProductChoice(
                    item: item,
                    variants: (activeVariantsByItem[item.id] ?? []).sorted { lhs, rhs in
                        variantDisplayName(lhs, optionValues: optionValues, variantOptionValues: variantOptionValues).localizedStandardCompare(variantDisplayName(rhs, optionValues: optionValues, variantOptionValues: variantOptionValues)) == .orderedAscending
                    }
                )
            }
    }
}
