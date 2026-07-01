//
//  DeckSelectionReadout.swift
//  OPS
//
//  Pure reducer: turn a selection over a DeckDrawingData into totals broken down
//  by type — decking area by material, edge linear feet by category (deck edge /
//  railing-by-type / house-by-cladding), and stairs (count + run).
//
//  Extracted from DeckTab2DView so the fullscreen viewer's peek-sheet readout can
//  render the same breakdown without owning the canvas. No view state, no
//  side effects — recomputed synchronously on every selection change.
//

import SwiftUI

enum DeckSelectionReadout {

    /// One label/value line in the readout.
    struct Group: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    /// The full breakdown for a selection.
    struct Result {
        let surfaceGroups: [Group]
        let edgeGroups: [Group]
        let stairGroup: Group?
        let totalAreaText: String?
        let totalLengthText: String?
        let selectionCount: Int
    }

    // MARK: - Selectable geometry (across levels)

    /// Every edge across the design (top-level or all levels), for hit-testing.
    static func edges(in drawingData: DeckDrawingData) -> [DeckEdge] {
        drawingData.isMultiLevel ? drawingData.levels.flatMap(\.edges) : drawingData.edges
    }

    /// Every vertex across the design, paired to `edges(in:)`.
    static func vertices(in drawingData: DeckDrawingData) -> [DeckVertex] {
        drawingData.isMultiLevel ? drawingData.levels.flatMap(\.vertices) : drawingData.vertices
    }

    /// Detected closed faces across the design, each carrying the persisted store
    /// needed to resolve its material/label.
    static func surfaceContexts(
        in drawingData: DeckDrawingData
    ) -> [(face: DetectedSurface, persisted: [DeckSurface], footprint: DeckFootprint, primaryId: String?)] {
        if drawingData.isMultiLevel {
            return drawingData.levels.flatMap { level -> [(DetectedSurface, [DeckSurface], DeckFootprint, String?)] in
                let faces = level.detectedSurfaces
                let primary = DeckSurfaceInspector.primarySurfaceId(among: faces)
                return faces.map { ($0, level.surfaces, level.footprint, primary) }
            }
        }
        let faces = drawingData.detectedSurfaces
        let primary = DeckSurfaceInspector.primarySurfaceId(among: faces)
        return faces.map { ($0, drawingData.surfaces, drawingData.footprint, primary) }
    }

    // MARK: - Build

    /// Reduce a selection into totals grouped by type.
    static func build(
        drawingData: DeckDrawingData,
        selectedEdgeIds: Set<String>,
        selectedSurfaceIds: Set<String>
    ) -> Result {
        let system = drawingData.config.measurementSystem
        let scale = drawingData.effectiveScaleFactor

        // Surfaces → area grouped by board material.
        var surfaceTotals: [String: Double] = [:]
        var surfaceOrder: [String] = []
        for ctx in surfaceContexts(in: drawingData) where selectedSurfaceIds.contains(ctx.face.id) {
            let payload = DeckSurfaceInspector.resolvedPayload(
                detected: ctx.face,
                persisted: ctx.persisted,
                legacyFootprint: ctx.footprint,
                isLegacyPrimary: ctx.face.id == ctx.primaryId
            )
            let label = surfaceMaterialLabel(payload)
            if surfaceTotals[label] == nil { surfaceOrder.append(label) }
            surfaceTotals[label, default: 0] += PolygonMath.realWorldArea(vertices: ctx.face.positions, scaleFactor: scale)
        }
        let surfaceGroups = surfaceOrder.map {
            Group(id: "surf-\($0)", label: $0, value: DimensionEngine.formatArea(surfaceTotals[$0] ?? 0, system: system))
        }
        let totalArea = surfaceTotals.values.reduce(0, +)

        // Edges → linear length grouped by category; stairs aggregated apart.
        var edgeTotals: [String: Double] = [:]
        var edgeOrder: [String] = []
        var stairCount = 0
        var stairRunInches: Double = 0
        let allVertices = vertices(in: drawingData)
        for edge in edges(in: drawingData) where selectedEdgeIds.contains(edge.id) {
            let length = edgeLengthInches(edge, vertices: allVertices, scale: scale) ?? 0
            let label = edgeCategoryLabel(edge)
            if edgeTotals[label] == nil { edgeOrder.append(label) }
            edgeTotals[label, default: 0] += length
            if let stair = edge.stairConfig {
                stairCount += 1
                let tc = stair.treadCount ?? StairConfig.calculateTreadCount(totalRise: stair.totalRiseInches ?? 0, risePerStep: stair.risePerStep)
                stairRunInches += Double(tc) * stair.runPerTread
            }
        }
        let edgeGroups = edgeOrder.map {
            Group(id: "edge-\($0)", label: $0, value: DimensionEngine.format(edgeTotals[$0] ?? 0, system: system))
        }
        let totalLength = edgeTotals.values.reduce(0, +)

        let stairGroup: Group? = stairCount > 0
            ? Group(
                id: "stairs",
                label: stairCount == 1 ? "STAIRS" : "STAIRS ×\(stairCount)",
                value: "RUN \(DimensionEngine.format(stairRunInches, system: system))"
              )
            : nil

        return Result(
            surfaceGroups: surfaceGroups,
            edgeGroups: edgeGroups,
            stairGroup: stairGroup,
            totalAreaText: totalArea > 0 ? DimensionEngine.formatArea(totalArea, system: system) : nil,
            totalLengthText: totalLength > 0 ? DimensionEngine.format(totalLength, system: system) : nil,
            selectionCount: selectedEdgeIds.count + selectedSurfaceIds.count
        )
    }

    // MARK: - Labels

    /// Category label for an edge in the by-type breakdown.
    static func edgeCategoryLabel(_ edge: DeckEdge) -> String {
        switch edge.edgeType {
        case .houseEdge:
            if let m = edge.houseEdgeMaterial { return "HOUSE · \(m.displayName.uppercased())" }
            return "HOUSE"
        case .deckEdge:
            if let r = edge.railingConfig { return "RAILING · \(r.railingType.displayName.uppercased())" }
            return "DECK EDGE"
        }
    }

    /// Material label for a surface in the by-type breakdown — the assigned item's
    /// name when present, else the board material.
    static func surfaceMaterialLabel(_ payload: DeckResolvedSurfacePayload) -> String {
        if let item = payload.assignedItems.first?.name.trimmingCharacters(in: .whitespacesAndNewlines), !item.isEmpty {
            return item.uppercased()
        }
        let m = payload.boardMaterial.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? "DECKING" : m.uppercased()
    }

    /// Real-world length of an edge in inches — stored dimension when present, else
    /// canvas length over the effective scale. Searches `vertices` for the edge's
    /// endpoints (works across levels).
    static func edgeLengthInches(_ edge: DeckEdge, vertices: [DeckVertex], scale: Double) -> Double? {
        if let dim = edge.dimension, dim > 0 { return dim }
        guard let s = vertices.first(where: { $0.id == edge.startVertexId })?.position,
              let e = vertices.first(where: { $0.id == edge.endVertexId })?.position else { return nil }
        return SnapEngine.distance(s, e) / scale
    }
}
