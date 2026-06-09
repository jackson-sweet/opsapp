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
struct AssemblyMaterialDraft: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var costText: String = ""   // your cost per unit
    var qtyText: String = ""    // quantity used per assembly
    var unitId: String?         // optional catalog unit
}

/// One labor line behind an assembly — a service with a sell rate and a cost.
struct AssemblyLaborDraft: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var sellText: String = ""   // labor sell rate (per hour)
    var costText: String = ""   // your labor cost (per hour)
    var hoursText: String = ""  // hours per assembly
}

/// The whole in-progress assembly: a fixed all-in price plus what's in it.
struct AssemblyDraft: Codable, Equatable {
    var name: String = ""
    var taskTypeId: String?
    var priceText: String = ""              // fixed all-in sell price
    var materials: [AssemblyMaterialDraft] = []
    var labor: [AssemblyLaborDraft] = []
}
