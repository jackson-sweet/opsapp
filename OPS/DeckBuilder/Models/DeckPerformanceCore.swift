// OPS/DeckBuilder/Models/DeckPerformanceCore.swift

import CoreGraphics
import Foundation

/// Exact, ordered geometry identity for one drawing context. Only inputs that
/// can change topology or canvas-space metrics participate; labels, materials,
/// dimensions, and other metadata intentionally do not evict derived geometry.
struct DeckGeometryVertexKey: Equatable {
    let id: String
    let position: CGPoint
}

struct DeckGeometryEdgeKey: Equatable {
    let startVertexId: String
    let endVertexId: String
}

struct DeckGeometryContextKey: Equatable {
    let vertices: [DeckGeometryVertexKey]
    let edges: [DeckGeometryEdgeKey]
}

/// Small exact-key memoizer used by drawing and level geometry snapshots.
/// Reference semantics let value copies of `DeckDrawingData` retain the last
/// valid derivation; the exact key still prevents stale reuse after mutation.
final class DeckExactDerivedCache<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?
    private(set) var missCount = 0

    func resolve(key candidate: Key, build: () -> Value) -> Value {
        if key == candidate, let value {
            return value
        }

        let next = build()
        key = candidate
        value = next
        missCount += 1
        return next
    }
}

/// Coalesces an arbitrary burst of gesture callbacks into one scheduled frame
/// publication while always retaining the newest payload.
struct DeckGestureFrameBatcher<Value> {
    private var pending: Value?
    private var hasScheduledPublication = false
    private(set) var submissionCount = 0
    private(set) var publicationCount = 0

    /// Returns true only for the submission that must schedule a publication.
    mutating func submit(_ value: Value) -> Bool {
        pending = value
        submissionCount += 1
        guard !hasScheduledPublication else { return false }
        hasScheduledPublication = true
        return true
    }

    /// Consumes the latest submitted value and reopens the next frame slot.
    mutating func consume() -> Value? {
        guard hasScheduledPublication, let pending else { return nil }
        self.pending = nil
        hasScheduledPublication = false
        publicationCount += 1
        return pending
    }

    mutating func reset() {
        pending = nil
        hasScheduledPublication = false
    }
}

protocol DeckGeometryMutationVertex {
    var id: String { get }
    var position: CGPoint { get set }
}

protocol DeckGeometryMutationEdge {
    var id: String { get }
    var startVertexId: String { get }
    var endVertexId: String { get }
    var dimension: Double? { get set }
    var usesScaleDerivedDimension: Bool { get }
    var dimensionStale: Bool { get set }
}

struct DeckGeometryMutationMetrics: Equatable {
    let vertexIndexBuildCount: Int
    let updatedVertexCount: Int
    let edgeVisitCount: Int
    let dimensionRecalculationCount: Int
}

struct DeckGeometryMutationResult<Vertex, Edge> {
    let vertices: [Vertex]
    let edges: [Edge]
    let metrics: DeckGeometryMutationMetrics
}

/// Applies every live vertex position and every connected-edge dimension rule
/// in bounded linear passes. The old view-model path rescanned the edge array
/// once per moved vertex and repeatedly performed linear endpoint lookups.
enum DeckGeometryMutationEngine {
    static func applying<Vertex: DeckGeometryMutationVertex, Edge: DeckGeometryMutationEdge>(
        positions: [String: CGPoint],
        to sourceVertices: [Vertex],
        edges sourceEdges: [Edge],
        scaleFactor: Double?,
        fallbackScale: Double,
        staleThresholdInches: Double = 0.5
    ) -> DeckGeometryMutationResult<Vertex, Edge> {
        var vertices = sourceVertices
        var vertexIndexById: [String: Int] = [:]
        vertexIndexById.reserveCapacity(vertices.count)
        for index in vertices.indices {
            vertexIndexById[vertices[index].id] = index
        }

        var updatedVertexIds: Set<String> = []
        updatedVertexIds.reserveCapacity(positions.count)
        for (id, position) in positions {
            guard let index = vertexIndexById[id] else { continue }
            vertices[index].position = position
            updatedVertexIds.insert(id)
        }

        var edges = sourceEdges
        var dimensionRecalculationCount = 0
        let resolvedScale = (scaleFactor.map { $0 > 0 ? $0 : nil } ?? nil) ?? fallbackScale

        for index in edges.indices {
            let startId = edges[index].startVertexId
            let endId = edges[index].endVertexId
            guard updatedVertexIds.contains(startId) || updatedVertexIds.contains(endId),
                  let startIndex = vertexIndexById[startId],
                  let endIndex = vertexIndexById[endId] else { continue }

            dimensionRecalculationCount += 1
            let canvasDistance = hypot(
                vertices[endIndex].position.x - vertices[startIndex].position.x,
                vertices[endIndex].position.y - vertices[startIndex].position.y
            )

            if edges[index].usesScaleDerivedDimension {
                edges[index].dimension = Double(canvasDistance) / resolvedScale
                edges[index].dimensionStale = false
            } else if let typed = edges[index].dimension,
                      let scaleFactor,
                      scaleFactor > 0 {
                let drawnInches = Double(canvasDistance) / scaleFactor
                edges[index].dimensionStale = abs(drawnInches - typed) >= staleThresholdInches
            } else {
                edges[index].dimensionStale = false
            }
        }

        return DeckGeometryMutationResult(
            vertices: vertices,
            edges: edges,
            metrics: DeckGeometryMutationMetrics(
                vertexIndexBuildCount: 1,
                updatedVertexCount: updatedVertexIds.count,
                edgeVisitCount: edges.count,
                dimensionRecalculationCount: dimensionRecalculationCount
            )
        )
    }
}

/// Deterministic change gate for the SceneKit bridge. A committed drawing
/// revision replaces full JSON serialization as the rebuild decision.
struct DeckSceneRevisionGate {
    private var lastRevision: UInt64?
    private(set) var rebuildCount = 0

    mutating func shouldRebuild(for revision: UInt64) -> Bool {
        guard lastRevision != revision else { return false }
        lastRevision = revision
        rebuildCount += 1
        return true
    }
}
