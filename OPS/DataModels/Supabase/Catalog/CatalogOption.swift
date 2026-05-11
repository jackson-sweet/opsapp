//
//  CatalogOption.swift
//  OPS
//
//  A variant axis on a CatalogItem (e.g., "Color" or "Mount Type").
//

import Foundation
import SwiftData

@Model
final class CatalogOption: Identifiable {
    @Attribute(.unique) var id: String
    var catalogItemId: String
    var name: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        catalogItemId: String,
        name: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.catalogItemId = catalogItemId
        self.name = name
        self.sortOrder = sortOrder
    }
}
