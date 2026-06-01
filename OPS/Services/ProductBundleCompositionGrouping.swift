//
//  ProductBundleCompositionGrouping.swift
//  OPS
//

import Foundation

struct ProductBundleCompositionGroups {
    let required: [ProductBundleItem]
    let suggested: [ProductBundleItem]
}

enum ProductBundleCompositionGrouping {
    static func group(_ items: [ProductBundleItem]) -> ProductBundleCompositionGroups {
        let ordered = items
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.displayOrder != rhs.displayOrder {
                    return lhs.displayOrder < rhs.displayOrder
                }
                return lhs.id < rhs.id
            }

        return ProductBundleCompositionGroups(
            required: ordered.filter { $0.relationshipKind == .required },
            suggested: ordered.filter { $0.relationshipKind == .suggested }
        )
    }

    static func requiredRollupTotal(
        _ items: [ProductBundleItem],
        productsById: [String: Product]
    ) -> Double {
        group(items).required.reduce(0) { total, item in
            guard let product = productsById[item.childProductId] else { return total }
            return total + (product.basePrice * item.quantity)
        }
    }
}
