import XCTest
@testable import DeckKit

final class FramingPlanCodableTests: XCTestCase {
    func test_framingPlan_roundTrips_stable() throws {
        var data = DeckDrawingData()
        data.framing = sampleFramingPlan()

        let json = data.toJSON()
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let encodedAgain = decoded.toJSON()

        XCTAssertEqual(encodedAgain, json)
        XCTAssertEqual(decoded.framing, data.framing)
    }

    func test_legacyJSON_withoutFraming_decodesToNilFramingAndNilTerrain() throws {
        let json = #"{"edges":[],"vertices":[]}"#

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertNil(data.framing)
        XCTAssertNil(data.terrain)
    }

    func test_lightBuild_preservesFramingBlock_onReEncode() throws {
        var data = DeckDrawingData()
        data.framing = sampleFramingPlan()
        let json = data.toJSON()

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let reencoded = decoded.toJSON()

        XCTAssertEqual(try DeckJSONValue.parseObject(from: reencoded)["framing"],
                       try DeckJSONValue.parseObject(from: json)["framing"])
    }

    func test_malformedFramingMember_doesNotFailWholeDecode() throws {
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
          "framing": {
            "members": [
              {
                "levelId": "",
                "members": [
                  {"id":"bad","role":"spaninator","start":[0,0],"end":[120,0]},
                  {"id":"good","role":"joist","start":[0,0],"end":[0,120]}
                ]
              }
            ],
            "generationSource": "auto"
          }
        }
        """

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(data.vertices.count, 3)
        XCTAssertEqual(data.framing?.members.first?.members.map(\.id), ["good"])
    }

    func test_decodeIfPresent_defaults() throws {
        let json = """
        {
          "id": "joist-defaults",
          "role": "joist",
          "start": [0, 0],
          "end": [120, 0]
        }
        """

        let member = try JSONDecoder().decode(FramingMember.self, from: Data(json.utf8))

        XCTAssertEqual(member.plyCount, 1)
        XCTAssertFalse(member.locked)
    }

    func test_terrain_groundCover_roundTrips() throws {
        var data = DeckDrawingData()
        data.terrain = TerrainModel(
            gradePoints: [],
            groundCover: [
                GroundZone(
                    id: "grass-zone",
                    polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 120)],
                    cover: .grass
                ),
                GroundZone(
                    id: "gravel-zone",
                    polygon: [CGPoint(x: 120, y: 0), CGPoint(x: 240, y: 0), CGPoint(x: 240, y: 120)],
                    cover: .gravel
                ),
            ],
            slopeSource: .manual
        )

        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(data.toJSON()))

        XCTAssertEqual(decoded.terrain, data.terrain)
    }

    func test_terrain_groundCoverOnly_defaultsP4Fields() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "terrain": {
            "groundCover": [
              {"id":"zone","polygon":[[0,0],[120,0],[120,120]],"cover":"pavers"}
            ]
          }
        }
        """

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(data.terrain?.gradePoints, [])
        XCTAssertEqual(data.terrain?.slopeSource, .manual)
        XCTAssertEqual(data.terrain?.groundCover.first?.cover, .pavers)
    }

    func test_groundCover_allCases_decodable() throws {
        for cover in GroundCover.allCases {
            let encoded = try JSONEncoder.sorted.encode(cover)
            XCTAssertEqual(try JSONDecoder().decode(GroundCover.self, from: encoded), cover)
        }
    }

    func test_stamp_setsSchemaVersion2_whenFramingPresent() {
        var data = DeckDrawingData()
        data.framing = sampleFramingPlan()

        let stamped = DeckSchemaMigration.stampFramingVersion(data)

        XCTAssertEqual(stamped.schemaVersion, 2)
        XCTAssertEqual(stamped.framing?.generatedAtSchemaVersion, 2)
    }

    func test_stamp_isIdempotent_neverDowngrades() {
        var data = DeckDrawingData()
        data.schemaVersion = 7
        data.framing = sampleFramingPlan()

        let stamped = DeckSchemaMigration.stampFramingVersion(data)

        XCTAssertEqual(stamped.schemaVersion, 7)
        XCTAssertEqual(stamped.framing?.generatedAtSchemaVersion, 7)
    }

    func test_stamp_noOp_whenNoFraming() {
        var data = DeckDrawingData()
        data.schemaVersion = 7

        let stamped = DeckSchemaMigration.stampFramingVersion(data)

        XCTAssertEqual(stamped.schemaVersion, 7)
        XCTAssertNil(stamped.framing)
    }

    private func sampleFramingPlan() -> FramingPlan {
        FramingPlan(
            members: [
                FramingMemberSet(
                    levelId: "",
                    members: [
                        FramingMember(
                            id: "joist-1",
                            role: .joist,
                            start: CGPoint(x: 0, y: 0),
                            end: CGPoint(x: 0, y: 120),
                            nominalSize: .twoByEight,
                            spacingInchesOC: 16,
                            species: .sprucePineFir,
                            grade: .no2
                        ),
                        FramingMember(
                            id: "beam-1",
                            role: .beam,
                            start: CGPoint(x: 0, y: 120),
                            end: CGPoint(x: 144, y: 120),
                            nominalSize: .twoByTen,
                            plyCount: 2,
                            species: .sprucePineFir,
                            grade: .no2
                        ),
                        FramingMember(
                            id: "post-1",
                            role: .post,
                            start: CGPoint(x: 0, y: 120),
                            end: CGPoint(x: 0, y: 120),
                            nominalSize: .sixBySix,
                            species: .sprucePineFir,
                            grade: .no2
                        ),
                        FramingMember(
                            id: "post-2",
                            role: .post,
                            start: CGPoint(x: 144, y: 120),
                            end: CGPoint(x: 144, y: 120),
                            nominalSize: .sixBySix,
                            species: .sprucePineFir,
                            grade: .no2
                        ),
                    ]
                )
            ],
            loadPreset: LoadPreset(),
            generationSource: .auto,
            generatedAtSchemaVersion: nil
        )
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
