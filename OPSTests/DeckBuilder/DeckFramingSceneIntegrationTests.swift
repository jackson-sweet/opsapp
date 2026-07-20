import SceneKit
import XCTest
@testable import OPS

final class DeckFramingSceneIntegrationTests: XCTestCase {
    func testLive2114SceneContainsRealLoadPathAndNoLegacyPerimeterSupports() {
        let scene = DeckSceneBuilder.buildCalibratedScene(from: live2114Drawing())

        for role in ["ledger", "rimBand", "joist", "blocking", "beam", "post"] {
            XCTAssertFalse(
                scene.rootNode.nodes(withPrefix: "framing.\(role).").isEmpty,
                "Expected live scene to render \(role) framing."
            )
        }
        XCTAssertFalse(scene.rootNode.nodes(withPrefix: "framing.footing.").isEmpty)
        assertNoLegacySupports(in: scene.rootNode)
    }

    func testPersistedEmptySetSuppressesBothGeneratedAndLegacyStructure() throws {
        let emptyPlan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [])],
            generationSource: .manual
        )
        let drawing = try drawing(rectangleDrawing(), withPersistedFraming: emptyPlan)

        let scene = DeckSceneBuilder.buildScene(from: drawing)

        XCTAssertTrue(scene.rootNode.nodes(withPrefix: "framing.joist.").isEmpty)
        XCTAssertTrue(scene.rootNode.nodes(withPrefix: "framing.beam.").isEmpty)
        XCTAssertTrue(scene.rootNode.nodes(withPrefix: "framing.post.").isEmpty)
        XCTAssertTrue(scene.rootNode.nodes(withPrefix: "framing.footing.").isEmpty)
        assertNoLegacySupports(in: scene.rootNode)
    }

    func testPersistedFramingMemberCountsRemainAuthoritativeInScene() throws {
        let persisted = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [
                FramingMember(
                    id: "saved-ledger",
                    role: .ledger,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 120, y: 0),
                    nominalSize: .twoByTwelve
                ),
                FramingMember(
                    id: "saved-beam",
                    role: .beam,
                    start: CGPoint(x: 0, y: 72),
                    end: CGPoint(x: 120, y: 72),
                    nominalSize: .twoByTen,
                    plyCount: 2
                ),
                FramingMember(
                    id: "saved-post",
                    role: .post,
                    start: CGPoint(x: 0, y: 72),
                    end: CGPoint(x: 0, y: 72),
                    nominalSize: .sixBySix
                ),
            ])],
            generationSource: .manual
        )
        let drawing = try drawing(rectangleDrawing(), withPersistedFraming: persisted)

        let scene = DeckSceneBuilder.buildScene(from: drawing)

        XCTAssertEqual(scene.rootNode.nodes(withPrefix: "framing.ledger.").count, 1)
        XCTAssertEqual(scene.rootNode.nodes(withPrefix: "framing.beam.").count, 1)
        XCTAssertEqual(scene.rootNode.nodes(withPrefix: "framing.post.").count, 1)
        XCTAssertEqual(scene.rootNode.nodes(withPrefix: "framing.footing.").count, 1)
        XCTAssertTrue(scene.rootNode.nodes(withPrefix: "framing.joist.").isEmpty)
        assertNoLegacySupports(in: scene.rootNode)
    }

    func testCalibratedARUsesTheSameResolvedFramingPipeline() {
        let root = DeckSceneBuilder.buildCalibratedARNode(from: live2114Drawing())

        XCTAssertFalse(root.nodes(withPrefix: "framing.joist.").isEmpty)
        XCTAssertFalse(root.nodes(withPrefix: "framing.beam.").isEmpty)
        XCTAssertFalse(root.nodes(withPrefix: "framing.post.").isEmpty)
        XCTAssertFalse(root.nodes(withPrefix: "framing.footing.").isEmpty)
        assertNoLegacySupports(in: root)
    }

    func testMultiLevelFramingPreservesSharedHorizontalFrameAndEachLevelElevation() throws {
        let lowerJoist = FramingMember(
            id: "lower-joist",
            role: .joist,
            start: CGPoint(x: 0, y: 60),
            end: CGPoint(x: 120, y: 60),
            nominalSize: .twoByEight
        )
        let upperJoist = FramingMember(
            id: "upper-joist",
            role: .joist,
            start: CGPoint(x: 300, y: 60),
            end: CGPoint(x: 420, y: 60),
            nominalSize: .twoByEight
        )
        let persisted = FramingPlan(
            members: [
                FramingMemberSet(levelId: "lower", members: [lowerJoist]),
                FramingMemberSet(levelId: "upper", members: [upperJoist]),
            ],
            generationSource: .manual
        )
        let drawing = try drawing(twoLevelDrawing(), withPersistedFraming: persisted)

        let scene = DeckSceneBuilder.buildScene(from: drawing)

        let lowerNode = try XCTUnwrap(scene.rootNode.nodes(exactlyNamed: "framing.joist.lower-joist").first)
        let upperNode = try XCTUnwrap(scene.rootNode.nodes(exactlyNamed: "framing.joist.upper-joist").first)
        let lowerWorld = lowerNode.convertPosition(SCNVector3Zero, to: nil)
        let upperWorld = upperNode.convertPosition(SCNVector3Zero, to: nil)
        let joistDepthMeters = Float(7.25 / 39.3701)

        XCTAssertEqual(upperWorld.x - lowerWorld.x, Float(300 / 39.3701), accuracy: 0.000_01)
        XCTAssertEqual(lowerWorld.y + joistDepthMeters / 2, Float(2 * 0.3048), accuracy: 0.000_01)
        XCTAssertEqual(upperWorld.y + joistDepthMeters / 2, Float(5 * 0.3048), accuracy: 0.000_01)
    }

    private func assertNoLegacySupports(in root: SCNNode, file: StaticString = #filePath, line: UInt = #line) {
        for name in ["supportPost", "footing", "rimJoist"] {
            XCTAssertTrue(root.nodes(exactlyNamed: name).isEmpty, "Found legacy node \(name)", file: file, line: line)
        }
    }

    private func rectangleDrawing() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        drawing.overallElevation = 4
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        drawing.edges = [
            edge("e1", "v1", "v2", 120, type: .houseEdge),
            edge("e2", "v2", "v3", 120),
            edge("e3", "v3", "v4", 120),
            edge("e4", "v4", "v1", 120),
        ]
        return drawing
    }

    private func twoLevelDrawing() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1

        var lower = DeckLevel(id: "lower", name: "Lower")
        lower.elevation = 2
        lower.vertices = rectangleVertices(prefix: "lower", originX: 0)
        lower.edges = rectangleEdges(prefix: "lower")

        var upper = DeckLevel(id: "upper", name: "Upper")
        upper.elevation = 5
        upper.vertices = rectangleVertices(prefix: "upper", originX: 300)
        upper.edges = rectangleEdges(prefix: "upper")

        drawing.levels = [lower, upper]
        return drawing
    }

    private func rectangleVertices(prefix: String, originX: CGFloat) -> [DeckVertex] {
        [
            DeckVertex(id: "\(prefix)-v1", position: CGPoint(x: originX, y: 0)),
            DeckVertex(id: "\(prefix)-v2", position: CGPoint(x: originX + 120, y: 0)),
            DeckVertex(id: "\(prefix)-v3", position: CGPoint(x: originX + 120, y: 120)),
            DeckVertex(id: "\(prefix)-v4", position: CGPoint(x: originX, y: 120)),
        ]
    }

    private func rectangleEdges(prefix: String) -> [DeckEdge] {
        [
            edge("\(prefix)-e1", "\(prefix)-v1", "\(prefix)-v2", 120, type: .houseEdge),
            edge("\(prefix)-e2", "\(prefix)-v2", "\(prefix)-v3", 120),
            edge("\(prefix)-e3", "\(prefix)-v3", "\(prefix)-v4", 120),
            edge("\(prefix)-e4", "\(prefix)-v4", "\(prefix)-v1", 120),
        ]
    }

    private func live2114Drawing() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.overallElevation = 5.5
        drawing.vertices = [
            DeckVertex(id: "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", position: CGPoint(x: 2388, y: 2364)),
            DeckVertex(id: "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", position: CGPoint(x: 2520, y: 2364)),
            DeckVertex(id: "E8C262FD-081D-4617-BC9F-FC4D2554F017", position: CGPoint(x: 2520, y: 2400)),
            DeckVertex(id: "1F45EE10-1BAA-4A09-B848-850C20394322", position: CGPoint(x: 2388, y: 2436)),
            DeckVertex(id: "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", position: CGPoint(x: 2232, y: 2436)),
            DeckVertex(id: "187AF134-849A-4231-A7D1-FAE177E97E18", position: CGPoint(x: 2520, y: 2436)),
            DeckVertex(id: "E7DA228A-CBDE-486B-947C-922BEFE1EE70", position: CGPoint(x: 2520, y: 2724)),
            DeckVertex(id: "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", position: CGPoint(x: 2472, y: 2724)),
            DeckVertex(id: "6CF06C30-083C-48B4-A0E2-689DA2C55848", position: CGPoint(x: 2472, y: 2916)),
            DeckVertex(id: "72499BA4-8F0A-4E28-84F2-DC594359C614", position: CGPoint(x: 2232, y: 2916)),
        ]
        drawing.edges = [
            edge("196B3A15-D5C3-4D7B-883D-DDEDA1CCCC97", "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", 66),
            edge("31AE48D6-4298-421B-BE4F-27974F959FE2", "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", "E8C262FD-081D-4617-BC9F-FC4D2554F017", 18),
            edge("9E0337D1-1AB9-49EF-8042-1B5E0F87E969", "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", "1F45EE10-1BAA-4A09-B848-850C20394322", 36),
            edge("7B91B112-54A5-48D7-92FF-A19869B21F0D", "1F45EE10-1BAA-4A09-B848-850C20394322", "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", 78),
            edge("232924E5-8EE3-4F61-9A10-427F3AABF30B", "E8C262FD-081D-4617-BC9F-FC4D2554F017", "187AF134-849A-4231-A7D1-FAE177E97E18", 18),
            edge("F6FCB95B-1124-4307-B2EC-21618AAC4EC3", "187AF134-849A-4231-A7D1-FAE177E97E18", "E7DA228A-CBDE-486B-947C-922BEFE1EE70", 144),
            edge("4A958E9F-1969-4AA1-8822-AC1A20D4A035", "E7DA228A-CBDE-486B-947C-922BEFE1EE70", "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", 24),
            edge("C3ACE162-9199-4968-8A26-3A07DB56F1B3", "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", "6CF06C30-083C-48B4-A0E2-689DA2C55848", 96),
            edge("988C36C0-D25E-4921-8FB3-3DCAF484E93B", "6CF06C30-083C-48B4-A0E2-689DA2C55848", "72499BA4-8F0A-4E28-84F2-DC594359C614", 120, type: .houseEdge),
            edge("44EA3162-0E6D-46FB-840C-4A8007D1A0FC", "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", "72499BA4-8F0A-4E28-84F2-DC594359C614", 240),
        ]
        drawing.footprint.isClosed = true
        return drawing
    }

    private func edge(
        _ id: String,
        _ start: String,
        _ end: String,
        _ dimension: Double,
        type: EdgeType = .deckEdge
    ) -> DeckEdge {
        DeckEdge(
            id: id,
            startVertexId: start,
            endVertexId: end,
            edgeType: type,
            dimension: dimension,
            dimensionSource: .scale
        )
    }

    private func drawing(
        _ drawing: DeckDrawingData,
        withPersistedFraming framing: FramingPlan
    ) throws -> DeckDrawingData {
        var root = try DeckJSONValue.parseObject(from: drawing.toJSON())
        let framingData = try JSONEncoder().encode(framing)
        let framingJSON = try XCTUnwrap(String(data: framingData, encoding: .utf8))
        root["framing"] = .object(try DeckJSONValue.parseObject(from: framingJSON))
        let mergedJSON = try DeckJSONValue.object(root).renderedJSONString()
        return try XCTUnwrap(DeckDrawingData.fromJSON(mergedJSON))
    }
}

private extension SCNNode {
    func nodes(withPrefix prefix: String) -> [SCNNode] {
        let own = name?.hasPrefix(prefix) == true ? [self] : []
        return own + childNodes.flatMap { $0.nodes(withPrefix: prefix) }
    }

    func nodes(exactlyNamed target: String) -> [SCNNode] {
        let own = name == target ? [self] : []
        return own + childNodes.flatMap { $0.nodes(exactlyNamed: target) }
    }
}
