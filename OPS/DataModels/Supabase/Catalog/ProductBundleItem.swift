//
//  ProductBundleItem.swift
//  OPS
//
//  Child row of a bundle product. Bundle = Product with kind=.package; rows
//  here enumerate the bundle's children with per-row quantity + display
//  order. Persists locally for offline reads of bundle composition; syncs
//  to public.product_bundle_items via ProductBundleItemRepository.
//

import Foundation
import SwiftData

@Model
final class ProductBundleItem: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var bundleProductId: String
    var childProductId: String
    var quantity: Double
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        bundleProductId: String,
        childProductId: String,
        quantity: Double = 1,
        displayOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.bundleProductId = bundleProductId
        self.childProductId = childProductId
        self.quantity = quantity
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
