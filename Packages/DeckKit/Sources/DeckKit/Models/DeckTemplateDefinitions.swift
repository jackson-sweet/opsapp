// OPS/OPS/DeckBuilder/Models/DeckTemplateDefinitions.swift

import Foundation
import SwiftUI

public enum DeckTemplateType: String, CaseIterable, Identifiable {
    case rectangle
    case lShape
    case wraparound
    case tShape
    case frontPorch
    case freestanding
    case multiLevel
    case poolDeck

    public var id: String { rawValue }

    public var displayName: String {
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

    public var dimensionCount: Int {
        switch self {
        case .rectangle, .frontPorch, .freestanding: return 2
        case .poolDeck: return 3
        case .lShape, .wraparound, .tShape: return 4
        case .multiLevel: return 4
        }
    }

    public var dimensionLabels: [DimensionLabel] {
        // Bug e7965781 — palette migration: SwiftUI primitives (.green / .orange /
        // .blue / .red) replaced with OPSStyle tokens so badges and edge labels
        // read in the brand's military-tactical-minimalist tones (olive, tan,
        // steel-blue, rose) instead of saturated system colors.
        switch self {
        case .rectangle, .frontPorch, .freestanding:
            return [
                DimensionLabel(letter: "A", name: "Length", color: OPSStyle.Colors.olive),
                DimensionLabel(letter: "B", name: "Depth", color: OPSStyle.Colors.tan),
            ]
        case .lShape:
            return [
                DimensionLabel(letter: "A", name: "Long Side", color: OPSStyle.Colors.olive),
                DimensionLabel(letter: "B", name: "Full Depth", color: OPSStyle.Colors.tan),
                DimensionLabel(letter: "C", name: "Extension Width", color: OPSStyle.Colors.opsAccent),
                DimensionLabel(letter: "D", name: "Extension Depth", color: OPSStyle.Colors.rose),
            ]
        case .wraparound:
            return [
                DimensionLabel(letter: "A", name: "Long Side", color: OPSStyle.Colors.olive),
                DimensionLabel(letter: "B", name: "Full Depth", color: OPSStyle.Colors.tan),
                DimensionLabel(letter: "C", name: "Return Width", color: OPSStyle.Colors.opsAccent),
                DimensionLabel(letter: "D", name: "Return Depth", color: OPSStyle.Colors.rose),
            ]
        case .tShape:
            return [
                DimensionLabel(letter: "A", name: "Top Width", color: OPSStyle.Colors.olive),
                DimensionLabel(letter: "B", name: "Stem Depth", color: OPSStyle.Colors.tan),
                DimensionLabel(letter: "C", name: "Stem Width", color: OPSStyle.Colors.opsAccent),
                DimensionLabel(letter: "D", name: "Top Depth", color: OPSStyle.Colors.rose),
            ]
        case .multiLevel:
            return [
                DimensionLabel(letter: "A", name: "Upper Length", color: OPSStyle.Colors.olive),
                DimensionLabel(letter: "B", name: "Upper Depth", color: OPSStyle.Colors.tan),
                DimensionLabel(letter: "C", name: "Lower Length", color: OPSStyle.Colors.opsAccent),
                DimensionLabel(letter: "D", name: "Lower Depth", color: OPSStyle.Colors.rose),
            ]
        case .poolDeck:
            return [
                DimensionLabel(letter: "A", name: "Length", color: OPSStyle.Colors.olive),
                DimensionLabel(letter: "B", name: "Depth", color: OPSStyle.Colors.tan),
                DimensionLabel(letter: "C", name: "Pool Diameter", color: OPSStyle.Colors.opsAccent),
            ]
        }
    }

    /// SF Symbol for the template thumbnail
    public var iconName: String {
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
    public var hasHouseEdge: Bool {
        switch self {
        case .freestanding: return false
        default: return true
        }
    }

    // MARK: - Diagram ↔ Engine Wiring (Bug 22577979)

    /// Maps each user-facing dimension label (A/B/C/D, in `dimensionLabels`
    /// order) to the edge index of the polygon emitted by `DeckTemplateEngine`.
    ///
    /// Why this exists: edges in the engine's polygon aren't always in the
    /// same order as labels — e.g. an L-shape's edge 1 carries dimension `d`
    /// (the right-upper side, which the user names "Extension Depth"), not
    /// dimension `b` (the left side, which is "Full Depth" and lives at edge 5).
    /// Without this mapping the diagram painted label B onto the wrong edge,
    /// confusing the user before they ever pressed Create.
    public var labelEdgeIndices: [Int] {
        switch self {
        case .rectangle, .frontPorch, .freestanding:
            // Edge 0 = top (A), Edge 1 = right (B) — label A & B sit on those.
            return [0, 1]
        case .lShape:
            // Engine edges: 0=top(a), 1=rightUpper(d), 2=stepH(c),
            // 3=stepV(b-d), 4=bottom(a-c), 5=left(b).
            // Labels A=Long Side, B=Full Depth, C=Extension Width, D=Extension Depth.
            return [0, 5, 2, 1]
        case .wraparound:
            // Engine edges: 0=top(a), 1=right(b), 2=bottomRight(a-c),
            // 3=innerV(b-d), 4=innerH(c), 5=left(d).
            // Labels A=Long Side, B=Full Depth, C=Return Width, D=Return Depth.
            return [0, 1, 4, 5]
        case .tShape:
            // Engine edges (with stemDepth-as-input semantics): 0=top(a),
            // 1=rightOfTop(d), 2=rightOverhang, 3=stemRight(stemDepth),
            // 4=stemBottom(c), 5=stemLeft(stemDepth), 6=leftOverhang,
            // 7=leftOfTop(d).
            // Labels A=Top Width, B=Stem Depth, C=Stem Width, D=Top Depth.
            return [0, 3, 4, 1]
        case .multiLevel:
            // Diagram outline (see DeckTemplateEngine.vertexPositions):
            //   0=upper top (a),     1=upper right (b),  2=transition right,
            //   3=lower right (d),   4=lower bottom (c), 5=lower left (d),
            //   6=transition left,   7=upper left (b).
            // Labels A=Upper Length, B=Upper Depth, C=Lower Length, D=Lower Depth.
            return [0, 1, 4, 3]
        case .poolDeck:
            // Same rectangle polygon as `.rectangle`; pool diameter (C) has no
            // edge to live on, so we leave it off the diagram (sentinel -1 →
            // caller suppresses edge highlight, surfaces label as a centered
            // pool callout).
            return [0, 1, -1]
        }
    }

    /// Returns a list of inline validation messages for the given parsed
    /// dimensions (already converted to inches). Empty array means the
    /// dimensions form a valid shape for this template.
    ///
    /// Used by the input view to keep the Create button disabled and surface
    /// a specific message — replaces the silent "fallback to rectangle"
    /// behaviour the engine previously had for impossible L / wraparound /
    /// T-shapes. Bug 22577979.
    public func validationErrors(for dims: [Double]) -> [String] {
        guard dims.count >= dimensionCount else {
            return ["Enter all \(dimensionCount) dimensions."]
        }
        guard dims.prefix(dimensionCount).allSatisfy({ $0 > 0 }) else {
            return ["Dimensions must be greater than zero."]
        }

        switch self {
        case .rectangle, .frontPorch, .freestanding, .multiLevel:
            return []
        case .lShape:
            // c (extension width) must be smaller than a (long side); d
            // (extension depth) must be smaller than b (full depth) — else
            // it's not an L, it's a rectangle.
            let a = dims[0], b = dims[1], c = dims[2], d = dims[3]
            var errs: [String] = []
            if c >= a { errs.append("Extension width (C) must be less than long side (A).") }
            if d >= b { errs.append("Extension depth (D) must be less than full depth (B).") }
            return errs
        case .wraparound:
            let a = dims[0], b = dims[1], c = dims[2], d = dims[3]
            var errs: [String] = []
            if c >= a { errs.append("Return width (C) must be less than long side (A).") }
            if d >= b { errs.append("Return depth (D) must be less than full depth (B).") }
            return errs
        case .tShape:
            // T-shape input semantics (post-fix): A=top width, B=stem depth,
            // C=stem width, D=top depth. Stem must fit inside the top width.
            let a = dims[0], c = dims[2]
            var errs: [String] = []
            if c >= a { errs.append("Stem width (C) must be less than top width (A).") }
            return errs
        case .poolDeck:
            // Pool must physically fit inside the rectangle, with a small
            // margin so the deck doesn't degenerate into a ring of slivers.
            let a = dims[0], b = dims[1], pool = dims[2]
            var errs: [String] = []
            let minSide = min(a, b)
            if pool >= minSide { errs.append("Pool diameter must be less than the shorter deck side.") }
            return errs
        }
    }
}

public struct DimensionLabel: Identifiable {
    public let letter: String
    public let name: String
    public let color: Color

    public var id: String { letter }
}
