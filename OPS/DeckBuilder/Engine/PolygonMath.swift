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
    /// filled deck surface. Used by the stair renderer (bug a7429390) so
    /// stairs render on the empty side of the deck edge by default.
    ///
    /// Returns the unit perpendicular as `(x, y)`. If the polygon is open or
    /// degenerate, falls back to the CCW-90° perpendicular (the historical
    /// behaviour) so existing single-edge sketches still render reasonably.
    static func outwardPerpendicular(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        polygonVertices: [CGPoint]
    ) -> (x: Double, y: Double) {
        let dx = Double(edgeEnd.x - edgeStart.x)
        let dy = Double(edgeEnd.y - edgeStart.y)
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return (0, 0) }

        // Two perpendicular candidates — 90° CCW and 90° CW.
        let perpA = (x: -dy / length, y: dx / length)   // 90° CCW
        let perpB = (x: dy / length, y: -dx / length)   // 90° CW

        // Pick a probe point a small distance along each perpendicular from
        // the edge midpoint. Whichever probe lies OUTSIDE the polygon is the
        // outward normal. If both pass (open polygon) or neither (point on
        // boundary), fall back to the CCW perpendicular.
        guard polygonVertices.count >= 3 else { return perpA }

        let midX = Double(edgeStart.x + edgeEnd.x) / 2
        let midY = Double(edgeStart.y + edgeEnd.y) / 2
        // Probe distance: small in canvas units but large enough to get
        // clear of any boundary epsilon issues.
        let probeDist: Double = 1.0
        let probeA = CGPoint(x: midX + perpA.x * probeDist, y: midY + perpA.y * probeDist)
        let probeB = CGPoint(x: midX + perpB.x * probeDist, y: midY + perpB.y * probeDist)

        let aInside = pointInPolygon(probeA, vertices: polygonVertices)
        let bInside = pointInPolygon(probeB, vertices: polygonVertices)

        if aInside && !bInside { return perpB }
        if bInside && !aInside { return perpA }
        // Ambiguous — keep historical behaviour
        return perpA
    }
}
