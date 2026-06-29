import XCTest
@testable import DeckKit

final class HouseModelCodableTests: XCTestCase {
    func test_houseBlock_roundTrips_stably() throws {
        var data = DeckDrawingData()
        data.house = sampleHouseModel()

        let json = data.toJSON()
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let encodedAgain = decoded.toJSON()

        XCTAssertEqual(encodedAgain, json)
        XCTAssertEqual(decoded.house, data.house)
    }

    func test_legacyJSON_withoutHouse_decodesToNilHouse() throws {
        let json = #"{"edges":[],"vertices":[]}"#

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertNil(data.house)
        XCTAssertEqual(data.vertices, [])
        XCTAssertEqual(data.edges, [])
    }

    func test_externalHouseBlock_preservesOnReEncode() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "house": {
            "floorLineFeet": 9,
            "storyHeights": [108, 96],
            "openings": [
              {
                "id": "D1",
                "edgeId": "E1",
                "kind": "patioDoor",
                "widthInches": 72,
                "heightInches": 80,
                "sillHeightInches": 0,
                "offsetAlongEdgeInches": 24
              }
            ],
            "ledger": {
              "cladding": "brick",
              "attachmentAllowed": false,
              "fastenerSchedule": "Freestanding beam",
              "lateralConnectors": 4
            }
          }
        }
        """

        let root = try DeckJSONValue.parseObject(from: json)
        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        let encoded = data.toJSON()
        let encodedRoot = try DeckJSONValue.parseObject(from: encoded)

        XCTAssertEqual(encodedRoot["house"], root["house"])
    }

    func test_malformedHouseSubblock_decodesToNil_withoutFailingWholeDesign() throws {
        let json = """
        {
          "vertices": [
            {"id":"v1","position":[0,0]},
            {"id":"v2","position":[120,0]},
            {"id":"v3","position":[120,120]}
          ],
          "edges": [
            {"id":"e1","startVertexId":"v1","endVertexId":"v2"},
            {"id":"e2","startVertexId":"v2","endVertexId":"v3"},
            {"id":"e3","startVertexId":"v3","endVertexId":"v1"}
          ],
          "house": {
            "floorLineFeet": "abc",
            "storyHeights": "not-an-array",
            "openings": "not-an-array"
          }
        }
        """

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(data.vertices.count, 3)
        XCTAssertEqual(data.edges.count, 3)
        XCTAssertNil(data.house)
    }

    func test_houseModel_defaultsForPartialBlock() throws {
        let json = """
        {
          "floorLineFeet": 8,
          "openings": [
            {
              "id": "W1",
              "edgeId": "E1",
              "widthInches": 48,
              "heightInches": 42
            }
          ],
          "ledger": {
            "cladding": "stone",
            "attachmentAllowed": false
          }
        }
        """

        let house = try JSONDecoder().decode(HouseModel.self, from: Data(json.utf8))

        XCTAssertEqual(house.floorLineFeet, 8)
        XCTAssertEqual(house.storyHeights, [])
        XCTAssertEqual(house.openings.first?.kind, .window)
        XCTAssertEqual(house.openings.first?.sillHeightInches, 0)
        XCTAssertEqual(house.openings.first?.offsetAlongEdgeInches, 0)
        XCTAssertEqual(house.ledger?.cladding, .stone)
        XCTAssertEqual(house.ledger?.attachmentAllowed, false)
        XCTAssertNil(house.ledger?.fastenerSchedule)
        XCTAssertNil(house.ledger?.lateralConnectors)
    }

    func test_stamp_setsSchemaVersion5_whenHousePresent() {
        var data = DeckDrawingData()
        data.house = sampleHouseModel()

        let stamped = DeckSchemaMigration.stampFramingVersion(data)

        XCTAssertEqual(stamped.schemaVersion, 5)
    }

    private func sampleHouseModel() -> HouseModel {
        HouseModel(
            floorLineFeet: 9,
            storyHeights: [108, 96],
            openings: [
                WallOpening(
                    id: "D1",
                    edgeId: "E1",
                    kind: .patioDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
                WallOpening(
                    id: "W1",
                    edgeId: "E1",
                    kind: .window,
                    widthInches: 48,
                    heightInches: 42,
                    sillHeightInches: 36,
                    offsetAlongEdgeInches: 132
                ),
            ],
            ledger: LedgerDetail(
                cladding: .brick,
                attachmentAllowed: false,
                fastenerSchedule: "Freestanding beam",
                lateralConnectors: 4
            )
        )
    }
}
