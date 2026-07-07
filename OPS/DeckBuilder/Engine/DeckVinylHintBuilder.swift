// OPS/OPS/DeckBuilder/Engine/DeckVinylHintBuilder.swift
//
// Builds the `productId → vinyl-hint` blob that `DeckVinylDetection`'s rule 3
// consumes. One shared builder so the three call sites (the deck-tab materials
// section, the Vinyl Order sheet, and the project-details MARK ORDERED path)
// resolve a product's vinyl signal identically and cannot drift.
//
// An assigned area item references the company's Products table by `productId`,
// NOT the stock catalog — `Product.id` and `CatalogItem.id` are different id
// spaces (a product links into the catalog via `Product.linkedCatalogItemId`, an
// FK to `catalog_items.id`). The hint keyed by `product.id` therefore folds the
// product's OWN name together with its LINKED catalog item's name + description,
// so a vinyl signal carried only by the linked catalog item still surfaces even
// when the product's own name omits "vinyl".

import Foundation

enum DeckVinylHintBuilder {

    /// `product.id → lowercased "<product name> <linked catalog name> <linked
    /// catalog description>"`. `catalogItems` are indexed by `CatalogItem.id` so
    /// each product's `linkedCatalogItemId` resolves its stock-catalog entry;
    /// products with no link (or a dangling one) fall back to their own name.
    static func build(products: [Product], catalogItems: [CatalogItem]) -> [String: String] {
        var catalogById: [String: CatalogItem] = [:]
        for item in catalogItems { catalogById[item.id] = item }

        var hints: [String: String] = [:]
        for product in products {
            var parts = [product.name]
            if let linkedId = product.linkedCatalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !linkedId.isEmpty,
               let linked = catalogById[linkedId] {
                parts.append(linked.name)
                if let description = linked.itemDescription { parts.append(description) }
            }
            hints[product.id] = parts.joined(separator: " ").lowercased()
        }
        return hints
    }
}
