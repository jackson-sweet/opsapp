//
//  DeckMeasureReadout.swift
//  OPS
//
//  Pure reducer: turn the measure tool's polyline into the readout card's rows —
//  running total + segment count while the run is open, area + perimeter once
//  the loop closes. Mirrors DeckSelectionReadout so the fullscreen viewer's
//  measure card renders without owning canvas math. No view state, no side
//  effects — recomputed synchronously on every polyline change.
//

import SwiftUI

enum DeckMeasureReadout {

    /// Card content for one measure polyline. Formatted strings are ready to
    /// render; `nil` fields don't apply to the current phase.
    struct Result: Equatable {
        /// Sum of the drawn segments (open run only) — nil once the loop closes.
        let totalLengthText: String?
        /// Count of drawn segments. Closing adds an implicit edge on top.
        let segmentCount: Int
        /// Enclosed area — closed loops only. `—` when the loop self-intersects:
        /// a bowtie's shoelace area is a net value, not a real footprint, and a
        /// confidently-wrong number is worse than an honest dash.
        let areaText: String?
        /// Loop perimeter including the implicit closing edge — closed only.
        let perimeterText: String?
        /// True when the closed loop self-intersects (area suppressed).
        let isSelfIntersecting: Bool
    }

    /// Brand empty state — an em dash, never "N/A".
    static let emptyValue = "—"

    static func build(
        points: [CGPoint],
        closed: Bool,
        scaleFactor: Double,
        system: MeasurementSystem
    ) -> Result {
        let segmentCount = max(0, points.count - 1)
        guard scaleFactor > 0 else {
            return Result(
                totalLengthText: nil,
                segmentCount: segmentCount,
                areaText: closed && points.count >= 3 ? emptyValue : nil,
                perimeterText: closed && points.count >= 3 ? emptyValue : nil,
                isSelfIntersecting: false
            )
        }
        guard closed, points.count >= 3 else {
            let totalInches = openRunInches(points: points, scaleFactor: scaleFactor)
            return Result(
                totalLengthText: totalInches > 0 ? DimensionEngine.format(totalInches, system: system) : nil,
                segmentCount: segmentCount,
                areaText: nil,
                perimeterText: nil,
                isSelfIntersecting: false
            )
        }
        let selfIntersecting = PolygonMath.isSelfIntersecting(vertices: points)
        let perimeterInches = PolygonMath.perimeter(vertices: points) / scaleFactor
        let areaSqIn = PolygonMath.realWorldArea(vertices: points, scaleFactor: scaleFactor)
        return Result(
            totalLengthText: nil,
            segmentCount: segmentCount,
            areaText: selfIntersecting ? emptyValue : DimensionEngine.formatArea(areaSqIn, system: system),
            perimeterText: DimensionEngine.format(perimeterInches, system: system),
            isSelfIntersecting: selfIntersecting
        )
    }

    /// Sum of consecutive drawn segments in real-world inches (no closing edge).
    static func openRunInches(points: [CGPoint], scaleFactor: Double) -> Double {
        guard scaleFactor > 0, points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += SnapEngine.distance(points[i - 1], points[i])
        }
        return total / scaleFactor
    }
}
