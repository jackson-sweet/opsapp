//
//  AssemblyDraft.swift
//  OPS
//
//  In-progress working state for the assembly builder (a fixed-price package =
//  materials + labor). Held in the view while building; only committed
//  assemblies (SavedAssembly) are persisted in the resume snapshot.
//

import Foundation

/// One material line behind an assembly — a stock-backed part with a cost.
///
/// Two provenances: an existing catalog variant (`catalogVariantId` set — the
/// commit references it, never duplicating stock) or an inline-created one
/// (`catalogVariantId == nil` — the commit scaffolds a family + variant). The
/// D3 reconciliation: referencing wins whenever the operator picks something
/// that already exists.
/// One option axis on an inline-created material (e.g. Color → [Black, White]).
/// Ordered: `values` keep insertion order for sortOrder and the cartesian walk.
struct AssemblyMaterialAxis: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var values: [String] = [""]
}

struct AssemblyMaterialDraft: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var costText: String = ""   // your cost per unit
    var qtyText: String = ""    // quantity used per assembly
    var unitId: String?         // optional catalog unit
    /// When set, this line references an existing `CatalogVariant`; commit
    /// reuses it instead of creating a new family + variant. `name`/`costText`
    /// are hydrated from the variant for display + margin math.
    var catalogVariantId: String?
    /// 0, 1, or 2 option axes on the create-new path. Empty => today's single
    /// labeled variant. Non-empty => the commit generates the full variant matrix
    /// (a family + option(s) + a variant per combo) and pins the recipe to the
    /// first generated variant. Only ever set when `catalogVariantId == nil`.
    var axes: [AssemblyMaterialAxis] = []
}

extension AssemblyMaterialDraft {
    /// Hard cap on generated variants — keeps the sequential write loop fast and
    /// well above any real assembly need (a 12 × 2 vinyl matrix is 24).
    static let maxVariants = 100

    /// Axes with a non-blank name and ≥1 non-blank, case-insensitively de-duped
    /// value (first occurrence wins, order preserved). Drives both the count
    /// readout and the commit walk, so the UI and the writer never disagree.
    var cleanAxes: [AssemblyMaterialAxis] {
        axes.compactMap { axis in
            let name = axis.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var seen = Set<String>()
            var values: [String] = []
            for value in axis.values {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
                values.append(trimmed)
            }
            guard !values.isEmpty else { return nil }
            return AssemblyMaterialAxis(id: axis.id, name: name, values: values)
        }
    }

    var hasUsableAxes: Bool { !cleanAxes.isEmpty }

    /// Product of the clean axis value counts (12 × 2 = 24). 1 when no clean axes.
    var variantComboCount: Int { cleanAxes.reduce(1) { $0 * $1.values.count } }

    /// Cartesian product of clean axis values as ordered tuples (axis-1 outer).
    /// [["Black","White"],["45mil","60mil"]] →
    /// [["Black","45mil"],["Black","60mil"],["White","45mil"],["White","60mil"]]
    var variantCombos: [[String]] {
        cleanAxes.map(\.values).reduce([[]]) { acc, vals in acc.flatMap { row in vals.map { row + [$0] } } }
    }
}

/// One labor line behind an assembly — a service with a sell rate and a cost,
/// priced per its chosen unit (per hour by default, or piecework per ft / sq ft).
struct AssemblyLaborDraft: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var sellText: String = ""   // labor sell rate (per chosen unit)
    var costText: String = ""   // your labor cost (per chosen unit)
    var hoursText: String = ""  // quantity per assembly (hours, ft, sq ft…)
    var unitId: String?         // nil = hour-style; resolved via pricingUnit(for:)
}

/// The whole in-progress assembly: a fixed all-in price plus what's in it. The
/// price can be flat (whole job) or per-unit (per linear ft / sq ft / each).
struct AssemblyDraft: Codable, Equatable {
    var name: String = ""
    var taskTypeId: String?
    var priceText: String = ""              // fixed all-in sell price (per unit when priceUnitId set)
    var priceUnitId: String?                // nil = flat rate (whole job)
    var materials: [AssemblyMaterialDraft] = []
    var labor: [AssemblyLaborDraft] = []
}
