import XCTest
@testable import OPS

final class FractionalRankTests: XCTestCase {

    func testBetween_emptyList_returnsZero() {
        XCTAssertEqual(FractionalRank.between(nil, nil), 0)
    }

    func testBetween_openTop_isAboveLower() {
        XCTAssertEqual(FractionalRank.between(nil, 100), 99)
    }

    func testBetween_openBottom_isBelowUpper() {
        XCTAssertEqual(FractionalRank.between(100, nil), 101)
    }

    func testBetween_twoNeighbors_isMidpoint() {
        XCTAssertEqual(FractionalRank.between(10, 20), 15)
    }

    func testBetween_strictlyOrderedAfterRepeatedTopInserts() {
        var upper = 0.0
        var last = Double.greatestFiniteMagnitude
        for _ in 0..<40 {
            let r = FractionalRank.between(nil, upper)
            XCTAssertLessThan(r, upper)
            XCTAssertLessThan(r, last)
            last = r
            upper = r
        }
    }

    func testNeedsNormalization_trueWhenGapTooSmall() {
        XCTAssertTrue(FractionalRank.needsNormalization(between: 1.0, and: 1.0 + 1e-10))
        XCTAssertFalse(FractionalRank.needsNormalization(between: 1.0, and: 2.0))
    }

    func testNormalize_evenlySpacesPreservingOrder() {
        let ids = ["a", "b", "c", "d"]
        let ranks = FractionalRank.normalize(orderedIds: ids)
        XCTAssertEqual(ids.sorted { ranks[$0]! < ranks[$1]! }, ids)
        XCTAssertEqual(ranks["a"], 1024)
        XCTAssertEqual(ranks["d"], 4096)
    }
}
