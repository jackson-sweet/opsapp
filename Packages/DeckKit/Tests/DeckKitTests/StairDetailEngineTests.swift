import XCTest
@testable import DeckKit

final class StairDetailEngineTests: XCTestCase {
    func testDetailPreservesBaseStringerPlanAndSizesNotchedStringerFromPackageTable() throws {
        let base = StairCalculator.calculate(totalRise: 30, width: 48)

        let result = StairDetailEngine.detail(
            base: base,
            treadType: .closedRiser,
            treadMaterial: "composite",
            stringerSpacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            package: samplePackage()
        )

        XCTAssertEqual(result.stringerCount, base.stringerCount)
        XCTAssertEqual(result.stringerSpacingInchesOC, 24, accuracy: 0.001)
        XCTAssertEqual(result.stringerType, .notchedWoodOpen)
        XCTAssertEqual(result.treadType, .closedRiser)
        XCTAssertEqual(result.treadMaterial, "composite")
        XCTAssertEqual(result.noseProjectionInches, 1, accuracy: 0.001)
        XCTAssertTrue(result.handrailRequired)
        XCTAssertEqual(result.handrailCodeSection, "IRC R311.7.8")

        let sizing = try XCTUnwrap(result.stringerSizing)
        guard case let .ok(value, citation, assumptions) = sizing.outcome else {
            return XCTFail("Expected stringer sizing inside the package envelope.")
        }

        XCTAssertEqual(value.size, .twoByTwelve)
        XCTAssertEqual(value.plyCount, 1)
        XCTAssertEqual(value.actualSpanFeet, base.stringerLength / 12, accuracy: 0.001)
        XCTAssertEqual(value.allowableSpanFeet, 180.0 / 12.0, accuracy: 0.001)
        XCTAssertEqual(value.utilization, base.stringerLength / 180.0, accuracy: 0.001)
        XCTAssertEqual(citation.codeSection, "AWC DCA6-12 Stair stringer table")
        XCTAssertEqual(citation.packageEdition, "IRC 2021 / DCA6-12")
        XCTAssertEqual(assumptions.species, .sprucePineFir)
        XCTAssertEqual(assumptions.grade, .no2)
    }

    func testHandrailRequiredAtFourRisersOnly() {
        let threeRisers = StairCalculator.calculate(totalRise: 21, width: 48, treadCountOverride: 3)
        let fourRisers = StairCalculator.calculate(totalRise: 28, width: 48, treadCountOverride: 4)

        let threeRiserResult = StairDetailEngine.detail(
            base: threeRisers,
            treadType: .openRiser,
            treadMaterial: "pt",
            stringerSpacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            package: samplePackage()
        )
        let fourRiserResult = StairDetailEngine.detail(
            base: fourRisers,
            treadType: .openRiser,
            treadMaterial: "pt",
            stringerSpacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            package: samplePackage()
        )

        XCTAssertFalse(threeRiserResult.handrailRequired)
        XCTAssertTrue(fourRiserResult.handrailRequired)
        XCTAssertEqual(fourRiserResult.handrailCodeSection, "IRC R311.7.8")
        XCTAssertEqual(threeRiserResult.noseProjectionInches, 0, accuracy: 0.001)
    }

    func testLandingInsertedWhenSingleFlightRiseExceedsPackageLimit() {
        let base = StairCalculator.calculate(totalRise: 160, width: 48)

        let result = StairDetailEngine.detail(
            base: base,
            treadType: .closedRiser,
            treadMaterial: "cedar",
            stringerSpacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            package: samplePackage(maxSingleFlightRiseInches: 147)
        )

        XCTAssertEqual(result.landings, [
            StairLanding(afterRiserIndex: 11, depthInches: 48),
        ])
    }

    func testQuarterTurnWinderUsesPackageInnerRunAndWalklineRun() {
        let base = StairCalculator.calculate(
            totalRise: 30,
            width: 48,
            runPerTread: 10.5
        )

        let result = StairDetailEngine.detail(
            base: base,
            treadType: .closedRiser,
            treadMaterial: "composite",
            stringerSpacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            package: samplePackage(),
            winder: StairWinderSpec(turnDegrees: 90, treadCount: 3)
        )

        XCTAssertEqual(result.winders, [
            WinderTread(index: 1, innerRunInches: 6, walklineRunInches: 10.5),
            WinderTread(index: 2, innerRunInches: 6, walklineRunInches: 10.5),
            WinderTread(index: 3, innerRunInches: 6, walklineRunInches: 10.5),
        ])
    }

    func testStringerSizingHardStopsWhenPackageHasNoCoveringNotchedStringerRow() throws {
        let base = StairCalculator.calculate(totalRise: 96, width: 48)

        let result = StairDetailEngine.detail(
            base: base,
            treadType: .closedRiser,
            treadMaterial: "composite",
            stringerSpacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            package: samplePackage(rows: [
                StairStringerSizingRow(
                    size: .twoByTwelve,
                    species: .sprucePineFir,
                    grade: .no2,
                    maxSpacingInchesOC: 16,
                    maxStringerLengthInches: 60,
                    codeSection: "AWC DCA6-12 Stair stringer table"
                ),
            ])
        )

        let sizing = try XCTUnwrap(result.stringerSizing)
        guard case let .outOfEnvelope(reason, citation) = sizing.outcome else {
            return XCTFail("Expected stringer sizing to stop outside the package envelope.")
        }

        XCTAssertTrue(reason.contains("notched-stringer"))
        XCTAssertTrue(reason.contains("outside the code package"))
        XCTAssertEqual(citation.codeSection, "AWC DCA6-12 Stair stringer table")
    }

    func testSteelStringerDoesNotUseWoodNotchedStringerRows() throws {
        let base = StairCalculator.calculate(totalRise: 30, width: 48)

        let result = StairDetailEngine.detail(
            base: base,
            treadType: .closedRiser,
            treadMaterial: "steel-pan-composite",
            stringerSpacingInchesOC: 24,
            species: .sprucePineFir,
            grade: .no2,
            package: samplePackage(),
            stringerType: .steel
        )

        XCTAssertEqual(result.stringerType, .steel)
        XCTAssertEqual(result.treadMaterial, "steel-pan-composite")

        let sizing = try XCTUnwrap(result.stringerSizing)
        guard case let .outOfEnvelope(reason, citation) = sizing.outcome else {
            return XCTFail("Expected steel stringers to require a steel-specific package row.")
        }

        XCTAssertTrue(reason.contains("steel stringer"))
        XCTAssertEqual(citation.codeSection, "IRC R311.7 / AWC DCA6")
    }

    func testOlderCodePackageJSONDecodesWithDefaultStairRules() throws {
        let data = Data("""
        {
          "jurisdictionId": "US-IRC",
          "edition": "IRC 2021"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(CodePackage.self, from: data)

        XCTAssertEqual(decoded.jurisdictionId, "US-IRC")
        XCTAssertEqual(decoded.edition, "IRC 2021")
        XCTAssertEqual(decoded.unitSystem, .imperial)
        XCTAssertEqual(decoded.stairRules.handrailRequiredRiserCount, 4)
        XCTAssertEqual(decoded.stairRules.handrailCodeSection, "IRC R311.7.8")
    }

    private func samplePackage(
        rows: [StairStringerSizingRow] = [
            StairStringerSizingRow(
                size: .twoByTwelve,
                species: .sprucePineFir,
                grade: .no2,
                maxSpacingInchesOC: 24,
                maxStringerLengthInches: 180,
                codeSection: "AWC DCA6-12 Stair stringer table"
            ),
        ],
        maxSingleFlightRiseInches: Double = 147
    ) -> CodePackage {
        var rules = StairRules()
        rules.maxSingleFlightRiseInches = maxSingleFlightRiseInches
        rules.notchedStringerSizing = rows

        return CodePackage(
            jurisdictionId: "US-IRC",
            edition: "IRC 2021 / DCA6-12",
            publishedDate: Date(timeIntervalSince1970: 0),
            unitSystem: .imperial,
            stairRules: rules
        )
    }
}
