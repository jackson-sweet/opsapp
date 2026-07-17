//
//  VinylConsumablesAggregatorTests.swift
//  OPSTests
//
//  Spec § 7 semantics: sticks summed across jobs THEN one ceil per type;
//  glue summed as per-job area/coverage ratios with one final round-up.
//

import XCTest
@testable import OPS

final class VinylConsumablesAggregatorTests: XCTestCase {

    private func need(
        drip: Int = 0,
        ninety: Int = 0,
        clip: Int = 0,
        glueArea: Double = 0,
        glueCoverage: Double = 400
    ) -> VinylConsumableNeed {
        VinylConsumableNeed(
            dripSticks: drip,
            ninetySticks: ninety,
            clipSticks: clip,
            glueAreaSqFt: glueArea,
            glueCoverageSqFt: glueCoverage
        )
    }

    /// The batching-economics case: 4 jobs × 8 drip sticks = 32 sticks = 2
    /// tubes of 30 — NOT 4 over-ordered single-job tubes.
    func testSticksSumAcrossJobsBeforeCeil() {
        let needs = Array(repeating: need(drip: 8), count: 4)
        let suggestion = VinylConsumablesAggregator.suggest(needs: needs, clipPerTube: 50, flashingPerTube: 30)
        XCTAssertEqual(suggestion.totalDripSticks, 32)
        XCTAssertEqual(suggestion.dripTubes, 2)
    }

    func testExactTubeBoundaries() {
        let at30 = VinylConsumablesAggregator.suggest(needs: [need(drip: 30)], clipPerTube: 50, flashingPerTube: 30)
        XCTAssertEqual(at30.dripTubes, 1)

        let at31 = VinylConsumablesAggregator.suggest(needs: [need(drip: 31)], clipPerTube: 50, flashingPerTube: 30)
        XCTAssertEqual(at31.dripTubes, 2)

        let clipAt50 = VinylConsumablesAggregator.suggest(needs: [need(clip: 50)], clipPerTube: 50, flashingPerTube: 30)
        XCTAssertEqual(clipAt50.clipTubes, 1)

        let clipAt51 = VinylConsumablesAggregator.suggest(needs: [need(clip: 51)], clipPerTube: 50, flashingPerTube: 30)
        XCTAssertEqual(clipAt51.clipTubes, 2)
    }

    func testNinetyUsesFlashingCapacity() {
        let suggestion = VinylConsumablesAggregator.suggest(
            needs: [need(ninety: 31)],
            clipPerTube: 50,
            flashingPerTube: 30
        )
        XCTAssertEqual(suggestion.ninetyTubes, 2)
        XCTAssertEqual(suggestion.totalNinetySticks, 31)
    }

    func testEmptyNeedsAllZero() {
        let suggestion = VinylConsumablesAggregator.suggest(needs: [], clipPerTube: 50, flashingPerTube: 30)
        XCTAssertEqual(suggestion, VinylConsumablesSuggestion(
            dripTubes: 0, ninetyTubes: 0, clipTubes: 0, glueBuckets: 0,
            totalDripSticks: 0, totalNinetySticks: 0, totalClipSticks: 0,
            exactGlueBuckets: 0
        ))
    }

    /// Mixed per-design coverage: 200/400 + 300/400 = 1.25 exact → 2 buckets.
    func testGlueSumsPerJobRatiosThenOneCeil() {
        let suggestion = VinylConsumablesAggregator.suggest(
            needs: [need(glueArea: 200, glueCoverage: 400), need(glueArea: 300, glueCoverage: 400)],
            clipPerTube: 50,
            flashingPerTube: 30
        )
        XCTAssertEqual(suggestion.exactGlueBuckets, 1.25, accuracy: 0.0001)
        XCTAssertEqual(suggestion.glueBuckets, 2)
    }

    /// Coverage differing per design changes each job's ratio independently.
    func testGlueRespectsPerDesignCoverage() {
        let suggestion = VinylConsumablesAggregator.suggest(
            needs: [need(glueArea: 200, glueCoverage: 100), need(glueArea: 200, glueCoverage: 400)],
            clipPerTube: 50,
            flashingPerTube: 30
        )
        XCTAssertEqual(suggestion.exactGlueBuckets, 2.5, accuracy: 0.0001)
        XCTAssertEqual(suggestion.glueBuckets, 3)
    }

    func testZeroCoverageRowIgnored() {
        let suggestion = VinylConsumablesAggregator.suggest(
            needs: [need(glueArea: 500, glueCoverage: 0), need(glueArea: 400, glueCoverage: 400)],
            clipPerTube: 50,
            flashingPerTube: 30
        )
        XCTAssertEqual(suggestion.exactGlueBuckets, 1.0, accuracy: 0.0001)
        XCTAssertEqual(suggestion.glueBuckets, 1)
    }

    func testPerTubeZeroClampsToOne() {
        let suggestion = VinylConsumablesAggregator.suggest(
            needs: [need(drip: 3, clip: 2)],
            clipPerTube: 0,
            flashingPerTube: 0
        )
        XCTAssertEqual(suggestion.dripTubes, 3)
        XCTAssertEqual(suggestion.clipTubes, 2)
    }

    func testNegativeStickCountsContributeNothing() {
        let suggestion = VinylConsumablesAggregator.suggest(
            needs: [need(drip: -5), need(drip: 8)],
            clipPerTube: 50,
            flashingPerTube: 30
        )
        XCTAssertEqual(suggestion.totalDripSticks, 8)
        XCTAssertEqual(suggestion.dripTubes, 1)
    }
}
