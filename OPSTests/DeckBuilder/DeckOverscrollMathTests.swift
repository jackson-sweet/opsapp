// OPS/OPSTests/DeckBuilder/DeckOverscrollMathTests.swift

import XCTest
@testable import OPS

final class DeckOverscrollMathTests: XCTestCase {

    func testProgressIsZeroAtRest() {
        XCTAssertEqual(DeckOverscrollMath.progress(pull: 0), 0, accuracy: 0.0001)
    }

    func testProgressIsHalfwayAtHalfThreshold() {
        XCTAssertEqual(
            DeckOverscrollMath.progress(pull: 60, threshold: 120),
            0.5, accuracy: 0.0001
        )
    }

    func testProgressClampsToOne() {
        XCTAssertEqual(DeckOverscrollMath.progress(pull: 999, threshold: 120), 1, accuracy: 0.0001)
    }

    func testNegativePullReadsAsZero() {
        XCTAssertEqual(DeckOverscrollMath.progress(pull: -30), 0, accuracy: 0.0001)
    }

    func testZeroThresholdIsSafe() {
        XCTAssertEqual(DeckOverscrollMath.progress(pull: 50, threshold: 0), 0, accuracy: 0.0001)
    }

    func testCommitFalseBelowThreshold() {
        XCTAssertFalse(DeckOverscrollMath.isCommitted(pull: 119))
    }

    func testCommitTrueAtThreshold() {
        XCTAssertTrue(DeckOverscrollMath.isCommitted(pull: 120))
    }
}
