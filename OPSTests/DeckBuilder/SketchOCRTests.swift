// OPS/OPSTests/DeckBuilder/SketchOCRTests.swift

import XCTest
@testable import OPS

final class SketchOCRTests: XCTestCase {
    let fullImageSize = CGSize(width: 3000, height: 4000)

    // MARK: - Dimension Classification

    func testClassify_feetWithApostrophe() {
        let result = SketchOCR.classifyText(
            "24'",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 288.0, accuracy: 1.0) // 24 * 12
        } else {
            XCTFail("Expected dimension, got \(result)")
        }
    }

    func testClassify_feetAndInches() {
        let result = SketchOCR.classifyText(
            "16' 6\"",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 198.0, accuracy: 1.0) // 16*12 + 6
        } else {
            XCTFail("Expected dimension")
        }
    }

    func testClassify_metersUnit() {
        let result = SketchOCR.classifyText(
            "7.5m",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertGreaterThan(inches, 290) // ~295 inches
        } else {
            XCTFail("Expected dimension")
        }
    }

    func testClassify_plainNumber() {
        let result = SketchOCR.classifyText(
            "24",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 288.0, accuracy: 1.0) // assume feet
        } else {
            XCTFail("Expected dimension")
        }
    }

    func testClassify_crossDimension() {
        let result = SketchOCR.classifyText(
            "24x16",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 288.0, accuracy: 1.0) // max(24*12, 16*12) = 288
        } else {
            XCTFail("Expected dimension, got \(result)")
        }
    }

    func testClassify_feetWithUnicodePrime() {
        let result = SketchOCR.classifyText(
            "24\u{2032}",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 288.0, accuracy: 1.0)
        } else {
            XCTFail("Expected dimension, got \(result)")
        }
    }

    func testClassify_feetUnit() {
        let result = SketchOCR.classifyText(
            "12ft",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 144.0, accuracy: 1.0) // 12 * 12
        } else {
            XCTFail("Expected dimension, got \(result)")
        }
    }

    func testClassify_inchesOnly() {
        let result = SketchOCR.classifyText(
            "36\"",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 36.0, accuracy: 1.0)
        } else {
            XCTFail("Expected dimension, got \(result)")
        }
    }

    // MARK: - Stair Count

    func testClassify_treads() {
        let result = SketchOCR.classifyText(
            "13 treads",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .stairCount(let count) = result {
            XCTAssertEqual(count, 13)
        } else {
            XCTFail("Expected stairCount")
        }
    }

    func testClassify_steps() {
        let result = SketchOCR.classifyText(
            "4 steps",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .stairCount(let count) = result {
            XCTAssertEqual(count, 4)
        } else {
            XCTFail("Expected stairCount")
        }
    }

    func testClassify_risers() {
        let result = SketchOCR.classifyText(
            "7 risers",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .stairCount(let count) = result {
            XCTAssertEqual(count, 7)
        } else {
            XCTFail("Expected stairCount, got \(result)")
        }
    }

    func testClassify_singleStep() {
        let result = SketchOCR.classifyText(
            "1 step",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .stairCount(let count) = result {
            XCTAssertEqual(count, 1)
        } else {
            XCTFail("Expected stairCount, got \(result)")
        }
    }

    // MARK: - Client Name

    func testClassify_clientName() {
        // Top of image (y < 20% of 4000 = 800)
        let result = SketchOCR.classifyText(
            "Heather Wilson",
            boundingBox: CGRect(x: 100, y: 100, width: 400, height: 60),
            imageSize: fullImageSize
        )
        if case .clientName(let name) = result {
            XCTAssertEqual(name, "Heather Wilson")
        } else {
            XCTFail("Expected clientName, got \(result)")
        }
    }

    func testClassify_clientNameNotAtTop() {
        // Middle of image — should NOT be classified as client name
        let result = SketchOCR.classifyText(
            "Heather Wilson",
            boundingBox: CGRect(x: 100, y: 2000, width: 400, height: 60),
            imageSize: fullImageSize
        )
        // Should be unknown or label, not clientName
        if case .clientName = result {
            XCTFail("Should not classify as client name when not at top of image")
        }
    }

    func testClassify_clientNameSingleChar() {
        // Single character at top — too short to be a client name
        let result = SketchOCR.classifyText(
            "A",
            boundingBox: CGRect(x: 100, y: 100, width: 50, height: 60),
            imageSize: fullImageSize
        )
        if case .clientName = result {
            XCTFail("Single character should not be classified as client name")
        }
    }

    func testClassify_clientNameNoCapital() {
        // All lowercase at top — no capital letter
        let result = SketchOCR.classifyText(
            "john smith",
            boundingBox: CGRect(x: 100, y: 100, width: 400, height: 60),
            imageSize: fullImageSize
        )
        if case .clientName = result {
            XCTFail("All lowercase should not be classified as client name")
        }
    }

    // MARK: - Labels

    func testClassify_label_stairs() {
        let result = SketchOCR.classifyText(
            "stairs",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .label(let text) = result {
            XCTAssertEqual(text, "stairs")
        } else {
            XCTFail("Expected label")
        }
    }

    func testClassify_label_house() {
        let result = SketchOCR.classifyText(
            "House",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .label(let text) = result {
            XCTAssertEqual(text, "house")
        } else {
            XCTFail("Expected label")
        }
    }

    func testClassify_label_deck() {
        let result = SketchOCR.classifyText(
            "DECK",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .label(let text) = result {
            XCTAssertEqual(text, "deck")
        } else {
            XCTFail("Expected label, got \(result)")
        }
    }

    func testClassify_label_railing() {
        let result = SketchOCR.classifyText(
            "Railing",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .label(let text) = result {
            XCTAssertEqual(text, "railing")
        } else {
            XCTFail("Expected label, got \(result)")
        }
    }

    // MARK: - Unknown

    func testClassify_unknown() {
        let result = SketchOCR.classifyText(
            "xyz123",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .unknown = result {
            // pass
        } else {
            XCTFail("Expected unknown")
        }
    }

    func testClassify_unknownRandomText() {
        let result = SketchOCR.classifyText(
            "asdf",
            boundingBox: CGRect(x: 100, y: 2000, width: 200, height: 50),
            imageSize: fullImageSize
        )
        if case .unknown = result {
            // pass
        } else {
            XCTFail("Expected unknown, got \(result)")
        }
    }

    // MARK: - Priority Ordering

    func testClassify_dimensionTakesPriorityOverLabel() {
        // "stair" is a label, but "13 treads" should match stair count first,
        // and a dimension like "24'" should match dimension first, not label.
        // Verify dimension wins over any label interpretation.
        let result = SketchOCR.classifyText(
            "24'",
            boundingBox: CGRect(x: 100, y: 100, width: 200, height: 50),
            imageSize: fullImageSize
        )
        // Even at top of image, dimension should take priority over client name
        if case .dimension(let inches) = result {
            XCTAssertEqual(inches, 288.0, accuracy: 1.0)
        } else {
            XCTFail("Dimension should take priority, got \(result)")
        }
    }

    func testClassify_stairCountTakesPriorityOverClientName() {
        // "13 treads" at top of image — stair count should win over client name
        let result = SketchOCR.classifyText(
            "13 treads",
            boundingBox: CGRect(x: 100, y: 100, width: 300, height: 50),
            imageSize: fullImageSize
        )
        if case .stairCount(let count) = result {
            XCTAssertEqual(count, 13)
        } else {
            XCTFail("Stair count should take priority, got \(result)")
        }
    }
}
