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

enum ProductBundleRelationshipKind: String, CaseIterable, Codable {
    case required
    case suggested
}

@Model
final class ProductBundleItem: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var bundleProductId: String
    var childProductId: String
    var quantity: Double
    var relationshipKind: ProductBundleRelationshipKind = ProductBundleRelationshipKind.required
    var suggestionReason: String?
    var compatibilitySelectorJSON: String?
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    /// Last successful round-trip to Supabase. Used by InboundProcessor merge
    /// to dedupe re-fetches. Matches the ProductMaterial pattern.
    var lastSyncedAt: Date?

    /// Pending local-only changes that haven't pushed yet. Outbound sync uses
    /// this; inbound merge skips rows where this is true so a stale server
    /// read doesn't clobber an in-flight local edit.
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        companyId: String,
        bundleProductId: String,
        childProductId: String,
        quantity: Double = 1,
        relationshipKind: ProductBundleRelationshipKind = .required,
        suggestionReason: String? = nil,
        compatibilitySelectorJSON: String? = nil,
        displayOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.bundleProductId = bundleProductId
        self.childProductId = childProductId
        self.quantity = quantity
        self.relationshipKind = relationshipKind
        self.suggestionReason = suggestionReason
        self.compatibilitySelectorJSON = compatibilitySelectorJSON
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
