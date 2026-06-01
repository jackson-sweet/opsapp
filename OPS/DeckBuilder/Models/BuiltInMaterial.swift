//
//  BuiltInMaterial.swift
//  OPS
//
//  Industry-standard material defaults surfaced in MaterialPickerSheet's
//  "// STANDARDS" section. Lets a fresh-install company spec a real
//  material without having to populate Products first — they pick "Parapet
//  Wall" or "Composite Decking" and the assignment is created with a
//  nil productId. Estimate flow already handles nil productId (the
//  operator fills in the price at quote time) and the cut list emits a
//  generic line. Bug ee787f29.
//
//  Adding a new standard is additive only — never remove or rename an
//  entry's `id` once shipped, since older iOS builds will decode the
//  resulting AssignedItem JSON and need the id to round-trip if/when we
//  later add productId-mapping.
//

import Foundation

struct BuiltInMaterial: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String

    /// Standards offered when the picker is in linear mode (railings,
    /// edge-mounted materials).
    static let linearStandards: [BuiltInMaterial] = [
        BuiltInMaterial(id: "std.wall.parapet",       name: "Parapet Wall",       subtitle: "Low capped masonry wall",            icon: "rectangle.bottomhalf.filled"),
        BuiltInMaterial(id: "std.cladding.stucco",    name: "Stucco Wall",        subtitle: "House edge cladding",                icon: "house"),
        BuiltInMaterial(id: "std.cladding.hardie",    name: "Hardie Plank",       subtitle: "Fiber cement house siding",          icon: "house"),
        BuiltInMaterial(id: "std.cladding.woodVertical", name: "Wood Vertical",    subtitle: "Vertical house siding",              icon: "house"),
        BuiltInMaterial(id: "std.cladding.brick",     name: "Brick Veneer",       subtitle: "House edge masonry",                 icon: "house"),
        BuiltInMaterial(id: "std.cladding.stone",     name: "Stone Veneer",       subtitle: "House edge stone cladding",          icon: "house"),
        BuiltInMaterial(id: "std.cladding.vinyl",     name: "Vinyl Siding",       subtitle: "House edge siding",                  icon: "house"),
        BuiltInMaterial(id: "std.gate.standard",      name: "Gate Section",       subtitle: "Single-leaf hinged opening",         icon: "door.left.hand.open")
    ]

    /// Standards offered when the picker is in area mode (surfaces).
    static let areaStandards: [BuiltInMaterial] = [
        BuiltInMaterial(id: "std.decking.composite",          name: "Composite Decking",   subtitle: "TimberTech, Trex, AZEK style",   icon: "square.grid.3x3"),
        BuiltInMaterial(id: "std.decking.pvc",                name: "PVC Decking",         subtitle: "Cellular PVC capstock",          icon: "square.grid.3x3"),
        BuiltInMaterial(id: "std.decking.pressureTreatedWood", name: "Pressure-Treated Wood", subtitle: "Stain-grade dimensional lumber", icon: "square.grid.3x3"),
        BuiltInMaterial(id: "std.decking.cedar",              name: "Cedar Decking",       subtitle: "Western red cedar boards",       icon: "square.grid.3x3"),
        BuiltInMaterial(id: "std.decking.hardwood",           name: "Hardwood Decking",    subtitle: "Ipe, mahogany, garapa",          icon: "square.grid.3x3"),
        BuiltInMaterial(id: "std.surface.concrete",           name: "Concrete Pad",        subtitle: "Stamped or broom finish",        icon: "square.grid.3x3"),
        BuiltInMaterial(id: "std.surface.pavers",             name: "Pavers",              subtitle: "Stone or concrete unit pavers",  icon: "square.grid.3x3")
    ]
}
