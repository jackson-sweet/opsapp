import CoreGraphics
import Foundation

public enum FramingGeometry {
    public typealias Segment = (start: CGPoint, end: CGPoint)

    public static func joistAxis(
        forSurface positions: [CGPoint],
        edges: [DeckEdge],
        houseEdge: DeckEdge?,
        scaleFactor: Double
    ) -> (joist: CGVector, beam: CGVector) {
        guard positions.count >= 2 else {
            return (CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0))
        }

        let reference = referenceSegment(for: houseEdge, positions: positions, edges: edges)
            ?? longestSegment(in: positions)
            ?? (positions[0], positions[1])
        let beam = normalized(vector(from: reference.0, to: reference.1))
        let centroid = centroid(of: positions)
        let midpoint = CGPoint(
            x: (reference.0.x + reference.1.x) / 2,
            y: (reference.0.y + reference.1.y) / 2
        )
        let towardInterior = vector(from: midpoint, to: centroid)
        let candidate = perpendicularClockwise(beam)
        let opposite = CGVector(dx: -candidate.dx, dy: -candidate.dy)
        let joist = dot(candidate, towardInterior) >= dot(opposite, towardInterior) ? candidate : opposite

        return (joist: joist, beam: beam)
    }

    public static func joistLines(
        surface positions: [CGPoint],
        axis: CGVector,
        spacingInchesOC: Double,
        scaleFactor: Double
    ) -> [Segment] {
        guard positions.count >= 3, spacingInchesOC > 0, scaleFactor > 0 else { return [] }

        let joistAxis = normalized(axis)
        let beamAxis = perpendicularCounterClockwise(joistAxis)
        let projections = positions.map { dot($0, beamAxis) }
        guard let minProjection = projections.min(), let maxProjection = projections.max() else { return [] }

        let step = spacingInchesOC * scaleFactor
        let span = maxProjection - minProjection
        let count = max(Int(floor(span / step + 0.000001)) + 1, 1)

        return (0..<count).flatMap { index in
            clippedSegments(
                surface: positions,
                constantAxis: beamAxis,
                runAxis: joistAxis,
                constant: minProjection + Double(index) * step
            )
        }
    }

    public static func beamLines(
        surface positions: [CGPoint],
        joistAxis: CGVector,
        houseEdge: DeckEdge?,
        scaleFactor: Double
    ) -> [Segment] {
        guard positions.count >= 3 else { return [] }

        let joist = normalized(joistAxis)
        let beam = perpendicularCounterClockwise(joist)
        let projections = positions.map { dot($0, joist) }
        guard let minProjection = projections.min(), let maxProjection = projections.max() else { return [] }

        if houseEdge == nil {
            return [minProjection, maxProjection].flatMap { projection in
                clippedSegments(surface: positions, constantAxis: joist, runAxis: beam, constant: projection)
            }
        }

        let centroidProjection = dot(centroid(of: positions), joist)
        let target = abs(maxProjection - centroidProjection) >= abs(minProjection - centroidProjection)
            ? maxProjection
            : minProjection
        return clippedSegments(surface: positions, constantAxis: joist, runAxis: beam, constant: target)
    }

    public static func postPoints(
        alongBeam start: CGPoint,
        end: CGPoint,
        maxSpacingInches: Double,
        scaleFactor: Double
    ) -> [CGPoint] {
        let lengthCanvas = distance(start, end)
        guard lengthCanvas > 0, maxSpacingInches > 0, scaleFactor > 0 else { return [start] }

        let lengthInches = lengthCanvas / scaleFactor
        let segmentCount = max(Int(ceil(lengthInches / maxSpacingInches)), 1)
        return (0...segmentCount).map { index in
            let t = Double(index) / Double(segmentCount)
            return interpolate(start, end, t: t)
        }
    }

    public static func rimAndLedgerSegments(
        surface positions: [CGPoint],
        edges: [DeckEdge]
    ) -> (rim: [Segment], ledger: [Segment]) {
        guard positions.count >= 2 else { return ([], []) }

        var rim: [Segment] = []
        var ledger: [Segment] = []
        let count = min(edges.count, positions.count)
        for index in 0..<count {
            let segment = (positions[index], positions[(index + 1) % positions.count])
            if edges[index].edgeType == .houseEdge {
                ledger.append(segment)
            } else {
                rim.append(segment)
            }
        }
        return (rim, ledger)
    }

    public static func blockingRows(
        joistSpanInches: Double,
        surface positions: [CGPoint],
        joistAxis: CGVector,
        capInches: Double,
        scaleFactor: Double
    ) -> [Segment] {
        guard positions.count >= 3, capInches > 0, joistSpanInches > capInches else { return [] }

        let joist = normalized(joistAxis)
        let beam = perpendicularCounterClockwise(joist)
        let projections = positions.map { dot($0, joist) }
        guard let minProjection = projections.min(), let maxProjection = projections.max() else { return [] }

        let segmentCount = max(Int(ceil(joistSpanInches / capInches)), 1)
        guard segmentCount > 1 else { return [] }

        return (1..<segmentCount).flatMap { index in
            let t = Double(index) / Double(segmentCount)
            let projection = minProjection + (maxProjection - minProjection) * t
            return clippedSegments(surface: positions, constantAxis: joist, runAxis: beam, constant: projection)
        }
    }

    private static func clippedSegments(
        surface positions: [CGPoint],
        constantAxis: CGVector,
        runAxis: CGVector,
        constant: Double
    ) -> [Segment] {
        guard positions.count >= 3 else { return [] }

        var runs: [Double] = []
        let epsilon = 0.000001
        for index in positions.indices {
            let next = (index + 1) % positions.count
            let p0 = positions[index]
            let p1 = positions[next]
            let c0 = dot(p0, constantAxis)
            let c1 = dot(p1, constantAxis)
            let r0 = dot(p0, runAxis)
            let r1 = dot(p1, runAxis)

            if abs(c1 - c0) < epsilon {
                if abs(constant - c0) < epsilon {
                    runs.append(r0)
                    runs.append(r1)
                }
                continue
            }

            let minC = min(c0, c1) - epsilon
            let maxC = max(c0, c1) + epsilon
            guard constant >= minC, constant <= maxC else { continue }

            let t = (constant - c0) / (c1 - c0)
            guard t >= -epsilon, t <= 1 + epsilon else { continue }
            runs.append(r0 + (r1 - r0) * t)
        }

        let uniqueRuns = uniqueSorted(runs)
        guard uniqueRuns.count >= 2 else { return [] }

        var segments: [Segment] = []
        var index = 0
        while index + 1 < uniqueRuns.count {
            let startRun = uniqueRuns[index]
            let endRun = uniqueRuns[index + 1]
            if abs(endRun - startRun) > epsilon {
                segments.append((
                    point(constant: constant, run: startRun, constantAxis: constantAxis, runAxis: runAxis),
                    point(constant: constant, run: endRun, constantAxis: constantAxis, runAxis: runAxis)
                ))
            }
            index += 2
        }
        return segments
    }

    private static func referenceSegment(
        for houseEdge: DeckEdge?,
        positions: [CGPoint],
        edges: [DeckEdge]
    ) -> (CGPoint, CGPoint)? {
        guard let houseEdge, let index = edges.firstIndex(where: { $0.id == houseEdge.id }),
              index < positions.count else { return nil }
        return (positions[index], positions[(index + 1) % positions.count])
    }

    private static func longestSegment(in positions: [CGPoint]) -> (CGPoint, CGPoint)? {
        guard positions.count >= 2 else { return nil }

        var best: (CGPoint, CGPoint, Double)?
        for index in positions.indices {
            let next = (index + 1) % positions.count
            let candidate = (positions[index], positions[next], distance(positions[index], positions[next]))
            if candidate.2 > (best?.2 ?? -1) {
                best = candidate
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    private static func centroid(of positions: [CGPoint]) -> CGPoint {
        guard !positions.isEmpty else { return .zero }
        let total = positions.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: total.x / CGFloat(positions.count), y: total.y / CGFloat(positions.count))
    }

    private static func normalized(_ vector: CGVector) -> CGVector {
        let length = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard length > 0 else { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private static func vector(from start: CGPoint, to end: CGPoint) -> CGVector {
        normalized(CGVector(dx: Double(end.x - start.x), dy: Double(end.y - start.y)))
    }

    private static func perpendicularClockwise(_ vector: CGVector) -> CGVector {
        CGVector(dx: vector.dy, dy: -vector.dx)
    }

    private static func perpendicularCounterClockwise(_ vector: CGVector) -> CGVector {
        CGVector(dx: -vector.dy, dy: vector.dx)
    }

    private static func dot(_ lhs: CGVector, _ rhs: CGVector) -> Double {
        lhs.dx * rhs.dx + lhs.dy * rhs.dy
    }

    private static func dot(_ point: CGPoint, _ axis: CGVector) -> Double {
        Double(point.x) * axis.dx + Double(point.y) * axis.dy
    }

    private static func point(
        constant: Double,
        run: Double,
        constantAxis: CGVector,
        runAxis: CGVector
    ) -> CGPoint {
        CGPoint(
            x: constantAxis.dx * constant + runAxis.dx * run,
            y: constantAxis.dy * constant + runAxis.dy * run
        )
    }

    private static func interpolate(_ start: CGPoint, _ end: CGPoint, t: Double) -> CGPoint {
        CGPoint(
            x: Double(start.x) + (Double(end.x - start.x) * t),
            y: Double(start.y) + (Double(end.y - start.y) * t)
        )
    }

    private static func distance(_ start: CGPoint, _ end: CGPoint) -> Double {
        hypot(Double(end.x - start.x), Double(end.y - start.y))
    }

    private static func uniqueSorted(_ values: [Double]) -> [Double] {
        let sorted = values.sorted()
        var output: [Double] = []
        for value in sorted {
            if let last = output.last, abs(last - value) < 0.0001 {
                continue
            }
            output.append(value)
        }
        return output
    }
}
