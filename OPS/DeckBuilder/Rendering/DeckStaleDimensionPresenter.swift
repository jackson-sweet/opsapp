// OPS/OPS/DeckBuilder/Rendering/DeckStaleDimensionPresenter.swift
//
// How an OVERRIDDEN dimension looks, in one place. Bug 59d7f468.
//
// There is exactly one way a deck's typed dimensions and its drawn geometry can
// disagree: the operator typed (or measured) a length, then moved the drawing.
// `DeckEdge.dimensionStale` records that, and it is the only honest signal in
// this area — the "unconfirmed edge length" blocker that used to sit on the
// order sheet and the materials tab named no edge and pointed at nothing.
//
// So the state is shown where the operator can act on it: on the dimension
// itself, on the edge itself, in every 2D view. Tan is the attention semantic;
// the caption says plainly what happened. Retype or re-measure the dimension
// and it clears.

import SwiftUI

enum DeckStaleDimensionPresenter {

    /// Caption under an overridden dimension. UPPERCASE for authority, terse.
    static let caption = "DRAWN LENGTH CHANGED"

    /// Whether this edge carries a dimension the operator set and the drawing
    /// has since moved away from.
    static func isOverridden(_ edge: DeckEdge) -> Bool {
        edge.dimensionStale
    }

    /// Chip fill behind an overridden dimension. Tan wash, not a solid — the
    /// value must stay the loudest thing in the chip.
    static var chipFill: Color {
        OPSStyle.Colors.warningStatus.opacity(0.15)
    }

    /// Hairline around an overridden dimension chip.
    static var chipStroke: Color {
        OPSStyle.Colors.warningStatus.opacity(0.5)
    }

    /// The dimension value itself when overridden.
    static var valueColor: Color {
        OPSStyle.Colors.warningStatus
    }
}
