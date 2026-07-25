// OPSTests/DeckBuilder/VinylRollPackerTests.swift
//
// First-fit-decreasing full-roll packing (spec § 4.1). A strip is cut from ONE
// roll and never spans two; a strip longer than a roll is flagged, not dropped.

import XCTest
@testable import OPS

final class VinylRollPackerTests: XCTestCase {

    func testEmptyStripsNeedNoRolls() {
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 0, overlengthStripCount: 0))
    }

    func testSingleStripUnderRollFitsOneRoll() {
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [70], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 1, overlengthStripCount: 0))
    }

    func testStripEqualToRollLengthFitsOneRoll() {
        // Exact fit must not spill into a second roll (epsilon tolerance).
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [75], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 1, overlengthStripCount: 0))
    }

    func testTwoStripsThatCannotCoFitTakeTwoRolls() {
        // 40 + 40 = 80 > 75, so they cannot share a roll.
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [40, 40], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 2, overlengthStripCount: 0))
    }

    func testThreeStripsPackIntoTwoRollsFFD() {
        // FFD: 40+30 on roll one (70 ≤ 75), 30 on roll two.
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [40, 30, 30], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 2, overlengthStripCount: 0))
    }

    func testThreeNearFullStripsTakeThreeRolls() {
        // Each 70 leaves only 5' — no two co-fit.
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [70, 70, 70], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 3, overlengthStripCount: 0))
    }

    func testOverlengthStripIsFlaggedNotPacked() {
        // 80 > 75 cannot be produced at this roll length.
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [80], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 0, overlengthStripCount: 1))
    }

    func testMixedPackableAndOverlength() {
        // 90 overlength; 40+30 co-fit on one roll, 30 opens a second.
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [90, 40, 30, 30], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 2, overlengthStripCount: 1))
    }

    func testNonPositiveRollLengthMakesEveryStripUnproducible() {
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [40, 30, 30], rollLengthFeet: 0)
        XCTAssertEqual(result, RollPackResult(rollCount: 0, overlengthStripCount: 3))
    }

    func testDegenerateZeroLengthStripsConsumeNoRoll() {
        // A 0-length strip needs no material and is not overlength.
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [0, 0], rollLengthFeet: 75)
        XCTAssertEqual(result, RollPackResult(rollCount: 0, overlengthStripCount: 0))
    }

    func testCustomRollLengthPacksAccordingly() {
        // At a 100' roll, 40+30+30 = 100 all fit on one roll.
        let result = VinylRollPacker.rollsNeeded(stripLengthsFeet: [40, 30, 30], rollLengthFeet: 100)
        XCTAssertEqual(result, RollPackResult(rollCount: 1, overlengthStripCount: 0))
    }

    func testPackingIsOrderIndependent() {
        // FFD sorts internally, so input order never changes the roll count.
        let a = VinylRollPacker.rollsNeeded(stripLengthsFeet: [30, 40, 30, 20, 55], rollLengthFeet: 75)
        let b = VinylRollPacker.rollsNeeded(stripLengthsFeet: [55, 20, 30, 40, 30], rollLengthFeet: 75)
        XCTAssertEqual(a, b)
    }

    func testPackingPlanRetainsEachRollsCutsUsedAndLeftoverFeet() {
        let plan = VinylRollPacker.packingPlan(
            stripLengthsFeet: [40, 30, 30],
            rollLengthFeet: 75
        )

        XCTAssertEqual(plan.rolls.count, 2)
        XCTAssertEqual(plan.rolls[0].stripLengthsFeet, [40, 30])
        XCTAssertEqual(plan.rolls[0].usedFeet, 70, accuracy: 0.001)
        XCTAssertEqual(plan.rolls[0].leftoverFeet, 5, accuracy: 0.001)
        XCTAssertEqual(plan.rolls[1].stripLengthsFeet, [30])
        XCTAssertEqual(plan.rolls[1].usedFeet, 30, accuracy: 0.001)
        XCTAssertEqual(plan.rolls[1].leftoverFeet, 45, accuracy: 0.001)
    }

    func testPackingPlanExactFitLeavesNothing() {
        let plan = VinylRollPacker.packingPlan(
            stripLengthsFeet: [45, 30],
            rollLengthFeet: 75
        )

        XCTAssertEqual(plan.rolls.count, 1)
        XCTAssertEqual(plan.rolls[0].usedFeet, 75, accuracy: 0.001)
        XCTAssertEqual(plan.rolls[0].leftoverFeet, 0, accuracy: 0.001)
    }

    func testPackingPlanKeepsOverlengthCutsOutsideEveryRoll() {
        let plan = VinylRollPacker.packingPlan(
            stripLengthsFeet: [80, 40, 30],
            rollLengthFeet: 75
        )

        XCTAssertEqual(plan.overlengthStripLengthsFeet, [80])
        XCTAssertEqual(plan.rolls.flatMap(\.stripLengthsFeet), [40, 30])
        XCTAssertEqual(plan.summary, RollPackResult(rollCount: 1, overlengthStripCount: 1))
    }

    func testPackingPlanIsDeterministicAcrossInputOrder() {
        let a = VinylRollPacker.packingPlan(
            stripLengthsFeet: [30, 40, 30, 20, 55],
            rollLengthFeet: 75
        )
        let b = VinylRollPacker.packingPlan(
            stripLengthsFeet: [55, 20, 30, 40, 30],
            rollLengthFeet: 75
        )

        XCTAssertEqual(a, b)
    }
}
