//
//  CatalogCategory.swift
//  OPS
//
//  Nested category for catalog items (parent_id self-FK, 2-level UI max).
//

import Foundation
import SwiftData

@Model
final class CatalogCategory: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var parentId: String?
    var sortOrder: Int
    var colorHex: String?
    var defaultWarningThreshold: Double?
    var defaultCriticalThreshold: Double?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        parentId: String? = nil,
        sortOrder: Int = 0,
        colorHex: String? = nil,
        defaultWarningThreshold: Double? = nil,
        defaultCriticalThreshold: Double? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.defaultWarningThreshold = defaultWarningThreshold
        self.defaultCriticalThreshold = defaultCriticalThreshold
    }
}
