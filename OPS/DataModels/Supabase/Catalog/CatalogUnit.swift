//
//  CatalogUnit.swift
//  OPS
//
//  Unit of measure for catalog variants (replaces InventoryUnit).
//

import Foundation
import SwiftData

@Model
final class CatalogUnit: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var display: String          // e.g., "ea", "box", "ft"
    var abbreviation: String?
    var dimension: String        // 'count' | 'length' | 'area' | 'volume' | 'mass' | 'time'
    var isDefault: Bool
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        display: String,
        abbreviation: String? = nil,
        dimension: String = "count",
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.companyId = companyId
        self.display = display
        self.abbreviation = abbreviation
        self.dimension = dimension
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }
}
