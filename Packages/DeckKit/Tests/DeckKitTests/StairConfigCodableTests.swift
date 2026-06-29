//
//  StairConfigCodableTests.swift
//  OPSTests
//
//  Locks the flipDirection round-trip so a future key rename or decoder
//  change can't silently swallow the stair-swap toggle (it decodes via
//  decodeLegacyBoolIfPresent, which defaults to false on any miss).
//

import XCTest
@testable import DeckKit

final class StairConfigCodableTests: XCTestCase {

    func testFlipDirectionSurvivesRoundTrip() throws {
        let original = StairConfig(width: 48, flipDirection: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StairConfig.self, from: data)
        XCTAssertTrue(decoded.flipDirection,
                      "flipDirection must survive an encode/decode round-trip")
    }

    func testFlipDirectionDefaultsFalseForLegacyJSON() throws {
        let legacy = Data(#"{"width":48}"#.utf8)
        let decoded = try JSONDecoder().decode(StairConfig.self, from: legacy)
        XCTAssertFalse(decoded.flipDirection,
                       "legacy JSON without flipDirection must default to false")
    }

    func testRailingProductOptionsSurviveRoundTrip() throws {
        let original = RailingConfig(
            railingType: .glass,
            maxPostSpacing: 60,
            frameStyle: .frameless,
            mountPlacement: .fasciaMounted
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RailingConfig.self, from: data)

        XCTAssertEqual(decoded.frameStyle, .frameless)
        XCTAssertEqual(decoded.mountPlacement, .fasciaMounted)
    }

    func testRailingProductOptionsDefaultForLegacyJSON() throws {
        let legacy = Data(#"{"railingType":"glass","maxPostSpacing":60}"#.utf8)
        let decoded = try JSONDecoder().decode(RailingConfig.self, from: legacy)

        XCTAssertEqual(decoded.frameStyle, .framed)
        XCTAssertEqual(decoded.mountPlacement, .topMounted)
    }

    func testStairProductOptionsSurviveRoundTrip() throws {
        let original = StairConfig(
            width: 48,
            stringerStyle: .closed,
            stringerMaterial: .steel,
            treadMaterial: .fiveQuarterDecking
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StairConfig.self, from: data)

        XCTAssertEqual(decoded.stringerStyle, .closed)
        XCTAssertEqual(decoded.stringerMaterial, .steel)
        XCTAssertEqual(decoded.treadMaterial, .fiveQuarterDecking)
    }

    func testStairProductOptionsDefaultForLegacyJSON() throws {
        let legacy = Data(#"{"width":48}"#.utf8)
        let decoded = try JSONDecoder().decode(StairConfig.self, from: legacy)

        XCTAssertEqual(decoded.stringerStyle, .open)
        XCTAssertEqual(decoded.stringerMaterial, .pressureTreatedWood)
        XCTAssertEqual(decoded.treadMaterial, .composite)
    }
}
