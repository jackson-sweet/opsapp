import CoreGraphics
import XCTest
@testable import OPS

final class DeckDrawingFutureBlocksTests: XCTestCase {
    func testUnknownTopLevelBlocksRoundTripWithNestedValuesAndExactNumbers() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "overheadStructure": {
            "version": 900719925474099312345678901234567890,
            "members": [
              {
                "id": "j1",
                "loads": [3.1415926535897932384626433832795028841971, 6.02214076e23, null]
              }
            ]
          },
          "futureParcelOverlay": {
            "enabled": true,
            "notes": null,
            "findings": [
              {
                "code": "REAR_SETBACK_CONCERN",
                "distance": 0.000000000000000000123456789
              }
            ]
          }
        }
        """

        let expected: [String: DeckJSONValue] = [
            "overheadStructure": .object([
                "members": .array([
                    .object([
                        "id": .string("j1"),
                        "loads": .array([
                            .number("3.1415926535897932384626433832795028841971"),
                            .number("6.02214076e23"),
                            .null,
                        ]),
                    ]),
                ]),
                "version": .number("900719925474099312345678901234567890"),
            ]),
            "futureParcelOverlay": .object([
                "enabled": .bool(true),
                "findings": .array([
                    .object([
                        "code": .string("REAR_SETBACK_CONCERN"),
                        "distance": .number("0.000000000000000000123456789"),
                    ]),
                ]),
                "notes": .null,
            ]),
        ]

        let drawing = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        XCTAssertEqual(drawing.futureBlocks, expected)

        let encodedObject = try DeckJSONValue.parseObject(from: drawing.toJSON())
        XCTAssertEqual(encodedObject["overheadStructure"], expected["overheadStructure"])
        XCTAssertEqual(encodedObject["futureParcelOverlay"], expected["futureParcelOverlay"])

        let redecoded = try XCTUnwrap(DeckDrawingData.fromJSON(drawing.toJSON()))
        XCTAssertEqual(redecoded.futureBlocks, expected)
    }

    func testFutureBlocksCannotOverwriteKnownDrawingKeys() throws {
        var drawing = DeckDrawingData()
        drawing.vertices = [DeckVertex(id: "v1", position: CGPoint(x: 12, y: 24))]
        drawing.futureBlocks = [
            "vertices": .string("shadowed-vertices"),
            "edges": .string("shadowed-edges"),
            "config": .string("shadowed-config"),
            "schemaVersion": .number("999"),
            "framing": .string("shadowed-framing"),
            "rogue": .object([
                "enabled": .bool(true),
                "exactCounter": .number("900719925474099312345678901234567890"),
            ]),
        ]

        let object = try DeckJSONValue.parseObject(from: drawing.toJSON())

        guard case .array(let vertices)? = object["vertices"] else {
            return XCTFail("Known vertices must remain the encoded geometry array")
        }
        XCTAssertEqual(vertices.count, 1)
        XCTAssertEqual(object["edges"], .array([]))
        guard case .object? = object["config"] else {
            return XCTFail("Known config must remain the encoded config object")
        }
        XCTAssertNotEqual(object["schemaVersion"], .number("999"))
        XCTAssertNotEqual(object["framing"], .string("shadowed-framing"))
        XCTAssertEqual(object["rogue"], .object([
            "enabled": .bool(true),
            "exactCounter": .number("900719925474099312345678901234567890"),
        ]))
    }
}
