// OPS/DeckBuilder/Models/DeckBuilderMetricReadout.swift

import Foundation

/// Reduces the builder's live selection and whole-design measurements into the
/// two stable values rendered by its compact metric instrument. Selection is
/// authoritative whenever anything is selected, including vertices that do
/// not themselves carry a length or area.
enum DeckBuilderMetricReadout {
    static let emptyValue = "—"

    enum Scope: Equatable {
        case design
        case selection
    }

    struct Result: Equatable {
        let scope: Scope
        let lengthText: String
        let areaText: String
        let shouldDisplay: Bool
    }

    /// Pure and synchronous by design: SwiftUI rebuilds this value whenever
    /// the published drawing or selection changes, so the readout never waits
    /// on a cache, timer, or save boundary.
    static func build(
        drawingData: DeckDrawingData,
        selection: SelectionState,
        wholeArea: Double?,
        wholeLength: Double?
    ) -> Result {
        let system = drawingData.config.measurementSystem

        guard !selection.isEmpty else {
            return Result(
                scope: .design,
                lengthText: wholeLength.map { DimensionEngine.format($0, system: system) } ?? emptyValue,
                areaText: wholeArea.map { DimensionEngine.formatArea($0, system: system) } ?? emptyValue,
                shouldDisplay: wholeArea != nil
            )
        }

        let selected = DeckSelectionReadout.build(
            drawingData: drawingData,
            selectedEdgeIds: selection.selectedEdgeIds,
            selectedSurfaceIds: selection.selectedSurfaceIds
        )
        return Result(
            scope: .selection,
            lengthText: selected.totalLengthText ?? emptyValue,
            areaText: selected.totalAreaText ?? emptyValue,
            shouldDisplay: true
        )
    }
}
