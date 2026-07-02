// OPS/OPSTests/DeckBuilder/DeckSplitReadoutTests.swift

import XCTest
@testable import OPS

final class DeckSplitReadoutTests: XCTestCase {

    private let square: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    func testEvenSplit_formatsBothSides() {
        // Scale 2.0 pts/inch → 50"×50" face = 2500 in²; halves = 1250 in² =
        // 8.68 ft² → "8.7 sq ft" each; chord 100 pts = 50" = "4' 2\"".
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 50, y: -10), cutB: CGPoint(x: 50, y: 110),
            scaleFactor: 2.0, system: .imperial
        )
        XCTAssertTrue(r.didSplit)
        XCTAssertEqual(r.sideAText, "8.7 sq ft")
        XCTAssertEqual(r.sideBText, "8.7 sq ft")
        XCTAssertEqual(r.cutLengthText, "4' 2\"")
    }

    func testMiss_reportsNoSplit() {
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 300, y: 0), cutB: CGPoint(x: 300, y: 100),
            scaleFactor: 2.0, system: .imperial
        )
        XCTAssertFalse(r.didSplit)
        XCTAssertNil(r.sideAText)
        XCTAssertNil(r.sideBText)
    }

    func testZeroScale_noSplit() {
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 50, y: -10), cutB: CGPoint(x: 50, y: 110),
            scaleFactor: 0, system: .imperial
        )
        XCTAssertFalse(r.didSplit)
    }

    func testResultCarriesPolygonsForRendering() {
        let r = DeckSplitReadout.build(
            surface: square,
            cutA: CGPoint(x: 50, y: -10), cutB: CGPoint(x: 50, y: 110),
            scaleFactor: 2.0, system: .imperial
        )
        XCTAssertGreaterThanOrEqual(r.sideAPolygon.count, 3)
        XCTAssertGreaterThanOrEqual(r.sideBPolygon.count, 3)
        XCTAssertEqual(r.chordSegments.count, 1)
    }
}
