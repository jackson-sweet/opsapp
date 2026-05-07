//
//  ProductPricingModifier.swift
//  OPS
//
//  A rule that bumps price based on an option's value (or integer count).
//

import Foundation
import SwiftData

enum PricingModifierKind: String, CaseIterable, Codable {
    case addPerUnit = "add_per_unit"
    case addFlat = "add_flat"
    case addPerCount = "add_per_count"
    case multiplyUnitPrice = "multiply_unit_price"
}

@Model
final class ProductPricingModifier: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var optionId: String
    var triggerValueId: String?         // when option is select-kind
    var triggerIntMin: Int?             // when option is integer-kind
    var triggerIntMax: Int?
    var modifierKind: PricingModifierKind
    var amount: Double

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        productId: String,
        optionId: String,
        triggerValueId: String? = nil,
        triggerIntMin: Int? = nil,
        triggerIntMax: Int? = nil,
        modifierKind: PricingModifierKind,
        amount: Double
    ) {
        self.id = id
        self.productId = productId
        self.optionId = optionId
        self.triggerValueId = triggerValueId
        self.triggerIntMin = triggerIntMin
        self.triggerIntMax = triggerIntMax
        self.modifierKind = modifierKind
        self.amount = amount
    }
}
