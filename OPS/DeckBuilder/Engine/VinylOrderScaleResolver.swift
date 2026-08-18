// OPS/OPS/DeckBuilder/Engine/VinylOrderScaleResolver.swift
//
// Pure resolution of the scale a vinyl order (and the deck-tab materials list)
// should use. Extracted from `DeckBuilderViewModel` so read-only surfaces — the
// project Deck tab's materials section — can resolve scale WITHOUT
// instantiating the editor view model.
//
// Bug 59d7f468 — this used to be able to answer "no scale", which the UI
// surfaced as a CONFIRM ONE EDGE LENGTH blocker on the order sheet, the
// materials section and the bulk-order wizard. That blocker named no edge,
// pointed at nothing on the canvas, and stopped an order the operator had
// every right to place. It is gone.
//
// A drawing always has a scale. Either the user calibrated one, or the
// dimensions they typed imply one, or the canvas is already drawing, snapping
// and dimensioning at the prescale fallback — a freehand deck is at a sound,
// internally-consistent scale even before anyone confirms anything.
//
// What the old resolver was really detecting is a genuine and separate fact:
// the operator typed a dimension and then dragged the geometry away from it.
// That state lives on the edge itself as `DeckEdge.dimensionStale`, and it is
// surfaced where it belongs — on the overridden dimension, in every 2D view,
// in tan with a DRAWN LENGTH CHANGED caption. See `DeckStaleDimensionPresenter`.

import CoreGraphics
import Foundation

enum VinylOrderScaleResolver {

    /// Scale (canvas points per real-world inch) for vinyl ordering and the
    /// materials list. Always > 0.
    ///
    /// Resolution order:
    /// 1. The calibrated `scaleFactor`, once AR / a sketch scan / a template /
    ///    a typed dimension has set one.
    /// 2. The scale implied by the dimensions the user measured or typed —
    ///    the median, so one drifted edge cannot drag the whole drawing.
    /// 3. The prescale fallback the canvas already draws at.
    static func resolve(_ data: DeckDrawingData) -> Double {
        if let scaleFactor = data.scaleFactor, scaleFactor > 0 {
            return scaleFactor
        }
        if let inferred = inferredScaleFromMeasuredDimensions(data) {
            return inferred
        }
        return data.effectiveScaleFactor
    }

    private struct Measurement {
        let canvasLength: Double
        let inches: Double
        let source: DimensionSource

        var scaleFactor: Double {
            canvasLength / inches
        }
    }

    /// Median scale across every edge whose dimension the user actually
    /// measured or typed. The median — not the mean — so a single edge the
    /// user dragged away from its typed value shifts nothing.
    private static func inferredScaleFromMeasuredDimensions(_ data: DeckDrawingData) -> Double? {
        let authoritative = scaleMeasurements(data).filter { measurement in
            isMeasuredDimensionSource(measurement.source)
        }
        guard !authoritative.isEmpty else { return nil }

        let sortedScales = authoritative.map(\.scaleFactor).sorted()
        let referenceScale = sortedScales[sortedScales.count / 2]
        guard referenceScale.isFinite, referenceScale > 0 else { return nil }
        return referenceScale
    }

    private static func scaleMeasurements(_ data: DeckDrawingData) -> [Measurement] {
        if data.isMultiLevel {
            return data.levels.flatMap { level in
                scaleMeasurements(edges: level.edges, vertices: level.vertices)
            }
        }

        return scaleMeasurements(edges: data.edges, vertices: data.vertices)
    }

    private static func scaleMeasurements(
        edges: [DeckEdge],
        vertices: [DeckVertex]
    ) -> [Measurement] {
        let verticesById = Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) })
        return edges.compactMap { edge in
            guard let inches = edge.dimension,
                  inches.isFinite,
                  inches > 0,
                  let start = verticesById[edge.startVertexId],
                  let end = verticesById[edge.endVertexId] else {
                return nil
            }

            let canvasLength = SnapEngine.distance(start.position, end.position)
            guard canvasLength.isFinite, canvasLength > 0 else { return nil }
            return Measurement(
                canvasLength: canvasLength,
                inches: inches,
                source: edge.dimensionSource
            )
        }
    }

    private static func isMeasuredDimensionSource(_ source: DimensionSource) -> Bool {
        source == .manual || source == .laser || source == .ar
    }
}
