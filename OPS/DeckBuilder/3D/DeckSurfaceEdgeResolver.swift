//
//  DeckSurfaceEdgeResolver.swift
//  OPS
//
//  Resolves which graph edges are visible perimeter edges for 3D rendering.
//

import Foundation

enum DeckSurfaceEdgeResolver {

    static func visibleRimJoistEdgeIds(
        edges: [DeckEdge],
        surfaces: [DeckSceneBuilder.SurfaceMesh3D]
    ) -> Set<String> {
        guard !surfaces.isEmpty else {
            return Set(edges.map(\.id))
        }

        var surfaceEdgeCounts: [VertexPair: Int] = [:]
        for surface in surfaces {
            guard surface.vertexIds.count >= 3 else { continue }
            for index in surface.vertexIds.indices {
                let nextIndex = surface.vertexIds.index(after: index) == surface.vertexIds.endIndex
                    ? surface.vertexIds.startIndex
                    : surface.vertexIds.index(after: index)
                let pair = VertexPair(surface.vertexIds[index], surface.vertexIds[nextIndex])
                surfaceEdgeCounts[pair, default: 0] += 1
            }
        }

        return Set(edges.compactMap { edge in
            let pair = VertexPair(edge.startVertexId, edge.endVertexId)
            return surfaceEdgeCounts[pair] == 1 ? edge.id : nil
        })
    }

    static func carriesVisible3DFeature(_ edge: DeckEdge) -> Bool {
        edge.edgeType == .houseEdge || edge.railingConfig != nil || edge.stairConfig != nil
    }
}

private struct VertexPair: Hashable {
    let a: String
    let b: String

    init(_ first: String, _ second: String) {
        if first <= second {
            a = first
            b = second
        } else {
            a = second
            b = first
        }
    }
}
