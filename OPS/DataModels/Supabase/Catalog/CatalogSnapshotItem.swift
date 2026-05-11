//
//  CatalogSnapshotItem.swift
//  OPS
//

import Foundation
import SwiftData

@Model
final class CatalogSnapshotItem: Identifiable {
    @Attribute(.unique) var id: String
    var snapshotId: String
    var originalVariantId: String?
    var familyName: String              // denormalized
    var variantLabel: String?           // e.g., "Black · Topmount"
    var quantity: Double
    var unitDisplay: String?
    var sku: String?
    var itemDescription: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        snapshotId: String,
        originalVariantId: String? = nil,
        familyName: String,
        variantLabel: String? = nil,
        quantity: Double = 0,
        unitDisplay: String? = nil,
        sku: String? = nil,
        itemDescription: String? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.originalVariantId = originalVariantId
        self.familyName = familyName
        self.variantLabel = variantLabel
        self.quantity = quantity
        self.unitDisplay = unitDisplay
        self.sku = sku
        self.itemDescription = itemDescription
    }
}
