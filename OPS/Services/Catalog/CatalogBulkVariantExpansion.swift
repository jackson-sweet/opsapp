//
//  CatalogBulkVariantExpansion.swift
//  OPS
//
//  Pure planning and validation for expanding one option axis across existing
//  catalog families. The server repeats these checks before committing.
//

import CryptoKit
import Foundation

struct CatalogBulkOptionValueSnapshot: Codable, Equatable, Hashable, Sendable {
    let id: String
    let value: String
    let sortOrder: Int
}

struct CatalogBulkOptionSnapshot: Codable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let sortOrder: Int
    let values: [CatalogBulkOptionValueSnapshot]
}

struct CatalogBulkVariantSnapshot: Codable, Equatable, Hashable, Sendable {
    let id: String
    let sku: String?
    let quantity: Double
    let priceOverride: Double?
    let unitCostOverride: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitId: String?
    let isActive: Bool
    let optionValueIds: [String]
}

struct CatalogBulkFamilySnapshot: Codable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let options: [CatalogBulkOptionSnapshot]
    let variants: [CatalogBulkVariantSnapshot]
}

struct CatalogBulkVariantExpansionInput: Equatable, Sendable {
    let axisName: String
    let existingValue: String
    let newValues: [String]
    let families: [CatalogBulkFamilySnapshot]
}

struct CatalogBulkVariantExpansionBlocker: Equatable, Identifiable, Sendable {
    let code: String
    let message: String
    let familyId: String?

    var id: String { "\(familyId ?? "global"):\(code)" }
}

struct CatalogBulkVariantOptionSelection: Codable, Equatable, Hashable, Sendable {
    let optionName: String
    let value: String
}

struct CatalogBulkExistingVariantAssignment: Codable, Equatable, Hashable, Sendable {
    let variantId: String
}

struct CatalogBulkNewVariantPlan: Codable, Equatable, Hashable, Sendable {
    let sourceVariantId: String
    let newValue: String
    let sku: String?
    let quantity: Double
    let priceOverride: Double?
    let unitCostOverride: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitId: String?
    let isActive: Bool
    let optionSelections: [CatalogBulkVariantOptionSelection]
}

struct CatalogBulkFamilyExpansionPlan: Codable, Equatable, Sendable {
    let familyId: String
    let familyName: String
    let targetOptionId: String?
    let resolvedExistingValueId: String?
    let resolvedNewValueIds: [String: String]
    let existingAssignments: [CatalogBulkExistingVariantAssignment]
    let newVariants: [CatalogBulkNewVariantPlan]
    let skippedExistingCombinationCount: Int
    let sourceFingerprint: String
    let source: CatalogBulkFamilySnapshot
}

struct CatalogBulkVariantExpansionPreview: Equatable, Sendable {
    let axisName: String
    let existingValue: String
    let newValues: [String]
    let familyPlans: [CatalogBulkFamilyExpansionPlan]
    let blockers: [CatalogBulkVariantExpansionBlocker]

    var familyCount: Int { familyPlans.count }
    var existingVariantAssignmentCount: Int {
        familyPlans.reduce(0) { $0 + $1.existingAssignments.count }
    }
    var newVariantCount: Int {
        familyPlans.reduce(0) { $0 + $1.newVariants.count }
    }
    var canApply: Bool { blockers.isEmpty && newVariantCount > 0 }
}

enum CatalogBulkVariantExpansionPlanner {
    static func makePreview(
        _ input: CatalogBulkVariantExpansionInput
    ) -> CatalogBulkVariantExpansionPreview {
        let axisName = clean(input.axisName)
        let existingValue = clean(input.existingValue)
        let newValues = input.newValues.map(clean)

        if axisName.isEmpty {
            return blocked(
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues,
                code: "axis_name_required",
                message: "Enter an option name."
            )
        }
        if existingValue.isEmpty {
            return blocked(
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues,
                code: "existing_value_required",
                message: "Enter the value your current variants use."
            )
        }
        if newValues.isEmpty || newValues.contains(where: \.isEmpty) {
            return blocked(
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues,
                code: "new_value_required",
                message: "Add at least one new value."
            )
        }

        let normalizedNewValues = newValues.map(normalize)
        if Set(normalizedNewValues).count != normalizedNewValues.count {
            return blocked(
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues,
                code: "duplicate_new_value",
                message: "Each new value must be unique."
            )
        }
        if normalizedNewValues.contains(normalize(existingValue)) {
            return blocked(
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues,
                code: "new_value_matches_existing",
                message: "A new value matches the existing value."
            )
        }
        if input.families.isEmpty {
            return blocked(
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues,
                code: "families_required",
                message: "Select at least one stock family."
            )
        }

        let sortedFamilies = input.families.sorted {
            let nameOrder = clean($0.name).localizedCaseInsensitiveCompare(clean($1.name))
            return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
        }
        var plans: [CatalogBulkFamilyExpansionPlan] = []
        var blockers: [CatalogBulkVariantExpansionBlocker] = []

        for family in sortedFamilies {
            switch planFamily(
                family,
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues
            ) {
            case .success(let plan):
                plans.append(plan)
            case .failure(let error):
                blockers.append(error.blocker)
            }
        }

        let preview = CatalogBulkVariantExpansionPreview(
            axisName: axisName,
            existingValue: existingValue,
            newValues: newValues,
            familyPlans: plans,
            blockers: blockers
        )
        if blockers.isEmpty && preview.newVariantCount == 0 {
            return CatalogBulkVariantExpansionPreview(
                axisName: axisName,
                existingValue: existingValue,
                newValues: newValues,
                familyPlans: plans,
                blockers: [
                    .init(
                        code: "no_variants_to_add",
                        message: "Those variant combinations already exist.",
                        familyId: nil
                    )
                ]
            )
        }
        return preview
    }

    private static func planFamily(
        _ family: CatalogBulkFamilySnapshot,
        axisName: String,
        existingValue: String,
        newValues: [String]
    ) -> Result<CatalogBulkFamilyExpansionPlan, FamilyPlanningError> {
        let options = family.options.sorted(by: optionOrder)
        let variants = family.variants.filter(\.isActive).sorted { $0.id < $1.id }
        let familyName = clean(family.name)

        let targetOptions = options.filter { normalize($0.name) == normalize(axisName) }
        if targetOptions.count > 1 {
            return .failure(.init(blocker: .init(
                code: "duplicate_option_axis",
                message: "\(familyName) has more than one option named \(axisName).",
                familyId: family.id
            )))
        }

        let allKnownValueIds = Set(options.flatMap(\.values).map(\.id))
        for variant in variants where !Set(variant.optionValueIds).isSubset(of: allKnownValueIds) {
            return .failure(.init(blocker: .init(
                code: "unknown_option_value",
                message: "\(familyName) has a variant linked to an unknown option value.",
                familyId: family.id
            )))
        }

        var pinsByVariant: [String: [String: CatalogBulkOptionValueSnapshot]] = [:]
        for variant in variants {
            var pins: [String: CatalogBulkOptionValueSnapshot] = [:]
            let selected = Set(variant.optionValueIds)
            for option in options {
                let matches = option.values.filter { selected.contains($0.id) }
                if matches.isEmpty {
                    return .failure(.init(blocker: .init(
                        code: "incomplete_variant_options",
                        message: "\(familyName) has a variant missing an option value.",
                        familyId: family.id
                    )))
                }
                if matches.count > 1 {
                    return .failure(.init(blocker: .init(
                        code: "multiple_values_for_option",
                        message: "\(familyName) has a variant with multiple values for one option.",
                        familyId: family.id
                    )))
                }
                pins[option.id] = matches[0]
            }
            pinsByVariant[variant.id] = pins
        }

        var variantBySignature: [String: CatalogBulkVariantSnapshot] = [:]
        for variant in variants {
            let signature = signatureForExistingVariant(
                pinsByVariant[variant.id] ?? [:],
                options: options
            )
            if variantBySignature[signature] != nil {
                return .failure(.init(blocker: .init(
                    code: "duplicate_variant_signature",
                    message: "\(familyName) has duplicate variant combinations.",
                    familyId: family.id
                )))
            }
            variantBySignature[signature] = variant
        }

        guard let targetOption = targetOptions.first else {
            let assignments = variants.map {
                CatalogBulkExistingVariantAssignment(variantId: $0.id)
            }
            let clones = variants.flatMap { source in
                newValues.map { newValue in
                    clone(
                        source,
                        selections: selections(
                            for: source,
                            pinsByVariant: pinsByVariant,
                            options: options
                        ) + [.init(optionName: axisName, value: newValue)],
                        newValue: newValue
                    )
                }
            }
            return .success(.init(
                familyId: family.id,
                familyName: familyName,
                targetOptionId: nil,
                resolvedExistingValueId: nil,
                resolvedNewValueIds: [:],
                existingAssignments: assignments,
                newVariants: clones,
                skippedExistingCombinationCount: 0,
                sourceFingerprint: fingerprint(family),
                source: family
            ))
        }

        let existingMatches = targetOption.values.filter {
            normalize($0.value) == normalize(existingValue)
        }
        if existingMatches.count > 1 {
            return .failure(.init(blocker: .init(
                code: "duplicate_option_value",
                message: "\(familyName) has duplicate values for \(axisName).",
                familyId: family.id
            )))
        }
        guard let resolvedExisting = existingMatches.first else {
            return .failure(.init(blocker: .init(
                code: "existing_value_missing",
                message: "\(familyName) does not have \(existingValue) under \(axisName).",
                familyId: family.id
            )))
        }

        var resolvedNewValueIds: [String: String] = [:]
        for newValue in newValues {
            let matches = targetOption.values.filter {
                normalize($0.value) == normalize(newValue)
            }
            if matches.count > 1 {
                return .failure(.init(blocker: .init(
                    code: "duplicate_option_value",
                    message: "\(familyName) has duplicate values for \(axisName).",
                    familyId: family.id
                )))
            }
            if let match = matches.first {
                resolvedNewValueIds[normalize(newValue)] = match.id
            }
        }

        let sources = variants.filter {
            pinsByVariant[$0.id]?[targetOption.id]?.id == resolvedExisting.id
        }
        var clones: [CatalogBulkNewVariantPlan] = []
        var skipped = 0
        for source in sources {
            for newValue in newValues {
                var desiredPins = pinsByVariant[source.id] ?? [:]
                if let resolvedId = resolvedNewValueIds[normalize(newValue)],
                   let resolved = targetOption.values.first(where: { $0.id == resolvedId }) {
                    desiredPins[targetOption.id] = resolved
                    let signature = signatureForExistingVariant(desiredPins, options: options)
                    if variantBySignature[signature] != nil {
                        skipped += 1
                        continue
                    }
                }

                let mappedSelections = options.map { option in
                    let value: String
                    if option.id == targetOption.id {
                        value = newValue
                    } else {
                        value = clean(desiredPins[option.id]?.value ?? "")
                    }
                    return CatalogBulkVariantOptionSelection(
                        optionName: clean(option.name),
                        value: value
                    )
                }
                clones.append(clone(source, selections: mappedSelections, newValue: newValue))
            }
        }

        return .success(.init(
            familyId: family.id,
            familyName: familyName,
            targetOptionId: targetOption.id,
            resolvedExistingValueId: resolvedExisting.id,
            resolvedNewValueIds: resolvedNewValueIds,
            existingAssignments: [],
            newVariants: clones,
            skippedExistingCombinationCount: skipped,
            sourceFingerprint: fingerprint(family),
            source: family
        ))
    }

    private static func selections(
        for variant: CatalogBulkVariantSnapshot,
        pinsByVariant: [String: [String: CatalogBulkOptionValueSnapshot]],
        options: [CatalogBulkOptionSnapshot]
    ) -> [CatalogBulkVariantOptionSelection] {
        options.map { option in
            .init(
                optionName: clean(option.name),
                value: clean(pinsByVariant[variant.id]?[option.id]?.value ?? "")
            )
        }
    }

    private static func clone(
        _ source: CatalogBulkVariantSnapshot,
        selections: [CatalogBulkVariantOptionSelection],
        newValue: String
    ) -> CatalogBulkNewVariantPlan {
        .init(
            sourceVariantId: source.id,
            newValue: newValue,
            sku: nil,
            quantity: 0,
            priceOverride: source.priceOverride,
            unitCostOverride: source.unitCostOverride,
            warningThreshold: source.warningThreshold,
            criticalThreshold: source.criticalThreshold,
            unitId: source.unitId,
            isActive: source.isActive,
            optionSelections: selections
        )
    }

    private static func signatureForExistingVariant(
        _ pins: [String: CatalogBulkOptionValueSnapshot],
        options: [CatalogBulkOptionSnapshot]
    ) -> String {
        options.map { option in
            "\(option.id)=\(pins[option.id]?.id ?? "missing")"
        }.joined(separator: "|")
    }

    private static func fingerprint(_ family: CatalogBulkFamilySnapshot) -> String {
        let optionState = family.options.sorted(by: optionOrder).map { option in
            let values = option.values.sorted {
                $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
            }.map { "\($0.id),\(clean($0.value)),\($0.sortOrder)" }.joined(separator: ";")
            return "\(option.id),\(clean(option.name)),\(option.sortOrder)[\(values)]"
        }.joined(separator: "|")
        let variantState = family.variants.filter(\.isActive).sorted { $0.id < $1.id }.map { variant in
            let pins = variant.optionValueIds.sorted().joined(separator: ",")
            return [
                variant.id,
                variant.sku ?? "nil",
                stableNumber(variant.quantity),
                stableNumber(variant.priceOverride),
                stableNumber(variant.unitCostOverride),
                stableNumber(variant.warningThreshold),
                stableNumber(variant.criticalThreshold),
                variant.unitId ?? "nil",
                String(variant.isActive),
                pins
            ].joined(separator: ",")
        }.joined(separator: "|")
        let canonical = "\(family.id)#\(clean(family.name))#\(optionState)#\(variantState)"
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func stableNumber(_ value: Double?) -> String {
        value.map { String($0.bitPattern, radix: 16) } ?? "nil"
    }

    private static func optionOrder(
        _ lhs: CatalogBulkOptionSnapshot,
        _ rhs: CatalogBulkOptionSnapshot
    ) -> Bool {
        lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ value: String) -> String {
        clean(value).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func blocked(
        axisName: String,
        existingValue: String,
        newValues: [String],
        code: String,
        message: String
    ) -> CatalogBulkVariantExpansionPreview {
        .init(
            axisName: axisName,
            existingValue: existingValue,
            newValues: newValues,
            familyPlans: [],
            blockers: [.init(code: code, message: message, familyId: nil)]
        )
    }

    private struct FamilyPlanningError: Error {
        let blocker: CatalogBulkVariantExpansionBlocker
    }
}
