//
//  CatalogOrderItem.swift
//  OPS
//

import Foundation
import SwiftData

@Model
final class CatalogOrderItem: Identifiable {
    @Attribute(.unique) var id: String
    var orderId: String
    var catalogVariantId: String
    var quantityRequested: Double
    var costPerUnit: Double?
    var notes: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        orderId: String,
        catalogVariantId: String,
        quantityRequested: Double,
        costPerUnit: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.catalogVariantId = catalogVariantId
        self.quantityRequested = quantityRequested
        self.costPerUnit = costPerUnit
        self.notes = notes
    }
}
