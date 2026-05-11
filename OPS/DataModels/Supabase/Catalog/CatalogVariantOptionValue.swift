//
//  CatalogVariantOptionValue.swift
//  OPS
//
//  Junction: CatalogVariant ↔ CatalogOptionValue. Each variant has
//  exactly one row per CatalogOption on its family.
//

import Foundation
import SwiftData

@Model
final class CatalogVariantOptionValue {
    var variantId: String
    var optionValueId: String

    var lastSyncedAt: Date?

    init(variantId: String, optionValueId: String) {
        self.variantId = variantId
        self.optionValueId = optionValueId
    }
}
