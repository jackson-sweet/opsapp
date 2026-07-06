// OPS/OPS/DeckBuilder/Engine/VinylOrderScaleResolver.swift
//
// Pure resolution of the scale a vinyl order (and the deck-tab materials list)
// should use. Extracted verbatim from `DeckBuilderViewModel` so read-only
// surfaces — the project Deck tab's materials section — can resolve scale
// WITHOUT instantiating the editor view model. The view model delegates to this;
// behavior is unchanged.
//
// Vinyl is a stricter consumer than the editor's area/perimeter readout or
// estimate generation: a cut-to-size order can't tolerate a drawing whose typed
// dimensions disagree with the drawn geometry. Any stale edge blocks the order.
// When a legacy drawing has confirmed dimensions but no persisted `scaleFactor`,
// infer the scale only if every stored dimension still agrees with the geometry.

import CoreGraphics
import Foundation

enum VinylOrderScaleResolver {

    /// Resolved scale (canvas points per real-world inch) for vinyl ordering, or
    /// nil when the drawing can't be trusted for a cut-to-size order. Always > 0
    /// when non-nil.
    static func resolve(_ data: DeckDrawingData) -> Double? {
        guard !data.allEdges.contains(where: \.dimensionStale) else { return nil }
        if let scaleFactor = data.scaleFactor, scaleFactor > 0 {
            return scaleFactor
        }
        if canUsePrescaleFallback(data) {
            return data.effectiveScaleFactor
        }
        return inferredScaleFromConfirmedDimensions(data)
    }

    private static func canUsePrescaleFallback(_ data: DeckDrawingData) -> Bool {
        let edges = data.allEdges
        guard !edges.isEmpty else { return false }
        return edges.allSatisfy { edge in
            edge.dimensionSource == .scale && !edge.dimensionStale
        }
    }

    private struct Measurement {
        let canvasLength: Double
        let inches: Double
        let source: DimensionSource

        var scaleFactor: Double {
            canvasLength / inches
        }
    }

    private static func inferredScaleFromConfirmedDimensions(_ data: DeckDrawingData) -> Double? {
        let measurements = scaleMeasurements(data)
        guard !measurements.isEmpty else { return nil }

        let authoritative = measurements.filter { measurement in
            isConfirmedDimensionSource(measurement.source)
        }
        guard !authoritative.isEmpty else { return nil }

        let sortedScales = authoritative.map(\.scaleFactor).sorted()
        let referenceScale = sortedScales[sortedScales.count / 2]
        guard referenceScale.isFinite, referenceScale > 0 else { return nil }

        let dimensionsAgree = measurements.allSatisfy { measurement in
            let expectedInches = measurement.canvasLength / referenceScale
            return abs(expectedInches - measurement.inches) < toleranceInches
        }
        return dimensionsAgree ? referenceScale : nil
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

    private static let toleranceInches = 0.5

    private static func isConfirmedDimensionSource(_ source: DimensionSource) -> Bool {
        source == .manual || source == .laser || source == .ar
    }
}
