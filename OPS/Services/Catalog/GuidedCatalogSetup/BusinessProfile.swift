//
//  BusinessProfile.swift
//  OPS
//
//  Diagnostic profile produced by the Guided Catalog Setup survey, plus the
//  pure derivation of which setup modules a given business needs. No UI, no
//  side effects — fully unit-testable.
//

import Foundation

/// What the company primarily sells. (Survey Q1)
enum BusinessSells: String, Codable, CaseIterable {
    case services   // time & expertise
    case goods      // physical products supplied/installed
    case mix        // both
}

/// How a job is priced. (Survey Q2) — only this gates assemblies.
enum BusinessPricing: String, Codable, CaseIterable {
    case fixedJob   // one all-in price for the whole job
    case lineItem   // line by line
    case hourly     // time & materials
    case mixed      // depends
}

/// How much material/parts a typical job consumes. (Survey Q3)
enum BusinessMaterialUse: String, Codable, CaseIterable {
    case heavy      // lots of parts
    case some       // a few key materials
    case none       // doesn't track materials
}

/// Whether stock is counted or only costed. (Survey Q4)
enum BusinessInventoryChoice: String, Codable, CaseIterable {
    case tracked    // count it + reorder warnings
    case costOnly   // just costs & margins
}

/// The setup modules the guide can run, in canonical order.
enum SetupModuleKind: String, Codable, CaseIterable, Identifiable {
    case assembly   // fixed-price packages (Slice 2)
    case services   // labor / service lines (Slice 1)
    case goods      // physical products sold directly (Slice 1)
    case stock      // stock counting via GuidedStockSetupFlow (Slice 3)

    var id: String { rawValue }
}

/// The completed answers from the survey.
struct BusinessProfile: Codable, Equatable {
    var sells: BusinessSells
    var pricing: BusinessPricing
    var materialUse: BusinessMaterialUse
    var inventory: BusinessInventoryChoice?   // nil when materialUse == .none (Q4 skipped)
    var trackCost: Bool                        // Q5 — show "Your cost" + margin everywhere
}

extension BusinessProfile {

    /// Pricing only gates assemblies; selling a thing always offers its module.
    var runServices: Bool { sells != .goods || pricing == .hourly }
    var runGoods: Bool { sells != .services }
    var runAssemblies: Bool { pricing == .fixedJob || pricing == .mixed }
    var runMaterials: Bool { materialUse != .none }
    var runStock: Bool { runMaterials && inventory == .tracked }

    /// The ordered, de-duplicated modules this profile needs. Assembly (the hero)
    /// leads for fixed-job businesses; a safety floor guarantees a non-empty plan
    /// so no answer combination can strand the user on an empty setup.
    var setupModules: [SetupModuleKind] {
        var mods: [SetupModuleKind] = []
        if runAssemblies { mods.append(.assembly) }
        if runServices { mods.append(.services) }
        if runGoods { mods.append(.goods) }
        if runStock { mods.append(.stock) }
        if mods.isEmpty { mods = [.services, .goods] }

        var seen = Set<SetupModuleKind>()
        return mods.filter { seen.insert($0).inserted }
    }
}
