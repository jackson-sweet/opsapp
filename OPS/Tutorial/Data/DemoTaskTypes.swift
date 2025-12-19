//
//  DemoTaskTypes.swift
//  OPS
//
//  Demo task type data for the interactive tutorial.
//  12 task types with pastel colors and SF Symbol icons.
//

import Foundation

/// Data structure for demo task types
struct DemoTaskTypeData {
    let id: String
    let display: String
    let color: String  // Hex color code
    let icon: String   // SF Symbol name
}

// MARK: - All Demo Task Types

extension DemoTaskTypeData {
    /// All demo task types
    static let all: [DemoTaskTypeData] = [
        cleaning,
        demolition,
        painting,
        sealing,
        paving,
        landscaping,
        installation,
        pressureWash,
        diagnostic,
        removal,
        coating,
        planting
    ]

    // MARK: - Individual Task Types

    static let cleaning = DemoTaskTypeData(
        id: DemoIDs.cleaning,
        display: "Cleaning",
        color: "#A8D8B9",
        icon: "sparkles"
    )

    static let demolition = DemoTaskTypeData(
        id: DemoIDs.demolition,
        display: "Demolition",
        color: "#E8A87C",
        icon: "hammer.fill"
    )

    static let painting = DemoTaskTypeData(
        id: DemoIDs.painting,
        display: "Painting",
        color: "#89B4E8",
        icon: "paintbrush.fill"
    )

    static let sealing = DemoTaskTypeData(
        id: DemoIDs.sealing,
        display: "Sealing",
        color: "#B4C7E8",
        icon: "drop.fill"
    )

    static let paving = DemoTaskTypeData(
        id: DemoIDs.paving,
        display: "Paving",
        color: "#C4B7D4",
        icon: "rectangle.split.3x3.fill"
    )

    static let landscaping = DemoTaskTypeData(
        id: DemoIDs.landscaping,
        display: "Landscaping",
        color: "#8FD4A4",
        icon: "leaf.fill"
    )

    static let installation = DemoTaskTypeData(
        id: DemoIDs.installation,
        display: "Installation",
        color: "#D4A8C7",
        icon: "wrench.and.screwdriver.fill"
    )

    static let pressureWash = DemoTaskTypeData(
        id: DemoIDs.pressureWash,
        display: "Pressure Wash",
        color: "#E8D48A",
        icon: "wind"
    )

    static let diagnostic = DemoTaskTypeData(
        id: DemoIDs.diagnostic,
        display: "Diagnostic",
        color: "#8AD4D4",
        icon: "magnifyingglass"
    )

    static let removal = DemoTaskTypeData(
        id: DemoIDs.removal,
        display: "Removal",
        color: "#E8B89A",
        icon: "trash.fill"
    )

    static let coating = DemoTaskTypeData(
        id: DemoIDs.coating,
        display: "Coating",
        color: "#7AA8D4",
        icon: "paintpalette.fill"
    )

    static let planting = DemoTaskTypeData(
        id: DemoIDs.planting,
        display: "Planting",
        color: "#B8E8A8",
        icon: "camera.macro"
    )

    // MARK: - Lookup Methods

    /// Find a task type by ID
    static func find(byId id: String) -> DemoTaskTypeData? {
        return all.first { $0.id == id }
    }

    /// Find a task type by display name
    static func find(byName name: String) -> DemoTaskTypeData? {
        return all.first { $0.display.lowercased() == name.lowercased() }
    }
}
