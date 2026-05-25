// OPS/OPS/DeckBuilder/Engine/SurfaceDetector.swift
//
// DECK-NEW-1 — multi-surface support.
//
// The previous model assumed a deck level was ONE polygon: every vertex had
// to have exactly two neighbors and the graph had to form a single Hamiltonian
// cycle. The moment the user drew anything beyond the perimeter (an internal
// detail line, a short dangling stroke, a second adjacent loop) the
// "isClosed" check failed and the entire fill disappeared.
//
// SurfaceDetector instead treats the vertex/edge set as a planar graph and
// detects every closed face. Two adjacent loops sharing an edge become two
// surfaces, dangling lines are pruned and ignored, and the renderer fills
// each detected face independently.

import Foundation
import CoreGraphics

/// One closed face in the deck-edge graph.
struct DetectedSurface: Identifiable, Equatable {
    /// Stable ID derived from the sorted vertex IDs that make up the face.
    /// Lets the selection layer remember which surface the user picked even
    /// across edits that don't change the face's vertex set.
    let id: String
    /// Vertex IDs ordered around the face boundary. Walk direction matches
    /// the canonical CCW-in-canvas-coords convention used elsewhere in the
    /// builder (negative shoelace area in screen space).
    let vertexIds: [String]
    /// Canvas-space positions of `vertexIds`, in the same order.
    let positions: [CGPoint]
}

/// Reconciles a list of persisted `DeckSurface` records with the surfaces
/// currently detected in the geometry. Goal: preserve per-surface material
/// and label assignments across edits.
///
/// Strategy:
/// 1. For each detected surface, look for a persisted entry with EXACTLY
///    the same vertex set (no rebind needed).
/// 2. Otherwise, find the unclaimed persisted entry with the highest
///    Jaccard overlap. If the overlap meets `rebindThreshold`, treat it
///    as the same surface across the edit and update its `vertexIds`.
/// 3. Detected surfaces with no acceptable match get a brand-new persisted
///    entry (empty `assignedItems` / `label`).
/// 4. Persisted entries that nothing matched are dropped.
enum SurfaceReconciler {
    /// Minimum Jaccard overlap between a detected surface's vertex set and
    /// an unclaimed persisted DeckSurface's vertex set for them to be
    /// treated as the same surface across an edit.
    static let rebindThreshold: Double = 0.5

    /// Returns a reconciled surfaces array — one entry per detected surface,
    /// in the same order as `detected`. Pure function: callers persist the
    /// returned array on `DeckDrawingData.surfaces` (or `DeckLevel.surfaces`).
    static func reconcile(
        detected: [DetectedSurface],
        persisted: [DeckSurface]
    ) -> [DeckSurface] {
        guard !detected.isEmpty else { return [] }

        var claimedIds: Set<String> = []
        var output: [DeckSurface] = []

        for d in detected {
            let dSet = Set(d.vertexIds)

            // Exact match wins outright.
            if let exact = persisted.first(where: {
                !claimedIds.contains($0.id) && $0.vertexIds == dSet
            }) {
                claimedIds.insert(exact.id)
                output.append(exact)
                continue
            }

            // Best Jaccard match among unclaimed entries.
            var bestMatch: (surface: DeckSurface, jaccard: Double)? = nil
            for p in persisted where !claimedIds.contains(p.id) {
                let intersection = dSet.intersection(p.vertexIds).count
                let union = dSet.union(p.vertexIds).count
                guard union > 0 else { continue }
                let jaccard = Double(intersection) / Double(union)
                if jaccard > (bestMatch?.jaccard ?? -1) {
                    bestMatch = (p, jaccard)
                }
            }

            if let match = bestMatch, match.jaccard >= rebindThreshold {
                claimedIds.insert(match.surface.id)
                var rebound = match.surface
                rebound.vertexIds = dSet
                output.append(rebound)
            } else {
                output.append(DeckSurface(vertexIds: dSet))
            }
        }

        return output
    }

    /// Migrates legacy `DeckFootprint.assignedItems` / `label` onto the
    /// largest detected surface — once. Call this when the persisted
    /// surfaces array is empty but the legacy footprint has a populated
    /// payload. The caller is responsible for clearing the legacy fields
    /// after this returns so the migration is idempotent.
    static func migratedFromLegacy(
        detected: [DetectedSurface],
        legacyFootprint: DeckFootprint
    ) -> [DeckSurface] {
        let baseline = reconcile(detected: detected, persisted: [])
        guard !baseline.isEmpty else { return [] }

        let hasLegacyPayload = !legacyFootprint.assignedItems.isEmpty || legacyFootprint.label != nil
        guard hasLegacyPayload else { return baseline }

        // Pick the largest detected surface (matches the previous
        // single-footprint render behavior — items applied to the biggest
        // visible polygon).
        let detectedAreas = detected.map { face -> Double in
            abs(PolygonMath.signedArea(vertices: face.positions))
        }
        guard let largestIdx = detectedAreas.indices.max(by: { detectedAreas[$0] < detectedAreas[$1] }) else {
            return baseline
        }

        var migrated = baseline
        migrated[largestIdx].assignedItems = legacyFootprint.assignedItems
        if let label = legacyFootprint.label, !label.isEmpty {
            migrated[largestIdx].label = label
        }
        return migrated
    }
}

enum SurfaceDetector {

    /// Find every closed face in the edge graph. Returns an empty array when
    /// nothing is closed yet. Uses the planar face-walking algorithm:
    ///   1. Prune vertices of degree ≤ 1 iteratively (drops dangling lines
    ///      that aren't part of any cycle).
    ///   2. Sort each surviving vertex's neighbors by angle.
    ///   3. For each directed edge (u, v), follow the next edge clockwise
    ///      around v from u — this traces the face on one side of (u, v).
    ///      Visiting both directions of every edge enumerates every face,
    ///      including the unbounded outer face.
    ///   4. Drop the outer face (largest absolute signed area) and dedupe.
    static func detect(vertices: [DeckVertex], edges: [DeckEdge]) -> [DetectedSurface] {
        guard vertices.count >= 3, edges.count >= 3 else { return [] }

        // 1. Adjacency
        var adjacency: [String: Set<String>] = [:]
        for v in vertices { adjacency[v.id] = [] }
        for e in edges {
            // Self-loops can't bound a face.
            guard e.startVertexId != e.endVertexId else { continue }
            adjacency[e.startVertexId, default: []].insert(e.endVertexId)
            adjacency[e.endVertexId, default: []].insert(e.startVertexId)
        }

        // 2. Prune degree-≤1 vertices iteratively. After this pass every
        //    surviving vertex has at least two neighbors and is therefore a
        //    candidate for face membership.
        var changed = true
        while changed {
            changed = false
            let danglers = adjacency.compactMap { $0.value.count <= 1 ? $0.key : nil }
            for d in danglers {
                let neighbors = adjacency[d] ?? []
                for n in neighbors { adjacency[n]?.remove(d) }
                adjacency.removeValue(forKey: d)
                changed = true
            }
        }

        let coreIds = Set(adjacency.keys)
        guard coreIds.count >= 3 else { return [] }

        let vertexById: [String: DeckVertex] = Dictionary(
            uniqueKeysWithValues: vertices.filter { coreIds.contains($0.id) }.map { ($0.id, $0) }
        )

        // 3. Angularly sort each vertex's neighbors. We use atan2(dy, dx) in
        //    screen coords (Y-down). The "next edge clockwise around v from u"
        //    in screen coords corresponds to the PREVIOUS entry in this sort.
        var sortedNeighbors: [String: [String]] = [:]
        for vid in coreIds {
            guard let center = vertexById[vid] else { continue }
            let sorted = (adjacency[vid] ?? []).sorted { a, b in
                guard let pa = vertexById[a]?.position, let pb = vertexById[b]?.position else { return false }
                let angA = atan2(pa.y - center.position.y, pa.x - center.position.x)
                let angB = atan2(pb.y - center.position.y, pb.x - center.position.x)
                return angA < angB
            }
            sortedNeighbors[vid] = sorted
        }

        // 4. Walk faces. Each directed edge belongs to exactly one face on
        //    its left side (relative to the walk).
        var visited: Set<String> = []
        let edgeKey: (String, String) -> String = { "\($0)|\($1)" }

        func nextDirectedEdge(from u: String, to v: String) -> (String, String)? {
            guard let neighbors = sortedNeighbors[v], !neighbors.isEmpty,
                  let idxU = neighbors.firstIndex(of: u) else { return nil }
            // Take the neighbor immediately clockwise from u around v —
            // that's the previous entry in the CCW-sorted list (Y-down
            // makes the "screen CCW" winding correspond to math CW).
            let prevIdx = (idxU - 1 + neighbors.count) % neighbors.count
            let w = neighbors[prevIdx]
            return (v, w)
        }

        var rawFaces: [[String]] = []

        let walkableEdges = edges.filter {
            coreIds.contains($0.startVertexId) && coreIds.contains($0.endVertexId)
        }

        for edge in walkableEdges {
            for (u0, v0) in [(edge.startVertexId, edge.endVertexId),
                              (edge.endVertexId, edge.startVertexId)] {
                if visited.contains(edgeKey(u0, v0)) { continue }

                var face: [String] = []
                var (u, v) = (u0, v0)
                let cap = walkableEdges.count * 4 + 4
                var iter = 0
                var safe = true
                while iter < cap {
                    if visited.contains(edgeKey(u, v)) {
                        // Re-visiting a directed edge inside a single walk
                        // means the graph topology is unexpected (e.g.
                        // multi-edge). Bail rather than loop forever.
                        safe = false
                        break
                    }
                    visited.insert(edgeKey(u, v))
                    face.append(u)
                    guard let next = nextDirectedEdge(from: u, to: v) else {
                        safe = false
                        break
                    }
                    if next.0 == u0 && next.1 == v0 {
                        // Closed cleanly back to the starting directed edge.
                        break
                    }
                    u = next.0
                    v = next.1
                    iter += 1
                }

                if safe && face.count >= 3 {
                    rawFaces.append(face)
                }
            }
        }

        guard !rawFaces.isEmpty else { return [] }

        // 5. Each connected component of the planar graph contributes its
        //    own unbounded outer face (the CCW walk around the entire
        //    component). The previous implementation only dropped the
        //    SINGLE largest face, which left the outer face of every
        //    smaller component in the result — those rendered in 3D as
        //    stray inverted polygons that visually "connected" two
        //    distinct surfaces. Bug 6d1c0a2a.
        //
        //    Fix: partition faces by connected component (via vertex-set
        //    union-find on adjacency), then drop the largest face from
        //    each component. The remaining faces are the true interior
        //    surfaces.
        struct FaceWithArea {
            let ids: [String]
            let positions: [CGPoint]
            let absArea: Double
        }

        let faces: [FaceWithArea] = rawFaces.map { ids in
            let positions = ids.compactMap { vertexById[$0]?.position }
            let area = abs(PolygonMath.signedArea(vertices: positions))
            return FaceWithArea(ids: ids, positions: positions, absArea: area)
        }

        // Build connected components via BFS over the core adjacency.
        var componentOf: [String: Int] = [:]
        var nextComponent = 0
        for seed in coreIds where componentOf[seed] == nil {
            var queue: [String] = [seed]
            componentOf[seed] = nextComponent
            while let v = queue.popLast() {
                for n in adjacency[v] ?? [] where componentOf[n] == nil {
                    componentOf[n] = nextComponent
                    queue.append(n)
                }
            }
            nextComponent += 1
        }

        // Find the largest face per component — that's its outer face.
        var outerIndicesByComponent: [Int: Int] = [:]
        for (i, face) in faces.enumerated() {
            guard let component = face.ids.first.flatMap({ componentOf[$0] }) else { continue }
            if let prev = outerIndicesByComponent[component] {
                if face.absArea > faces[prev].absArea {
                    outerIndicesByComponent[component] = i
                }
            } else {
                outerIndicesByComponent[component] = i
            }
        }
        let outerIndices = Set(outerIndicesByComponent.values)

        // 6. Dedupe inner faces by sorted vertex set. The walk should already
        //    enumerate each face once, but this is cheap insurance against
        //    pathological topologies.
        var seen: Set<String> = []
        var result: [DetectedSurface] = []
        for (i, f) in faces.enumerated() where !outerIndices.contains(i) {
            // A degenerate face with zero area (collinear vertices) isn't a
            // real surface — skip it.
            guard f.absArea > 0.5 else { continue }
            let dedupKey = f.ids.sorted().joined(separator: "|")
            if seen.insert(dedupKey).inserted {
                result.append(DetectedSurface(
                    id: "surface-" + String(dedupKey.hashValue),
                    vertexIds: f.ids,
                    positions: f.positions
                ))
            }
        }

        return result
    }
}
