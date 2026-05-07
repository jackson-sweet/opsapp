//
//  CatalogVariant.swift
//  OPS
//
//  The concrete SKU. Belongs to a CatalogItem (family) and references
//  one CatalogOptionValue per CatalogOption on that family.
//

import Foundation
import SwiftData

// NOTE: `ThresholdStatus` is defined in `InventoryItem.swift` for now.
// When that file is deleted (Phase 4 / Task 41), move the enum to a
// dedicated `OPS/DataModels/Enums/ThresholdStatus.swift` file or
// reintroduce it here.

@Model
final class CatalogVariant: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var catalogItemId: String
    var sku: String?
    var quantity: Double
    var priceOverride: Double?
    var unitCostOverride: Double?
    var warningThreshold: Double?
    var criticalThreshold: Double?
    var unitId: String?
    var isActive: Bool

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        catalogItemId: String,
        sku: String? = nil,
        quantity: Double = 0,
        priceOverride: Double? = nil,
        unitCostOverride: Double? = nil,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil,
        unitId: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.companyId = companyId
        self.catalogItemId = catalogItemId
        self.sku = sku
        self.quantity = quantity
        self.priceOverride = priceOverride
        self.unitCostOverride = unitCostOverride
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.unitId = unitId
        self.isActive = isActive
    }
}
