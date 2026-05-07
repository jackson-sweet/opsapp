//
//  ProductOption.swift
//  OPS
//
//  Configuration knob on a Product. Affects price, recipe, or both.
//

import Foundation
import SwiftData

enum ProductOptionKind: String, CaseIterable, Codable {
    case select
    case integer
    case boolean
}

@Model
final class ProductOption: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var name: String
    var kind: ProductOptionKind
    var affectsPrice: Bool
    var affectsRecipe: Bool
    var required: Bool
    var defaultValue: String?
    var optionDefaultSource: String?    // e.g. "$design.color"
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        productId: String,
        name: String,
        kind: ProductOptionKind,
        affectsPrice: Bool = false,
        affectsRecipe: Bool = false,
        required: Bool = true,
        defaultValue: String? = nil,
        optionDefaultSource: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.kind = kind
        self.affectsPrice = affectsPrice
        self.affectsRecipe = affectsRecipe
        self.required = required
        self.defaultValue = defaultValue
        self.optionDefaultSource = optionDefaultSource
        self.sortOrder = sortOrder
    }
}
