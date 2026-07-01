import CoreGraphics
import Foundation
import XCTest
@testable import DeckKit

final class CodePackageFixtureTests: XCTestCase {
    func testUSIRC2021FixtureDecodesKnownDCA6CellsAndDrivesSizing() throws {
        let package = try loadFixture("US-IRC-2021")

        XCTAssertEqual(package.jurisdictionId, "US-IRC")
        XCTAssertEqual(package.unitSystem, .imperial)
        XCTAssertEqual(package.guardRules.minGuardHeightInches, 36, accuracy: 0.0001)
        XCTAssertEqual(package.guardRules.guardRequiredHeightInches, 30, accuracy: 0.0001)
        XCTAssertEqual(package.guardRules.maxOpeningInches, 4, accuracy: 0.0001)
        XCTAssertEqual(package.ledgerRules.minLateralConnectors, 2)
        XCTAssertEqual(package.stairRules.maxSingleFlightRiseInches, 144, accuracy: 0.0001)
        XCTAssertEqual(package.stairRules.minLandingDepthInches, 36, accuracy: 0.0001)
        XCTAssertEqual(package.stairRules.handrailRequiredRiserCount, 4)

        let joistRow = try XCTUnwrap(package.beamSpanTable.first {
            $0.role == .joist
                && $0.size == .twoByEight
                && $0.plyCount == 1
                && $0.species == .sprucePineFir
                && $0.grade == .no2
        })
        XCTAssertEqual(joistRow.maxSpanFeet, 11 + (1.0 / 12.0), accuracy: 0.0001)
        XCTAssertEqual(joistRow.maxLiveLoadPSF, 40)
        XCTAssertEqual(joistRow.maxDeadLoadPSF, 10)
        XCTAssertEqual(joistRow.codeSection, "AWC DCA6-15 Table 2")
        XCTAssertEqual(joistRow.limitingCheck, "2x8 SPF #2 joist span at 16 in. o.c.")

        let sizedJoist = StructuralSizingEngine.beamSizing(
            member: FramingMember(
                id: "fixture-joist",
                role: .joist,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 132, y: 0),
                nominalSize: .twoByEight,
                spacingInchesOC: 16,
                species: .sprucePineFir,
                grade: .no2
            ),
            load: LoadPreset(species: .sprucePineFir, grade: .no2),
            package: package
        )

        guard case let .ok(value, citation, assumptions) = sizedJoist.outcome else {
            return XCTFail("Expected fixture joist row to size inside the DCA6 subset envelope.")
        }
        XCTAssertEqual(value.size, .twoByEight)
        XCTAssertEqual(value.allowableSpanFeet, joistRow.maxSpanFeet, accuracy: 0.0001)
        XCTAssertEqual(citation.codeSection, joistRow.codeSection)
        XCTAssertEqual(assumptions.packageEdition, package.edition)

        let beamRow = try XCTUnwrap(package.beamSpanTable.first {
            $0.role == .beam
                && $0.size == .twoByTen
                && $0.plyCount == 2
                && $0.species == .sprucePineFir
                && $0.grade == .no2
        })
        XCTAssertEqual(beamRow.maxSpanFeet, 6.25, accuracy: 0.0001)
        XCTAssertEqual(beamRow.codeSection, "AWC DCA6-15 Table 3A")

        let postRow = try XCTUnwrap(package.postHeightTable.first {
            $0.size == .sixBySix && $0.species == .sprucePineFir && $0.grade == .no2
        })
        XCTAssertEqual(postRow.maxHeightFeet, 14, accuracy: 0.0001)
        XCTAssertEqual(postRow.codeSection, "AWC DCA6-15 Table 4")
        XCTAssertEqual(package.envelopeLimits.maxPostHeightFeet, 14)
    }

    func testBCBC2024FixtureDecodesMetricPart9SubsetAndDivergesFromImperial() throws {
        let us = try loadFixture("US-IRC-2021")
        let bc = try loadFixture("CA-BC-2024")

        XCTAssertEqual(bc.jurisdictionId, "CA-BC")
        XCTAssertEqual(bc.unitSystem, .metric)
        XCTAssertNotEqual(bc.unitSystem, us.unitSystem)

        XCTAssertEqual(bc.guardRules.guardRequiredHeightInches, millimeters(600), accuracy: 0.0001)
        XCTAssertEqual(bc.guardRules.minGuardHeightInches, millimeters(900), accuracy: 0.0001)
        XCTAssertEqual(bc.guardRules.maxOpeningInches, millimeters(100), accuracy: 0.0001)
        XCTAssertNotEqual(bc.guardRules.maxOpeningInches, us.guardRules.maxOpeningInches)

        XCTAssertEqual(bc.stairRules.maxRiserHeightInches, millimeters(200), accuracy: 0.0001)
        XCTAssertEqual(bc.stairRules.minTreadRunInches, millimeters(255), accuracy: 0.0001)
        XCTAssertGreaterThan(bc.stairRules.maxRiserHeightInches, us.stairRules.maxRiserHeightInches)
        XCTAssertGreaterThan(bc.stairRules.minTreadRunInches, us.stairRules.minTreadRunInches)
        XCTAssertTrue(bc.stairRules.notchedStringerSizing.isEmpty)
    }

    func testFixturesDeclareScopeAndSourceUrlsOutsideDecodablePackageShape() throws {
        let usMetadata = try loadMetadata("US-IRC-2021")
        let bcMetadata = try loadMetadata("CA-BC-2024")

        XCTAssertEqual(usMetadata["_fixtureScope"] as? String, "Known subset for DeckKit engine tests; not a complete jurisdiction package.")
        XCTAssertEqual(bcMetadata["_fixtureScope"] as? String, "Known subset for DeckKit engine tests; not a complete jurisdiction package.")
        XCTAssertFalse((usMetadata["_sourceUrls"] as? [String] ?? []).isEmpty)
        XCTAssertFalse((bcMetadata["_sourceUrls"] as? [String] ?? []).isEmpty)
    }

    private func loadFixture(_ name: String) throws -> CodePackage {
        try JSONDecoder().decode(CodePackage.self, from: fixtureData(name))
    }

    private func loadMetadata(_ name: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: fixtureData(name))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    private func fixtureURL(_ name: String) -> URL {
        if let bundled = Bundle.module.url(
            forResource: name,
            withExtension: "test.json",
            subdirectory: "Fixtures/CodePackages"
        ) {
            return bundled
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("CodePackages")
            .appendingPathComponent("\(name).test.json")
    }

    private func millimeters(_ value: Double) -> Double {
        value / 25.4
    }
}
