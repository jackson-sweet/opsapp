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
