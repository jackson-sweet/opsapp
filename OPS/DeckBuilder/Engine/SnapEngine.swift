// OPS/OPS/DeckBuilder/Engine/SnapEngine.swift

import Foundation
import SwiftUI

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
