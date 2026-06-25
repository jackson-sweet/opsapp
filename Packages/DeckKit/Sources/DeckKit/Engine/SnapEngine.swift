// OPS/OPS/DeckBuilder/Engine/SnapEngine.swift

import Foundation
import SwiftUI

// MARK: - Alignment Guide Types

public enum AlignmentGuideType: Equatable {
    case horizontal    // endpoint shares Y with another vertex
    case vertical      // endpoint shares X with another vertex
    case parallel      // line is parallel to an existing edge
    case perpendicular // line is perpendicular to an existing edge
}

public struct AlignmentGuide: Equatable {
    public let from: CGPoint    // start of the dotted guide line
    public let to: CGPoint      // end of the dotted guide line
    public let type: AlignmentGuideType
    public let referenceLabel: String?  // optional label (e.g., "∥" or "⊥")
}

public struct AlignmentResult {
    public var snappedPoint: CGPoint       // the endpoint after alignment snapping
    public var guides: [AlignmentGuide]    // active guide lines to render
}

public struct SnapEngine {

    // MARK: - Angle Snapping

    /// Snap an angle to the nearest increment
    /// - Parameters:
    ///   - angle: Raw angle in degrees (0-360)
    ///   - increment: Snap increment in degrees (e.g., 15)
    /// - Returns: Snapped angle in degrees
    public static func snapAngle(_ angle: Double, increment: Double) -> Double {
        guard increment > 0 else { return angle }
        let snapped = (angle / increment).rounded() * increment
        return snapped.truncatingRemainder(dividingBy: 360.0)
    }

    /// Calculate the angle of a line from start to end in degrees (0 = right, 90 = up)
    public static func lineAngle(from start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y  // Note: SwiftUI Y is flipped (down = positive)
        let radians = atan2(-dy, dx) // negate Y for standard math orientation
        var degrees = radians * 180.0 / .pi
        if degrees < 0 { degrees += 360.0 }
        return degrees
    }

    /// Given a start point, raw end point, and snap config, return the snapped end point
    /// that lies on the nearest snapped angle at the same distance
    public static func snapEndpoint(
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

    // MARK: - Endpoint Magnetic Snap

    /// Find the nearest existing vertex within snap radius
    /// - Returns: The vertex ID if within radius, nil otherwise
    public static func findSnapTarget(
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
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Grid Snap

    /// Snap a point to the nearest grid intersection.
    /// Grid spacing is in canvas points (same as lengthIncrement in canvas points).
    public static func snapToGrid(_ point: CGPoint, gridSpacing: Double) -> CGPoint {
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
    public static func detectAlignmentGuides(
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
    public static func inchesToCanvasPoints(_ inches: Double, scaleFactor: Double) -> Double {
        guard scaleFactor > 0 else { return inches }
        return inches * scaleFactor
    }

    /// Convert canvas points to real-world inches using scale factor
    public static func canvasPointsToInches(_ points: Double, scaleFactor: Double) -> Double {
        guard scaleFactor > 0 else { return points }
        return points / scaleFactor
    }
}
