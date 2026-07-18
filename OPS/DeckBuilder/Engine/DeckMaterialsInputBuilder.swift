// OPS/OPS/DeckBuilder/Engine/DeckMaterialsInputBuilder.swift
//
// Read-only equivalent of `DeckBuilderViewModel.vinylOrderSurfaceInputs(scope:
// .allSurfaces)` — builds the same measured surface inputs the Vinyl Order sheet
// uses, but WITHOUT calling `reconcileSurfaces()` (the deck tab is read-only and
// must not mutate persisted geometry). The persisted↔detected matcher core is
// shared verbatim; only the mutation is dropped.
//
// Returns each input paired with the persisted surface's `assignedItems` so the
// caller (vinyl detection, § 5) can classify a surface's area material. Detected-
// fallback faces (empty persisted store) carry no items.

import CoreGraphics
import Foundation

enum DeckMaterialsInputBuilder {

    /// One measured surface plus the persisted area items assigned to it. Items
    /// are empty for detected-fallback faces (legacy designs never reconciled).
    typealias SurfaceInput = (input: VinylOrderSurfaceInput, assignedItems: [AssignedItem])

    /// Read-only surface inputs for the materials list. Persisted surfaces are
    /// matched to detected faces (exact vertex set, else best Jaccard ≥
    /// `SurfaceReconciler.rebindThreshold`). When the persisted store is EMPTY,
    /// every detected face becomes an input directly (legacy designs never
    /// reconciled since DECK-NEW-1) with labels "Surface N". Multi-level threads
    /// each level's name and sums across levels.
    static func surfaceInputs(for data: DeckDrawingData, scale: Double) -> [SurfaceInput] {
        if data.isMultiLevel {
            return data.levels.flatMap { level in
                inputs(
                    persisted: level.surfaces,
                    detected: level.detectedSurfaces,
                    edges: level.edges,
                    scale: scale,
                    levelName: level.name
                )
            }
        }

        return inputs(
            persisted: data.surfaces,
            detected: data.detectedSurfaces,
            edges: data.edges,
            scale: scale,
            levelName: nil
        )
    }

    private static func inputs(
        persisted: [DeckSurface],
        detected: [DetectedSurface],
        edges: [DeckEdge],
        scale: Double,
        levelName: String?
    ) -> [SurfaceInput] {
        // Empty persisted store → every detected face becomes an input directly.
        // A legacy design never opened in the builder since DECK-NEW-1 has no
        // persisted surfaces; without this fallback it would produce no
        // materials at all despite having renderable geometry.
        if persisted.isEmpty {
            return detected.enumerated().map { index, face in
                let input = VinylOrderSurfaceInput(
                    id: face.id,
                    label: "Surface \(index + 1)",
                    levelName: levelName,
                    positions: face.positions,
                    scaleFactor: scale,
                    edges: surfaceEdges(for: face, edges: edges)
                )
                return (input, [])
            }
        }

        return persisted.enumerated().compactMap { index, surface in
            guard let face = detectedSurface(for: surface, in: detected) else { return nil }
            let trimmedLabel = surface.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = trimmedLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "Surface \(index + 1)"
            let input = VinylOrderSurfaceInput(
                // Geometry owns order-plan identity. Persisted DeckSurface IDs
                // are created during reconciliation, so using one here would
                // make an unchanged legacy deck look edited after first open.
                id: face.id,
                label: label,
                levelName: levelName,
                positions: face.positions,
                scaleFactor: scale,
                edges: surfaceEdges(for: face, edges: edges)
            )
            return (input, surface.assignedItems)
        }
    }

    /// Boundary edges in face order, each matched bidirectionally to a `DeckEdge`
    /// (fallback `.deckEdge`). Verbatim from `vinylOrderSurfaceEdges`.
    private static func surfaceEdges(
        for face: DetectedSurface,
        edges: [DeckEdge]
    ) -> [VinylOrderSurfaceEdge] {
        guard face.vertexIds.count == face.positions.count, face.vertexIds.count >= 2 else { return [] }

        return face.vertexIds.indices.map { index in
            let nextIndex = (index + 1) % face.vertexIds.count
            let startId = face.vertexIds[index]
            let endId = face.vertexIds[nextIndex]
            let matchingEdge = edges.first {
                ($0.startVertexId == startId && $0.endVertexId == endId) ||
                    ($0.startVertexId == endId && $0.endVertexId == startId)
            }

            return VinylOrderSurfaceEdge(
                id: matchingEdge?.id ?? "\(startId)-\(endId)",
                start: face.positions[index],
                end: face.positions[nextIndex],
                edgeType: matchingEdge?.edgeType ?? .deckEdge,
                label: matchingEdge?.label,
                startVertexId: startId,
                endVertexId: endId,
                isParapet: matchingEdge?.railingConfig?.railingType == .parapetWall,
                dimensionInches: matchingEdge?.dimension.flatMap { $0 > 0 ? $0 : nil }
            )
        }
    }

    /// Match a persisted surface to a current detected face — exact vertex set,
    /// else best Jaccard overlap ≥ `rebindThreshold`. Verbatim from the view
    /// model's `detectedSurface(for:in:)`.
    private static func detectedSurface(
        for persisted: DeckSurface,
        in detected: [DetectedSurface]
    ) -> DetectedSurface? {
        if let exact = detected.first(where: { Set($0.vertexIds) == persisted.vertexIds }) {
            return exact
        }

        var best: (surface: DetectedSurface, jaccard: Double)?
        for face in detected {
            let faceIds = Set(face.vertexIds)
            let intersection = faceIds.intersection(persisted.vertexIds).count
            let union = faceIds.union(persisted.vertexIds).count
            guard union > 0 else { continue }
            let score = Double(intersection) / Double(union)
            if score > (best?.jaccard ?? -1) {
                best = (face, score)
            }
        }
        guard let best, best.jaccard >= SurfaceReconciler.rebindThreshold else { return nil }
        return best.surface
    }
}
