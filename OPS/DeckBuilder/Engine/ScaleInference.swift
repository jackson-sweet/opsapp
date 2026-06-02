// OPS/OPS/DeckBuilder/Engine/ScaleInference.swift

import Foundation

struct ScaleInference {

    // MARK: - From Graph Paper

    /// Inches that one grid square represents when the drawing has no usable
    /// dimension annotations, defaulting per measurement system.
    /// Imperial graph paper convention in North America is 1 square = 1 foot (12").
    /// Metric engineering/graph paper convention is 1 square = 10 cm (3.937").
    private static func defaultInchesPerSquare(for system: MeasurementSystem) -> Double {
        switch system {
        case .imperial: return 12.0          // 1 foot
        case .metric:   return 10.0 / 2.54   // 10 cm = 3.937 in
        }
    }

    /// Infer scale from graph paper grid spacing combined with annotated dimensions
    /// - Parameters:
    ///   - gridSpacingPixels: Pixels between grid lines (from GridDetector)
    ///   - associations: Dimension associations (text → edge matches)
    ///   - segments: Detected line segments
    ///   - measurementSystem: Drives the no-annotation fallback (imperial → 1 square =
    ///     1 foot, metric → 1 square = 10 cm). Ignored when annotations are present,
    ///     since annotated dimensions derive the true scale directly.
    /// - Returns: ScaleResult with pixels-per-inch scale factor
    static func inferFromGrid(
        gridSpacingPixels: Double,
        associations: [DimensionAssociation],
        segments: [DetectedLineSegment],
        measurementSystem: MeasurementSystem = .imperial
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
            let (squaresPerUnit, unitName) = classifyGridScale(
                inchesPerSquare: inchesPerSquare,
                measurementSystem: measurementSystem
            )

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

        // No annotations — fall back to the conventional grid square for the
        // drawing's measurement system (imperial: 1 square = 1 foot;
        // metric: 1 square = 10 cm). Assuming feet for a metric drawing is off
        // by ~3x, which then scales every derived dimension and area.
        let inchesPerSquare = defaultInchesPerSquare(for: measurementSystem)
        let pixelsPerInch = gridSpacingPixels / inchesPerSquare

        let fallbackUnitName: String
        switch measurementSystem {
        case .imperial: fallbackUnitName = "1 square = 1 foot"
        case .metric:   fallbackUnitName = "1 square = 10 cm"
        }

        return ScaleResult(
            scaleFactor: pixelsPerInch,
            source: .graphPaper(squaresPerUnit: 1.0, unitName: fallbackUnitName),
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

    /// Classify the grid scale into a human-readable description.
    ///
    /// `scaleFactor` is always derived from the real annotated dimension, so this
    /// only controls the label and `squaresPerUnit`. The candidate set is ordered by
    /// the drawing's measurement system so a metric grid snaps to metric spacings
    /// (10 cm, 25 cm, 50 cm, 1 m) before imperial ones, and vice versa.
    /// - Parameters:
    ///   - inchesPerSquare: How many inches one grid square represents
    ///   - measurementSystem: Orders the candidate spacings and the unrecognized fallback label
    /// - Returns: (squaresPerUnit, description)
    private static func classifyGridScale(
        inchesPerSquare: Double,
        measurementSystem: MeasurementSystem
    ) -> (Double, String) {
        // Each candidate: (inchesPerSquare, squaresPerUnit, label, tolerance fraction).
        // squaresPerUnit = grid squares per primary unit (foot for imperial, meter for metric).
        let cmToIn = 1.0 / 2.54
        let imperialCandidates: [(Double, Double, String)] = [
            (12.0,  1.0,  "1 square = 1 foot"),     // most common
            (6.0,   2.0,  "1 square = 6 inches"),   // detailed drawings
            (24.0,  0.5,  "1 square = 2 feet"),     // large decks
            (3.0,   4.0,  "1 square = 3 inches")    // fine detail
        ]
        let metricCandidates: [(Double, Double, String)] = [
            (10.0 * cmToIn, 10.0, "1 square = 10 cm"),  // most common metric graph paper
            (25.0 * cmToIn, 4.0,  "1 square = 25 cm"),
            (50.0 * cmToIn, 2.0,  "1 square = 50 cm"),
            (100.0 * cmToIn, 1.0, "1 square = 1 meter"),
            (1.0 * cmToIn,  100.0, "1 square = 1 cm")
        ]

        // Match against the measurement system's own conventions first, then the
        // other system's, so a near-miss in one doesn't shadow an exact match in
        // the other.
        let ordered: [(Double, Double, String)]
        switch measurementSystem {
        case .imperial: ordered = imperialCandidates + metricCandidates
        case .metric:   ordered = metricCandidates + imperialCandidates
        }

        for (inches, squaresPerUnit, label) in ordered
        where abs(inchesPerSquare - inches) / inches < 0.25 {
            return (squaresPerUnit, label)
        }

        // Unrecognized spacing — describe it in the drawing's own units.
        switch measurementSystem {
        case .imperial:
            let feet = inchesPerSquare / 12.0
            return (feet > 0 ? 1.0 / feet : 1.0, String(format: "1 square ≈ %.1f inches", inchesPerSquare))
        case .metric:
            let cm = inchesPerSquare * 2.54
            let meters = cm / 100.0
            return (meters > 0 ? 1.0 / meters : 1.0, String(format: "1 square ≈ %.1f cm", cm))
        }
    }
}
