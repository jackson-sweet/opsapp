//
//  CatalogItemTag.swift
//  OPS
//
//  Junction: CatalogItem (family) ↔ CatalogTag.
//

import Foundation
import SwiftData

@Model
final class CatalogItemTag {
    @Attribute(.unique) var id: String
    var catalogItemId: String
    var tagId: String

    var lastSyncedAt: Date?

    init(
        id: String = UUID().uuidString,
        catalogItemId: String,
        tagId: String
    ) {
        self.id = id
        self.catalogItemId = catalogItemId
        self.tagId = tagId
    }
}
