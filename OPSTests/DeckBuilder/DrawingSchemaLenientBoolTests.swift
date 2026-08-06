//
//  DrawingSchemaLenientBoolTests.swift
//  OPSTests
//
//  Bug bb3c2b5c — every boolean the app pushed inside `drawing_data` was stored
//  as 0/1 (the AnyJSON bridge flattened it). A production walk of
//  `deck_designs.drawing_data` found ZERO boolean-typed values, so any strict
//  `Bool` decode in the drawing schema is a live decode landmine: the row is
//  skipped on pull and the design silently never merges.
//
//  The drawing schema has exactly ten stored `Bool`s. Eight already route
//  through `decodeLegacyBoolIfPresent`; these two did not.
//

import XCTest
@testable import OPS

final class DrawingSchemaLenientBoolTests: XCTestCase {

    // MARK: - VinylOrderSettings.allowsDirectionalChanges

    /// The exact shape observed in production, plus the honest boolean form.
    func test_vinylSettingsDecodeDirectionalChangesAsBoolOrNumber() throws {
        XCTAssertTrue(try decodeVinyl(rawValue: "true").allowsDirectionalChanges)
        XCTAssertFalse(try decodeVinyl(rawValue: "false").allowsDirectionalChanges)
        XCTAssertTrue(try decodeVinyl(rawValue: "1").allowsDirectionalChanges)
        XCTAssertFalse(try decodeVinyl(rawValue: "0").allowsDirectionalChanges)
    }

    func test_vinylSettingsKeepDefaultWhenDirectionalChangesAbsentOrNull() throws {
        let absent = try JSONDecoder().decode(
            VinylOrderSettings.self,
            from: Data(#"{"color":"Sand","rollWidthInches":72}"#.utf8)
        )
        XCTAssertFalse(absent.allowsDirectionalChanges)

        XCTAssertFalse(try decodeVinyl(rawValue: "null").allowsDirectionalChanges)
    }

    /// Non-boolean junk still throws — leniency covers the 0/1 wire shape, it is
    /// not a blanket "swallow anything" fallback.
    func test_vinylSettingsRejectNonBooleanDirectionalChanges() {
        XCTAssertThrowsError(try decodeVinyl(rawValue: "2"))
        XCTAssertThrowsError(try decodeVinyl(rawValue: #""maybe""#))
    }

    /// String "true"/"false" round-trips too — the shared helper accepts them and
    /// legacy blobs in this schema have carried stringified flags before.
    func test_vinylSettingsAcceptStringifiedDirectionalChanges() throws {
        XCTAssertTrue(try decodeVinyl(rawValue: #""true""#).allowsDirectionalChanges)
        XCTAssertFalse(try decodeVinyl(rawValue: #""false""#).allowsDirectionalChanges)
    }

    // MARK: - DeckMaterialsSnapshot.isOrderedEdited

    func test_materialsSnapshotDecodesIsOrderedEditedAsBoolOrNumber() throws {
        XCTAssertTrue(try decodeSnapshot(rawValue: "true").isOrderedEdited)
        XCTAssertFalse(try decodeSnapshot(rawValue: "false").isOrderedEdited)
        XCTAssertTrue(try decodeSnapshot(rawValue: "1").isOrderedEdited)
        XCTAssertFalse(try decodeSnapshot(rawValue: "0").isOrderedEdited)
    }

    func test_materialsSnapshotKeepsDefaultWhenIsOrderedEditedAbsent() throws {
        let snapshot = try JSONDecoder().decode(
            DeckMaterialsSnapshot.self,
            from: Data(#"{"orderedAt":770000000}"#.utf8)
        )
        XCTAssertFalse(snapshot.isOrderedEdited)
    }

    // MARK: - Whole-drawing round trip

    /// A full `drawing_data` blob in the corrupted production shape must decode
    /// end to end — this is the pull path that was silently dropping rows.
    func test_drawingDataWithNumericBooleansDecodes() throws {
        let json = """
        {
          "schemaVersion": 3,
          "vertices": [],
          "edges": [],
          "config": {"snappingEnabled": 1, "gridVisible": 0},
          "vinylOrderSettings": {
            "color": "Sand",
            "rollWidthInches": 72,
            "seamOverlapInches": 1.5,
            "edgeWrapInches": 6,
            "direction": "automatic",
            "allowsDirectionalChanges": 1
          },
          "orderedMaterials": {
            "orderedAt": 770000000,
            "isOrderedEdited": 1
          }
        }
        """

        let drawing = try JSONDecoder().decode(
            DeckDrawingData.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(drawing.vinylOrderSettings?.allowsDirectionalChanges, true)
        XCTAssertEqual(drawing.orderedMaterials?.isOrderedEdited, true)
        XCTAssertTrue(drawing.config.snappingEnabled)
        XCTAssertFalse(drawing.config.gridVisible)
    }

    // MARK: - Helpers

    private func decodeVinyl(rawValue: String) throws -> VinylOrderSettings {
        try JSONDecoder().decode(
            VinylOrderSettings.self,
            from: Data(
                """
                {"color":"Sand","rollWidthInches":72,
                 "allowsDirectionalChanges":\(rawValue)}
                """.utf8
            )
        )
    }

    private func decodeSnapshot(rawValue: String) throws -> DeckMaterialsSnapshot {
        try JSONDecoder().decode(
            DeckMaterialsSnapshot.self,
            from: Data(
                """
                {"orderedAt":770000000,
                 "isOrderedEdited":\(rawValue)}
                """.utf8
            )
        )
    }
}
