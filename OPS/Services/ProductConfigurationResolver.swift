//
//  ProductConfigurationResolver.swift
//  OPS
//
//  Computes resolved_unit_price and resolved_options_label given a Product
//  and a configured_options map. Pure function — no side effects, no I/O.
//  Used by the line item form, the design→estimate adapter, and tests.
//

import Foundation

struct ProductConfigurationResolver {

    enum OptionValue {
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
                return "\(n) \(opt.name.lowercased())\(n == 1 ? "" : "s")"
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

/// Lightweight `Encodable` wrapper for snapshot serialization. Local to this resolver —
/// distinct from `RawJSONColumn` (DTO passthrough) and Supabase's `AnyJSON`.
struct AnyCodable: Encodable {
    let value: Any
    init(_ v: Any) { self.value = v }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String:  try c.encode(s)
        case let i as Int:     try c.encode(i)
        case let d as Double:  try c.encode(d)
        case let b as Bool:    try c.encode(b)
        default:               try c.encodeNil()
        }
    }
}
