// OPS/OPSTests/DeckBuilder/StairCalculatorTests.swift

import XCTest
@testable import DeckKit

final class StairCalculatorTests: XCTestCase {

    func testCalculate_30inchDeck_4treads() {
        let spec = StairCalculator.calculate(totalRise: 30, width: 48)
        XCTAssertEqual(spec.treadCount, 4)  // 30 / 7.5 = 4
        XCTAssertEqual(spec.risePerStep, 7.5, accuracy: 0.01)
        XCTAssertEqual(spec.totalRun, 40.0, accuracy: 0.01) // 4 * 10
        XCTAssertEqual(spec.stringerCount, 3) // ceil(48/24) + 1 = 3 (24" o.c. max)
    }

    func testCalculate_8footDeck_13treads() {
        // 8 feet = 96 inches
        let spec = StairCalculator.calculate(totalRise: 96, width: 48)
        XCTAssertEqual(spec.treadCount, 13) // ceil(96/7.5) = 13
        // Actual rise per step: 96/13 ≈ 7.38"
        XCTAssertEqual(spec.risePerStep, 96.0 / 13.0, accuracy: 0.01)
    }

    func testCalculate_zeroRise_zeroTreads() {
        let spec = StairCalculator.calculate(totalRise: 0, width: 48)
        XCTAssertEqual(spec.treadCount, 0)
    }

    func testCalculate_manualTreadCountOverridesCalculatedCount() {
        let spec = StairCalculator.calculate(
            totalRise: 30,
            width: 48,
            risePerStep: 7.5,
            runPerTread: 10,
            treadCountOverride: 6
        )

        XCTAssertEqual(spec.treadCount, 6)
        XCTAssertEqual(spec.risePerStep, 5.0, accuracy: 0.01)
        XCTAssertEqual(spec.totalRun, 60.0, accuracy: 0.01)
    }

    func testStringerLength_pythagorean() {
        // 30" rise, 4 treads at 10" = 40" run
        // sqrt(30² + 40²) = sqrt(900 + 1600) = sqrt(2500) = 50
        let spec = StairCalculator.calculate(totalRise: 30, width: 48)
        XCTAssertEqual(spec.stringerLength, 50.0, accuracy: 0.1)
    }

    func testRailingPostCount() {
        // 50" stringer with 60" max spacing = 1 span + 1 = 2 posts
        XCTAssertEqual(StairCalculator.railingPostCount(stringerLength: 50, maxSpacing: 60), 2)
        // 120" stringer with 60" max spacing = 2 spans + 1 = 3 posts
        XCTAssertEqual(StairCalculator.railingPostCount(stringerLength: 120, maxSpacing: 60), 3)
    }
}
