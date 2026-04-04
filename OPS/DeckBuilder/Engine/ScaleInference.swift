// OPS/OPS/DeckBuilder/Engine/ScaleInference.swift

import Foundation

struct ScaleInference {

    // MARK: - From Graph Paper

    /// Infer scale from graph paper grid spacing combined with annotated dimensions
    /// - Parameters:
    ///   - gridSpacingPixels: Pixels between grid lines (from GridDetector)
    ///   - associations: Dimension associations (text → edge matches)
    ///   - segments: Detected line segments
    /// - Returns: ScaleResult with pixels-per-inch scale factor
    static func inferFromGrid(
        gridSpacingPixels: Double,
        associations: [DimensionAssociation],
        segments: [DetectedLineSegment]
    ) -> ScaleResult {
        guard gridSpacingPixels > 0 else {
            return ScaleResult(
                scaleFactor: 1.0,
                source: .graphPaper(squaresPerUnit: 1.0, unitName: "unknown"),
                conflicts: []
            )
        }

        // If we have annotated dimensions, use them to determine what each grid square represents
        if let bestAssoc = findBestGridCalibration(
            gridSpacingPixels: gridSpacingPixels,
            associations: associations,
            segments: segments
        ) {
            let segment = segments.first { $0.id == bestAssoc.segmentId }
            let segmentLengthPixels = segment?.lengthPixels ?? 1.0
            let squaresAlongEdge = segmentLengthPixels / gridSpacingPixels
            let inchesPerSquare = bestAssoc.dimensionInches / squaresAlongEdge

            // Determine human-readable grid scale
            let (squaresPerUnit, unitName) = classifyGridScale(inchesPerSquare: inchesPerSquare)

            let pixelsPerInch = gridSpacingPixels / inchesPerSquare

            // Detect conflicts
            let conflicts = detectConflicts(
                associations: associations,
                segments: segments,
                pixelsPerInch: pixelsPerInch
            )

            return ScaleResult(
                scaleFactor: pixelsPerInch,
                source: .graphPaper(squaresPerUnit: squaresPerUnit, unitName: unitName),
                conflicts: conflicts
            )
        }

        // No annotations — assume 1 square = 1 foot (most common in NA)
        let inchesPerSquare = 12.0 // 1 foot
        let pixelsPerInch = gridSpacingPixels / inchesPerSquare

        return ScaleResult(
            scaleFactor: pixelsPerInch,
            source: .graphPaper(squaresPerUnit: 1.0, unitName: "1 square = 1 foot"),
            conflicts: []
        )
    }

    // MARK: - From Annotations

    /// Infer scale from annotated dimensions (no grid available)
    /// - Parameters:
    ///   - associations: Dimension associations
    ///   - segments: Detected line segments
    /// - Returns: ScaleResult averaged across all annotated edges
    static func inferFromAnnotations(
        associations: [DimensionAssociation],
        segments: [DetectedLineSegment]
    ) -> ScaleResult {
        guard !associations.isEmpty else {
            return ScaleResult(scaleFactor: 1.0, source: .averaged, conflicts: [])
        }

        // Calculate pixels-per-inch for each annotated edge
        var scaleFactors: [(segmentId: String, ppi: Double)] = []

        for assoc in associations {
            guard assoc.dimensionInches > 0,
                  let segment = segments.first(where: { $0.id == assoc.segmentId }),
                  segment.lengthPixels > 0 else { continue }

            let ppi = segment.lengthPixels / assoc.dimensionInches
            scaleFactors.append((segmentId: assoc.segmentId, ppi: ppi))
        }

        guard !scaleFactors.isEmpty else {
            return ScaleResult(scaleFactor: 1.0, source: .averaged, conflicts: [])
        }

        // If only one annotation, use it directly
        if scaleFactors.count == 1 {
            let conflicts = detectConflicts(
                associations: associations,
                segments: segments,
                pixelsPerInch: scaleFactors[0].ppi
            )
            return ScaleResult(
                scaleFactor: scaleFactors[0].ppi,
                source: .annotatedDimension(edgeId: scaleFactors[0].segmentId),
                conflicts: conflicts
            )
        }

        // Average across all annotations
        let averagePPI = scaleFactors.reduce(0.0) { $0 + $1.ppi } / Double(scaleFactors.count)

        let conflicts = detectConflicts(
            associations: associations,
            segments: segments,
            pixelsPerInch: averagePPI
        )

        return ScaleResult(
            scaleFactor: averagePPI,
            source: .averaged,
            conflicts: conflicts
        )
    }

    // MARK: - Conflict Detection

    /// Compare annotated dimensions against scale-derived dimensions
    /// - Parameters:
    ///   - associations: Dimension associations
    ///   - segments: Detected line segments
    ///   - pixelsPerInch: The established scale factor
    /// - Returns: Array of conflicts where difference exceeds 15%
    static func detectConflicts(
        associations: [DimensionAssociation],
        segments: [DetectedLineSegment],
        pixelsPerInch: Double
    ) -> [ScaleConflict] {
        guard pixelsPerInch > 0 else { return [] }

        var conflicts: [ScaleConflict] = []

        for assoc in associations {
            guard let segment = segments.first(where: { $0.id == assoc.segmentId }),
                  assoc.dimensionInches > 0 else { continue }

            let scaleDerivedInches = segment.lengthPixels / pixelsPerInch
            let percentDiff = abs(assoc.dimensionInches - scaleDerivedInches) / assoc.dimensionInches * 100.0

            if percentDiff > 15.0 {
                conflicts.append(ScaleConflict(
                    segmentId: assoc.segmentId,
                    annotatedInches: assoc.dimensionInches,
                    scaleDerivedInches: scaleDerivedInches,
                    percentDifference: percentDiff
                ))
            }
        }

        return conflicts
    }

    // MARK: - Private Helpers

    /// Find the best annotated edge for grid calibration
    /// Prefers longer edges (more grid squares = more accurate measurement)
    private static func findBestGridCalibration(
        gridSpacingPixels: Double,
        associations: [DimensionAssociation],
        segments: [DetectedLineSegment]
    ) -> DimensionAssociation? {
        var best: DimensionAssociation?
        var bestScore = 0.0

        for assoc in associations {
            guard let segment = segments.first(where: { $0.id == assoc.segmentId }) else { continue }
            // Score: longer edges are better calibrators (more grid squares to count)
            let squareCount = segment.lengthPixels / gridSpacingPixels
            let score = squareCount * assoc.score // combine with association confidence
            if score > bestScore {
                bestScore = score
                best = assoc
            }
        }

        return best
    }

    /// Classify the grid scale into a human-readable description
    /// - Parameter inchesPerSquare: How many inches one grid square represents
    /// - Returns: (squaresPerUnit, description)
    private static func classifyGridScale(inchesPerSquare: Double) -> (Double, String) {
        // Common graph paper scales for deck drawings:
        // 1 square = 1 foot (12 inches)     — most common
        // 1 square = 6 inches (0.5 foot)    — detailed drawings
        // 1 square = 2 feet (24 inches)     — large decks
        // 1 square = 1 meter (39.37 inches) — metric

        if abs(inchesPerSquare - 12.0) / 12.0 < 0.25 {
            return (1.0, "1 square = 1 foot")
        } else if abs(inchesPerSquare - 6.0) / 6.0 < 0.25 {
            return (2.0, "1 square = 6 inches")
        } else if abs(inchesPerSquare - 24.0) / 24.0 < 0.25 {
            return (0.5, "1 square = 2 feet")
        } else if abs(inchesPerSquare - 39.37) / 39.37 < 0.25 {
            return (1.0, "1 square = 1 meter")
        } else {
            let feet = inchesPerSquare / 12.0
            return (1.0 / feet, String(format: "1 square ≈ %.1f inches", inchesPerSquare))
        }
    }
}
