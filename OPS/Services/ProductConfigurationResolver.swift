//
//  ProductConfigurationResolver.swift
//  OPS
//
//  Computes resolved_unit_price and resolved_options_label given a Product
//  and a configured_options map. Pure function — no side effects, no I/O.
//  Used by the line item form, the design→estimate adapter, and tests.
//

import Foundation
import DeckKit

struct ProductConfigurationResolver {

    enum OptionValue: Equatable {
        case selectId(String)   // Points at a ProductOptionValue.id
        case integer(Int)
        case boolean(Bool)
    }

    struct Resolution {
        let unitPrice: Double
        let label: String
        /// Configured options, normalized for snapshot serialization to JSON.
        let serializedOptions: [String: AnyCodable]
    }

    func resolve(
        product: Product,
        options: [ProductOption],
        optionValues: [ProductOptionValue],
        modifiers: [ProductPricingModifier],
        configured: [String: OptionValue]
    ) -> Resolution {
        var price = product.basePrice
        for mod in modifiers {
            guard let configValue = configured[mod.optionId] else { continue }
            guard fires(modifier: mod, value: configValue) else { continue }
            switch mod.modifierKind {
            case .addPerUnit:
                price += mod.amount
            case .addFlat:
                price += mod.amount
            case .addPerCount:
                if case .integer(let n) = configValue {
                    price += mod.amount * Double(n)
                }
            case .multiplyUnitPrice:
                price *= mod.amount
            }
        }

        let labelParts = options.sorted { $0.sortOrder < $1.sortOrder }.compactMap { opt -> String? in
            guard let v = configured[opt.id] else { return nil }
            switch v {
            case .selectId(let id):
                return optionValues.first { $0.id == id }?.value
            case .integer(let n):
                if n == 0 { return nil }
                let lower = opt.name.lowercased()
                // Don't double-pluralize: "Corners" (plural option name)
                // → "4 corners", not "4 cornerss". Single-form names like
                // "Corner" still pluralize → "4 corners".
                let needsTrailingS = !lower.hasSuffix("s") && n != 1
                return "\(n) \(lower)\(needsTrailingS ? "s" : "")"
            case .boolean(let b):
                return b ? opt.name : nil
            }
        }
        let label = labelParts.joined(separator: " · ")

        var serialized: [String: AnyCodable] = [:]
        for (key, value) in configured {
            switch value {
            case .selectId(let id): serialized[key] = AnyCodable(id)
            case .integer(let n):   serialized[key] = AnyCodable(n)
            case .boolean(let b):   serialized[key] = AnyCodable(b)
            }
        }

        return Resolution(unitPrice: price, label: label, serializedOptions: serialized)
    }

    private func fires(modifier: ProductPricingModifier, value: OptionValue) -> Bool {
        if let triggerId = modifier.triggerValueId {
            if case .selectId(let id) = value, id == triggerId { return true }
            return false
        }
        if let minN = modifier.triggerIntMin {
            if case .integer(let n) = value {
                if let maxN = modifier.triggerIntMax {
                    return n >= minN && n <= maxN
                }
                return n >= minN
            }
        }
        return false
    }
}

// `AnyCodable` lives in `OPS/DeckBuilder/Engine/ComponentEmitter.swift`.
// The components-projection emitter and this resolver share the same
// scalar Codable wrapper — kept in one place so encode + decode behave
// identically on either side of the line_item snapshot boundary.
