// OPS/OPS/DeckBuilder/Models/DeckSplitReadout.swift

import SwiftUI

/// Pure reducer: selected surface + two cut points → the split card's rows
/// and the render geometry. Mirrors DeckMeasureReadout / DeckSelectionReadout
/// so the fullscreen viewer renders without owning canvas math.
enum DeckSplitReadout {

    struct Result: Equatable {
        let didSplit: Bool
        /// Formatted per-side areas — nil until a valid split exists.
        let sideAText: String?
        let sideBText: String?
        /// Formatted total chord length (the board line).
        let cutLengthText: String?
        /// Render geometry (canvas space). Empty when no split.
        let sideAPolygon: [CGPoint]
        let sideBPolygon: [CGPoint]
        let chordSegments: [PolygonSplitter.ChordSegment]
    }

    static let empty = Result(
        didSplit: false, sideAText: nil, sideBText: nil, cutLengthText: nil,
        sideAPolygon: [], sideBPolygon: [], chordSegments: []
    )

    static func build(
        surface: [CGPoint],
        cutA: CGPoint,
        cutB: CGPoint,
        scaleFactor: Double,
        system: MeasurementSystem
    ) -> Result {
        guard scaleFactor > 0 else { return empty }
        let split = PolygonSplitter.split(polygon: surface, lineA: cutA, lineB: cutB)
        guard split.didSplit else { return empty }

        let areaA = PolygonMath.realWorldArea(vertices: split.sideA, scaleFactor: scaleFactor)
        let areaB = PolygonMath.realWorldArea(vertices: split.sideB, scaleFactor: scaleFactor)
        let chordInches = split.chordSegments.reduce(0.0) {
            $0 + SnapEngine.distance($1.start, $1.end)
        } / scaleFactor

        return Result(
            didSplit: true,
            sideAText: DimensionEngine.formatArea(areaA, system: system),
            sideBText: DimensionEngine.formatArea(areaB, system: system),
            cutLengthText: DimensionEngine.format(chordInches, system: system),
            sideAPolygon: split.sideA,
            sideBPolygon: split.sideB,
            chordSegments: split.chordSegments
        )
    }
}
