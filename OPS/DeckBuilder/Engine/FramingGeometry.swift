import CoreGraphics
import Foundation

/// Pure canvas-space geometry shared by the transient framing planner and its
/// SceneKit renderer. Lines are always clipped against detected surface loops,
/// so concave outlines can produce several honest member segments instead of
/// one member that bridges empty space.
enum FramingGeometry {
    struct Segment: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    static func blockingRows(
        joistSpanInches: Double,
        surface: [CGPoint],
        joistAxis: CGVector,
        capInches: Double,
        scaleFactor: Double
    ) -> [Segment] {
        guard surface.count >= 3,
              joistSpanInches > 0,
              capInches > 0,
              scaleFactor > 0,
              let axis = unit(joistAxis) else { return [] }

        let rowCount = max(0, Int(ceil(joistSpanInches / capInches)) - 1)
        guard rowCount > 0,
              let bounds = projectionBounds(of: surface, onto: axis) else { return [] }

        let spacing = (bounds.max - bounds.min) / CGFloat(rowCount + 1)
        let rowDirection = CGVector(dx: -axis.dy, dy: axis.dx)
        return (1...rowCount).flatMap { rowIndex in
            clippedLine(
                to: surface,
                direction: rowDirection,
                normal: axis,
                projection: bounds.min + CGFloat(rowIndex) * spacing
            )
        }
    }

    static func clippedLine(
        to surface: [CGPoint],
        direction: CGVector,
        normal: CGVector,
        projection: CGFloat
    ) -> [Segment] {
        guard surface.count >= 3,
              let lineDirection = unit(direction),
              let lineNormal = unit(normal) else { return [] }

        let lineA = CGPoint(
            x: lineNormal.dx * projection,
            y: lineNormal.dy * projection
        )
        let lineB = CGPoint(
            x: lineA.x + lineDirection.dx,
            y: lineA.y + lineDirection.dy
        )

        return PolygonSplitter.chords(polygon: surface, lineA: lineA, lineB: lineB)
            .map { canonicalSegment(start: $0.start, end: $0.end) }
            .filter { SnapEngine.distance($0.start, $0.end) > 0.001 }
            .sorted(by: segmentComesFirst)
    }

    static func projectionBounds(
        of points: [CGPoint],
        onto axis: CGVector
    ) -> (min: CGFloat, max: CGFloat)? {
        guard let unitAxis = unit(axis), let first = points.first else { return nil }
        var minimum = dot(first, unitAxis)
        var maximum = minimum
        for point in points.dropFirst() {
            let projection = dot(point, unitAxis)
            minimum = min(minimum, projection)
            maximum = max(maximum, projection)
        }
        return (minimum, maximum)
    }

    static func inwardNormal(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        surface: [CGPoint]
    ) -> CGVector? {
        let edgeVector = CGVector(dx: edgeEnd.x - edgeStart.x, dy: edgeEnd.y - edgeStart.y)
        guard let along = unit(edgeVector) else { return nil }

        let candidateA = CGVector(dx: -along.dy, dy: along.dx)
        let candidateB = CGVector(dx: -candidateA.dx, dy: -candidateA.dy)
        let midpoint = CGPoint(x: (edgeStart.x + edgeEnd.x) / 2, y: (edgeStart.y + edgeEnd.y) / 2)
        let edgeLength = SnapEngine.distance(edgeStart, edgeEnd)
        let probeDistance = CGFloat(max(0.001, min(1, edgeLength * 0.01)))

        let probeA = CGPoint(
            x: midpoint.x + candidateA.dx * probeDistance,
            y: midpoint.y + candidateA.dy * probeDistance
        )
        let probeB = CGPoint(
            x: midpoint.x + candidateB.dx * probeDistance,
            y: midpoint.y + candidateB.dy * probeDistance
        )
        let aInside = PolygonMath.pointInPolygon(probeA, vertices: surface)
        let bInside = PolygonMath.pointInPolygon(probeB, vertices: surface)

        if aInside != bInside { return aInside ? candidateA : candidateB }
        return candidateA
    }

    static func unit(_ vector: CGVector) -> CGVector? {
        let length = hypot(vector.dx, vector.dy)
        guard length > 1e-9 else { return nil }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    static func dot(_ point: CGPoint, _ axis: CGVector) -> CGFloat {
        point.x * axis.dx + point.y * axis.dy
    }

    private static func canonicalSegment(start: CGPoint, end: CGPoint) -> Segment {
        if pointComesFirst(end, start) {
            return Segment(start: end, end: start)
        }
        return Segment(start: start, end: end)
    }

    private static func segmentComesFirst(_ lhs: Segment, _ rhs: Segment) -> Bool {
        if pointComesFirst(lhs.start, rhs.start) { return true }
        if pointComesFirst(rhs.start, lhs.start) { return false }
        return pointComesFirst(lhs.end, rhs.end)
    }

    private static func pointComesFirst(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        if abs(lhs.x - rhs.x) > 0.000_001 { return lhs.x < rhs.x }
        return lhs.y < rhs.y
    }
}
