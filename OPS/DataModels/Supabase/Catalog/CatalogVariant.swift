//
//  CatalogVariant.swift
//  OPS
//
//  The concrete SKU. Belongs to a CatalogItem (family) and references
//  one CatalogOptionValue per CatalogOption on that family.
//

import Foundation
import SwiftData

enum ThresholdStatus: String, CaseIterable, Comparable {
    case normal
    case warning
    case critical

    static func < (lhs: ThresholdStatus, rhs: ThresholdStatus) -> Bool {
        let order: [ThresholdStatus: Int] = [.normal: 0, .warning: 1, .critical: 2]
        return (order[lhs] ?? 0) < (order[rhs] ?? 0)
    }
}

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
