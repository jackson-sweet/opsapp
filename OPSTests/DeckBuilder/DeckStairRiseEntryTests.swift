//
//  DeckStairRiseEntryTests.swift
//  OPSTests
//
//  Bug 46c2d6eb (A1) — the stair sheet's three rise vocabularies drifted out
//  of sync. Entering 4'0" in Height and switching to Treads showed whatever
//  the dial happened to hold, because nothing ever wrote one from the other.
//  Treads and height are two readings of ONE number; entering either has to
//  move the other.
//

import XCTest
@testable import OPS

final class DeckStairRiseEntryTests: XCTestCase {

    // MARK: - Height → treads

    func testEnteringAHeightDerivesTheTreadCount() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)

        entry.setHeight(feet: 4, inches: 0)

        XCTAssertEqual(entry.heightRiseInches, 48)
        // 48" over a 7.5" max riser needs 7 steps (6.86" actual).
        XCTAssertEqual(entry.treadCount, 7)
    }

    func testEnteringAHeightThatDividesEvenlyRoundTrips() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)

        entry.setHeight(feet: 2, inches: 6)

        XCTAssertEqual(entry.treadCount, 4)
        XCTAssertEqual(entry.treadRiseInches, 30)
        XCTAssertEqual(entry.heightRiseInches, 30)
    }

    /// A height entry must not be rewritten by the tread count it just
    /// produced — 4'0" stays 4'0" even though 7 treads spans 4'4.5".
    func testDerivingTreadsDoesNotRewriteTheEnteredHeight() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)

        entry.setHeight(feet: 4, inches: 0)

        XCTAssertEqual(entry.feet, 4)
        XCTAssertEqual(entry.inches, 0)
        XCTAssertEqual(entry.treadRiseInches, 52.5)
    }

    // MARK: - Treads → height

    func testEnteringATreadCountDerivesTheHeight() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)

        entry.setTreadCount(6)

        XCTAssertEqual(entry.treadCount, 6)
        // 6 × 7.5" = 45" = 3'9"
        XCTAssertEqual(entry.feet, 3)
        XCTAssertEqual(entry.inches, 9)
        XCTAssertEqual(entry.heightRiseInches, 45)
    }

    func testTreadCountClampsToTheDialRange() {
        var entry = DeckStairRiseEntry(totalRiseInches: 30, risePerStep: 7.5)

        entry.setTreadCount(0)
        XCTAssertEqual(entry.treadCount, 1)

        entry.setTreadCount(99)
        XCTAssertEqual(entry.treadCount, 30)
    }

    // MARK: - Rise per step re-derives whichever side is not authoritative

    func testChangingRisePerStepUnderHeightAuthorityRecomputesTreads() {
        var entry = DeckStairRiseEntry(totalRiseInches: 36, risePerStep: 7.5)
        XCTAssertEqual(entry.treadCount, 5)

        entry.setRisePerStep(7.0, authority: .height)

        XCTAssertEqual(entry.heightRiseInches, 36)
        XCTAssertEqual(entry.treadCount, 6)
    }

    func testChangingRisePerStepUnderTreadAuthorityRecomputesHeight() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)
        entry.setTreadCount(5)
        // 5 x 7.5" = 37.5". The dials hold whole inches, so the HEIGHT
        // reading rounds to 3'2" while `treadRiseInches` keeps the exact
        // figure the stair is built to.
        XCTAssertEqual(entry.treadRiseInches, 37.5)
        XCTAssertEqual(entry.heightRiseInches, 38)

        entry.setRisePerStep(7.0, authority: .treads)

        XCTAssertEqual(entry.treadCount, 5)
        XCTAssertEqual(entry.treadRiseInches, 35)
        XCTAssertEqual(entry.heightRiseInches, 35)
    }

    /// Treads mode commits the exact tread-derived rise, not the whole-inch
    /// figure the height dials can show — a stair is built to its steps.
    func testTreadDerivedRiseKeepsItsFractionForTheCommit() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.25)

        entry.setTreadCount(3)

        XCTAssertEqual(entry.treadRiseInches, 21.75)
        XCTAssertEqual(entry.heightRiseInches, 22)
    }

    // MARK: - Measured / prefilled rise

    /// The AR measure and the prefill from a level's resolved height both
    /// hand over a raw inch figure; both vocabularies follow it.
    func testSettingATotalRiseSyncsBothVocabularies() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)

        entry.setTotalRiseInches(66)

        XCTAssertEqual(entry.feet, 5)
        XCTAssertEqual(entry.inches, 6)
        XCTAssertEqual(entry.treadCount, 9)
    }

    func testAZeroRiseStillLeavesAWorkableTreadCount() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)

        XCTAssertEqual(entry.heightRiseInches, 0)
        XCTAssertEqual(entry.treadCount, 1)
    }

    func testANegativeMeasurementIsFlooredAtZero() {
        var entry = DeckStairRiseEntry(totalRiseInches: 30, risePerStep: 7.5)

        entry.setTotalRiseInches(-12)

        XCTAssertEqual(entry.heightRiseInches, 0)
        XCTAssertEqual(entry.feet, 0)
        XCTAssertEqual(entry.inches, 0)
    }

    func testInchesEntryNormalisesIntoFeet() {
        var entry = DeckStairRiseEntry(totalRiseInches: 0, risePerStep: 7.5)

        entry.setHeight(feet: 2, inches: 18)

        XCTAssertEqual(entry.feet, 3)
        XCTAssertEqual(entry.inches, 6)
        XCTAssertEqual(entry.heightRiseInches, 42)
    }
}
