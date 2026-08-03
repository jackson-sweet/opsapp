// OPS/OPS/DeckBuilder/Engine/PolygonMath.swift

import Foundation
import SwiftUI

struct PolygonMath {

    // MARK: - Area (Shoelace Formula)

    /// Calculate the area of a polygon defined by ordered vertices (canvas coordinates)
    /// Returns area in canvas points squared
    static func area(vertices: [CGPoint]) -> Double {
        abs(signedArea(vertices: vertices))
    }

    /// Signed shoelace area. Sign encodes winding direction: in SwiftUI canvas
    /// coordinates (Y-down) a positive result means the vertices wind CW
    /// visually, negative means CCW. Used by `orderedPositions` to normalize
    /// winding so downstream code (3D extrusion normals, AR placement, any
    /// future fill-rule-sensitive consumer) sees a consistent direction.
    static func signedArea(vertices: [CGPoint]) -> Double {
        guard vertices.count >= 3 else { return 0 }
        var sum = 0.0
        let n = vertices.count
        for i in 0..<n {
            let j = (i + 1) % n
            sum += Double(vertices[i].x * vertices[j].y)
            sum -= Double(vertices[j].x * vertices[i].y)
        }
        return sum / 2.0
    }

    /// Calculate area in real-world square inches given a scale factor
    static func realWorldArea(vertices: [CGPoint], scaleFactor: Double) -> Double {
        guard scaleFactor > 0 else { return 0 }
        let canvasArea = area(vertices: vertices)
        return canvasArea / (scaleFactor * scaleFactor)
    }

    // MARK: - Centroid

    /// Area-weighted centroid of a simple polygon — the correct anchor for a
    /// label that must sit "inside the shape" even when it's concave (the
    /// plain vertex average drifts toward dense vertex clusters and can exit
    /// an L-shape entirely). Falls back to the vertex average for degenerate
    /// inputs (< 3 vertices or near-zero area) where the standard formula
    /// divides by ~0. Canvas coordinates in, canvas coordinates out.
    static func polygonCentroid(vertices: [CGPoint]) -> CGPoint? {
        guard !vertices.isEmpty else { return nil }
        let n = vertices.count
        let vertexAverage = CGPoint(
            x: vertices.reduce(0.0) { $0 + Double($1.x) } / Double(n),
            y: vertices.reduce(0.0) { $0 + Double($1.y) } / Double(n)
        )
        guard n >= 3 else { return vertexAverage }

        let a = signedArea(vertices: vertices)
        guard abs(a) > 1e-6 else { return vertexAverage }

        var cx = 0.0
        var cy = 0.0
        for i in 0..<n {
            let j = (i + 1) % n
            let cross = Double(vertices[i].x) * Double(vertices[j].y)
                      - Double(vertices[j].x) * Double(vertices[i].y)
            cx += (Double(vertices[i].x) + Double(vertices[j].x)) * cross
            cy += (Double(vertices[i].y) + Double(vertices[j].y)) * cross
        }
        return CGPoint(x: cx / (6 * a), y: cy / (6 * a))
    }

    // MARK: - Perimeter

    /// Calculate total perimeter in canvas points
    static func perimeter(vertices: [CGPoint]) -> Double {
        guard vertices.count >= 2 else { return 0 }
        var total = 0.0
        for i in 0..<vertices.count {
            let j = (i + 1) % vertices.count
            total += SnapEngine.distance(vertices[i], vertices[j])
        }
        return total
    }

    // MARK: - Edge Length

    /// Calculate the length of an edge between two vertex positions
    static func edgeLength(from start: CGPoint, to end: CGPoint) -> Double {
        SnapEngine.distance(start, end)
    }

    // MARK: - Point in Polygon (Ray Casting)

    /// Test if a point is inside a polygon defined by ordered vertices
    static func pointInPolygon(_ point: CGPoint, vertices: [CGPoint]) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        let n = vertices.count
        var j = n - 1
        for i in 0..<n {
            let vi = vertices[i]
            let vj = vertices[j]
            if (vi.y > point.y) != (vj.y > point.y) {
                let intersectX = vj.x + (point.y - vj.y) / (vi.y - vj.y) * (vi.x - vj.x)
                if point.x < intersectX {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }

    // MARK: - Self-Intersection Detection

    /// Check if a polygon's edges cross each other (figure-8, bowties, etc.)
    /// Only checks non-adjacent edge pairs. Returns true if any intersection found.
    static func isSelfIntersecting(vertices: [CGPoint]) -> Bool {
        let n = vertices.count
        guard n >= 4 else { return false } // triangles can't self-intersect

        // Outer loop stops at n - 1: when i == n - 1 the inner range
        // (i + 2)..<n would be (n + 1)..<n and crash Swift's Range init.
        // Every non-adjacent pair involving the last edge is already
        // visited by earlier i values, so skipping i = n - 1 is lossless.
        for i in 0..<(n - 1) {
            let a1 = vertices[i]
            let a2 = vertices[(i + 1) % n]

            // Check against non-adjacent edges (skip i-1 and i+1 which share vertices)
            for j in (i + 2)..<n {
                // Skip if j wraps to be adjacent to i
                if i == 0 && j == n - 1 { continue }

                let b1 = vertices[j]
                let b2 = vertices[(j + 1) % n]

                if segmentsIntersect(a1, a2, b1, b2) {
                    return true
                }
            }
        }
        return false
    }

    /// Test if two line segments (p1→p2) and (p3→p4) properly intersect (cross each other)
    private static func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        let d1 = direction(p3, p4, p1)
        let d2 = direction(p3, p4, p2)
        let d3 = direction(p1, p2, p3)
        let d4 = direction(p1, p2, p4)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        return false
    }

    /// Cross product of vectors (pi→pk) relative to (pi→pj)
    private static func direction(_ pi: CGPoint, _ pj: CGPoint, _ pk: CGPoint) -> Double {
        (Double(pk.x) - Double(pi.x)) * (Double(pj.y) - Double(pi.y)) -
        (Double(pk.y) - Double(pi.y)) * (Double(pj.x) - Double(pi.x))
    }

    // MARK: - Edge Hit Testing

    /// Find the closest point on a line segment to a given point
    /// Returns (closest point, distance to point)
    static func closestPointOnSegment(
        point: CGPoint,
        segStart: CGPoint,
        segEnd: CGPoint
    ) -> (closest: CGPoint, distance: Double) {
        let dx = segEnd.x - segStart.x
        let dy = segEnd.y - segStart.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            // Degenerate segment (start == end)
            let d = SnapEngine.distance(point, segStart)
            return (segStart, d)
        }

        // Project point onto segment, clamped to [0, 1]
        var t = ((point.x - segStart.x) * dx + (point.y - segStart.y) * dy) / lengthSquared
        t = max(0, min(1, t))

        let closest = CGPoint(
            x: segStart.x + t * dx,
            y: segStart.y + t * dy
        )
        let d = SnapEngine.distance(point, closest)
        return (closest, d)
    }

    /// Find the edge closest to a tap point within a hit threshold
    /// Returns edge ID or nil
    static func findEdgeAtPoint(
        _ point: CGPoint,
        edges: [DeckEdge],
        vertices: [DeckVertex],
        hitThreshold: Double = 20.0
    ) -> String? {
        var closestEdgeId: String?
        var closestDistance = Double.infinity

        for edge in edges {
            guard let start = vertices.first(where: { $0.id == edge.startVertexId }),
                  let end = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }

            let (_, distance) = closestPointOnSegment(
                point: point,
                segStart: start.position,
                segEnd: end.position
            )

            if distance < hitThreshold && distance < closestDistance {
                closestDistance = distance
                closestEdgeId = edge.id
            }
        }
        return closestEdgeId
    }

    /// Find the vertex closest to a tap point within a hit threshold
    static func findVertexAtPoint(
        _ point: CGPoint,
        vertices: [DeckVertex],
        hitThreshold: Double = 25.0
    ) -> String? {
        var closestId: String?
        var closestDistance = Double.infinity

        for vertex in vertices {
            let d = SnapEngine.distance(point, vertex.position)
            if d < hitThreshold && d < closestDistance {
                closestDistance = d
                closestId = vertex.id
            }
        }
        return closestId
    }

    /// Outward perpendicular unit vector for an edge inside a closed polygon.
    /// "Outward" means away from the polygon interior — i.e. away from the
    /// filled deck surface. Used by the stair renderers (bug a7429390) so
    /// stairs land on the empty side of the deck edge by default.
    ///
    /// Resolved from the polygon's WINDING, not by probing points near the
    /// boundary. For any simple polygon — convex or concave — the interior
    /// lies to the left of every edge traversed in positive-area order and to
    /// the right in negative-area order, so the outward side follows exactly
    /// once we know which way this edge runs relative to that traversal.
    ///
    /// The previous implementation offset 1 canvas unit off the edge midpoint
    /// and asked `pointInPolygon` which side was inside. That is unstable near
    /// short edges and at boundary epsilons, and it silently returned garbage
    /// whenever the caller supplied a non-simple polygon (see
    /// `DeckDrawingData.stairFacePolygon(forEdgeId:)` — the callers' old
    /// `orderedPositions` degenerates to an unordered vertex dump the moment a
    /// drawing holds two shapes or any detail line, which is what made stairs
    /// face the wrong way on most real decks).
    ///
    /// Falls back to the CCW-90° perpendicular (historical behaviour) for a
    /// degenerate polygon, and to a centroid test when the edge is not one of
    /// the polygon's own sides.
    static func outwardPerpendicular(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        polygonVertices: [CGPoint]
    ) -> (x: Double, y: Double) {
        let dx = Double(edgeEnd.x - edgeStart.x)
        let dy = Double(edgeEnd.y - edgeStart.y)
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return (0, 0) }

        // Perpendicular candidates: "left" of the edge direction and "right".
        let left = (x: -dy / length, y: dx / length)
        let right = (x: dy / length, y: -dx / length)

        guard polygonVertices.count >= 3 else { return left }
        let area = signedArea(vertices: polygonVertices)
        guard area != 0 else { return left }

        // Interior is left of a positively-wound traversal → outward is right.
        let outwardAlongTraversal = area > 0 ? right : left

        if let runsForward = edgeRunsWithTraversal(
            edgeStart: edgeStart,
            edgeEnd: edgeEnd,
            polygonVertices: polygonVertices
        ) {
            return runsForward
                ? outwardAlongTraversal
                : (x: -outwardAlongTraversal.x, y: -outwardAlongTraversal.y)
        }

        // Edge isn't a side of this polygon (transformed/clipped input):
        // point away from the polygon's centroid.
        let centroidX = polygonVertices.reduce(0.0) { $0 + Double($1.x) } / Double(polygonVertices.count)
        let centroidY = polygonVertices.reduce(0.0) { $0 + Double($1.y) } / Double(polygonVertices.count)
        let midX = Double(edgeStart.x + edgeEnd.x) / 2
        let midY = Double(edgeStart.y + edgeEnd.y) / 2
        let awayX = midX - centroidX
        let awayY = midY - centroidY
        return (left.x * awayX + left.y * awayY) >= 0 ? left : right
    }

    /// Whether the given edge runs WITH the polygon's own vertex traversal.
    /// Returns nil when the edge is not one of the polygon's sides. Endpoint
    /// matching uses an epsilon scaled to the polygon's extent so the same
    /// logic serves canvas points and metres alike.
    private static func edgeRunsWithTraversal(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        polygonVertices: [CGPoint]
    ) -> Bool? {
        let xs = polygonVertices.map { Double($0.x) }
        let ys = polygonVertices.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let extent = max(maxX - minX, maxY - minY)
        // Tolerance rides the polygon's own size, with a floor for tiny shapes.
        let epsilon = max(extent * 1e-4, 1e-6)

        func matches(_ a: CGPoint, _ b: CGPoint) -> Bool {
            abs(Double(a.x - b.x)) <= epsilon && abs(Double(a.y - b.y)) <= epsilon
        }

        let count = polygonVertices.count
        for index in 0..<count {
            let sideStart = polygonVertices[index]
            let sideEnd = polygonVertices[(index + 1) % count]
            if matches(sideStart, edgeStart) && matches(sideEnd, edgeEnd) { return true }
            if matches(sideStart, edgeEnd) && matches(sideEnd, edgeStart) { return false }
        }
        return nil
    }
}
