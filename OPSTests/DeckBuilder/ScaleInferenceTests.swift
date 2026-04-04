// OPS/OPSTests/DeckBuilder/ScaleInferenceTests.swift

import XCTest
@testable import OPS

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

        // Default: 1 square = 1 foot → pixels per inch = 50 / 12
        XCTAssertEqual(result.scaleFactor, 50.0 / 12.0, accuracy: 0.01)

        if case .graphPaper(_, let unitName) = result.source {
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
