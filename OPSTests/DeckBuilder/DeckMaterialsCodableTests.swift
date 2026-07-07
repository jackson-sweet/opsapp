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
        // Full-roll ordering additions default to the cut-list purchasing mode
        // and a 75' full-roll length (spec § 3.2).
        XCTAssertEqual(s.orderMode, .cutList)
        XCTAssertEqual(s.fullRollLengthFeet, 75)
    }

    func testSettingsPartialJSONFillsDefaults() throws {
        let json = #"{"glueCoverageSqFt":350}"#
        let s = try JSONDecoder().decode(DeckMaterialsSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.glueCoverageSqFt, 350)
        XCTAssertEqual(s.clipStickFeet, 10)
        // Absent order-mode keys fall back to their defaults.
        XCTAssertEqual(s.orderMode, .cutList)
        XCTAssertEqual(s.fullRollLengthFeet, 75)
    }

    /// A settings JSON that sets only the order mode keeps every other field —
    /// including the untouched full-roll length and stick/glue presets — at its
    /// default (additive-field discipline).
    func testSettingsPartialJSONSetsOrderModeKeepsOtherDefaults() throws {
        let json = #"{"orderMode":"fullRolls"}"#
        let s = try JSONDecoder().decode(DeckMaterialsSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.orderMode, .fullRolls)
        XCTAssertEqual(s.fullRollLengthFeet, 75)
        XCTAssertEqual(s.glueCoverageSqFt, 400)
        XCTAssertEqual(s.dripStickFeet, 8)
        XCTAssertEqual(s.ninetyStickFeet, 8)
        XCTAssertEqual(s.clipStickFeet, 10)
    }

    func testVinylOrderModeRawRoundTrip() throws {
        for mode in VinylOrderMode.allCases {
            let decoded = try JSONDecoder().decode(VinylOrderMode.self, from: JSONEncoder().encode(mode))
            XCTAssertEqual(decoded, mode)
        }
        // Raw values are the stable JSON contract.
        XCTAssertEqual(VinylOrderMode.cutList.rawValue, "cutList")
        XCTAssertEqual(VinylOrderMode.fullRolls.rawValue, "fullRolls")
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
            glueAreaSqFt: 240, glueBuckets: 1,
            vinylSurfaceCount: 2
        )
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(data.toJSON()))
        XCTAssertEqual(decoded.materialsSettings, data.materialsSettings)
        XCTAssertEqual(decoded.orderedMaterials, data.orderedMaterials)
        // The explicit surface count survives the round-trip (not reconstructed).
        XCTAssertEqual(decoded.orderedMaterials?.vinylSurfaceCount, 2)
    }

    /// A snapshot JSON written before `vinylSurfaceCount` existed decodes with the
    /// old distinct-label reconstruction — additive-field discipline, no crash,
    /// legacy behavior unchanged. (Two cut groups share the label "Main" → 1.)
    func testSnapshotWithoutSurfaceCountFallsBackToLabelCount() throws {
        let json = """
        {
          "orderedAt": 1780000000,
          "cutGroups": [
            {"surfaceLabel": "Main", "count": 2, "lengthInches": 252, "rollWidthInches": 72},
            {"surfaceLabel": "Main", "count": 1, "lengthInches": 144, "rollWidthInches": 72}
          ]
        }
        """
        let snapshot = try JSONDecoder().decode(DeckMaterialsSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.vinylSurfaceCount, 1)
    }

    func testVinylOrderSettingsCodableRoundTrip() throws {
        var s = VinylOrderSettings.default
        s.rollWidthInches = 61
        s.direction = .widthwise
        let decoded = try JSONDecoder().decode(VinylOrderSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}
