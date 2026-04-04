// OPS/OPS/DeckBuilder/Engine/AccuracyModel.swift

import Foundation

struct AccuracyModel {

    /// Estimate accuracy percentage for an AR measurement based on distance
    /// - Parameter distanceMeters: The measured distance in meters
    /// - Returns: Estimated error as a percentage (e.g., 3.0 = ±3%)
    static func estimateAccuracy(distanceMeters: Double) -> Double {
        switch distanceMeters {
        case ..<1.0:    return 1.0   // ±1% for very short distances
        case ..<3.0:    return 1.5   // ±1.5% under 3m
        case ..<5.0:    return 2.0   // ±2% under 5m
        case ..<10.0:   return 2.5   // ±2.5% under 10m
        case ..<15.0:   return 3.0   // ±3% under 15m
        default:        return 4.0   // ±4% for longer distances
        }
    }

    /// Format accuracy as a display string: "±6\""
    /// - Parameters:
    ///   - dimensionInches: The measured dimension in inches
    ///   - accuracyPercent: The accuracy percentage
    ///   - system: Measurement system for formatting
    /// - Returns: Formatted accuracy string
    static func formatAccuracy(
        dimensionInches: Double,
        accuracyPercent: Double,
        system: MeasurementSystem = .imperial
    ) -> String {
        let errorInches = dimensionInches * accuracyPercent / 100.0
        switch system {
        case .imperial:
            if errorInches >= 12 {
                let feet = errorInches / 12.0
                return String(format: "±%.1f'", feet)
            }
            return String(format: "±%.0f\"", errorInches.rounded())
        case .metric:
            let errorCm = errorInches * 2.54
            if errorCm >= 100 {
                return String(format: "±%.2fm", errorCm / 100.0)
            }
            return String(format: "±%.0fcm", errorCm.rounded())
        }
    }

    /// Propagate accuracy to area calculation
    /// For area = L1 * L2, relative error ≈ sum of relative errors (first-order)
    /// - Parameters:
    ///   - edgeAccuracies: Array of (dimensionInches, accuracyPercent) for each edge
    /// - Returns: Area accuracy as percentage
    static func areaAccuracy(edgeAccuracies: [(Double, Double)]) -> Double {
        guard !edgeAccuracies.isEmpty else { return 0 }
        // For a polygon, area error is approximately the sum of the accuracy percentages
        // of the two longest perpendicular dimensions (simplified)
        let sorted = edgeAccuracies.sorted { $0.0 > $1.0 }
        if sorted.count >= 2 {
            return sorted[0].1 + sorted[1].1  // ±(p1 + p2)%
        }
        return sorted[0].1 * 2
    }

    /// Propagate accuracy to linear footage (perimeter sum)
    /// For sum of edges, absolute errors add, relative error is weighted average
    /// - Parameters:
    ///   - edgeAccuracies: Array of (dimensionInches, accuracyPercent) for each edge
    /// - Returns: Perimeter accuracy as percentage
    static func perimeterAccuracy(edgeAccuracies: [(Double, Double)]) -> Double {
        guard !edgeAccuracies.isEmpty else { return 0 }
        let totalLength = edgeAccuracies.reduce(0.0) { $0 + $1.0 }
        let totalError = edgeAccuracies.reduce(0.0) { $0 + $1.0 * $1.1 / 100.0 }
        guard totalLength > 0 else { return 0 }
        return (totalError / totalLength) * 100.0
    }

    /// Post count error from AR measurement
    /// Integer rounding absorbs small errors, but we show ±1
    static func postCountError(edgeLengthInches: Double, accuracyPercent: Double, maxSpacing: Double) -> Int {
        let nominalCount = DimensionEngine.postCount(edgeLengthInches: edgeLengthInches, maxSpacing: maxSpacing)
        let maxLength = edgeLengthInches * (1 + accuracyPercent / 100.0)
        let maxCount = DimensionEngine.postCount(edgeLengthInches: maxLength, maxSpacing: maxSpacing)
        return maxCount - nominalCount  // typically 0 or 1
    }

    /// Check if all edges in a drawing have been manually verified (no AR accuracy remaining)
    static func allEdgesVerified(_ drawingData: DeckDrawingData) -> Bool {
        drawingData.edges.allSatisfy { $0.accuracyPercent == nil }
    }
}
