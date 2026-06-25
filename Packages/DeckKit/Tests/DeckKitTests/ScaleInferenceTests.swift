// OPS/OPSTests/DeckBuilder/ScaleInferenceTests.swift

import XCTest
@testable import DeckKit

final class ScaleInferenceTests: XCTestCase {

    // MARK: - Grid Scale Inference

    func testInferFromGrid_oneFootPerSquare() {
        // Grid spacing: 50 pixels between lines
        // Segment: 1200 pixels long (24 grid squares)
        // Annotation: "24'" = 288 inches
        // → 24 squares for 288 inches → 12 inches per square → 1 ft per square
        // → pixels per inch = 50 / 12 ≈ 4.167

        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1200, y: 0)
        )

        let assoc = DimensionAssociation(
            textId: "t1",
            segmentId: "s1",
            dimensionInches: 288.0,
            score: 1.0
        )

        let result = ScaleInference.inferFromGrid(
            gridSpacingPixels: 50.0,
            associations: [assoc],
            segments: [seg]
        )

        // pixels per inch = 50 / 12 = 4.1667
        XCTAssertEqual(result.scaleFactor, 50.0 / 12.0, accuracy: 0.01)

        if case .graphPaper(_, let unitName) = result.source {
            XCTAssertTrue(unitName.contains("1 foot"), "Expected '1 foot' in unit name, got: \(unitName)")
        } else {
            XCTFail("Expected graphPaper source")
        }
    }

    func testInferFromGrid_sixInchPerSquare() {
        // Grid spacing: 50 pixels
        // Segment: 2400 pixels (48 squares)
        // Annotation: "24'" = 288 inches
        // → 48 squares for 288 inches → 6 inches per square
        // → pixels per inch = 50 / 6 ≈ 8.333

        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 2400, y: 0)
        )

        let assoc = DimensionAssociation(
            textId: "t1",
            segmentId: "s1",
            dimensionInches: 288.0,
            score: 1.0
        )

        let result = ScaleInference.inferFromGrid(
            gridSpacingPixels: 50.0,
            associations: [assoc],
            segments: [seg]
        )

        XCTAssertEqual(result.scaleFactor, 50.0 / 6.0, accuracy: 0.01)

        if case .graphPaper(_, let unitName) = result.source {
            XCTAssertTrue(unitName.contains("6 inches"), "Expected '6 inches' in unit name, got: \(unitName)")
        } else {
            XCTFail("Expected graphPaper source")
        }
    }

    func testInferFromGrid_noAnnotations_defaultsToOneFoot() {
        let result = ScaleInference.inferFromGrid(
            gridSpacingPixels: 50.0,
            associations: [],
            segments: []
        )

        // Default (imperial, the parameter's default): 1 square = 1 foot
        // → pixels per inch = 50 / 12
        XCTAssertEqual(result.scaleFactor, 50.0 / 12.0, accuracy: 0.01)

        if case .graphPaper(_, let unitName) = result.source {
            XCTAssertTrue(unitName.contains("1 foot"))
        } else {
            XCTFail("Expected graphPaper source")
        }
    }

    func testInferFromGrid_noAnnotations_imperialExplicit_defaultsToOneFoot() {
        // Passing .imperial explicitly must behave identically to the default.
        let result = ScaleInference.inferFromGrid(
            gridSpacingPixels: 50.0,
            associations: [],
            segments: [],
            measurementSystem: .imperial
        )

        XCTAssertEqual(result.scaleFactor, 50.0 / 12.0, accuracy: 0.01)
        if case .graphPaper(_, let unitName) = result.source {
            XCTAssertTrue(unitName.contains("1 foot"))
        } else {
            XCTFail("Expected graphPaper source")
        }
    }

    func testInferFromGrid_noAnnotations_metric_defaultsToTenCentimeters() {
        // BUG G-3: a metric drawing with a grid but no annotations must NOT assume
        // feet. Metric convention is 1 square = 10 cm = 3.937".
        // → pixels per inch = 50 / 3.937 ≈ 12.7
        let result = ScaleInference.inferFromGrid(
            gridSpacingPixels: 50.0,
            associations: [],
            segments: [],
            measurementSystem: .metric
        )

        let expectedInchesPerSquare = 10.0 / 2.54   // 3.937"
        XCTAssertEqual(result.scaleFactor, 50.0 / expectedInchesPerSquare, accuracy: 0.01)

        // Sanity: metric scale is ~3.05x the (wrong) imperial assumption for the same grid.
        XCTAssertEqual(result.scaleFactor / (50.0 / 12.0), 12.0 / expectedInchesPerSquare, accuracy: 0.01)

        if case .graphPaper(_, let unitName) = result.source {
            XCTAssertTrue(unitName.contains("10 cm"), "Expected '10 cm' in unit name, got: \(unitName)")
        } else {
            XCTFail("Expected graphPaper source")
        }
    }

    func testInferFromGrid_metricAnnotated_classifiesAsMetricGrid() {
        // Metric drawing WITH an annotation. The true scale comes from the annotation,
        // but the human-readable grid label should classify as metric, not imperial.
        // Grid spacing 50px; segment 1000px = 20 squares; annotation 200 cm (≈78.74").
        // → inchesPerSquare = 78.74 / 20 ≈ 3.937" ≈ 10 cm per square.
        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1000, y: 0)
        )
        let assoc = DimensionAssociation(
            textId: "t1",
            segmentId: "s1",
            dimensionInches: 200.0 / 2.54,   // 200 cm in inches
            score: 1.0
        )

        let result = ScaleInference.inferFromGrid(
            gridSpacingPixels: 50.0,
            associations: [assoc],
            segments: [seg],
            measurementSystem: .metric
        )

        // pixels per inch = gridSpacing / inchesPerSquare = 50 / 3.937 ≈ 12.7
        XCTAssertEqual(result.scaleFactor, 50.0 / (10.0 / 2.54), accuracy: 0.05)

        if case .graphPaper(_, let unitName) = result.source {
            XCTAssertTrue(unitName.contains("10 cm"), "Expected metric '10 cm' label, got: \(unitName)")
        } else {
            XCTFail("Expected graphPaper source")
        }
    }

    func testInferFromGrid_imperialAnnotated_unchangedByMetricSupport() {
        // Regression guard: the existing imperial 1-foot case must be byte-for-byte
        // identical after threading measurementSystem (default .imperial).
        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 1200, y: 0)
        )
        let assoc = DimensionAssociation(textId: "t1", segmentId: "s1", dimensionInches: 288.0, score: 1.0)

        let result = ScaleInference.inferFromGrid(
            gridSpacingPixels: 50.0,
            associations: [assoc],
            segments: [seg]
        )

        XCTAssertEqual(result.scaleFactor, 50.0 / 12.0, accuracy: 0.01)
        if case .graphPaper(let squaresPerUnit, let unitName) = result.source {
            XCTAssertEqual(squaresPerUnit, 1.0, accuracy: 0.001)
            XCTAssertTrue(unitName.contains("1 foot"))
        } else {
            XCTFail("Expected graphPaper source")
        }
    }

    // MARK: - Annotation Scale Inference

    func testInferFromAnnotations_singleEdge() {
        // Segment: 500 pixels, annotated as 10 feet (120 inches)
        // → pixels per inch = 500 / 120 ≈ 4.167
        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 500, y: 0)
        )

        let assoc = DimensionAssociation(
            textId: "t1",
            segmentId: "s1",
            dimensionInches: 120.0,
            score: 1.0
        )

        let result = ScaleInference.inferFromAnnotations(
            associations: [assoc],
            segments: [seg]
        )

        XCTAssertEqual(result.scaleFactor, 500.0 / 120.0, accuracy: 0.01)

        if case .annotatedDimension(let edgeId) = result.source {
            XCTAssertEqual(edgeId, "s1")
        } else {
            XCTFail("Expected annotatedDimension source")
        }
    }

    func testInferFromAnnotations_multipleEdges_averages() {
        let seg1 = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 480, y: 0)
        )
        let seg2 = DetectedLineSegment(
            id: "s2",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: 320)
        )

        let assoc1 = DimensionAssociation(textId: "t1", segmentId: "s1", dimensionInches: 120.0, score: 1.0)
        let assoc2 = DimensionAssociation(textId: "t2", segmentId: "s2", dimensionInches: 80.0, score: 1.0)

        let result = ScaleInference.inferFromAnnotations(
            associations: [assoc1, assoc2],
            segments: [seg1, seg2]
        )

        // seg1: 480/120 = 4.0 ppi, seg2: 320/80 = 4.0 ppi → average = 4.0
        XCTAssertEqual(result.scaleFactor, 4.0, accuracy: 0.01)

        if case .averaged = result.source {
            // pass
        } else {
            XCTFail("Expected averaged source")
        }
    }

    func testInferFromAnnotations_emptyAssociations() {
        let result = ScaleInference.inferFromAnnotations(associations: [], segments: [])
        XCTAssertEqual(result.scaleFactor, 1.0)
    }

    // MARK: - Conflict Detection

    func testDetectConflicts_noConflict() {
        // Segment: 480 pixels, annotated as 120 inches
        // Scale: 4.0 ppi → derived = 480/4 = 120 inches → exact match
        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 480, y: 0)
        )

        let assoc = DimensionAssociation(textId: "t1", segmentId: "s1", dimensionInches: 120.0, score: 1.0)

        let conflicts = ScaleInference.detectConflicts(
            associations: [assoc],
            segments: [seg],
            pixelsPerInch: 4.0
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testDetectConflicts_flagsLargeMismatch() {
        // Segment: 800 pixels at 4.0 ppi → derived = 200 inches
        // Annotated as 160 inches → 25% difference → should flag
        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 800, y: 0)
        )

        let assoc = DimensionAssociation(textId: "t1", segmentId: "s1", dimensionInches: 160.0, score: 1.0)

        let conflicts = ScaleInference.detectConflicts(
            associations: [assoc],
            segments: [seg],
            pixelsPerInch: 4.0
        )

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].segmentId, "s1")
        XCTAssertEqual(conflicts[0].annotatedInches, 160.0)
        XCTAssertEqual(conflicts[0].scaleDerivedInches, 200.0, accuracy: 0.1)
        XCTAssertGreaterThan(conflicts[0].percentDifference, 15.0)
    }

    func testDetectConflicts_ignoresSmallMismatch() {
        // Segment: 500 pixels at 4.0 ppi → derived = 125 inches
        // Annotated as 120 inches → ~4.2% difference → should NOT flag
        let seg = DetectedLineSegment(
            id: "s1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 500, y: 0)
        )

        let assoc = DimensionAssociation(textId: "t1", segmentId: "s1", dimensionInches: 120.0, score: 1.0)

        let conflicts = ScaleInference.detectConflicts(
            associations: [assoc],
            segments: [seg],
            pixelsPerInch: 4.0
        )

        XCTAssertTrue(conflicts.isEmpty)
    }
}
