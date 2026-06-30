import CoreGraphics
import XCTest
@testable import DeckKit

final class SurfaceFeaturePlanCodableTests: XCTestCase {
    func testDecodeMissingBlockIsNil() throws {
        let json = #"{"edges":[],"vertices":[]}"#

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertNil(data.surfaceFeatures)
        XCTAssertEqual(data.vertices, [])
        XCTAssertEqual(data.edges, [])
    }

    func testDecodePartialPatternSpecAppliesDefaults() throws {
        let json = """
        {
          "surfaceId": "surface-main",
          "pattern": "picture_frame"
        }
        """

        let spec = try JSONDecoder().decode(SurfacePatternSpec.self, from: Data(json.utf8))

        XCTAssertEqual(spec.surfaceId, "surface-main")
        XCTAssertEqual(spec.pattern, .pictureFrame)
        XCTAssertEqual(spec.boardAngleDegrees, 0)
        XCTAssertEqual(spec.pictureFrameCourses, 0)
    }

    func testRoundTripStable() throws {
        var data = DeckDrawingData()
        data.surfaceFeatures = sampleSurfaceFeaturePlan()

        let json = data.toJSON()
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))
        let encodedAgain = decoded.toJSON()

        XCTAssertEqual(encodedAgain, json)
        XCTAssertEqual(decoded.surfaceFeatures, data.surfaceFeatures)
    }

    func testRoundTripLightBuildPreservesBlock() throws {
        let json = """
        {
          "vertices": [],
          "edges": [],
          "surfaceFeatures": {
            "patterns": [
              {
                "surfaceId": "surface-main",
                "pattern": "diagonal",
                "boardAngleDegrees": 45,
                "pictureFrameCourses": 0
              }
            ],
            "fastenerSystem": "face_screw",
            "finishes": [
              {
                "kind": "stain",
                "coats": 2
              }
            ],
            "fascia": true,
            "skirting": {
              "material": "cedar",
              "ventilated": true
            },
            "builtIns": [
              {
                "id": "bench-1",
                "kind": "bench",
                "polygon": [
                  [0, 0],
                  [48, 0],
                  [48, 18]
                ],
                "heightInches": 18
              }
            ],
            "lighting": {
              "fixtures": [
                [12, 24],
                [60, 24]
              ],
              "transformerWatts": 60,
              "receptacles": [
                [0, 120]
              ]
            }
          }
        }
        """

        let root = try DeckJSONValue.parseObject(from: json)
        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertTrue(DeckCapabilities.light.contains(.materials))

        let encodedRoot = try DeckJSONValue.parseObject(from: data.toJSON())
        XCTAssertEqual(encodedRoot["surfaceFeatures"], root["surfaceFeatures"])
    }

    func testMalformedSubBlockDecodesToNilWithoutFailingDesign() throws {
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
          "surfaceFeatures": {
            "patterns": [
              {
                "surfaceId": "surface-main",
                "pattern": "parallel"
              }
            ],
            "lighting": "not-an-object"
          }
        }
        """

        let data = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(data.vertices.count, 3)
        XCTAssertEqual(data.edges.count, 3)
        XCTAssertEqual(data.surfaceFeatures?.patterns.count, 1)
        XCTAssertNil(data.surfaceFeatures?.lighting)
    }

    func testVersionBumpSetsSixWhenPresent() {
        var data = DeckDrawingData()
        data.surfaceFeatures = sampleSurfaceFeaturePlan()

        let stamped = DeckSchemaMigration.stampFramingVersion(data)

        XCTAssertEqual(DeckSchemaMigration.currentSchemaVersion, 6)
        XCTAssertEqual(stamped.schemaVersion, 6)
    }

    private func sampleSurfaceFeaturePlan() -> SurfaceFeaturePlan {
        SurfaceFeaturePlan(
            patterns: [
                SurfacePatternSpec(
                    surfaceId: "surface-main",
                    pattern: .parallel,
                    boardAngleDegrees: 0,
                    pictureFrameCourses: 0
                ),
                SurfacePatternSpec(
                    surfaceId: "surface-border",
                    pattern: .pictureFrame,
                    boardAngleDegrees: 0,
                    pictureFrameCourses: 2
                ),
            ],
            fastenerSystem: .hiddenClip,
            finishes: [
                FinishSpec(kind: "stain", coats: 2),
            ],
            fascia: true,
            skirting: SkirtingSpec(material: "cedar", ventilated: true),
            builtIns: [
                BuiltInFeature(
                    id: "bench-1",
                    kind: .bench,
                    polygon: [
                        CGPoint(x: 0, y: 0),
                        CGPoint(x: 48, y: 0),
                        CGPoint(x: 48, y: 18),
                    ],
                    heightInches: 18
                ),
            ],
            lighting: LightingPlan(
                fixtures: [
                    CGPoint(x: 12, y: 24),
                    CGPoint(x: 60, y: 24),
                ],
                transformerWatts: 60,
                receptacles: [
                    CGPoint(x: 0, y: 120),
                ]
            )
        )
    }
}
