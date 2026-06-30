import CoreGraphics
import XCTest
@testable import DeckKit

final class FootingPlanCodableTests: XCTestCase {
    func test_deckDrawingData_roundTripsFootingPlanBlock() throws {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "V1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "V2", position: CGPoint(x: 120, y: 0))
        ]
        data.edges = [
            DeckEdge(id: "E1", startVertexId: "V1", endVertexId: "V2")
        ]
        data.footings = FootingPlan(
            footings: [
                Footing(
                    id: "F1",
                    vertexId: "V1",
                    position: CGPoint(x: 0, y: 0),
                    type: .sonoTube,
                    diameterInches: 18,
                    depthInches: 48
                )
            ],
            soil: SoilInput(bearingCapacityPSF: 1500, source: .presumptive),
            frost: FrostInput(depthInches: 48, source: .bundledTable)
        )

        let json = data.toJSON()
        let decoded = try XCTUnwrap(DeckDrawingData.fromJSON(json))

        XCTAssertEqual(decoded.footings, data.footings)
        XCTAssertEqual(decoded.toJSON(), json)
    }

    func test_footingPlan_roundTripsContractFields() throws {
        let plan = FootingPlan(
            footings: [
                Footing(
                    id: "F-perimeter",
                    vertexId: "V1",
                    position: CGPoint(x: 12, y: 24),
                    type: .sonoTube,
                    diameterInches: 16,
                    depthInches: 48,
                    helicalTorqueFtLb: nil,
                    connection: PostFootingConnection(hardwareModel: "ABU66", upliftRated: true),
                    sizing: FootingSizingResult(
                        diameterInches: 18,
                        depthInches: 60,
                        bearingAreaSqIn: 254.47,
                        requiredFrostDepthInches: 48,
                        citation: EngineCitation(
                            limitingCheck: "bearing",
                            codeSection: "IRC R507.3.1",
                            packageEdition: "IRC 2021 / DCA6-12"
                        )
                    )
                ),
                Footing(
                    id: "F-free",
                    vertexId: nil,
                    position: CGPoint(x: 96, y: 24),
                    type: .helicalPile,
                    helicalTorqueFtLb: 5500
                )
            ],
            soil: SoilInput(bearingCapacityPSF: 1500, source: .presumptive),
            frost: FrostInput(depthInches: 48, source: .bundledTable)
        )

        let encoded = try JSONEncoder.sortedDeckKit.encode(plan)
        let decoded = try JSONDecoder().decode(FootingPlan.self, from: encoded)

        XCTAssertEqual(decoded, plan)
    }

    func test_footingDefensiveDecode_defaultsMissingFields() throws {
        let json = """
        {
          "id": "F-min",
          "position": [10, 20]
        }
        """

        let footing = try JSONDecoder().decode(Footing.self, from: Data(json.utf8))

        XCTAssertEqual(footing.id, "F-min")
        XCTAssertNil(footing.vertexId)
        XCTAssertEqual(footing.position, CGPoint(x: 10, y: 20))
        XCTAssertEqual(footing.type, .sonoTube)
        XCTAssertNil(footing.diameterInches)
        XCTAssertNil(footing.depthInches)
        XCTAssertNil(footing.helicalTorqueFtLb)
        XCTAssertNil(footing.connection)
        XCTAssertNil(footing.sizing)
    }

    func test_malformedFooting_isDroppedWithoutFailingPlanDecode() throws {
        let json = """
        {
          "footings": [
            {
              "id": "F-good",
              "position": [0, 0],
              "type": "concrete_pad"
            },
            {
              "id": "F-bad",
              "position": "not-a-point"
            }
          ],
          "soil": { "bearingCapacityPSF": 2000, "source": "geotechReport" },
          "frost": { "depthInches": 60, "source": "ahjVerified" }
        }
        """

        let plan = try JSONDecoder().decode(FootingPlan.self, from: Data(json.utf8))

        XCTAssertEqual(plan.footings.map(\.id), ["F-good"])
        XCTAssertEqual(plan.footings.first?.type, .concretePad)
        XCTAssertEqual(plan.soil, SoilInput(bearingCapacityPSF: 2000, source: .geotechReport))
        XCTAssertEqual(plan.frost, FrostInput(depthInches: 60, source: .ahjVerified))
    }

    func test_malformedFootingsArray_defaultsToEmptyPlan() throws {
        let json = """
        {
          "footings": "not-an-array",
          "soil": { "bearingCapacityPSF": "not-a-number" },
          "frost": { "source": "userEntered" }
        }
        """

        let plan = try JSONDecoder().decode(FootingPlan.self, from: Data(json.utf8))

        XCTAssertEqual(plan.footings, [])
        XCTAssertNil(plan.soil)
        XCTAssertEqual(plan.frost, FrostInput(depthInches: nil, source: .userEntered))
    }
}

private extension JSONEncoder {
    static var sortedDeckKit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
