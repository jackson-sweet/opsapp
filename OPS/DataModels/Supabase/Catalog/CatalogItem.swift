//
//  CatalogItem.swift
//  OPS
//
//  Variant family — one row per logical product (e.g., "Corner") that
//  may have N variants differing by option values. The family carries
//  default price/cost/threshold; variants can override per-SKU.
//

import Foundation
import SwiftData

@Model
final class CatalogItem: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var categoryId: String?
    var name: String
    var itemDescription: String?
    var defaultPrice: Double?
    var defaultUnitCost: Double?
    var defaultWarningThreshold: Double?
    var defaultCriticalThreshold: Double?
    var defaultUnitId: String?
    var imageUrl: String?
    var notes: String?
    var isActive: Bool

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        categoryId: String? = nil,
        defaultPrice: Double? = nil,
        defaultUnitCost: Double? = nil,
        defaultWarningThreshold: Double? = nil,
        defaultCriticalThreshold: Double? = nil,
        defaultUnitId: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.categoryId = categoryId
        self.defaultPrice = defaultPrice
        self.defaultUnitCost = defaultUnitCost
        self.defaultWarningThreshold = defaultWarningThreshold
        self.defaultCriticalThreshold = defaultCriticalThreshold
        self.defaultUnitId = defaultUnitId
        self.isActive = isActive
    }
}
