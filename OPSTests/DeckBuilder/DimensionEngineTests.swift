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

    // MARK: - Bug e7965781 — Imperial Apostrophe-Notation Suite

    /// 6'7" should equal 6 feet 7 inches = 79".
    func testParseImperial_apostropheFeetInches() {
        XCTAssertEqual(DimensionEngine.parseToInches("6'7\"", system: .imperial), 79)
    }

    /// 6'7 (inches mark missing) should still equal 79 — the parser knows the
    /// trailing number after a feet marker is inches.
    func testParseImperial_apostropheFeet_implicitInches() {
        XCTAssertEqual(DimensionEngine.parseToInches("6'7", system: .imperial), 79)
    }

    /// 6.5' should equal 6 feet 6 inches = 78". Decimal feet must round-trip
    /// to the same total inches as the contractor would expect from "six and
    /// a half feet".
    func testParseImperial_decimalFeet() {
        XCTAssertEqual(DimensionEngine.parseToInches("6.5'", system: .imperial), 78)
    }

    /// 6' 1/2" should equal 6 feet plus a half inch = 72.5".
    func testParseImperial_mixedFractionalInches() {
        XCTAssertEqual(DimensionEngine.parseToInches("6' 1/2\"", system: .imperial), 72.5)
    }

    /// 6' 1 1/2" — feet plus mixed-number inches.
    func testParseImperial_mixedNumberInches() {
        XCTAssertEqual(DimensionEngine.parseToInches("6' 1 1/2\"", system: .imperial), 73.5)
    }

    /// Bare fraction interpreted as inches.
    func testParseImperial_bareFractionIsInches() {
        XCTAssertEqual(DimensionEngine.parseToInches("1/2\"", system: .imperial), 0.5)
    }

    /// Three-eighths inch — exercises non-half denominators.
    func testParseImperial_thirdsAndEighths() {
        XCTAssertEqual(DimensionEngine.parseToInches("3/8\"", system: .imperial), 0.375)
        XCTAssertEqual(DimensionEngine.parseToInches("5/8\"", system: .imperial), 0.625)
    }

    /// Smart curly apostrophe (U+2019) instead of straight ASCII '.
    func testParseImperial_smartQuoteFeet() {
        let smart = "6\u{2019}7\""
        XCTAssertEqual(DimensionEngine.parseToInches(smart, system: .imperial), 79)
    }

    /// Whitespace tolerance — leading/trailing spaces, no inner space.
    func testParseImperial_whitespace() {
        XCTAssertEqual(DimensionEngine.parseToInches("  24' 6\"  ", system: .imperial), 294)
    }

    /// Two bare numbers with no marker — first is feet, second is inches.
    func testParseImperial_twoBareNumbers() {
        XCTAssertEqual(DimensionEngine.parseToInches("12 6", system: .imperial), 150)
    }

    /// "ft" / "in" word suffixes normalize to symbols.
    func testParseImperial_wordSuffixes() {
        XCTAssertEqual(DimensionEngine.parseToInches("12 ft 6 in", system: .imperial), 150)
        XCTAssertEqual(DimensionEngine.parseToInches("12 feet 6 inches", system: .imperial), 150)
    }

    // MARK: - Bug e7965781 — Metric Suite

    /// 2m → 200 cm → 78.7401" (rounded for display, exact for math).
    func testParseMetric_meters() {
        let inches = DimensionEngine.parseToInches("2m", system: .metric)
        XCTAssertNotNil(inches)
        XCTAssertEqual(inches!, 200.0 / 2.54, accuracy: 0.0001)
    }

    /// 2.5m → 250 cm → 98.425".
    func testParseMetric_decimalMeters() {
        let inches = DimensionEngine.parseToInches("2.5m", system: .metric)
        XCTAssertNotNil(inches)
        XCTAssertEqual(inches!, 250.0 / 2.54, accuracy: 0.0001)
    }

    /// 200cm → 200 cm → 78.7401".
    func testParseMetric_centimeters() {
        let inches = DimensionEngine.parseToInches("200cm", system: .metric)
        XCTAssertNotNil(inches)
        XCTAssertEqual(inches!, 200.0 / 2.54, accuracy: 0.0001)
    }

    /// 2000mm → 200 cm → 78.7401". Catches a previous bug where mm matched the
    /// `.contains("m")` branch and was mis-treated as 2000 metres.
    func testParseMetric_millimeters() {
        let inches = DimensionEngine.parseToInches("2000mm", system: .metric)
        XCTAssertNotNil(inches)
        XCTAssertEqual(inches!, 200.0 / 2.54, accuracy: 0.0001)
    }

    /// Compound metric input: "2m 50cm" = 250 cm.
    func testParseMetric_compound() {
        let inches = DimensionEngine.parseToInches("2m 50cm", system: .metric)
        XCTAssertNotNil(inches)
        XCTAssertEqual(inches!, 250.0 / 2.54, accuracy: 0.0001)
    }

    /// Bare number with no unit → defaults to cm under metric mode.
    func testParseMetric_bareNumberDefaultsToCm() {
        let inches = DimensionEngine.parseToInches("150", system: .metric)
        XCTAssertNotNil(inches)
        XCTAssertEqual(inches!, 150.0 / 2.54, accuracy: 0.0001)
    }

    /// Empty string returns nil under metric, mirroring imperial behavior.
    func testParseMetric_emptyReturnsNil() {
        XCTAssertNil(DimensionEngine.parseToInches("", system: .metric))
    }
}
