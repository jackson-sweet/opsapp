// OPS/OPSTests/DeckBuilder/DimensionEngineTests.swift

import XCTest
@testable import OPS

final class DimensionEngineTests: XCTestCase {

    // MARK: - Formatting

    func testFormatImperial_evenFeet() {
        XCTAssertEqual(DimensionEngine.formatImperial(144), "12'")
        XCTAssertEqual(DimensionEngine.formatImperial(240), "20'")
    }

    func testFormatImperial_feetAndInches() {
        XCTAssertEqual(DimensionEngine.formatImperial(294), "24' 6\"")
        XCTAssertEqual(DimensionEngine.formatImperial(192), "16'")
    }

    // MARK: - Parsing

    func testParseImperial_feetAndInches() {
        XCTAssertEqual(DimensionEngine.parseToInches("24' 6\"", system: .imperial), 294)
        XCTAssertEqual(DimensionEngine.parseToInches("16'", system: .imperial), 192)
    }

    func testParseImperial_plainNumber_assumesFeet() {
        XCTAssertEqual(DimensionEngine.parseToInches("24", system: .imperial), 288)
    }

    func testParseImperial_emptyString_returnsNil() {
        XCTAssertNil(DimensionEngine.parseToInches("", system: .imperial))
    }

    // MARK: - Scale Factor

    func testCalculateScaleFactor() {
        // 200 canvas points represents 24' (288")
        let scale = DimensionEngine.calculateScaleFactor(canvasLength: 200, realWorldInches: 288)
        XCTAssertNotNil(scale)
        XCTAssertEqual(scale!, 200.0 / 288.0, accuracy: 0.0001)
    }

    // MARK: - Post Count

    func testPostCount_exactMultiple() {
        // 120" edge with 60" spacing = 2 spans = 3 posts
        XCTAssertEqual(DimensionEngine.postCount(edgeLengthInches: 120, maxSpacing: 60), 3)
    }

    func testPostCount_nonExactMultiple() {
        // 150" edge with 60" spacing = ceil(2.5) = 3 spans = 4 posts
        XCTAssertEqual(DimensionEngine.postCount(edgeLengthInches: 150, maxSpacing: 60), 4)
    }
}
