// OPS/DeckBuilder/Models/DeckGeometrySnapshot.swift

import CoreGraphics
import Foundation

extension DeckVertex: DeckGeometryMutationVertex {}

extension DeckEdge: DeckGeometryMutationEdge {
    var usesScaleDerivedDimension: Bool { dimensionSource == .scale }
}

struct DeckGeometryEdgeSegment: Equatable {
    let startVertexId: String
    let endVertexId: String
    let start: CGPoint
    let end: CGPoint
}

/// Immutable geometry-only derivation for one root drawing or level. It never
/// stores edge/vertex metadata, so exact-key reuse across label, assignment,
/// elevation, and dimension changes cannot return stale user data.
struct DeckGeometryContextSnapshot {
    let vertexPositionsById: [String: CGPoint]
    let edgeSegments: [DeckGeometryEdgeSegment]
    let connectedEdgeIndicesByVertexId: [String: [Int]]
    let detectedSurfaces: [DetectedSurface]
    let orderedPositions: [CGPoint]
    let isDegreeTwoClosed: Bool
    let isSingleClosedWalk: Bool
    let totalCanvasArea: Double?
    let totalCanvasPerimeter: Double?

    static func key(vertices: [DeckVertex], edges: [DeckEdge]) -> DeckGeometryContextKey {
        DeckGeometryContextKey(
            vertices: vertices.map { DeckGeometryVertexKey(id: $0.id, position: $0.position) },
            edges: edges.map {
                DeckGeometryEdgeKey(
                    startVertexId: $0.startVertexId,
                    endVertexId: $0.endVertexId
                )
            }
        )
    }

    static func build(
        vertices: [DeckVertex],
        edges: [DeckEdge],
        closureRequiresSingleWalk: Bool
    ) -> DeckGeometryContextSnapshot {
        let vertexPositionsById = Dictionary(
            vertices.map { ($0.id, $0.position) },
            uniquingKeysWith: { first, _ in first }
        )

        var connectedEdgeIndicesByVertexId: [String: [Int]] = [:]
        var edgeSegments: [DeckGeometryEdgeSegment] = []
        edgeSegments.reserveCapacity(edges.count)
        for edge in edges {
            guard let start = vertexPositionsById[edge.startVertexId],
                  let end = vertexPositionsById[edge.endVertexId] else { continue }
            let segmentIndex = edgeSegments.count
            connectedEdgeIndicesByVertexId[edge.startVertexId, default: []].append(segmentIndex)
            connectedEdgeIndicesByVertexId[edge.endVertexId, default: []].append(segmentIndex)
            edgeSegments.append(DeckGeometryEdgeSegment(
                startVertexId: edge.startVertexId,
                endVertexId: edge.endVertexId,
                start: start,
                end: end
            ))
        }

        let degreeTwoClosed = Self.degreeTwoClosed(vertices: vertices, edges: edges)
        let singleClosedWalk = Self.singleClosedWalk(vertices: vertices, edges: edges)
        let orderedPositions = Self.orderedPositions(
            vertices: vertices,
            edges: edges,
            positionsById: vertexPositionsById
        )
        let detectedSurfaces = SurfaceDetector.detect(vertices: vertices, edges: edges)
        let closedForFallback = closureRequiresSingleWalk ? singleClosedWalk : degreeTwoClosed

        let totalCanvasArea: Double? = {
            if !detectedSurfaces.isEmpty {
                let total = detectedSurfaces.reduce(0.0) { partial, surface in
                    guard !PolygonMath.isSelfIntersecting(vertices: surface.positions) else { return partial }
                    return partial + abs(PolygonMath.signedArea(vertices: surface.positions))
                }
                return total > 0 ? total : nil
            }
            guard closedForFallback,
                  !PolygonMath.isSelfIntersecting(vertices: orderedPositions) else { return nil }
            let area = abs(PolygonMath.signedArea(vertices: orderedPositions))
            return area > 0 ? area : nil
        }()

        let perimeter = PolygonMath.perimeter(vertices: orderedPositions)

        return DeckGeometryContextSnapshot(
            vertexPositionsById: vertexPositionsById,
            edgeSegments: edgeSegments,
            connectedEdgeIndicesByVertexId: connectedEdgeIndicesByVertexId,
            detectedSurfaces: detectedSurfaces,
            orderedPositions: orderedPositions,
            isDegreeTwoClosed: degreeTwoClosed,
            isSingleClosedWalk: singleClosedWalk,
            totalCanvasArea: totalCanvasArea,
            totalCanvasPerimeter: perimeter > 0 ? perimeter : nil
        )
    }

    private static func degreeTwoClosed(vertices: [DeckVertex], edges: [DeckEdge]) -> Bool {
        guard vertices.count >= 3, edges.count >= 3 else { return false }
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].insert(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].insert(edge.startVertexId)
        }
        return vertices.allSatisfy { (adjacency[$0.id]?.count ?? 0) == 2 }
    }

    private static func singleClosedWalk(vertices: [DeckVertex], edges: [DeckEdge]) -> Bool {
        guard degreeTwoClosed(vertices: vertices, edges: edges),
              let startId = vertices.first?.id else { return false }

        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].insert(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].insert(edge.startVertexId)
        }

        var visited: Set<String> = [startId]
        var currentId = startId
        for _ in 0..<vertices.count {
            guard let neighbors = adjacency[currentId] else { return false }
            let unvisited = neighbors.subtracting(visited)
            if unvisited.isEmpty {
                return visited.count == vertices.count && neighbors.contains(startId)
            }
            guard let nextId = unvisited.first else { return false }
            visited.insert(nextId)
            currentId = nextId
        }
        return false
    }

    private static func orderedPositions(
        vertices: [DeckVertex],
        edges: [DeckEdge],
        positionsById: [String: CGPoint]
    ) -> [CGPoint] {
        guard vertices.count >= 3, edges.count >= 3 else {
            return vertices.map(\.position)
        }

        var adjacency: [String: [String]] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].append(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].append(edge.startVertexId)
        }
        for vertex in vertices where (adjacency[vertex.id]?.count ?? 0) != 2 {
            return vertices.map(\.position)
        }

        guard let startId = vertices.first?.id,
              let startPosition = positionsById[startId] else { return vertices.map(\.position) }
        var ordered: [CGPoint] = [startPosition]
        var visited: Set<String> = [startId]
        var previousId: String?
        var currentId = startId

        for _ in 0..<vertices.count - 1 {
            guard let neighbors = adjacency[currentId] else { break }
            let nextId = previousId.map { previous in
                neighbors.first(where: { $0 != previous })
            } ?? neighbors.sorted().first
            guard let nextId,
                  !visited.contains(nextId),
                  let nextPosition = positionsById[nextId] else { break }
            visited.insert(nextId)
            previousId = currentId
            currentId = nextId
            ordered.append(nextPosition)
        }

        guard ordered.count == vertices.count else { return vertices.map(\.position) }
        if PolygonMath.signedArea(vertices: ordered) > 0 {
            ordered.reverse()
        }
        return ordered
    }
}

struct DeckLevelGeometrySnapshot: Equatable {
    let levelId: String
    let key: DeckGeometryContextKey
}

struct DeckDrawingGeometryKey: Equatable {
    let root: DeckGeometryContextKey
    let levels: [DeckLevelGeometrySnapshot]
}

struct DeckDrawingGeometrySnapshot {
    let root: DeckGeometryContextSnapshot
    let levels: [(id: String, context: DeckGeometryContextSnapshot)]
    let allVertexPositionsById: [String: CGPoint]
    let totalCanvasArea: Double?
    let totalCanvasPerimeter: Double?

    func level(id: String) -> DeckGeometryContextSnapshot? {
        levels.first(where: { $0.id == id })?.context
    }
}
