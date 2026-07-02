// OPS/OPS/DeckBuilder/Engine/PolygonSplitter.swift

import Foundation
import SwiftUI

/// Pure geometry: split a simple polygon by the INFINITE line through two
/// points. Used by the fullscreen viewer's look-only split tool — the user
/// draws a rough slash across a selected surface (endpoints anywhere) and
/// reads the area on each side. Sutherland–Hodgman half-plane clipping:
/// concave polygons may split into multiple pieces per side; each side is
/// returned as ONE polygon whose zero-width bridges are invisible in fills
/// and contribute nothing to the shoelace area, so per-side totals stay
/// correct — which is the number the user asked for.
enum PolygonSplitter {

    struct ChordSegment: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    struct SplitResult: Equatable {
        /// Vertices on the cross(B−A, p−A) ≥ 0 side. Empty when the line misses.
        let sideA: [CGPoint]
        /// Vertices on the other side.
        let sideB: [CGPoint]
        /// Visible cut segments — the line clipped to the polygon interior.
        let chordSegments: [ChordSegment]
        /// True when the line genuinely crosses the face: both sides carry
        /// meaningful area (≥ 0.5% of the whole — degenerate slivers from a
        /// cut along an edge do not count as a split).
        let didSplit: Bool
    }

    /// Signed side of point `p` relative to the directed line a→b.
    private static func side(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        (Double(b.x) - Double(a.x)) * (Double(p.y) - Double(a.y))
      - (Double(b.y) - Double(a.y)) * (Double(p.x) - Double(a.x))
    }

    /// Intersection of segment p→q with the infinite line a→b (call only when
    /// p and q are on strictly opposite sides).
    private static func intersect(_ p: CGPoint, _ q: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let sp = side(p, a, b)
        let sq = side(q, a, b)
        let t = sp / (sp - sq)
        return CGPoint(
            x: p.x + CGFloat(t) * (q.x - p.x),
            y: p.y + CGFloat(t) * (q.y - p.y)
        )
    }

    /// Sutherland–Hodgman: clip `polygon` to one half-plane of line a→b.
    /// `keepPositive` selects the cross ≥ 0 side. On-line vertices (|side| ≤ ε)
    /// are kept by BOTH half-planes so the two outputs share the cut boundary.
    static func clip(polygon: [CGPoint], lineA a: CGPoint, lineB b: CGPoint, keepPositive: Bool) -> [CGPoint] {
        guard polygon.count >= 3 else { return [] }
        let epsilon = 1e-9
        var output: [CGPoint] = []
        let n = polygon.count
        for i in 0..<n {
            let current = polygon[i]
            let next = polygon[(i + 1) % n]
            let sc = side(current, a, b) * (keepPositive ? 1 : -1)
            let sn = side(next, a, b) * (keepPositive ? 1 : -1)
            let currentIn = sc >= -epsilon
            let nextIn = sn >= -epsilon
            if currentIn {
                output.append(current)
                if !nextIn {
                    output.append(intersect(current, next, a, b))
                }
            } else if nextIn {
                output.append(intersect(current, next, a, b))
            }
        }
        return output.count >= 3 ? output : []
    }

    /// Split `polygon` by the infinite line through `lineA`→`lineB`.
    static func split(polygon: [CGPoint], lineA: CGPoint, lineB: CGPoint) -> SplitResult {
        let none = SplitResult(sideA: [], sideB: [], chordSegments: [], didSplit: false)
        guard polygon.count >= 3 else { return none }
        // Coincident definition points define no line.
        guard SnapEngine.distance(lineA, lineB) > 0.5 else { return none }

        let a = clip(polygon: polygon, lineA: lineA, lineB: lineB, keepPositive: true)
        let b = clip(polygon: polygon, lineA: lineA, lineB: lineB, keepPositive: false)

        let total = PolygonMath.area(vertices: polygon)
        let areaA = PolygonMath.area(vertices: a)
        let areaB = PolygonMath.area(vertices: b)
        // Both sides must carry real area — a cut along an edge or a miss
        // leaves one side ~empty and is not a split.
        let minimum = total * 0.005
        guard total > 0, areaA >= minimum, areaB >= minimum else { return none }

        return SplitResult(
            sideA: a,
            sideB: b,
            chordSegments: chords(polygon: polygon, lineA: lineA, lineB: lineB),
            didSplit: true
        )
    }

    /// The visible cut: intersections of the line with the polygon boundary,
    /// sorted along the line direction, paired even–odd into interior segments.
    static func chords(polygon: [CGPoint], lineA a: CGPoint, lineB b: CGPoint) -> [ChordSegment] {
        guard polygon.count >= 3 else { return [] }
        let epsilon = 1e-9
        var hits: [CGPoint] = []
        let n = polygon.count
        for i in 0..<n {
            let p = polygon[i]
            let q = polygon[(i + 1) % n]
            let sp = side(p, a, b)
            let sq = side(q, a, b)
            if (sp > epsilon && sq < -epsilon) || (sp < -epsilon && sq > epsilon) {
                hits.append(intersect(p, q, a, b))
            } else if abs(sp) <= epsilon {
                hits.append(p) // vertex exactly on the line
            }
        }
        guard hits.count >= 2 else { return [] }
        // Sort along the line direction, dedupe near-identical hits (vertex +
        // both touching edges can each report the same point).
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        var sorted = hits.sorted {
            (Double($0.x) * dx + Double($0.y) * dy) < (Double($1.x) * dx + Double($1.y) * dy)
        }
        var deduped: [CGPoint] = []
        for h in sorted {
            if let last = deduped.last, SnapEngine.distance(last, h) < 0.5 { continue }
            deduped.append(h)
        }
        sorted = deduped
        var segments: [ChordSegment] = []
        var i = 0
        while i + 1 < sorted.count {
            let mid = CGPoint(x: (sorted[i].x + sorted[i + 1].x) / 2, y: (sorted[i].y + sorted[i + 1].y) / 2)
            if PolygonMath.pointInPolygon(mid, vertices: polygon) {
                segments.append(ChordSegment(start: sorted[i], end: sorted[i + 1]))
                i += 1
            } else {
                i += 1
            }
        }
        return segments
    }
}
