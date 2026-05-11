//
//  CatalogSnapshot.swift
//  OPS
//
//  Variant-aware historical snapshot of stock at a point in time.
//

import Foundation
import SwiftData

@Model
final class CatalogSnapshot: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var createdById: String?
    var isAutomatic: Bool
    var itemCount: Int
    var notes: String?
    var createdAt: Date

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        companyId: String,
        createdAt: Date = Date(),
        createdById: String? = nil,
        isAutomatic: Bool = false,
        itemCount: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.createdAt = createdAt
        self.createdById = createdById
        self.isAutomatic = isAutomatic
        self.itemCount = itemCount
        self.notes = notes
    }
}
