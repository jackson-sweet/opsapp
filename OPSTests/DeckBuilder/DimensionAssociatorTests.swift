// OPS/OPSTests/DeckBuilder/DimensionAssociatorTests.swift

import XCTest
@testable import OPS

final class DimensionAssociatorTests: XCTestCase {
    let imageSize = CGSize(width: 3000, height: 4000)

    // MARK: - Association

    func testAssociate_matchesNearestEdge() {
        // Horizontal segment at y=500
        let seg1 = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 100, y: 500),
            endPoint: CGPoint(x: 1000, y: 500)
        )
        // Horizontal segment at y=2000
        let seg2 = DetectedLineSegment(
            id: "seg2",
            startPoint: CGPoint(x: 100, y: 2000),
            endPoint: CGPoint(x: 1000, y: 2000)
        )

        // Dimension text near seg1 (at y=450)
        let text = RecognizedText(
            id: "t1",
            text: "24'",
            boundingBox: CGRect(x: 400, y: 430, width: 150, height: 40),
            confidence: 0.9,
            classification: .dimension(inches: 288)
        )

        let result = DimensionAssociator.associate(
            texts: [text],
            segments: [seg1, seg2],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].segmentId, "seg1")
        XCTAssertEqual(result[0].dimensionInches, 288.0)
    }

    func testAssociate_orientationBonus() {
        // Vertical segment
        let segV = DetectedLineSegment(
            id: "segV",
            startPoint: CGPoint(x: 500, y: 100),
            endPoint: CGPoint(x: 500, y: 1000)
        )
        // Horizontal segment at same distance
        let segH = DetectedLineSegment(
            id: "segH",
            startPoint: CGPoint(x: 100, y: 600),
            endPoint: CGPoint(x: 1000, y: 600)
        )

        // Vertical text (taller than wide) equidistant from both segments
        let text = RecognizedText(
            id: "t1",
            text: "16'",
            boundingBox: CGRect(x: 530, y: 400, width: 40, height: 150),
            confidence: 0.9,
            classification: .dimension(inches: 192)
        )

        let result = DimensionAssociator.associate(
            texts: [text],
            segments: [segV, segH],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 1)
        // Should prefer vertical segment due to orientation bonus
        XCTAssertEqual(result[0].segmentId, "segV")
    }

    func testAssociate_ignoresDistantEdges() {
        // Segment far from text (more than 15% of diagonal away)
        let seg = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0)
        )

        let text = RecognizedText(
            id: "t1",
            text: "24'",
            boundingBox: CGRect(x: 2500, y: 3500, width: 150, height: 40),
            confidence: 0.9,
            classification: .dimension(inches: 288)
        )

        let result = DimensionAssociator.associate(
            texts: [text],
            segments: [seg],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 0) // too far
    }

    func testAssociate_onlyProcessesDimensionTexts() {
        let seg = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 100, y: 500),
            endPoint: CGPoint(x: 1000, y: 500)
        )

        let label = RecognizedText(
            id: "t1",
            text: "stairs",
            boundingBox: CGRect(x: 400, y: 480, width: 150, height: 40),
            confidence: 0.9,
            classification: .label(text: "stairs")
        )

        let result = DimensionAssociator.associate(
            texts: [label],
            segments: [seg],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 0) // not a dimension
    }

    func testAssociate_emptyTexts() {
        let seg = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 100, y: 500),
            endPoint: CGPoint(x: 1000, y: 500)
        )

        let result = DimensionAssociator.associate(
            texts: [],
            segments: [seg],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 0)
    }

    func testAssociate_emptySegments() {
        let text = RecognizedText(
            id: "t1",
            text: "24'",
            boundingBox: CGRect(x: 400, y: 430, width: 150, height: 40),
            confidence: 0.9,
            classification: .dimension(inches: 288)
        )

        let result = DimensionAssociator.associate(
            texts: [text],
            segments: [],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 0)
    }

    func testAssociate_multipleDimensionsMultipleSegments() {
        // Two horizontal segments at different y positions
        let seg1 = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 100, y: 200),
            endPoint: CGPoint(x: 800, y: 200)
        )
        let seg2 = DetectedLineSegment(
            id: "seg2",
            startPoint: CGPoint(x: 100, y: 1500),
            endPoint: CGPoint(x: 800, y: 1500)
        )

        // Text near seg1
        let text1 = RecognizedText(
            id: "t1",
            text: "12'",
            boundingBox: CGRect(x: 300, y: 170, width: 120, height: 40),
            confidence: 0.9,
            classification: .dimension(inches: 144)
        )
        // Text near seg2
        let text2 = RecognizedText(
            id: "t2",
            text: "8'",
            boundingBox: CGRect(x: 300, y: 1470, width: 100, height: 40),
            confidence: 0.9,
            classification: .dimension(inches: 96)
        )

        let result = DimensionAssociator.associate(
            texts: [text1, text2],
            segments: [seg1, seg2],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 2)

        let assoc1 = result.first(where: { $0.textId == "t1" })
        let assoc2 = result.first(where: { $0.textId == "t2" })
        XCTAssertEqual(assoc1?.segmentId, "seg1")
        XCTAssertEqual(assoc1?.dimensionInches, 144.0)
        XCTAssertEqual(assoc2?.segmentId, "seg2")
        XCTAssertEqual(assoc2?.dimensionInches, 96.0)
    }

    func testAssociate_scoreIsPositive() {
        let seg = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 100, y: 500),
            endPoint: CGPoint(x: 1000, y: 500)
        )
        let text = RecognizedText(
            id: "t1",
            text: "10'",
            boundingBox: CGRect(x: 400, y: 460, width: 100, height: 40),
            confidence: 0.9,
            classification: .dimension(inches: 120)
        )

        let result = DimensionAssociator.associate(
            texts: [text],
            segments: [seg],
            imageSize: imageSize
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertGreaterThan(result[0].score, 0.0)
    }

    // MARK: - Find Nearest Segment

    func testFindNearestSegment_returnsClosest() {
        let seg1 = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 0)
        )
        let seg2 = DetectedLineSegment(
            id: "seg2",
            startPoint: CGPoint(x: 0, y: 500),
            endPoint: CGPoint(x: 100, y: 500)
        )

        let result = DimensionAssociator.findNearestSegment(
            to: CGPoint(x: 50, y: 10),
            segments: [seg1, seg2]
        )
        XCTAssertEqual(result, "seg1")
    }

    func testFindNearestSegment_emptySegments() {
        let result = DimensionAssociator.findNearestSegment(
            to: CGPoint(x: 50, y: 10),
            segments: []
        )
        XCTAssertNil(result)
    }

    func testFindNearestSegment_pointOnSegment() {
        let seg = DetectedLineSegment(
            id: "seg1",
            startPoint: CGPoint(x: 0, y: 100),
            endPoint: CGPoint(x: 200, y: 100)
        )

        // Point exactly on the segment
        let result = DimensionAssociator.findNearestSegment(
            to: CGPoint(x: 100, y: 100),
            segments: [seg]
        )
        XCTAssertEqual(result, "seg1")
    }

    func testFindNearestSegment_pointCloserToMidline() {
        // Two segments: one vertical, one horizontal
        let segV = DetectedLineSegment(
            id: "segV",
            startPoint: CGPoint(x: 100, y: 0),
            endPoint: CGPoint(x: 100, y: 500)
        )
        let segH = DetectedLineSegment(
            id: "segH",
            startPoint: CGPoint(x: 0, y: 300),
            endPoint: CGPoint(x: 500, y: 300)
        )

        // Point at (105, 250) — 5px from segV, 50px from segH
        let result = DimensionAssociator.findNearestSegment(
            to: CGPoint(x: 105, y: 250),
            segments: [segV, segH]
        )
        XCTAssertEqual(result, "segV")
    }
}
