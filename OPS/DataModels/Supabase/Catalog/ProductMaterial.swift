//
//  ProductMaterial.swift
//  OPS
//
//  Recipe row: how much of which catalog variant (or family + selector)
//  a Product consumes per unit. Resolves at install task creation.
//

import Foundation
import SwiftData

@Model
final class ProductMaterial: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var catalogVariantId: String?       // pinned variant
    var catalogItemId: String?          // family head (resolved via selector)
    var variantSelectorJSON: String?    // jsonb stored as JSON string
    var quantityPerUnit: Double
    var scaledByOptionId: String?
    var unitId: String?
    var notes: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        productId: String,
        catalogVariantId: String? = nil,
        catalogItemId: String? = nil,
        variantSelectorJSON: String? = nil,
        quantityPerUnit: Double,
        scaledByOptionId: String? = nil,
        unitId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.productId = productId
        self.catalogVariantId = catalogVariantId
        self.catalogItemId = catalogItemId
        self.variantSelectorJSON = variantSelectorJSON
        self.quantityPerUnit = quantityPerUnit
        self.scaledByOptionId = scaledByOptionId
        self.unitId = unitId
        self.notes = notes
    }
}
