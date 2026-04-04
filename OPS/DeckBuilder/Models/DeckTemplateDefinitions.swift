// OPS/OPS/DeckBuilder/Models/DeckTemplateDefinitions.swift

import Foundation
import SwiftUI

enum DeckTemplateType: String, CaseIterable, Identifiable {
    case rectangle
    case lShape
    case wraparound
    case tShape
    case frontPorch
    case freestanding
    case multiLevel
    case poolDeck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangle:   return "Rectangle"
        case .lShape:      return "L-Shape"
        case .wraparound:  return "Wraparound"
        case .tShape:      return "T-Shape"
        case .frontPorch:  return "Front Porch"
        case .freestanding: return "Freestanding"
        case .multiLevel:  return "Multi-Level"
        case .poolDeck:    return "Pool Deck"
        }
    }

    var dimensionCount: Int {
        switch self {
        case .rectangle, .frontPorch, .freestanding: return 2
        case .poolDeck: return 3
        case .lShape, .wraparound, .tShape, .multiLevel: return 4
        }
    }

    var dimensionLabels: [DimensionLabel] {
        switch self {
        case .rectangle, .frontPorch, .freestanding:
            return [
                DimensionLabel(letter: "A", name: "Length", color: .green),
                DimensionLabel(letter: "B", name: "Depth", color: .orange),
            ]
        case .lShape:
            return [
                DimensionLabel(letter: "A", name: "Long Side", color: .green),
                DimensionLabel(letter: "B", name: "Full Depth", color: .orange),
                DimensionLabel(letter: "C", name: "Extension Width", color: .blue),
                DimensionLabel(letter: "D", name: "Extension Depth", color: .red),
            ]
        case .wraparound:
            return [
                DimensionLabel(letter: "A", name: "Long Side", color: .green),
                DimensionLabel(letter: "B", name: "Full Depth", color: .orange),
                DimensionLabel(letter: "C", name: "Return Width", color: .blue),
                DimensionLabel(letter: "D", name: "Return Depth", color: .red),
            ]
        case .tShape:
            return [
                DimensionLabel(letter: "A", name: "Top Width", color: .green),
                DimensionLabel(letter: "B", name: "Stem Depth", color: .orange),
                DimensionLabel(letter: "C", name: "Stem Width", color: .blue),
                DimensionLabel(letter: "D", name: "Top Depth", color: .red),
            ]
        case .multiLevel:
            return [
                DimensionLabel(letter: "A", name: "Upper Length", color: .green),
                DimensionLabel(letter: "B", name: "Upper Depth", color: .orange),
                DimensionLabel(letter: "C", name: "Lower Length", color: .blue),
                DimensionLabel(letter: "D", name: "Lower Depth", color: .red),
            ]
        case .poolDeck:
            return [
                DimensionLabel(letter: "A", name: "Length", color: .green),
                DimensionLabel(letter: "B", name: "Depth", color: .orange),
                DimensionLabel(letter: "C", name: "Pool Diameter", color: .blue),
            ]
        }
    }

    /// SF Symbol for the template thumbnail
    var iconName: String {
        switch self {
        case .rectangle:    return "rectangle"
        case .lShape:       return "square.bottomhalf.filled"
        case .wraparound:   return "rectangle.leadinghalf.inset.filled.arrow.leading"
        case .tShape:       return "t.square"
        case .frontPorch:   return "rectangle.split.2x1"
        case .freestanding: return "square.dashed"
        case .multiLevel:   return "square.stack"
        case .poolDeck:     return "circle.square"
        }
    }

    /// Whether this template auto-assigns a house edge
    var hasHouseEdge: Bool {
        switch self {
        case .freestanding: return false
        default: return true
        }
    }
}

struct DimensionLabel: Identifiable {
    let letter: String
    let name: String
    let color: Color

    var id: String { letter }
}
