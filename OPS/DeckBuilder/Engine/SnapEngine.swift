// OPS/OPS/DeckBuilder/Engine/SnapEngine.swift

import Foundation
import SwiftUI

// MARK: - Alignment Guide Types

enum AlignmentGuideType: Equatable {
    case horizontal    // endpoint shares Y with another vertex
    case vertical      // endpoint shares X with another vertex
    case parallel      // line is parallel to an existing edge
    case perpendicular // line is perpendicular to an existing edge
}

struct AlignmentGuide: Equatable {
    let from: CGPoint    // start of the dotted guide line
    let to: CGPoint      // end of the dotted guide line
    let type: AlignmentGuideType
    let referenceLabel: String?  // optional label (e.g., "∥" or "⊥")
}

struct AlignmentResult {
    var snappedPoint: CGPoint       // the endpoint after alignment snapping
    var guides: [AlignmentGuide]    // active guide lines to render
}

struct SnapEngine {

    // MARK: - Angle Snapping

    /// Snap an angle to the nearest increment
    /// - Parameters:
    ///   - angle: Raw angle in degrees (0-360)
    ///   - increment: Snap increment in degrees (e.g., 15)
    /// - Returns: Snapped angle in degrees
    static func snapAngle(_ angle: Double, increment: Double) -> Double {
        guard increment > 0 else { return angle }
        let snapped = (angle / increment).rounded() * increment
        return snapped.truncatingRemainder(dividingBy: 360.0)
    }

    /// Calculate the angle of a line from start to end in degrees (0 = right, 90 = up)
    static func lineAngle(from start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y  // Note: SwiftUI Y is flipped (down = positive)
        let radians = atan2(-dy, dx) // negate Y for standard math orientation
        var degrees = radians * 180.0 / .pi
        if degrees < 0 { degrees += 360.0 }
        return degrees
    }

    /// Given a start point, raw end point, and snap config, return the snapped end point
    /// that lies on the nearest snapped angle at the same distance
    static func snapEndpoint(
        from start: CGPoint,
        rawEnd: CGPoint,
        angleIncrement: Double,
        lengthIncrement: Double,  // in canvas points (pre-scaled)
        snappingEnabled: Bool
    ) -> CGPoint {
        guard snappingEnabled else { return rawEnd }

        let dx = rawEnd.x - start.x
        let dy = rawEnd.y - start.y
        var distance = sqrt(dx * dx + dy * dy)
        var angle = lineAngle(from: start, to: rawEnd)

        // Snap angle
        if angleIncrement > 0 {
            angle = snapAngle(angle, increment: angleIncrement)
        }

        // Snap length
        if lengthIncrement > 0 {
            distance = (distance / lengthIncrement).rounded() * lengthIncrement
        }

        // Convert back to cartesian
        let radians = angle * .pi / 180.0
        let snappedX = start.x + distance * cos(radians)
        let snappedY = start.y - distance * sin(radians) // negate Y back to SwiftUI
        return CGPoint(x: snappedX, y: snappedY)
    }

    // MARK: - Measurement Angle Snap

    /// Snap a measurement segment's end point so it lands exactly parallel or
    /// perpendicular to the nearest reference edge when the user's drawn angle is
    /// already within `toleranceDegrees`. The drawn LENGTH is preserved and the
    /// drawn DIRECTION is respected — the snap targets tile the circle every 90°
    /// (parallel, antiparallel, both perpendiculars) and at a ±5° tolerance only
    /// one can fall inside range, so the segment is nudged onto the true axis
    /// without ever reversing. Returns `candidate` unchanged when no reference
    /// edge is nearby or the pick is already off-axis.
    ///
    /// Angles use the same negated-Y "standard math" convention as `lineAngle`
    /// (0° = right, 90° = up); the reconstruction negates Y back into SwiftUI
    /// screen space (`start.y - length·sin`), identical to `snapEndpoint`.
    static func snapMeasurementEnd(
        from start: CGPoint,
        candidate: CGPoint,
        referenceEdges: [(start: CGPoint, end: CGPoint)],
        toleranceDegrees: Double = 5.0
    ) -> CGPoint {
        guard !referenceEdges.isEmpty else { return candidate }

        // Which edge is the user near? Closest edge-midpoint to the segment's
        // midpoint — a cheap "which edge do they mean" heuristic that avoids
        // anchoring the snap to a faraway edge.
        let midM = CGPoint(x: (start.x + candidate.x) / 2, y: (start.y + candidate.y) / 2)
        var bestEdgeAngle: Double?
        var bestDist = Double.infinity
        for edge in referenceEdges {
            let edgeMid = CGPoint(x: (edge.start.x + edge.end.x) / 2,
                                  y: (edge.start.y + edge.end.y) / 2)
            let d = distance(midM, edgeMid)
            if d < bestDist {
                bestDist = d
                bestEdgeAngle = lineAngle(from: edge.start, to: edge.end)
            }
        }
        guard let edgeAngle = bestEdgeAngle else { return candidate }

        let drawnAngle = lineAngle(from: start, to: candidate)
        let length = distance(start, candidate)
        guard length > 0 else { return candidate }

        // Parallel (both senses) + both perpendiculars.
        let targets: [Double] = [
            edgeAngle, edgeAngle + 180, edgeAngle - 180,
            edgeAngle + 90, edgeAngle - 90,
            edgeAngle + 270, edgeAngle - 270
        ]
        var snapAngle: Double?
        for t in targets {
            let normLine = ((drawnAngle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            let normT = ((t.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            var diff = abs(normLine - normT)
            if diff > 180 { diff = 360 - diff }
            if diff <= toleranceDegrees {
                snapAngle = t
                break
            }
        }
        guard let target = snapAngle else { return candidate }

        // Rotate the end around start onto the snapped axis, preserving length.
        // `target` is in lineAngle's negated-Y math convention, so Y must be
        // negated BACK into SwiftUI screen space — same as `snapEndpoint`.
        // (Bug: this used `start.y + …·sin`, reflecting the end across the
        // horizontal axis through start — a near-vertical measurement's second
        // tap landed point-mirrored through the first.)
        let rad = target * .pi / 180
        return CGPoint(
            x: start.x + CGFloat(length * cos(rad)),
            y: start.y - CGFloat(length * sin(rad))
        )
    }

    // MARK: - Endpoint Magnetic Snap

    /// Find the nearest existing vertex within snap radius
    /// - Returns: The vertex ID if within radius, nil otherwise
    static func findSnapTarget(
        point: CGPoint,
        vertices: [DeckVertex],
        snapRadius: Double,
        excludeVertexIds: Set<String> = []
    ) -> String? {
        var closestId: String?
        var closestDistance = Double.infinity

        for vertex in vertices {
            guard !excludeVertexIds.contains(vertex.id) else { continue }
            let d = distance(point, vertex.position)
            if d < snapRadius && d < closestDistance {
                closestDistance = d
                closestId = vertex.id
            }
        }
        return closestId
    }

    /// Distance between two points
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Grid Snap

    /// Snap a point to the nearest grid intersection.
    /// Grid spacing is in canvas points (same as lengthIncrement in canvas points).
    static func snapToGrid(_ point: CGPoint, gridSpacing: Double) -> CGPoint {
        guard gridSpacing > 0 else { return point }
        return CGPoint(
            x: (Double(point.x) / gridSpacing).rounded() * gridSpacing,
            y: (Double(point.y) / gridSpacing).rounded() * gridSpacing
        )
    }

    // MARK: - Alignment Guide Detection

    /// Detect alignment guides for the current drawing endpoint.
    /// Checks axis alignment with all vertices and parallel/perpendicular to all edges.
    /// Returns a snapped point and the active guide lines.
    static func detectAlignmentGuides(
        from start: CGPoint,
        currentEnd: CGPoint,
        vertices: [DeckVertex],
        edges: [DeckEdge],
        vertexLookup: (String) -> DeckVertex?,
        threshold: Double = 8.0,        // canvas points — how close to trigger
        excludeVertexIds: Set<String> = []
    ) -> AlignmentResult {
        var guides: [AlignmentGuide] = []
        var snappedX = currentEnd.x
        var snappedY = currentEnd.y
        var bestDx = threshold + 1.0  // track closest X alignment
        var bestDy = threshold + 1.0  // track closest Y alignment

        // --- Axis alignment with existing vertices ---
        for vertex in vertices {
            guard !excludeVertexIds.contains(vertex.id) else { continue }
            let pos = vertex.position

            // Vertical alignment: same X coordinate
            let dx = abs(Double(currentEnd.x - pos.x))
            if dx < threshold && dx < bestDx {
                bestDx = dx
                snappedX = pos.x
                // Guide line: vertical dotted line from the reference vertex to the snap point
                guides.removeAll { $0.type == .vertical }
                let minY = min(pos.y, currentEnd.y) - 20
                let maxY = max(pos.y, currentEnd.y) + 20
                guides.append(AlignmentGuide(
                    from: CGPoint(x: pos.x, y: minY),
                    to: CGPoint(x: pos.x, y: maxY),
                    type: .vertical,
                    referenceLabel: nil
                ))
            }

            // Horizontal alignment: same Y coordinate
            let dy = abs(Double(currentEnd.y - pos.y))
            if dy < threshold && dy < bestDy {
                bestDy = dy
                snappedY = pos.y
                // Guide line: horizontal dotted line from the reference vertex to the snap point
                guides.removeAll { $0.type == .horizontal }
                let minX = min(pos.x, currentEnd.x) - 20
                let maxX = max(pos.x, currentEnd.x) + 20
                guides.append(AlignmentGuide(
                    from: CGPoint(x: minX, y: pos.y),
                    to: CGPoint(x: maxX, y: pos.y),
                    type: .horizontal,
                    referenceLabel: nil
                ))
            }
        }

        // --- Parallel / Perpendicular to existing edges ---
        let currentAngle = lineAngle(from: start, to: CGPoint(x: snappedX, y: snappedY))
        let angleThreshold = 2.0  // degrees

        for edge in edges {
            guard let eStart = vertexLookup(edge.startVertexId),
                  let eEnd = vertexLookup(edge.endVertexId) else { continue }
            // Skip edges touching ANY excluded vertex. Previous code used
            // `excludeVertexIds.first` which honors a non-deterministic single
            // ID from the Set — silently broke once callers passed more than
            // one (e.g. vertex-drag exclusion).
            if excludeVertexIds.contains(edge.startVertexId) ||
               excludeVertexIds.contains(edge.endVertexId) {
                continue
            }

            let edgeAngle = lineAngle(from: eStart.position, to: eEnd.position)

            // Parallel: angles match (mod 180°)
            var angleDiff = abs(currentAngle - edgeAngle)
            if angleDiff > 180 { angleDiff = 360 - angleDiff }
            if angleDiff < angleThreshold || abs(angleDiff - 180) < angleThreshold {
                // Don't duplicate if we already have axis-aligned guides covering this
                if !guides.contains(where: { $0.type == .parallel }) {
                    guides.append(AlignmentGuide(
                        from: eStart.position,
                        to: eEnd.position,
                        type: .parallel,
                        referenceLabel: "∥"
                    ))
                }
            }

            // Perpendicular: angles differ by 90°
            if abs(angleDiff - 90) < angleThreshold || abs(angleDiff - 270) < angleThreshold {
                if !guides.contains(where: { $0.type == .perpendicular }) {
                    guides.append(AlignmentGuide(
                        from: eStart.position,
                        to: eEnd.position,
                        type: .perpendicular,
                        referenceLabel: "⊥"
                    ))
                }
            }
        }

        return AlignmentResult(
            snappedPoint: CGPoint(x: snappedX, y: snappedY),
            guides: guides
        )
    }

    // MARK: - Length Conversion

    /// Convert real-world inches to canvas points using scale factor
    static func inchesToCanvasPoints(_ inches: Double, scaleFactor: Double) -> Double {
        guard scaleFactor > 0 else { return inches }
        return inches * scaleFactor
    }

    /// Convert canvas points to real-world inches using scale factor
    static func canvasPointsToInches(_ points: Double, scaleFactor: Double) -> Double {
        guard scaleFactor > 0 else { return points }
        return points / scaleFactor
    }
}
