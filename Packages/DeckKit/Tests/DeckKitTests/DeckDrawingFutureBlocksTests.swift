import XCTest
@testable import DeckKit

final class DeckDrawingFutureBlocksTests: XCTestCase {
    func testUnknownFutureBlocksRoundTripThroughDeckDrawingDataPreservesStructureAndNumericTokens() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "overheadStructure": {
            "version": 900719925474099312345678901234567890,
            "members": [
              {
                "id": "j1",
                "kind": "joist",
                "span": 144,
                "loads": [3.1415926535897932384626433832795028841971, 6.02214076e23, null]
              }
            ]
          },
          "parcelZoning": {
            "apn": "PID-123",
            "notes": null,
            "findings": [
              {
                "severity": "warning",
                "code": "REAR_SETBACK_CONCERN",
                "distance": 0.000000000000000000123456789
              },
              {
                "active": true,
                "history": [{"timestamp": 1717171717171717171717}]
              }
            ]
          },
          "codeOverlay": {
            "enabled": true,
            "findings": [{"elementId": "j1", "severity": "violation"}]
          },
          "rendering": {
            "engine": "realitykit",
            "preset": "client_hero"
          }
        }
        """

        let expectedFutureBlocks: [String: DeckJSONValue] = [
            "overheadStructure": .object([
                "members": .array([
                    .object([
                        "id": .string("j1"),
                        "kind": .string("joist"),
                        "loads": .array([
                            .number("3.1415926535897932384626433832795028841971"),
                            .number("6.02214076e23"),
                            .null,
                        ]),
                        "span": .number("144"),
                    ])
                ]),
                "version": .number("900719925474099312345678901234567890"),
            ]),
            "parcelZoning": .object([
                "apn": .string("PID-123"),
                "findings": .array([
                    .object([
                        "code": .string("REAR_SETBACK_CONCERN"),
                        "distance": .number("0.000000000000000000123456789"),
                        "severity": .string("warning"),
                    ]),
                    .object([
                        "active": .bool(true),
                        "history": .array([
                            .object([
                                "timestamp": .number("1717171717171717171717"),
                            ])
                        ]),
                    ]),
                ]),
                "notes": .null,
            ]),
            "codeOverlay": .object([
                "enabled": .bool(true),
                "findings": .array([
                    .object([
                        "elementId": .string("j1"),
                        "severity": .string("violation"),
                    ])
                ]),
            ]),
            "rendering": .object([
                "engine": .string("realitykit"),
                "preset": .string("client_hero"),
            ]),
        ]

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        XCTAssertEqual(decoded.futureBlocks, expectedFutureBlocks)

        let encoded = decoded.toJSON()
        let encodedObject = try DeckJSONValue.parseObject(from: encoded)
        XCTAssertEqual(unknownBlocks(in: encodedObject), expectedFutureBlocks)

        let roundTripped = try XCTUnwrap(DeckDrawingData.fromJSON(encoded))
        XCTAssertEqual(roundTripped.futureBlocks, expectedFutureBlocks)
    }

    func testFutureBlocksCannotOverrideKnownDeckDrawingDataKeysOnEncode() throws {
        var data = DeckDrawingData()
        data.vertices = [DeckVertex(id: "v1", position: .zero)]
        data.edges = []
        data.futureBlocks = [
            "vertices": .string("shadowed-known-key"),
            "rogue": .object([
                "exactCounter": .number("900719925474099312345678901234567890"),
                "enabled": .bool(true),
            ]),
        ]

        let encoded = data.toJSON()
        let object = try DeckJSONValue.parseObject(from: encoded)

        guard case .array(let vertices)? = object["vertices"] else {
            return XCTFail("Known vertices key must remain the encoded vertex array")
        }
        XCTAssertEqual(vertices.count, 1)
        XCTAssertEqual(object["rogue"], .object([
            "enabled": .bool(true),
            "exactCounter": .number("900719925474099312345678901234567890"),
        ]))
        XCTAssertNotEqual(object["vertices"], .string("shadowed-known-key"))
    }

    private func unknownBlocks(in object: [String: DeckJSONValue]) -> [String: DeckJSONValue] {
        let knownKeys: Set<String> = [
            "schemaVersion",
            "vertices",
            "edges",
            "footprint",
            "surfaces",
            "config",
            "overallElevation",
            "scaleFactor",
            "poolDiameter",
            "photoOverlay",
            "levels",
            "levelConnections",
            "framing",
            "terrain",
            "footings",
            "house",
            "surfaceFeatures",
            "overhead",
            "wasteSettings",
            "components",
        ]
        return object.reduce(into: [:]) { result, entry in
            guard !knownKeys.contains(entry.key) else { return }
            result[entry.key] = entry.value
        }
    }
}
