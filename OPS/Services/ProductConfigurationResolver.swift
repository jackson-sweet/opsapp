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

    // MARK: - configured_options snapshot decoding

    /// Decodes a line item's `configured_options` JSON snapshot into typed
    /// option values. The single decoder for every reader (cut-list
    /// materialization, the line item editor) so they cannot drift.
    ///
    /// Wire format (written by `CatalogEstimateMerger.encodeConfiguredOptions`
    /// and the web editor):
    ///   - select kinds: `"<option_id>": "<option_value_id>"` (string)
    ///   - integer kinds: `"<option_id>": <number>` — integral values only
    ///   - boolean kinds: `"<option_id>": <bool>`
    ///
    /// `JSONSerialization` hands back JSON booleans as `NSNumber`s that
    /// `as? Int` reads as 0/1, so the CFBoolean check runs first. A
    /// non-integral number (`2.5`) is not a count and is left absent rather
    /// than truncated. Malformed JSON or a non-object root decodes to `[:]`.
    static func decodeConfiguredOptions(_ json: String) -> [String: OptionValue] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: OptionValue] = [:]
        for (key, raw) in object {
            if let s = raw as? String {
                result[key] = .selectId(s)
            } else if let number = raw as? NSNumber {
                if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                    result[key] = .boolean(number.boolValue)
                } else if let n = raw as? Int {
                    result[key] = .integer(n)
                } else {
                    let d = number.doubleValue
                    if d.isFinite,
                       d.rounded(.towardZero) == d,
                       d >= Double(Int.min), d < Double(Int.max) {
                        result[key] = .integer(Int(d))
                    }
                }
            }
        }
        return result
    }

    /// A whole count from an untyped value: a JSON integer, a whole-valued JSON
    /// number (`1.0`), or an integer string (`"2"`, surrounding whitespace
    /// allowed). A fractional number, a boolean, empty or other text, or no
    /// value at all is not a count — the caller leaves the count blank rather
    /// than guessing one. `JSONSerialization` hands booleans back as
    /// `NSNumber`s that `as? Int` reads as 0/1, so the CFBoolean check runs first.
    static func wholeCount(from raw: Any?) -> Int? {
        switch raw {
        case let number as NSNumber:
            guard CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            guard value.isFinite,
                  value.rounded(.towardZero) == value,
                  value >= Double(Int.min), value < Double(Int.max) else { return nil }
            return Int(value)
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.range(of: #"^-?[0-9]+$"#, options: .regularExpression) != nil else { return nil }
            return Int(trimmed)
        default:
            return nil
        }
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
