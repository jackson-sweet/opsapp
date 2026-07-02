// OPS/OPSTests/DeckBuilder/DeckMeasureReadoutTests.swift

import XCTest
@testable import OPS

final class DeckMeasureReadoutTests: XCTestCase {

    /// 100-canvas-pt square at 2.0 canvas-pts/inch → 50" sides.
    private let square: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]
    private let scale = 2.0

    // MARK: - Open runs

    func testOpenRun_singleSegmentTotal() {
        let r = DeckMeasureReadout.build(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            closed: false, scaleFactor: scale, system: .imperial
        )
        XCTAssertEqual(r.totalLengthText, "4' 2\"") // 50"
        XCTAssertEqual(r.segmentCount, 1)
        XCTAssertNil(r.areaText)
        XCTAssertNil(r.perimeterText)
    }

    func testOpenRun_polylineRunningTotal() {
        // L-run: 100 + 100 canvas pts = 100" total.
        let r = DeckMeasureReadout.build(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)],
            closed: false, scaleFactor: scale, system: .imperial
        )
        XCTAssertEqual(r.totalLengthText, "8' 4\"") // 100"
        XCTAssertEqual(r.segmentCount, 2)
    }

    func testOpenRun_singlePointHasNoTotal() {
        let r = DeckMeasureReadout.build(
            points: [CGPoint(x: 10, y: 10)],
            closed: false, scaleFactor: scale, system: .imperial
        )
        XCTAssertNil(r.totalLengthText)
        XCTAssertEqual(r.segmentCount, 0)
    }

    func testOpenRun_metricFormatting() {
        // 100 canvas pts = 50" = 127 cm = "1.27 m".
        let r = DeckMeasureReadout.build(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            closed: false, scaleFactor: scale, system: .metric
        )
        XCTAssertEqual(r.totalLengthText, "1.27 m")
    }

    // MARK: - Closed loops

    func testClosedLoop_areaAndPerimeter() {
        let r = DeckMeasureReadout.build(
            points: square, closed: true, scaleFactor: scale, system: .imperial
        )
        // 50" × 50" = 2500 in² = 17.36 ft² → "17 sq ft"; perimeter 200" → 16' 8".
        XCTAssertEqual(r.areaText, "17 sq ft")
        XCTAssertEqual(r.perimeterText, "16' 8\"")
        XCTAssertNil(r.totalLengthText, "perimeter replaces the running total once closed")
        XCTAssertFalse(r.isSelfIntersecting)
    }

    func testClosedLoop_needsThreePoints() {
        // A "closed" 2-point run is still an open segment — no area invented.
        let r = DeckMeasureReadout.build(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            closed: true, scaleFactor: scale, system: .imperial
        )
        XCTAssertNil(r.areaText)
        XCTAssertEqual(r.totalLengthText, "4' 2\"")
    }

    func testClosedLoop_selfIntersectingSuppressesArea() {
        // Bowtie: the shoelace value is a net, not a footprint — show the
        // brand empty state, keep the (still meaningful) perimeter.
        let bowtie: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 100),
        ]
        let r = DeckMeasureReadout.build(
            points: bowtie, closed: true, scaleFactor: scale, system: .imperial
        )
        XCTAssertEqual(r.areaText, DeckMeasureReadout.emptyValue)
        XCTAssertTrue(r.isSelfIntersecting)
        XCTAssertNotNil(r.perimeterText)
    }

    func testClosedLoop_metricArea() {
        // 2500 in² × 0.00064516 = 1.6129 m² → "1.6 m²".
        let r = DeckMeasureReadout.build(
            points: square, closed: true, scaleFactor: scale, system: .metric
        )
        XCTAssertEqual(r.areaText, "1.6 m²")
    }

    // MARK: - Guards

    func testZeroScaleFactorYieldsEmptyStates() {
        let open = DeckMeasureReadout.build(
            points: square, closed: false, scaleFactor: 0, system: .imperial
        )
        XCTAssertNil(open.totalLengthText)
        XCTAssertEqual(open.segmentCount, 3)

        let closed = DeckMeasureReadout.build(
            points: square, closed: true, scaleFactor: 0, system: .imperial
        )
        XCTAssertEqual(closed.areaText, DeckMeasureReadout.emptyValue)
        XCTAssertEqual(closed.perimeterText, DeckMeasureReadout.emptyValue)
    }

    func testOpenRunInches_sumsConsecutiveSegments() {
        let total = DeckMeasureReadout.openRunInches(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0), CGPoint(x: 60, y: 80)],
            scaleFactor: 2.0
        )
        XCTAssertEqual(total, 70.0, accuracy: 0.001) // (60 + 80) / 2
    }
}
