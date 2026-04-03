// OPS/OPS/DeckBuilder/Engine/DimensionEngine.swift

import Foundation

struct DimensionEngine {

    // MARK: - Formatting

    /// Format inches as feet and inches string (e.g., 294 → "24' 6\"")
    static func formatImperial(_ totalInches: Double) -> String {
        let feet = Int(totalInches) / 12
        let inches = totalInches - Double(feet * 12)
        if inches < 0.5 {
            return "\(feet)'"
        }
        let roundedInches = (inches * 2).rounded() / 2  // round to nearest 0.5"
        if roundedInches == roundedInches.rounded() {
            return "\(feet)' \(Int(roundedInches))\""
        }
        return String(format: "%d' %.1f\"", feet, roundedInches)
    }

    /// Format centimeters as meters and cm (e.g., 245 → "2.45 m")
    static func formatMetric(_ totalCm: Double) -> String {
        if totalCm >= 100 {
            return String(format: "%.2f m", totalCm / 100.0)
        }
        return String(format: "%.0f cm", totalCm)
    }

    /// Format a dimension based on the measurement system
    static func format(_ valueInInches: Double, system: MeasurementSystem) -> String {
        switch system {
        case .imperial:
            return formatImperial(valueInInches)
        case .metric:
            let cm = valueInInches * 2.54
            return formatMetric(cm)
        }
    }

    // MARK: - Area Formatting

    /// Format area in square feet (e.g., 56448 sq inches → "392 sq ft")
    static func formatAreaImperial(_ sqInches: Double) -> String {
        let sqFeet = sqInches / 144.0
        if sqFeet >= 10 {
            return "\(Int(sqFeet.rounded())) sq ft"
        }
        return String(format: "%.1f sq ft", sqFeet)
    }

    static func formatArea(_ sqInches: Double, system: MeasurementSystem) -> String {
        switch system {
        case .imperial:
            return formatAreaImperial(sqInches)
        case .metric:
            let sqMeters = sqInches * 0.00064516
            return String(format: "%.1f m²", sqMeters)
        }
    }

    // MARK: - Scale Calculation

    /// Calculate scale factor from one known dimension
    /// - Parameters:
    ///   - canvasLength: Length of the edge in canvas points
    ///   - realWorldInches: Known dimension in inches
    /// - Returns: Scale factor (canvas points per inch)
    static func calculateScaleFactor(canvasLength: Double, realWorldInches: Double) -> Double? {
        guard canvasLength > 0, realWorldInches > 0 else { return nil }
        return canvasLength / realWorldInches
    }

    /// Auto-fill dimensions for all edges using a scale factor
    /// - Parameters:
    ///   - drawingData: The current drawing data (mutated in place)
    ///   - scaleFactor: Canvas points per real-world inch
    /// - Returns: Updated drawing data with dimensions filled
    static func autoFillDimensions(
        drawingData: DeckDrawingData,
        scaleFactor: Double
    ) -> DeckDrawingData {
        var updated = drawingData
        updated.scaleFactor = scaleFactor

        for i in 0..<updated.edges.count {
            let edge = updated.edges[i]
            // Skip edges that already have manual or laser dimensions
            guard edge.dimensionSource == .scale || edge.dimension == nil else { continue }

            if let start = updated.vertex(byId: edge.startVertexId),
               let end = updated.vertex(byId: edge.endVertexId) {
                let canvasLength = SnapEngine.distance(start.position, end.position)
                updated.edges[i].dimension = canvasLength / scaleFactor
                updated.edges[i].dimensionSource = .scale
            }
        }
        return updated
    }

    // MARK: - Parsing

    /// Parse a dimension string like "24' 6\"", "24.5'", "24", "7.5m" into inches
    static func parseToInches(_ input: String, system: MeasurementSystem) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        switch system {
        case .imperial:
            return parseImperialToInches(trimmed)
        case .metric:
            return parseMetricToInches(trimmed)
        }
    }

    private static func parseImperialToInches(_ input: String) -> Double? {
        // Pattern: "24' 6\"", "24'6\"", "24'", "6\"", "24.5'"
        var totalInches = 0.0
        var remaining = input

        // Extract feet
        if let feetRange = remaining.range(of: #"(\d+\.?\d*)\s*'"#, options: .regularExpression) {
            let feetStr = remaining[feetRange].replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
            if let feet = Double(feetStr) {
                totalInches += feet * 12.0
            }
            remaining = String(remaining[feetRange.upperBound...])
        }

        // Extract inches
        if let inchRange = remaining.range(of: #"(\d+\.?\d*)\s*\""#, options: .regularExpression) {
            let inchStr = remaining[inchRange].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            if let inches = Double(inchStr) {
                totalInches += inches
            }
        } else if totalInches == 0, let plain = Double(remaining.trimmingCharacters(in: .whitespaces)) {
            // Plain number — assume feet
            totalInches = plain * 12.0
        }

        return totalInches > 0 ? totalInches : nil
    }

    private static func parseMetricToInches(_ input: String) -> Double? {
        let cleaned = input.replacingOccurrences(of: "m", with: "")
            .replacingOccurrences(of: "cm", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let value = Double(cleaned) else { return nil }

        if input.contains("cm") {
            return value / 2.54
        } else {
            // Assume meters
            return (value * 100.0) / 2.54
        }
    }

    // MARK: - Post Calculation

    /// Calculate number of posts for an edge with railing
    /// - Parameters:
    ///   - edgeLengthInches: Total edge length in inches
    ///   - maxSpacing: Maximum spacing between posts in inches
    /// - Returns: Number of posts (including corner posts)
    static func postCount(edgeLengthInches: Double, maxSpacing: Double) -> Int {
        guard edgeLengthInches > 0, maxSpacing > 0 else { return 0 }
        return Int(ceil(edgeLengthInches / maxSpacing)) + 1
    }
}
