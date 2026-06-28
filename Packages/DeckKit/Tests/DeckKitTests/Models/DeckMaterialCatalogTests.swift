import XCTest
@testable import DeckKit

final class DeckMaterialCatalogTests: XCTestCase {
    func testCompositeDeckingMapsFromBuiltIn() throws {
        let builtIn = try XCTUnwrap(
            BuiltInMaterial.areaStandards.first { $0.id == "std.decking.composite" }
        )

        let material = DeckMaterial.from(builtIn: builtIn)

        XCTAssertEqual(material.id, "std.decking.composite")
        XCTAssertEqual(material.family, .decking)
        XCTAssertEqual(material.displayName, "Composite Decking")
    }

    func testRoundTripPreservesLengthsAndFastener() throws {
        let material = DeckMaterial(
            id: "decking.composite.1x6",
            family: .decking,
            profile: "1x6 grooved",
            availableLengthsFeet: [12, 16, 20],
            coveragePerUnit: 5.5,
            fastenerSystem: "hidden_clip",
            finish: "factory",
            displayName: "Composite Board"
        )

        let encoded = try JSONEncoder().encode(material)
        let decoded = try JSONDecoder().decode(DeckMaterial.self, from: encoded)

        XCTAssertEqual(decoded, material)
    }

    func testLegacyDecodeFillsDefaults() throws {
        let json = """
        {
          "id": "legacy.decking",
          "family": "decking",
          "displayName": "Legacy Decking"
        }
        """

        let material = try JSONDecoder().decode(
            DeckMaterial.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(material.id, "legacy.decking")
        XCTAssertEqual(material.family, .decking)
        XCTAssertEqual(material.displayName, "Legacy Decking")
        XCTAssertNil(material.profile)
        XCTAssertEqual(material.availableLengthsFeet, [])
        XCTAssertNil(material.coveragePerUnit)
        XCTAssertNil(material.fastenerSystem)
        XCTAssertNil(material.finish)
    }
}
