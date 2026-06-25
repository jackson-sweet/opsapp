//
//  CatalogEstimateMerger.swift
//  OPS
//
//  Merges adapter-driven (catalog) line items with legacy-driven
//  (geometry-only) line items into one ordered list, applying the
//  de-dupe rule from the deck-catalog integration spec § 4.5.1:
//
//    - For every component_type the company has a CompanyDefaultProduct
//      for, the adapter's rows are authoritative — the legacy items in
//      the matching category are dropped.
//    - For component_types without a default, legacy items pass
//      through.
//    - Warnings (missing elevation, AR accuracy, multi-level connection
//      narratives) always pass through — the adapter does not produce
//      them.
//
//  Pure function — no I/O, no SwiftData. The viewModel handles Product
//  lookup and pre-enriches adapter rows before calling the merger.
//

import Foundation
import DeckKit

enum CatalogEstimateMerger {

    /// Unified line item shape — both paths produce this. The catalog
    /// snapshot fields (`configuredOptions`, `resolvedUnitPrice`,
    /// `resolvedOptionsLabel`) are populated only on adapter rows; legacy
    /// rows leave them nil and persist without a `configured_options`
    /// snapshot, which is correct — barebones flat products carry no
    /// recipe to resolve at install time.
    struct LineItem: Equatable {
        let name: String
        let description: String?
        let type: LineItemType
        let quantity: Double
        let unit: String
        let unitPrice: Double
        let productId: String?
        let taskTypeId: String?
        let category: String
        let sortOrder: Int
        let isOptional: Bool
        var warning: String?

        // Adapter-only — nil for legacy rows.
        let configuredOptions: [String: ProductConfigurationResolver.OptionValue]?
        let resolvedUnitPrice: Double?
        let resolvedOptionsLabel: String?
    }

    /// Pre-enriched adapter row — the viewModel resolves the Product's
    /// name / unit / category / taskTypeId before calling the merger so
    /// this layer stays SwiftData-free.
    struct EnrichedAdapterItem {
        let raw: DesignToEstimateAdapter.GeneratedLineItem
        let productName: String
        let productDescription: String?
        let unit: String
        /// Legacy-style category bucket — drives the parent task-type
        /// grouping in the existing persistence path. Pick one of the
        /// existing values ("Surface", "Railing", "Stairs", "Other") so
        /// the EstimateGeneratorService.groupByTaskType helper treats
        /// adapter and legacy rows uniformly.
        let category: String
        let taskTypeId: String?
    }

    static func merge(
        adapterItems: [EnrichedAdapterItem],
        legacyItems: [EstimateGeneratorService.GeneratedLineItem],
        defaultsCovered: Set<DesignComponentType>
    ) -> [LineItem] {
        var output: [LineItem] = []
        var sortOrder = 0

        // 1. Adapter rows first — these are the authoritative line items
        //    for every component_type the company has configured a default
        //    Product for.
        for enriched in adapterItems {
            let raw = enriched.raw
            output.append(LineItem(
                name: enriched.productName,
                description: enriched.productDescription
                    ?? (raw.resolvedOptionsLabel.isEmpty ? nil : raw.resolvedOptionsLabel),
                type: .material,
                quantity: raw.quantity,
                unit: enriched.unit,
                unitPrice: raw.resolvedUnitPrice,
                productId: raw.productId,
                taskTypeId: enriched.taskTypeId,
                category: enriched.category,
                sortOrder: sortOrder,
                isOptional: false,
                warning: nil,
                configuredOptions: raw.configuredOptions,
                resolvedUnitPrice: raw.resolvedUnitPrice,
                resolvedOptionsLabel: raw.resolvedOptionsLabel
            ))
            sortOrder += 1
        }

        // 2. Legacy rows — pass through unless covered by an adapter
        //    default. Warning rows always pass through (the adapter
        //    doesn't produce missing-elevation / AR accuracy notes).
        let drop = legacyCategoriesToDrop(forDefaults: defaultsCovered)
        for legacy in legacyItems {
            if legacy.warning != nil {
                output.append(legacyToLineItem(legacy, sortOrder: sortOrder))
                sortOrder += 1
                continue
            }
            if drop.contains(legacy.category) { continue }
            output.append(legacyToLineItem(legacy, sortOrder: sortOrder))
            sortOrder += 1
        }
        return output
    }

    /// Maps the set of default-covered component_types to the legacy
    /// EstimateGeneratorService categories that should be suppressed.
    /// post_set sits in the "Railing" category in the legacy generator;
    /// stair_set covers both single-level "Stairs" and multi-level
    /// "Connecting Stairs". gate has no dedicated legacy category, so a
    /// gate default does not drop anything.
    static func legacyCategoriesToDrop(forDefaults defaults: Set<DesignComponentType>) -> Set<String> {
        var drop = Set<String>()
        if defaults.contains(.railing) || defaults.contains(.postSet) {
            drop.insert("Railing")
        }
        if defaults.contains(.stairSet) {
            drop.insert("Stairs")
            drop.insert("Connecting Stairs")
        }
        if defaults.contains(.deckBoard) {
            drop.insert("Surface")
        }
        return drop
    }

    private static func legacyToLineItem(
        _ l: EstimateGeneratorService.GeneratedLineItem,
        sortOrder: Int
    ) -> LineItem {
        LineItem(
            name: l.name,
            description: l.description,
            type: l.type,
            quantity: l.quantity,
            unit: l.unit,
            unitPrice: l.unitPrice,
            productId: l.productId,
            taskTypeId: l.taskTypeId,
            category: l.category,
            sortOrder: sortOrder,
            isOptional: l.isOptional,
            warning: l.warning,
            configuredOptions: nil,
            resolvedUnitPrice: nil,
            resolvedOptionsLabel: nil
        )
    }

    // MARK: - Grouping (mirrors EstimateGeneratorService.groupByTaskType)

    /// Parent / child task-type grouping for the estimate persistence
    /// path. Mirrors `EstimateGeneratorService.groupByTaskType` so the
    /// caller writes one parent line item per task type with the
    /// children attached, regardless of which path produced each row.
    struct Group {
        let taskTypeId: String?
        let taskTypeName: String
        let children: [LineItem]
        let parentTotal: Double
    }

    static func groupByTaskType(
        _ items: [LineItem],
        taskTypes: [TaskType]
    ) -> [Group] {
        let grouped = Dictionary(grouping: items, by: { $0.taskTypeId ?? "__misc__" })
        var groups: [Group] = []
        for (key, children) in grouped.sorted(by: { $0.key < $1.key }) {
            let taskTypeId: String? = (key == "__misc__") ? nil : key
            let taskTypeName: String = {
                if let id = taskTypeId,
                   let tt = taskTypes.first(where: { $0.id == id && $0.deletedAt == nil }) {
                    return tt.display
                }
                return "Misc"
            }()
            let total = children.reduce(0.0) { $0 + ($1.quantity * $1.unitPrice) }
            groups.append(Group(
                taskTypeId: taskTypeId,
                taskTypeName: taskTypeName,
                children: children,
                parentTotal: round(total * 100) / 100
            ))
        }
        return groups
    }

    // MARK: - Configured-options snapshot encoding

    /// Encodes the configured_options snapshot map into a RawJSONColumn
    /// payload ready for `CreateLineItemDTO`. Returns nil when the map
    /// is empty (legacy rows or barebones flat products), which lets the
    /// DTO leave the column as JSON `null` instead of `{}`.
    ///
    /// Wire format mirrors `RecipeResolver.decodeConfigured` — select
    /// kinds map option_id → option_value_id (string), integer kinds
    /// map to JSON numbers, boolean kinds to JSON bools.
    static func encodeConfiguredOptions(
        _ configured: [String: ProductConfigurationResolver.OptionValue]
    ) -> RawJSONColumn? {
        guard !configured.isEmpty else { return nil }
        var jsonObject: [String: Any] = [:]
        for (key, value) in configured {
            switch value {
            case .selectId(let id): jsonObject[key] = id
            case .integer(let n):   jsonObject[key] = n
            case .boolean(let b):   jsonObject[key] = b
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return RawJSONColumn(rawJSONString: s)
    }
}
