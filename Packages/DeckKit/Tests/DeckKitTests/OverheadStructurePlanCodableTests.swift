import CoreGraphics
import XCTest
@testable import DeckKit

final class OverheadStructurePlanCodableTests: XCTestCase {
    func testDecodeMissingBlockIsNil() throws {
        let json = #"{"edges":[],"vertices":[]}"#

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertNil(data.overhead)
        XCTAssertEqual(data.vertices, [])
        XCTAssertEqual(data.edges, [])
    }

    func testDecodePartialStructureAppliesDefaults() throws {
        let json = """
        {
          "id": "pergola-1",
          "kind": "pergola"
        }
        """

        let structure = try JSONDecoder().decode(OverheadStructure.self, from: Data(json.utf8))

        XCTAssertEqual(structure.id, "pergola-1")
        XCTAssertEqual(structure.kind, .pergola)
        XCTAssertNil(structure.roofShape)
        XCTAssertEqual(structure.footprint, [])
        XCTAssertEqual(structure.framing, [])
        XCTAssertNil(structure.shadePercent)
        XCTAssertNil(structure.productModel)
    }

    func testRoundTripStable() throws {
        var data = DeckDrawingData()
        data.overhead = sampleOverheadStructurePlan()

        let json = data.toJSON()
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let encodedAgain = decoded.toJSON()

        XCTAssertEqual(encodedAgain, json)
        XCTAssertEqual(decoded.overhead, data.overhead)
    }

    func testRoundTripLightBuildPreservesBlock() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "overhead": {
            "structures": [
              {
                "id": "louvered-1",
                "kind": "louvered_roof",
                "roofShape": "shed",
                "footprint": [
                  [0, 0],
                  [144, 0],
                  [144, 120],
                  [0, 120]
                ],
                "framing": [
                  {
                    "id": "beam-1",
                    "role": "beam",
                    "start": [0, 0],
                    "end": [144, 0],
                    "nominalSize": "2x10",
                    "plyCount": 2,
                    "species": "df_l",
                    "grade": "no1",
                    "locked": true
                  }
                ],
                "shadePercent": 85,
                "productModel": "StruXure pergola X"
              }
            ]
          }
        }
        """

        let root = try DeckJSONValue.parseObject(from: json)
        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertTrue(DeckCapabilities.light.contains(.materials))

        let encodedRoot = try DeckJSONValue.parseObject(from: data.toJSON())
        XCTAssertEqual(encodedRoot["overhead"], root["overhead"])
    }

    func testMalformedFramingElementIsDroppedWithoutFailingDesign() throws {
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
          "overhead": {
            "structures": [
              {
                "id": "pergola-1",
                "kind": "pergola",
                "footprint": [
                  [0, 0],
                  [120, 0],
                  [120, 120]
                ],
                "framing": [
                  {
                    "id": "bad-member",
                    "role": "skyhook",
                    "start": [0, 0],
                    "end": [120, 0]
                  },
                  {
                    "id": "beam-1",
                    "role": "beam",
                    "start": [0, 0],
                    "end": [120, 0],
                    "nominalSize": "2x10"
                  }
                ]
              }
            ]
          }
        }
        """

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(data.vertices.count, 3)
        XCTAssertEqual(data.edges.count, 3)
        XCTAssertEqual(data.overhead?.structures.first?.framing.count, 1)
        XCTAssertEqual(data.overhead?.structures.first?.framing.first?.id, "beam-1")
    }

    func testFramingMemberReusePreservesSizedMemberOutcome() throws {
        let json = """
        {
          "structures": [
            {
              "id": "solid-roof-1",
              "kind": "solid_roof",
              "roofShape": "gable",
              "footprint": [
                [0, 0],
                [144, 0],
                [144, 120],
                [0, 120]
              ],
              "framing": [
                {
                  "id": "beam-sized",
                  "role": "beam",
                  "start": [0, 0],
                  "end": [144, 0],
                  "nominalSize": "2x10",
                  "plyCount": 2,
                  "species": "df_l",
                  "grade": "no1",
                  "sizing": {
                    "outcome": {
                      "case": "ok",
                      "value": {
                        "size": "2x10",
                        "plyCount": 2,
                        "allowableSpanFeet": 14,
                        "actualSpanFeet": 12,
                        "utilization": 0.86
                      },
                      "citation": {
                        "limitingCheck": "span table envelope",
                        "codeSection": "IRC R507.6",
                        "packageEdition": "IRC 2021 / DCA6-12"
                      },
                      "assumptions": {
                        "liveLoadPSF": 40,
                        "deadLoadPSF": 10,
                        "snowLoadPSF": 0,
                        "species": "df_l",
                        "grade": "no1",
                        "soilBearingPSF": null,
                        "packageEdition": "IRC 2021 / DCA6-12"
                      }
                    }
                  },
                  "locked": true
                }
              ]
            }
          ]
        }
        """

        let plan = try JSONDecoder().decode(OverheadStructurePlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.structures.count, 1)
        let structure = try XCTUnwrap(plan.structures.first)
        XCTAssertEqual(structure.framing.count, 1)
        let member = try XCTUnwrap(structure.framing.first)

        XCTAssertEqual(member.role, .beam)
        XCTAssertEqual(member.nominalSize, .twoByTen)
        XCTAssertEqual(member.plyCount, 2)
        XCTAssertEqual(member.species, .douglasFirLarch)
        XCTAssertEqual(member.grade, .no1)
        XCTAssertEqual(member.sizing, sampleSizing())
    }

    func testVersionBumpSetsSixWhenPresent() {
        var data = DeckDrawingData()
        data.overhead = sampleOverheadStructurePlan()

        let stamped = DeckSchemaMigration.stampFramingVersion(data)

        XCTAssertEqual(DeckSchemaMigration.currentSchemaVersion, 6)
        XCTAssertEqual(stamped.schemaVersion, 6)
    }

    private func sampleOverheadStructurePlan() -> OverheadStructurePlan {
        OverheadStructurePlan(
            structures: [
                OverheadStructure(
                    id: "pergola-1",
                    kind: .pergola,
                    roofShape: nil,
                    footprint: [
                        CGPoint(x: 0, y: 0),
                        CGPoint(x: 144, y: 0),
                        CGPoint(x: 144, y: 120),
                        CGPoint(x: 0, y: 120),
                    ],
                    framing: [
                        FramingMember(
                            id: "beam-1",
                            role: .beam,
                            start: CGPoint(x: 0, y: 0),
                            end: CGPoint(x: 144, y: 0),
                            nominalSize: .twoByTen,
                            plyCount: 2,
                            species: .douglasFirLarch,
                            grade: .no1,
                            sizing: sampleSizing(),
                            locked: true
                        ),
                    ],
                    shadePercent: 45,
                    productModel: nil
                ),
            ]
        )
    }

    private func sampleSizing() -> MemberSizingResult {
        MemberSizingResult(
            outcome: .ok(
                value: SizedMember(
                    size: .twoByTen,
                    plyCount: 2,
                    allowableSpanFeet: 14,
                    actualSpanFeet: 12,
                    utilization: 0.86
                ),
                citation: EngineCitation(
                    limitingCheck: "span table envelope",
                    codeSection: "IRC R507.6",
                    packageEdition: "IRC 2021 / DCA6-12"
                ),
                assumptions: EngineAssumptions(
                    liveLoadPSF: 40,
                    deadLoadPSF: 10,
                    snowLoadPSF: 0,
                    species: .douglasFirLarch,
                    grade: .no1,
                    soilBearingPSF: nil,
                    packageEdition: "IRC 2021 / DCA6-12"
                )
            )
        )
    }
}
