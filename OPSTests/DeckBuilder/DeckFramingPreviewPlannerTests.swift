import CoreGraphics
import Foundation
import XCTest
@testable import OPS

final class DeckFramingPreviewPlannerTests: XCTestCase {
    func testLive2114ShuffledGeometryResolvesACompleteSupportedFrame() throws {
        let drawing = live2114Drawing()
        let plan = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)
        let members = plan.members.flatMap(\.members)

        for role in [FramingRole.ledger, .rimBand, .joist, .beam, .post] {
            XCTAssertTrue(members.contains(where: { $0.role == role }), "Expected a generated \(role.rawValue) member.")
        }

        let houseStart = try XCTUnwrap(drawing.vertices.first(where: { $0.id == liveHouseStartId })?.position)
        let houseEnd = try XCTUnwrap(drawing.vertices.first(where: { $0.id == liveHouseEndId })?.position)
        let ledgers = members.filter { $0.role == .ledger }
        XCTAssertEqual(ledgers.count, 1)
        XCTAssertTrue(ledgers.contains(where: { segmentMatches($0, houseStart, houseEnd) }))

        let beams = members.filter { $0.role == .beam }
        let posts = members.filter { $0.role == .post }
        XCTAssertFalse(beams.isEmpty)
        XCTAssertFalse(posts.isEmpty)
        XCTAssertTrue(posts.allSatisfy { post in
            beams.contains(where: { point(post.start, liesOn: $0) })
        }, "Every generated post must bear directly beneath a generated beam.")
        XCTAssertFalse(posts.contains(where: { point($0.start, liesOnSegmentFrom: houseStart, to: houseEnd) }),
                       "The house edge is a ledger, never a decorative perimeter post line.")
    }

    func testLive2114ResolutionIsInvariantToVertexEdgeAndEndpointPermutation() {
        let drawing = live2114Drawing()
        let baseline = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)

        var permuted = drawing
        let vertexOrder = [9, 2, 7, 0, 5, 3, 8, 1, 6, 4]
        permuted.vertices = vertexOrder.map { drawing.vertices[$0] }
        permuted.edges = drawing.edges.reversed().enumerated().map { index, edge in
            guard index.isMultiple(of: 2) else { return edge }
            var reversed = edge
            reversed.startVertexId = edge.endVertexId
            reversed.endVertexId = edge.startVertexId
            return reversed
        }
        let resolved = DeckFramingPreviewPlanner.resolvedPlan(for: permuted)

        XCTAssertEqual(canonicalMembers(in: resolved), canonicalMembers(in: baseline))
    }

    func testGeneratedMemberIDsAreDeterministicAndUnique() {
        let drawing = live2114Drawing()
        let first = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)
        let second = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)
        let firstMembers = first.members.flatMap(\.members)
        let secondMembers = second.members.flatMap(\.members)

        XCTAssertEqual(firstMembers.map(\.id).sorted(), secondMembers.map(\.id).sorted())
        XCTAssertEqual(Set(firstMembers.map(\.id)).count, firstMembers.count)
    }

    func testAdjacentSurfacesOmitSharedSeamAndDedupeCoincidentMembers() {
        let drawing = twoSquaresSharingEdge()
        XCTAssertEqual(drawing.detectedSurfaces.count, 2)

        let plan = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)
        let members = plan.members.flatMap(\.members)
        let seamStart = CGPoint(x: 120, y: 0)
        let seamEnd = CGPoint(x: 120, y: 120)

        let perimeterMembers = members.filter { $0.role == .rimBand || $0.role == .ledger }
        XCTAssertFalse(perimeterMembers.contains(where: { segmentMatches($0, seamStart, seamEnd) }),
                       "An interior shared boundary is not a rim or ledger.")

        let signatures = members.map(memberGeometrySignature)
        XCTAssertEqual(Set(signatures).count, signatures.count,
                       "Shared surfaces must not emit coincident members twice.")
    }

    func testPersistedCompleteAndExplicitlyEmptyMemberSetsRemainAuthoritative() throws {
        let persistedMember = FramingMember(
            id: "manual-beam",
            role: .beam,
            start: CGPoint(x: 12, y: 42),
            end: CGPoint(x: 108, y: 42),
            nominalSize: .fourBySix,
            plyCount: 3,
            locked: true
        )
        let completePlan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [persistedMember])],
            generationSource: .manual,
            generatedAtSchemaVersion: 11
        )
        let completeDrawing = try drawing(
            rectangleDrawing(prefix: "complete", originX: 0),
            withPersistedFraming: completePlan
        )

        XCTAssertEqual(DeckFramingPreviewPlanner.resolvedPlan(for: completeDrawing), completePlan)

        let emptyPlan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [])],
            generationSource: .manual,
            generatedAtSchemaVersion: 11
        )
        let intentionallyEmptyDrawing = try drawing(
            rectangleDrawing(prefix: "empty", originX: 0),
            withPersistedFraming: emptyPlan
        )

        XCTAssertEqual(DeckFramingPreviewPlanner.resolvedPlan(for: intentionallyEmptyDrawing), emptyPlan,
                       "An explicitly persisted empty set is intentional and must not be silently regenerated.")
    }

    func testPartialPersistedPlanKeepsExistingLevelAndGeneratesOnlyMissingLevel() throws {
        var drawing = twoLevelDrawing()
        let lowerMember = FramingMember(
            id: "locked-lower-ledger",
            role: .ledger,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 120, y: 0),
            nominalSize: .twoByTwelve,
            plyCount: 1,
            locked: true
        )
        let lowerSet = FramingMemberSet(levelId: "lower", members: [lowerMember])
        let partial = FramingPlan(
            members: [lowerSet],
            generationSource: .manual,
            generatedAtSchemaVersion: 11
        )
        drawing = try self.drawing(drawing, withPersistedFraming: partial)

        let resolved = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)

        XCTAssertEqual(resolved.members.first(where: { $0.levelId == "lower" }), lowerSet)
        XCTAssertFalse(try XCTUnwrap(resolved.members.first(where: { $0.levelId == "upper" })).members.isEmpty)
        XCTAssertEqual(drawing.framing, partial, "Transient display completion must not rewrite persisted framing.")
    }

    func testLegacyPreviewNeverMutatesOrPersistsIntoDrawing() {
        let drawing = live2114Drawing()
        let originalVertices = drawing.vertices
        let originalEdges = drawing.edges
        let originalFutureBlocks = drawing.futureBlocks

        let preview = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)

        XCTAssertFalse(preview.members.flatMap(\.members).isEmpty)
        XCTAssertNil(drawing.framing)
        XCTAssertEqual(drawing.vertices, originalVertices)
        XCTAssertEqual(drawing.edges, originalEdges)
        XCTAssertEqual(drawing.futureBlocks, originalFutureBlocks)
    }

    // MARK: - Column placement (bug 311ccfe5)

    func testSixteenByTwelveLedgerDeckDrawsOneBeamAndThreePostsNoneOnAVertex() throws {
        let drawing = deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: true)
        let members = DeckFramingPreviewPlanner.resolvedPlan(for: drawing).members.flatMap(\.members)

        let beams = members.filter { $0.role == .beam }
        let posts = members.filter { $0.role == .post }
        XCTAssertEqual(beams.count, 1, "A 12 ft deep deck needs one beam. The old planner drew two.")
        XCTAssertEqual(posts.count, 3, "Eight posts and eight footings become three.")

        // The beam sits a full 24 in Table 3b cantilever inboard of the outer edge.
        let beam = try XCTUnwrap(beams.first)
        XCTAssertEqual(Double(beam.start.y), 120, accuracy: 0.001)
        XCTAssertEqual(Double(beam.end.y), 120, accuracy: 0.001)

        for post in posts {
            for vertex in drawing.vertices {
                XCTAssertGreaterThan(distance(post.start, vertex.position), 0.001,
                                     "A post on a deck corner is the reported bug.")
            }
            XCTAssertGreaterThan(Double(post.start.y), 0.001, "No post on the house edge.")
            XCTAssertLessThan(Double(post.start.y), 143.999, "No post on the outer edge.")
        }
    }

    /// The substance of the bug: a post on a corner.
    ///
    /// Every fixture here is a rectangle or a pair of rectangles, where the
    /// invariant holds by construction — a beam sits strictly between the
    /// reference edge and the outer edge, so its clipped ends land on the two
    /// side edges, never on a corner. The live 2114 drawing is deliberately
    /// absent: it is concave, and on a concave outline a beam chord can end
    /// exactly at a notch vertex. No cited source gives a beam-overhang limit
    /// that would let us pull such a post inboard, so that case is verified
    /// visually on device rather than asserted here.
    func testNoGeneratedPostEverLandsOnADeckVertex() {
        let fixtures: [(String, DeckDrawingData)] = [
            ("16x12 ledger", deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: true)),
            ("16x12 free-standing", deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: false)),
            ("24x20 ledger", deckDrawing(widthInches: 288, depthInches: 240, ledgerAttached: true)),
            ("120 square", rectangleDrawing(prefix: "square", originX: 0)),
            ("two levels", twoLevelDrawing()),
            ("shared seam", twoSquaresSharingEdge()),
        ]

        for (label, drawing) in fixtures {
            let plan = DeckFramingPreviewPlanner.resolvedPlan(for: drawing)
            let posts = plan.members.flatMap(\.members).filter { $0.role == .post }
            XCTAssertFalse(posts.isEmpty, "\(label): expected generated posts.")

            let vertices = drawing.isMultiLevel
                ? drawing.levels.flatMap(\.vertices)
                : drawing.vertices
            for post in posts {
                for vertex in vertices {
                    XCTAssertGreaterThan(
                        distance(post.start, vertex.position), 0.001,
                        "\(label): a post landed on a deck vertex."
                    )
                }
            }
        }
    }

    func testEveryBeamIsInboardOfTheOuterEdgeByTheFullPublishedCantilever() throws {
        for depthInches in [96.0, 120.0, 144.0, 168.0] {
            let drawing = deckDrawing(widthInches: 192, depthInches: depthInches, ledgerAttached: true)
            let members = DeckFramingPreviewPlanner.resolvedPlan(for: drawing).members.flatMap(\.members)
            let joist = try XCTUnwrap(members.first(where: { $0.role == .joist }))
            let joistSize = try XCTUnwrap(joist.nominalSize)
            let cantilever = try XCTUnwrap(DeckSpanTables.maxCantileverInches(nominalSize: joistSize))

            let outermost = try XCTUnwrap(members.filter { $0.role == .beam }.map { Double($0.start.y) }.max())
            XCTAssertEqual(outermost, depthInches - cantilever, accuracy: 0.001,
                           "\(depthInches) in deep: the beam must sit a full cantilever inboard.")
            XCTAssertNotEqual(depthInches - outermost, 12, accuracy: 0.001,
                              "12 in was the unsourced setback this change removes.")
        }
    }

    func testJoistsCarryTheSpeciesGradeSizeAndSpacingTheTablesChose() throws {
        let drawing = deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: true)
        let members = DeckFramingPreviewPlanner.resolvedPlan(for: drawing).members.flatMap(\.members)

        let joists = members.filter { $0.role == .joist }
        XCTAssertFalse(joists.isEmpty)
        for joist in joists {
            XCTAssertEqual(joist.nominalSize, .twoByTen)
            XCTAssertEqual(joist.spacingInchesOC, 24, "24 in o.c. is the BCBC 9.23.1.1 ceiling and the fewest joists.")
            XCTAssertEqual(joist.species, .hemFir)
            XCTAssertEqual(joist.grade, .no2)
        }

        let beam = try XCTUnwrap(members.first(where: { $0.role == .beam }))
        XCTAssertEqual(beam.nominalSize, .twoByTen)
        XCTAssertEqual(beam.plyCount, 2, "Table 5b gives 2-2x10 at a 12 ft entering span and 8 ft posts.")

        let posts = members.filter { $0.role == .post }
        XCTAssertTrue(posts.allSatisfy { $0.nominalSize == .sixBySix },
                      "BCBC 9.17.4.1 requires 6x6 absent a structural calculation.")
    }

    func testTheOverhangPastTheOuterBeamIsDrawnAsACantilever() throws {
        let drawing = deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: true)
        let members = DeckFramingPreviewPlanner.resolvedPlan(for: drawing).members.flatMap(\.members)

        let cantilevers = members.filter { $0.role == .cantilever }
        XCTAssertFalse(cantilevers.isEmpty, "The joist overhang past the beam is a cantilever, not a joist.")
        for member in cantilevers {
            let lower = min(Double(member.start.y), Double(member.end.y))
            let upper = max(Double(member.start.y), Double(member.end.y))
            XCTAssertEqual(lower, 120, accuracy: 0.001, "A cantilever starts at the beam.")
            XCTAssertEqual(upper, 144, accuracy: 0.001, "A cantilever ends at the deck edge.")
        }

        // Every joist run stops at the beam it bears on.
        for joist in members.filter({ $0.role == .joist }) {
            XCTAssertLessThanOrEqual(max(Double(joist.start.y), Double(joist.end.y)), 120.001)
        }
    }

    func testAFreeStandingDeckKeepsBothBeamsOffTheOuterEdges() throws {
        let drawing = deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: false)
        let members = DeckFramingPreviewPlanner.resolvedPlan(for: drawing).members.flatMap(\.members)

        let beamRows = Set(members.filter { $0.role == .beam }.map { (Double($0.start.y) * 1_000).rounded() })
        XCTAssertEqual(beamRows.count, 2, "No ledger means one beam inboard of each outer edge.")
        for row in beamRows {
            let y = row / 1_000
            XCTAssertGreaterThan(y, 0.001, "A beam on the outer edge is the bug.")
            XCTAssertLessThan(y, 143.999, "A beam on the outer edge is the bug.")
        }
        XCTAssertFalse(members.filter { $0.role == .cantilever }.isEmpty,
                       "A free-standing deck cantilevers past both beams.")
    }

    func testGeneratedFramingNeverCarriesEngineeringSizing() {
        for drawing in [
            live2114Drawing(),
            deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: true),
            deckDrawing(widthInches: 192, depthInches: 144, ledgerAttached: false),
        ] {
            let members = DeckFramingPreviewPlanner.resolvedPlan(for: drawing).members.flatMap(\.members)
            XCTAssertFalse(members.isEmpty)
            XCTAssertTrue(members.allSatisfy { $0.sizing == nil },
                          "The preview is a picture, not an engineered design.")
            XCTAssertTrue(members.allSatisfy { !$0.locked })
        }
    }

    // MARK: - Fixtures

    private let liveHouseStartId = "6CF06C30-083C-48B4-A0E2-689DA2C55848"
    private let liveHouseEndId = "72499BA4-8F0A-4E28-84F2-DC594359C614"

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
            DeckVertex(id: liveHouseStartId, position: CGPoint(x: 2472, y: 2916)),
            DeckVertex(id: liveHouseEndId, position: CGPoint(x: 2232, y: 2916)),
        ]
        drawing.edges = [
            edge("196B3A15-D5C3-4D7B-883D-DDEDA1CCCC97", "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", 66),
            edge("31AE48D6-4298-421B-BE4F-27974F959FE2", "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", "E8C262FD-081D-4617-BC9F-FC4D2554F017", 18),
            edge("9E0337D1-1AB9-49EF-8042-1B5E0F87E969", "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", "1F45EE10-1BAA-4A09-B848-850C20394322", 36),
            edge("7B91B112-54A5-48D7-92FF-A19869B21F0D", "1F45EE10-1BAA-4A09-B848-850C20394322", "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", 78),
            edge("232924E5-8EE3-4F61-9A10-427F3AABF30B", "E8C262FD-081D-4617-BC9F-FC4D2554F017", "187AF134-849A-4231-A7D1-FAE177E97E18", 18),
            edge("F6FCB95B-1124-4307-B2EC-21618AAC4EC3", "187AF134-849A-4231-A7D1-FAE177E97E18", "E7DA228A-CBDE-486B-947C-922BEFE1EE70", 144),
            edge("4A958E9F-1969-4AA1-8822-AC1A20D4A035", "E7DA228A-CBDE-486B-947C-922BEFE1EE70", "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", 24),
            edge("C3ACE162-9199-4968-8A26-3A07DB56F1B3", "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", liveHouseStartId, 96),
            edge("988C36C0-D25E-4921-8FB3-3DCAF484E93B", liveHouseStartId, liveHouseEndId, 120, type: .houseEdge),
            edge("44EA3162-0E6D-46FB-840C-4A8007D1A0FC", "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", liveHouseEndId, 240),
        ]
        drawing.footprint.isClosed = true
        return drawing
    }

    private func twoSquaresSharingEdge() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
            DeckVertex(id: "v5", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "v6", position: CGPoint(x: 240, y: 120)),
        ]
        drawing.edges = [
            edge("e1", "v1", "v2", 120),
            edge("e2", "v2", "v3", 120),
            edge("e3", "v3", "v4", 120),
            edge("e4", "v4", "v1", 120),
            edge("e5", "v2", "v5", 120),
            edge("e6", "v5", "v6", 120),
            edge("e7", "v6", "v3", 120),
        ]
        return drawing
    }

    /// A plain rectangle at one canvas unit per inch, with the reference edge at
    /// y = 0 and the deck running to y = depth.
    private func deckDrawing(
        widthInches: CGFloat,
        depthInches: CGFloat,
        ledgerAttached: Bool
    ) -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        let prefix = "deck-\(Int(widthInches))x\(Int(depthInches))-\(ledgerAttached ? "attached" : "free")"
        drawing.vertices = [
            DeckVertex(id: "\(prefix)-v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "\(prefix)-v2", position: CGPoint(x: widthInches, y: 0)),
            DeckVertex(id: "\(prefix)-v3", position: CGPoint(x: widthInches, y: depthInches)),
            DeckVertex(id: "\(prefix)-v4", position: CGPoint(x: 0, y: depthInches)),
        ]
        drawing.edges = [
            edge("\(prefix)-e1", "\(prefix)-v1", "\(prefix)-v2", Double(widthInches),
                 type: ledgerAttached ? .houseEdge : .deckEdge),
            edge("\(prefix)-e2", "\(prefix)-v2", "\(prefix)-v3", Double(depthInches)),
            edge("\(prefix)-e3", "\(prefix)-v3", "\(prefix)-v4", Double(widthInches)),
            edge("\(prefix)-e4", "\(prefix)-v4", "\(prefix)-v1", Double(depthInches)),
        ]
        return drawing
    }

    private func rectangleDrawing(prefix: String, originX: CGFloat) -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        drawing.vertices = rectangleVertices(prefix: prefix, originX: originX)
        drawing.edges = rectangleEdges(prefix: prefix)
        return drawing
    }

    private func twoLevelDrawing() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1

        var lower = DeckLevel(id: "lower", name: "Lower")
        lower.vertices = rectangleVertices(prefix: "lower", originX: 0)
        lower.edges = rectangleEdges(prefix: "lower")

        var upper = DeckLevel(id: "upper", name: "Upper")
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

    // MARK: - Assertions

    private func canonicalMembers(in plan: FramingPlan) -> [String] {
        plan.members.flatMap { set in
            set.members.map { member in
                "\(set.levelId)|\(member.id)|\(memberGeometrySignature(member))"
            }
        }.sorted()
    }

    private func memberGeometrySignature(_ member: FramingMember) -> String {
        let endpoints = [pointSignature(member.start), pointSignature(member.end)].sorted()
        return "\(member.role.rawValue)|\(endpoints[0])|\(endpoints[1])"
    }

    private func pointSignature(_ point: CGPoint) -> String {
        "\(Int((Double(point.x) * 1_000).rounded())):\(Int((Double(point.y) * 1_000).rounded()))"
    }

    private func segmentMatches(
        _ member: FramingMember,
        _ expectedStart: CGPoint,
        _ expectedEnd: CGPoint,
        tolerance: Double = 0.001
    ) -> Bool {
        let direct = distance(member.start, expectedStart) <= tolerance && distance(member.end, expectedEnd) <= tolerance
        let reversed = distance(member.start, expectedEnd) <= tolerance && distance(member.end, expectedStart) <= tolerance
        return direct || reversed
    }

    private func point(_ point: CGPoint, liesOn member: FramingMember, tolerance: Double = 0.001) -> Bool {
        self.point(point, liesOnSegmentFrom: member.start, to: member.end, tolerance: tolerance)
    }

    private func point(
        _ point: CGPoint,
        liesOnSegmentFrom start: CGPoint,
        to end: CGPoint,
        tolerance: Double = 0.001
    ) -> Bool {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, start) <= tolerance }

        let projection = ((Double(point.x - start.x) * dx) + (Double(point.y - start.y) * dy)) / lengthSquared
        guard projection >= -tolerance, projection <= 1 + tolerance else { return false }
        let closest = CGPoint(
            x: Double(start.x) + projection * dx,
            y: Double(start.y) + projection * dy
        )
        return distance(point, closest) <= tolerance
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(Double(rhs.x - lhs.x), Double(rhs.y - lhs.y))
    }
}
