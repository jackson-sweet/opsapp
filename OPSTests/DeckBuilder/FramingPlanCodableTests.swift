import CoreGraphics
import XCTest
@testable import OPS

final class FramingPlanCodableTests: XCTestCase {
    func testPersistedFramingRoundTripPreservesDeckKitContract() throws {
        let json = """
        {
          "schemaVersion": 7,
          "vertices": [],
          "edges": [],
          "framing": {
            "members": [
              {
                "levelId": "level-main",
                "members": [
                  {"id":"joist-1","role":"joist","start":[0,0],"end":[0,120]},
                  {
                    "id": "beam-1",
                    "role": "beam",
                    "start": [12.5, 24],
                    "end": [132.5, 24],
                    "nominalSize": "2x10",
                    "plyCount": 3,
                    "spacingInchesOC": 16,
                    "species": "df_l",
                    "grade": "no1",
                    "sizing": {
                      "engine": "bc-span-tables",
                      "outcome": {
                        "kind": "pass",
                        "utilization": 0.625,
                        "alternates": ["2x12", null]
                      }
                    },
                    "locked": true
                  },
                  {"id":"post-1","role":"post","start":[12.5,24],"end":[12.5,24]},
                  {"id":"ledger-1","role":"ledger","start":[0,0],"end":[120,0]},
                  {"id":"rim-1","role":"rimBand","start":[120,0],"end":[120,120]},
                  {"id":"blocking-1","role":"blocking","start":[0,60],"end":[120,60]},
                  {"id":"bridging-1","role":"bridging","start":[0,72],"end":[120,72]},
                  {"id":"cantilever-1","role":"cantilever","start":[120,0],"end":[144,0]}
                ]
              }
            ],
            "loadPreset": {
              "liveLoadPSF": 60,
              "deadLoadPSF": 15,
              "snowLoadPSF": 35,
              "species": "df_l",
              "grade": "no1"
            },
            "generationSource": "autoThenEdited",
            "generatedAtSchemaVersion": 7
          }
        }
        """

        let drawing = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let framing = try XCTUnwrap(drawing.framing)
        let memberSet = try XCTUnwrap(framing.members.first)

        XCTAssertEqual(drawing.schemaVersion, 7)
        XCTAssertEqual(memberSet.levelId, "level-main")
        XCTAssertEqual(
            memberSet.members.map(\.role),
            [.joist, .beam, .post, .ledger, .rimBand, .blocking, .bridging, .cantilever]
        )
        XCTAssertEqual(framing.generationSource, .autoThenEdited)
        XCTAssertEqual(framing.generatedAtSchemaVersion, 7)
        XCTAssertEqual(framing.loadPreset?.liveLoadPSF, 60)
        XCTAssertEqual(framing.loadPreset?.deadLoadPSF, 15)
        XCTAssertEqual(framing.loadPreset?.snowLoadPSF, 35)
        XCTAssertEqual(framing.loadPreset?.species, .douglasFirLarch)
        XCTAssertEqual(framing.loadPreset?.grade, .no1)

        let beam = try XCTUnwrap(memberSet.members.first(where: { $0.id == "beam-1" }))
        XCTAssertEqual(beam.start, CGPoint(x: 12.5, y: 24))
        XCTAssertEqual(beam.end, CGPoint(x: 132.5, y: 24))
        XCTAssertEqual(beam.nominalSize, .twoByTen)
        XCTAssertEqual(beam.plyCount, 3)
        XCTAssertEqual(beam.spacingInchesOC, 16)
        XCTAssertEqual(beam.species, .douglasFirLarch)
        XCTAssertEqual(beam.grade, .no1)
        XCTAssertTrue(beam.locked)

        let expectedSizing: DeckJSONValue = .object([
            "engine": .string("bc-span-tables"),
            "outcome": .object([
                "alternates": .array([.string("2x12"), .null]),
                "kind": .string("pass"),
                "utilization": .number("0.625"),
            ]),
        ])
        XCTAssertEqual(beam.sizing, expectedSizing)

        let redecoded = try XCTUnwrap(DeckDrawingData.fromJSON(drawing.toJSON()))
        XCTAssertEqual(redecoded.framing, drawing.framing)
        XCTAssertEqual(
            redecoded.framing?.members.first?.members.first(where: { $0.id == "beam-1" })?.sizing,
            expectedSizing
        )
    }

    func testMalformedFramingMemberIsSkippedWithoutDiscardingPlan() throws {
        let json = """
        {
          "vertices": [
            {"id":"v1","position":[0,0]},
            {"id":"v2","position":[120,0]},
            {"id":"v3","position":[0,120]}
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
                  {"id":"bad-role","role":"spaninator","start":[0,0],"end":[120,0]},
                  {"id":"bad-point","role":"joist","start":"not-a-point","end":[120,0]},
                  {"id":"good","role":"joist","start":[0,0],"end":[0,120]}
                ]
              }
            ],
            "generationSource": "auto"
          }
        }
        """

        let drawing = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(drawing.vertices.count, 3)
        XCTAssertEqual(drawing.framing?.members.first?.members.map(\.id), ["good"])
    }

    func testUntouchedFutureFramingRoundTripsRawFieldsAndMalformedMembersExactly() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "framing": {
            "members": [
              {
                "levelId": "",
                "futureSetCounter": 1.2300e+05,
                "members": [
                  {
                    "id": "good",
                    "role": "beam",
                    "start": [0,0],
                    "end": [120,0],
                    "futureHardware": {"capacity": 900719925474099312345678901234567890}
                  },
                  {
                    "id": "future-role",
                    "role": "helicalSupport",
                    "start": [0,0],
                    "end": [0,0],
                    "vendorPayload": [true, null, 0.000000000000000000123456789]
                  }
                ]
              }
            ],
            "generationSource": "auto",
            "futurePlanFlag": "next-schema"
          }
        }
        """

        let original = try DeckJSONValue.parseObject(from: json)
        let drawing = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(drawing.framing?.members.first?.members.map(\.id), ["good"])

        let untouched = try DeckJSONValue.parseObject(from: drawing.toJSON())
        XCTAssertEqual(untouched["framing"], original["framing"])
    }

    func testFutureNonRenderingMetadataDoesNotHideRenderableMembers() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "framing": {
            "members": [{
              "levelId": "",
              "members": [{
                "id":"beam",
                "role":"beam",
                "start":[0,0],
                "end":[120,0],
                "nominalSize":"2x14",
                "species":"future_species",
                "grade":"machine_stress_rated",
                "locked":"future_lock_state"
              }]
            }],
            "loadPreset": {
              "liveLoadPSF": 50,
              "deadLoadPSF": 12,
              "species": "future_species",
              "grade": "future_grade"
            },
            "generationSource": "future_generator"
          }
        }
        """

        let drawing = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let framing = try XCTUnwrap(drawing.framing)
        let beam = try XCTUnwrap(framing.members.first?.members.first)

        XCTAssertEqual(beam.id, "beam")
        XCTAssertEqual(beam.role, .beam)
        XCTAssertEqual(beam.start, CGPoint(x: 0, y: 0))
        XCTAssertEqual(beam.end, CGPoint(x: 120, y: 0))
        XCTAssertNil(beam.nominalSize)
        XCTAssertNil(beam.species)
        XCTAssertNil(beam.grade)
        XCTAssertFalse(beam.locked)
        XCTAssertEqual(framing.generationSource, .auto)
        XCTAssertEqual(framing.loadPreset?.liveLoadPSF, 50)
        XCTAssertEqual(framing.loadPreset?.deadLoadPSF, 12)
        XCTAssertEqual(framing.loadPreset?.species, .sprucePineFir)
        XCTAssertEqual(framing.loadPreset?.grade, .no2)
    }

    func testLegacyDrawingWithoutFramingStillDecodes() throws {
        let drawing = try XCTUnwrap(DeckDrawingData.fromJSON(#"{"vertices":[],"edges":[]}"#))

        XCTAssertNil(drawing.framing)
        XCTAssertNil(drawing.schemaVersion)
    }
}
