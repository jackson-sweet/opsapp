// OPSTests/DeckBuilder/DeckMaterialsCodableTests.swift

import XCTest
@testable import OPS

final class DeckMaterialsCodableTests: XCTestCase {

    func testLegacyJSONDecodesWithNilMaterialsNodes() throws {
        let legacy = #"{"vertices":[],"edges":[]}"#
        let data = try XCTUnwrap(DeckDrawingData.fromJSON(legacy))
        XCTAssertNil(data.materialsSettings)
        XCTAssertNil(data.orderedMaterials)
    }

    func testMaterialsSettingsDefaults() {
        let s = DeckMaterialsSettings()
        XCTAssertEqual(s.glueCoverageSqFt, 400)
        XCTAssertEqual(s.dripStickFeet, 8)
        XCTAssertEqual(s.ninetyStickFeet, 8)
        XCTAssertEqual(s.clipStickFeet, 10)
    }

    func testSettingsPartialJSONFillsDefaults() throws {
        let json = #"{"glueCoverageSqFt":350}"#
        let s = try JSONDecoder().decode(DeckMaterialsSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.glueCoverageSqFt, 350)
        XCTAssertEqual(s.clipStickFeet, 10)
    }

    func testSnapshotRoundTripsThroughDrawingData() throws {
        var data = DeckDrawingData()
        data.materialsSettings = DeckMaterialsSettings(glueCoverageSqFt: 350, dripStickFeet: 10, ninetyStickFeet: 8, clipStickFeet: 12)
        data.orderedMaterials = DeckMaterialsSnapshot(
            orderedAt: Date(timeIntervalSince1970: 1_780_000_000),
            orderedBy: "user-1",
            settings: data.materialsSettings!,
            vinylSettings: .default,
            vinylColor: "Sandstone",
            vinylOrderedSqFt: 260,
            vinylSurfaceAreaSqFt: 240,
            cutGroups: [DeckMaterialsSnapshot.CutGroup(surfaceLabel: "Main", count: 2, lengthInches: 252, rollWidthInches: 72)],
            dripEdgeFeet: 44, dripSticks: 6,
            clipFeet: 44, clipSticks: 5,
            ninetyFeet: 20, ninetySticks: 3,
            glueAreaSqFt: 240, glueBuckets: 1
        )
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(data.toJSON()))
        XCTAssertEqual(decoded.materialsSettings, data.materialsSettings)
        XCTAssertEqual(decoded.orderedMaterials, data.orderedMaterials)
    }

    func testVinylOrderSettingsCodableRoundTrip() throws {
        var s = VinylOrderSettings.default
        s.rollWidthInches = 61
        s.direction = .widthwise
        let decoded = try JSONDecoder().decode(VinylOrderSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}
