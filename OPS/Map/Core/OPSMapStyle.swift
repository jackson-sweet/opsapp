//
//  OPSMapStyle.swift
//  OPS
//
//  Defines three map visual profiles — Dark, Light, Classic — each
//  with a base Mapbox style URI and a full set of color overrides
//  derived from the OPS interface-design system.
//
//  Dark (default):  Near-black monochromatic. Matches #0A0A0A app background.
//  Light:           Clean bright neutrals. For daylight readability.
//  Classic:         Warm, desaturated traditional map. Familiar but muted.
//

import UIKit
import MapboxMaps

// MARK: - Style Enum

enum OPSMapStyle: String, CaseIterable, Identifiable {
    case dark
    case light
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark:    return "DARK"
        case .light:   return "LIGHT"
        case .classic: return "CLASSIC"
        }
    }

    /// Mapbox base style to load before applying color overrides.
    var baseStyleURI: StyleURI {
        switch self {
        case .dark:    return StyleURI(rawValue: "mapbox://styles/mapbox/dark-v11")!
        case .light:   return StyleURI(rawValue: "mapbox://styles/mapbox/light-v11")!
        case .classic: return StyleURI(rawValue: "mapbox://styles/mapbox/streets-v12")!
        }
    }

    /// Solid background shown while tiles stream in. Matches the profile's land color.
    var backgroundColor: UIColor {
        colors.land
    }

    /// Full color profile for this style.
    var colors: MapStyleColors {
        switch self {
        case .dark:    return .dark
        case .light:   return .light
        case .classic: return .classic
        }
    }
}

// MARK: - Color Profile

struct MapStyleColors {

    // Terrain
    let land: UIColor
    let water: UIColor
    let waterway: UIColor
    let park: UIColor

    // Roads
    let roadPrimary: UIColor     // Motorways, trunks, primary
    let roadSecondary: UIColor   // Secondary, tertiary
    let roadMinor: UIColor       // Residential, streets, service
    let roadCase: UIColor        // Casing / outline beneath road fill

    // Structures
    let building: UIColor
    let buildingStroke: UIColor

    // Labels
    let labelPrimary: UIColor    // Place names, city names
    let labelSecondary: UIColor  // Road names, minor labels
    let poi: UIColor             // POI labels / icons

    // Boundaries
    let boundary: UIColor

    /// If true, most POI and transit labels are hidden for a cleaner field map.
    let hidePOIs: Bool

    // ─────────────────────────────────────────
    // MARK: Dark
    // ─────────────────────────────────────────
    //
    // Near-black monochromatic. Land and water are almost
    // indistinguishable — roads provide the only real structure.
    // Matches system.md: background #0A0A0A, surface #0D0D0D–#141414.

    static let dark = MapStyleColors(
        land:           UIColor(hex: "#0A0A0A"),
        water:          UIColor(hex: "#101820"),   // Subtle dark navy — distinguishable from land
        waterway:       UIColor(hex: "#0E1620"),
        park:           UIColor(hex: "#0E100E"),

        roadPrimary:    UIColor(hex: "#666666"),   // Matches secondary text color for clear visibility
        roadSecondary:  UIColor(hex: "#444444"),
        roadMinor:      UIColor(hex: "#333333"),
        roadCase:       UIColor(hex: "#1A1A1A"),

        building:       UIColor(hex: "#0D0D0D"),
        buildingStroke: UIColor(hex: "#181818"),

        labelPrimary:   UIColor.white.withAlphaComponent(0.50),
        labelSecondary: UIColor.white.withAlphaComponent(0.30),
        poi:            UIColor.white.withAlphaComponent(0.20),

        boundary:       UIColor.white.withAlphaComponent(0.08),

        hidePOIs:       true
    )

    // ─────────────────────────────────────────
    // MARK: Light
    // ─────────────────────────────────────────
    //
    // Clean and bright but still understated. Cool grays
    // with a faint blue-gray tint on water. Follows the
    // system.md background-light #FFFFFF family.

    static let light = MapStyleColors(
        land:           UIColor(hex: "#F2F2F2"),
        water:          UIColor(hex: "#DFE6ED"),
        waterway:       UIColor(hex: "#D4DDE6"),
        park:           UIColor(hex: "#E5EAE0"),

        roadPrimary:    UIColor(hex: "#D8D8D8"),   // Visible against light land
        roadSecondary:  UIColor(hex: "#E0E0E0"),
        roadMinor:      UIColor(hex: "#E8E8E8"),
        roadCase:       UIColor(hex: "#C8C8C8"),

        building:       UIColor(hex: "#E8E8E8"),
        buildingStroke: UIColor(hex: "#DCDCDC"),

        labelPrimary:   UIColor(hex: "#1A1A1A").withAlphaComponent(0.80),
        labelSecondary: UIColor(hex: "#1A1A1A").withAlphaComponent(0.45),
        poi:            UIColor(hex: "#1A1A1A").withAlphaComponent(0.40),

        boundary:       UIColor(hex: "#1A1A1A").withAlphaComponent(0.10),

        hidePOIs:       false
    )

    // ─────────────────────────────────────────
    // MARK: Classic
    // ─────────────────────────────────────────
    //
    // Warm, desaturated traditional map. Water carries a
    // muted steel-blue nod to the OPS accent #597794.
    // Land is warm gray, parks are sage. Familiar but
    // pulled into the OPS color world.

    static let classic = MapStyleColors(
        land:           UIColor(hex: "#E8E5E0"),
        water:          UIColor(hex: "#C4D1DC"),
        waterway:       UIColor(hex: "#B8C8D6"),
        park:           UIColor(hex: "#D4DCCE"),

        roadPrimary:    UIColor(hex: "#FFFFFF"),
        roadSecondary:  UIColor(hex: "#F0EDE8"),
        roadMinor:      UIColor(hex: "#E8E5E0"),
        roadCase:       UIColor(hex: "#D5D0CB"),

        building:       UIColor(hex: "#D8D5D0"),
        buildingStroke: UIColor(hex: "#CCC8C2"),

        labelPrimary:   UIColor(hex: "#333333"),
        labelSecondary: UIColor(hex: "#666666"),
        poi:            UIColor(hex: "#555555"),

        boundary:       UIColor(hex: "#999999").withAlphaComponent(0.35),

        hidePOIs:       false
    )
}
