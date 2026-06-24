//
//  StairConfigCodableTests.swift
//  OPSTests
//
//  Locks the flipDirection round-trip so a future key rename or decoder
//  change can't silently swallow the stair-swap toggle (it decodes via
//  decodeLegacyBoolIfPresent, which defaults to false on any miss).
//

import XCTest
@testable import OPS

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
}
