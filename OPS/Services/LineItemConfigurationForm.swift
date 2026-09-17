//
//  LineItemConfigurationForm.swift
//  OPS
//
//  The line item editor's rules for a configurable product's options, kept out
//  of the view so they are provable without SwiftUI.
//
//  A count option (end posts, corners, wall returns) is the job's geometry. The
//  recipe books material per unit of it, and estimate acceptance refuses a line
//  whose count is blank — but acceptance cannot tell a real "no corners" from a
//  0 the editor filled in. So the editor never fills a count: not from the
//  catalogue's `default_value`, not with a fallback 0. A blank count stays blank
//  until the operator enters a number, an entered 0 is kept, and a required
//  option left blank stops the save by name.
//
//  Select and boolean options keep seeding their defaults, as they always have.
//  Mirrors the web editor (ops-web `resolveProductConfiguration`, 2026-09-17).
//

import Foundation

enum LineItemConfigurationForm {
    typealias OptionValue = ProductConfigurationResolver.OptionValue

    enum SaveGate: Equatable {
        case ready
        case blocked(missingOptionIds: [String])
    }

    /// The count control's bounds: 0 is the floor (a real answer, never a
    /// blank), 999 the ceiling.
    static let countRange = 0...999

    static let blockedTitle = "// NOT ENTERED"

    // MARK: - Starting values

    /// Fills what a NEW line starts with. Everything already on the line is
    /// kept. A select takes the value named by its default, or its first value
    /// when the default names none. A boolean takes its default, or `false`.
    /// A count is never filled.
    static func seeded(
        _ configured: [String: OptionValue],
        options: [ProductOption],
        optionValues: [ProductOptionValue]
    ) -> [String: OptionValue] {
        var result = configured
        for option in options where result[option.id] == nil {
            switch option.kind {
            case .select:
                let values = sortedValues(for: option, in: optionValues)
                if let match = values.first(where: { $0.value == option.defaultValue }) ?? values.first {
                    result[option.id] = .selectId(match.id)
                }
            case .boolean:
                result[option.id] = .boolean((option.defaultValue ?? "false").lowercased() == "true")
            case .integer:
                continue
            }
        }
        return result
    }

    /// What an EXISTING line opens with: its stored snapshot, with a count read
    /// only when the snapshot carries a whole number for it (a legacy integer
    /// string such as `"2"` included), then seeded like a new line. A count the
    /// snapshot never carried, or carries in a form that is not a whole number,
    /// opens blank.
    static func hydrated(
        snapshotJSON: String?,
        options: [ProductOption],
        optionValues: [ProductOptionValue]
    ) -> [String: OptionValue] {
        var configured = snapshotJSON.map(ProductConfigurationResolver.decodeConfiguredOptions) ?? [:]
        for option in options where option.kind == .integer {
            guard let stored = configured[option.id] else { continue }
            switch stored {
            case .integer:
                continue
            case .selectId(let text):
                configured[option.id] = ProductConfigurationResolver.wholeCount(from: text).map(OptionValue.integer)
            case .boolean:
                configured[option.id] = nil
            }
        }
        return seeded(configured, options: options, optionValues: optionValues)
    }

    // MARK: - Required options

    /// Required options the line has no usable value for, in the order the
    /// editor lists them. A value of the wrong kind, or a select pointing at a
    /// value the option does not have, is not a usable value.
    static func missingRequiredOptions(
        options: [ProductOption],
        optionValues: [ProductOptionValue],
        configured: [String: OptionValue]
    ) -> [ProductOption] {
        displayOrder(options).filter { option in
            option.required && !hasUsableValue(option, optionValues: optionValues, configured: configured)
        }
    }

    static func saveGate(
        options: [ProductOption],
        optionValues: [ProductOptionValue],
        configured: [String: OptionValue]
    ) -> SaveGate {
        let missing = missingRequiredOptions(options: options, optionValues: optionValues, configured: configured)
        return missing.isEmpty ? .ready : .blocked(missingOptionIds: missing.map(\.id))
    }

    /// The line under `blockedTitle`: every missing option by its catalogue
    /// name, then what the refusal is about.
    static func blockedMessage(for missing: [ProductOption]) -> String {
        "\(missing.map(\.name).joined(separator: ", ")). Required to save."
    }

    // MARK: - Count control

    /// The entered count for an option, or nil while it is blank.
    static func count(in configured: [String: OptionValue], optionId: String) -> Int? {
        if case .integer(let n) = configured[optionId] { return n }
        return nil
    }

    /// Minus from blank enters 0 — the one-tap answer for "none".
    static func decremented(_ count: Int?) -> Int {
        guard let count else { return countRange.lowerBound }
        return max(countRange.lowerBound, count - 1)
    }

    /// Plus from blank enters 1.
    static func incremented(_ count: Int?) -> Int {
        guard let count else { return countRange.lowerBound + 1 }
        return min(countRange.upperBound, count + 1)
    }

    static func canDecrement(_ count: Int?) -> Bool {
        guard let count else { return true }
        return count > countRange.lowerBound
    }

    static func canIncrement(_ count: Int?) -> Bool {
        guard let count else { return true }
        return count < countRange.upperBound
    }

    // MARK: - Saved snapshot

    /// The `configured_options` JSON the line saves. A blank count has no key;
    /// an entered 0 is the JSON number 0. Nil when nothing is configured.
    static func snapshotJSON(_ configured: [String: OptionValue]) -> String? {
        CatalogEstimateMerger.encodeConfiguredOptions(configured)?.rawJSONString
    }

    // MARK: - Helpers

    static func displayOrder(_ options: [ProductOption]) -> [ProductOption] {
        options.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    static func sortedValues(for option: ProductOption, in optionValues: [ProductOptionValue]) -> [ProductOptionValue] {
        optionValues
            .filter { $0.optionId == option.id }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    private static func hasUsableValue(
        _ option: ProductOption,
        optionValues: [ProductOptionValue],
        configured: [String: OptionValue]
    ) -> Bool {
        switch (option.kind, configured[option.id]) {
        case (.select, .selectId(let id)?):
            return optionValues.contains { $0.optionId == option.id && $0.id == id }
        case (.integer, .integer?), (.boolean, .boolean?):
            return true
        default:
            return false
        }
    }
}
