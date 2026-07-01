import CoreGraphics
import XCTest
@testable import DeckKit

final class PermitBOMEmitterTests: XCTestCase {
    func testEmitAddsEngineeredLumberFootingFastenerAndConcreteRows() throws {
        let rows = PermitBOMEmitter.emit(Self.engineeredDeck())
        let types = Set(rows.map(\.componentType))

        XCTAssertTrue(types.isSuperset(of: ["joist", "beam", "post", "footing", "fastener", "concrete"]))

        let joist = try XCTUnwrap(rows.first { $0.componentType == "joist" })
        XCTAssertEqual(joist.metadata["linear_feet"], AnyCodable(12.0))
        XCTAssertEqual(joist.metadata["nominal_size"], AnyCodable("2x8"))
        XCTAssertEqual(joist.metadata["species"], AnyCodable("spf"))
        XCTAssertEqual(joist.metadata["grade"], AnyCodable("no2"))

        let footing = try XCTUnwrap(rows.first {
            $0.componentType == "footing" && $0.metadata["footing_id"] == AnyCodable("f1")
        })
        XCTAssertEqual(footing.metadata["type"], AnyCodable("sono_tube"))
        XCTAssertEqual(footing.metadata["diameter_inches"], AnyCodable(12.0))
        XCTAssertEqual(footing.metadata["depth_inches"], AnyCodable(48.0))
        XCTAssertEqual(footing.metadata["hardware_model"], AnyCodable("ABU66"))
        XCTAssertEqual(footing.metadata["uplift_rated"], AnyCodable(true))

        let unsizedFooting = try XCTUnwrap(rows.first {
            $0.componentType == "footing" && $0.metadata["footing_id"] == AnyCodable("f2")
        })
        XCTAssertNil(unsizedFooting.metadata["diameter_inches"])
        XCTAssertNil(unsizedFooting.metadata["depth_inches"])

        let concrete = try XCTUnwrap(rows.first { $0.componentType == "concrete" })
        XCTAssertEqual(concrete.metadata["cubic_feet"], AnyCodable(3.14))
        XCTAssertEqual(concrete.metadata["bag_count"], AnyCodable(6))
        XCTAssertEqual(concrete.metadata["bag_size_lb"], AnyCodable(80))
        XCTAssertEqual(concrete.metadata["footing_count"], AnyCodable(1))

        let joistHangers = try XCTUnwrap(rows.first {
            $0.componentType == "fastener" && $0.metadata["kind"] == AnyCodable("joist_hanger")
        })
        XCTAssertEqual(joistHangers.metadata["count"], AnyCodable(2))
        XCTAssertEqual(joistHangers.metadata["basis"], AnyCodable("framing_members"))

        let postBases = try XCTUnwrap(rows.first {
            $0.componentType == "fastener" && $0.metadata["kind"] == AnyCodable("post_base")
        })
        XCTAssertEqual(postBases.metadata["count"], AnyCodable(1))
        XCTAssertEqual(postBases.metadata["hardware_model"], AnyCodable("ABU66"))
    }

    func testComponentEmitterAddsPermitRowsWithoutMutatingLegacyRows() {
        let base = Self.legacyDeck()
        let legacyRows = Self.legacyRows(in: ComponentEmitter.emit(base))

        var engineered = base
        engineered.framing = Self.engineeredDeck().framing
        engineered.footings = Self.engineeredDeck().footings
        let engineeredRows = ComponentEmitter.emit(engineered)

        XCTAssertEqual(Self.legacyRows(in: engineeredRows), legacyRows)
        XCTAssertTrue(engineeredRows.contains { $0.componentType == "footing" })
        XCTAssertTrue(engineeredRows.contains { $0.componentType == "concrete" })
        XCTAssertTrue(engineeredRows.contains {
            $0.componentType == "fastener" && $0.metadata["kind"] == AnyCodable("joist_hanger")
        })
    }

    private static func legacyRows(in rows: [DesignComponentRow]) -> [DesignComponentRow] {
        let legacyTypes: Set<String> = ["railing", "deck_board", "stair_set", "gate", "post_set"]
        return rows.filter { legacyTypes.contains($0.componentType) }
    }

    private static func engineeredDeck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.framing = FramingPlan(
            members: [
                FramingMemberSet(levelId: "", members: [
                    FramingMember(
                        id: "joist-1",
                        role: .joist,
                        start: .zero,
                        end: CGPoint(x: 144, y: 0),
                        nominalSize: .twoByEight
                    ),
                    FramingMember(
                        id: "beam-1",
                        role: .beam,
                        start: CGPoint(x: 0, y: 120),
                        end: CGPoint(x: 144, y: 120),
                        nominalSize: .twoByTen,
                        plyCount: 2
                    ),
                    FramingMember(
                        id: "post-1",
                        role: .post,
                        start: CGPoint(x: 0, y: 120),
                        end: CGPoint(x: 0, y: 120),
                        nominalSize: .sixBySix
                    )
                ])
            ],
            loadPreset: LoadPreset(),
            generationSource: .manual
        )
        data.footings = FootingPlan(
            footings: [
                Footing(
                    id: "f1",
                    position: CGPoint(x: 0, y: 120),
                    type: .sonoTube,
                    diameterInches: 12,
                    depthInches: 48,
                    connection: PostFootingConnection(hardwareModel: "ABU66", upliftRated: true)
                ),
                Footing(
                    id: "f2",
                    position: CGPoint(x: 144, y: 120),
                    type: .helicalPile,
                    helicalTorqueFtLb: 5_500
                )
            ],
            soil: SoilInput(bearingCapacityPSF: 1_500),
            frost: FrostInput(depthInches: 42)
        )
        return data
    }

    private static func legacyDeck() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1
        data.overallElevation = 4

        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144))

        var e1 = DeckEdge(
            id: "deck-edge-1",
            startVertexId: v1.id,
            endVertexId: v2.id,
            dimension: 144,
            railingConfig: RailingConfig(railingType: .picket, maxPostSpacing: 84),
            stairConfig: StairConfig(width: 48),
            assignedItems: [AssignedItem(name: "Gate", unitType: .each, isGate: true)]
        )
        var e2 = DeckEdge(id: "deck-edge-2", startVertexId: v2.id, endVertexId: v3.id, dimension: 144)
        var e3 = DeckEdge(id: "deck-edge-3", startVertexId: v3.id, endVertexId: v4.id, dimension: 144)
        var e4 = DeckEdge(id: "deck-edge-4", startVertexId: v4.id, endVertexId: v1.id, dimension: 144)
        e1.edgeType = .deckEdge
        e2.edgeType = .deckEdge
        e3.edgeType = .deckEdge
        e4.edgeType = .deckEdge

        data.vertices = [v1, v2, v3, v4]
        data.edges = [e1, e2, e3, e4]
        data.footprint = DeckFootprint(isClosed: true)
        return data
    }
}
