import SceneKit
import XCTest
@testable import OPS

final class FramingSceneBuilderTests: XCTestCase {
    private let inchesToMeters = 1.0 / 39.3701

    func testBuildsStableLayersAndOneNamedNodeForEveryRenderableRole() throws {
        let members = [
            member("joist", .joist, CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0), .twoByEight),
            member("beam", .beam, CGPoint(x: 0, y: 48), CGPoint(x: 120, y: 48), .twoByTen),
            member("post", .post, CGPoint(x: 0, y: 48), CGPoint(x: 0, y: 48), .sixBySix),
            member("ledger", .ledger, CGPoint(x: 0, y: 96), CGPoint(x: 120, y: 96), .twoByEight),
            member("rim", .rimBand, CGPoint(x: 0, y: 120), CGPoint(x: 120, y: 120), .twoByEight),
            member("blocking", .blocking, CGPoint(x: 60, y: 0), CGPoint(x: 60, y: 120), .twoByEight),
            member("bridging", .bridging, CGPoint(x: 72, y: 0), CGPoint(x: 72, y: 120), .twoByEight),
            member("cantilever", .cantilever, CGPoint(x: 88, y: 0), CGPoint(x: 88, y: 120), .twoByEight),
        ]
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: members)],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )

        XCTAssertEqual(root.name, "framingRoot")
        for layer in ["layer.joists", "layer.beams", "layer.posts", "layer.footings", "layer.rim", "layer.blocking"] {
            XCTAssertNotNil(root.firstNode(named: layer), "Missing stable framing layer \(layer)")
        }
        for item in members {
            XCTAssertNotNil(root.firstNode(named: "framing.\(item.role.rawValue).\(item.id)"))
        }
        XCTAssertNotNil(root.firstNode(named: "framing.footing.post"))
        XCTAssertEqual(root.nodes(withPrefix: "framing.footing.").count, 1)
    }

    func testUsesActualLumberDimensionsAndSeatsTheLoadPathWithoutGaps() throws {
        let joist = member("joist", .joist, CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0), .twoByEight)
        let beam = FramingMember(
            id: "beam",
            role: .beam,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 120, y: 0),
            nominalSize: .twoByTen,
            plyCount: 3
        )
        let post = member("post", .post, .zero, .zero, .sixBySix)
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [joist, beam, post])],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: [DeckVertex(id: "bearing", position: .zero, footingType: .concretePad)]
        )

        let joistNode = try XCTUnwrap(root.firstNode(named: "framing.joist.joist"))
        let beamNode = try XCTUnwrap(root.firstNode(named: "framing.beam.beam"))
        let postNode = try XCTUnwrap(root.firstNode(named: "framing.post.post"))
        let footingRoot = try XCTUnwrap(root.firstNode(named: "framing.footing.post"))
        let joistBox = try XCTUnwrap(joistNode.geometry as? SCNBox)
        let beamBox = try XCTUnwrap(beamNode.geometry as? SCNBox)
        let postBox = try XCTUnwrap(postNode.geometry as? SCNBox)
        let footingShape = try XCTUnwrap(footingRoot.childNodes.first)

        XCTAssertEqual(Double(joistBox.height), 7.25 * inchesToMeters, accuracy: 0.000_001)
        XCTAssertEqual(Double(beamBox.height), 9.25 * inchesToMeters, accuracy: 0.000_001)
        XCTAssertEqual(Double(beamBox.width), 4.5 * inchesToMeters, accuracy: 0.000_001)

        let joistBottom = Double(joistNode.position.y) - Double(joistBox.height) / 2
        let beamTop = Double(beamNode.position.y) + Double(beamBox.height) / 2
        let beamBottom = Double(beamNode.position.y) - Double(beamBox.height) / 2
        let postTop = Double(postNode.position.y) + Double(postBox.height) / 2
        let postBottom = Double(postNode.position.y) - Double(postBox.height) / 2
        let footingTop = Double(footingRoot.position.y + footingShape.position.y)
            + Double(try XCTUnwrap(footingShape.geometry?.boundingBox.max.y))

        XCTAssertEqual(beamTop, joistBottom, accuracy: 0.000_001)
        XCTAssertEqual(postTop, beamBottom, accuracy: 0.000_001)
        XCTAssertEqual(postBottom, footingTop, accuracy: 0.000_001)
    }

    func testFootingShapeUsesOnlyAnExactVertexAssignment() throws {
        let posts = [
            member("helical", .post, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0), .sixBySix),
            member("sono", .post, CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 0), .sixBySix),
            member("pad", .post, CGPoint(x: 80, y: 0), CGPoint(x: 80, y: 0), .sixBySix),
            member("schematic", .post, CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 0), .sixBySix),
        ]
        let bearingBeam = member(
            "bearing-beam",
            .beam,
            CGPoint(x: 0, y: 0),
            CGPoint(x: 120, y: 0),
            .twoByTen
        )
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [bearingBeam] + posts)],
            generationSource: .manual
        )
        let vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0), footingType: .helicalPile),
            DeckVertex(id: "v2", position: CGPoint(x: 40, y: 0), footingType: .sonoTube),
            DeckVertex(id: "v3", position: CGPoint(x: 80, y: 0), footingType: .concretePad),
            DeckVertex(id: "near-but-not-exact", position: CGPoint(x: 120.0005, y: 0), footingType: .helicalPile),
        ]

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: vertices
        )

        let expected = [
            "helical": "helical_pile",
            "sono": "sono_tube",
            "pad": "concrete_pad",
            "schematic": "schematic",
        ]
        for (postId, footingType) in expected {
            let footing = try XCTUnwrap(root.firstNode(named: "framing.footing.\(postId)"))
            XCTAssertNotNil(footing.firstNode(named: "footingShape.\(footingType)"))
        }
    }

    func testIgnoresZeroLengthLinearMembersWithoutProducingInvalidTransforms() {
        let invalid = member("zero", .joist, .zero, .zero, .twoByEight)
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [invalid])],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )

        XCTAssertNil(root.firstNode(named: "framing.joist.zero"))
    }

    func testSuppressesOrphanPostAndFootingWhenNoBeamBearsAboveIt() {
        let orphan = member("orphan", .post, .zero, .zero, .sixBySix)
        let zeroLengthBeam = member("zero-beam", .beam, .zero, .zero, .twoByTen)
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [orphan, zeroLengthBeam])],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )

        XCTAssertNil(root.firstNode(named: "framing.post.orphan"))
        XCTAssertNil(root.firstNode(named: "framing.footing.orphan"))
        XCTAssertNil(root.firstNode(named: "framing.beam.zero-beam"))
    }

    func testMixedRimAndBlockingDepthsDoNotLowerBeamAwayFromBearingJoist() throws {
        let joist = member(
            "bearing-joist",
            .joist,
            CGPoint(x: 0, y: 0),
            CGPoint(x: 120, y: 0),
            .twoByEight
        )
        let beam = member(
            "beam",
            .beam,
            CGPoint(x: 60, y: -60),
            CGPoint(x: 60, y: 60),
            .twoByTen
        )
        let deepRim = member(
            "deep-rim",
            .rimBand,
            CGPoint(x: 0, y: 120),
            CGPoint(x: 120, y: 120),
            .twoByTwelve
        )
        let deepBlocking = member(
            "deep-blocking",
            .blocking,
            CGPoint(x: 0, y: 90),
            CGPoint(x: 120, y: 90),
            .twoByTwelve
        )
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [joist, beam, deepRim, deepBlocking])],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )

        let joistNode = try XCTUnwrap(root.firstNode(named: "framing.joist.bearing-joist"))
        let beamNode = try XCTUnwrap(root.firstNode(named: "framing.beam.beam"))
        let joistBox = try XCTUnwrap(joistNode.geometry as? SCNBox)
        let beamBox = try XCTUnwrap(beamNode.geometry as? SCNBox)
        let joistBottom = Double(joistNode.position.y) - Double(joistBox.height) / 2
        let beamTop = Double(beamNode.position.y) + Double(beamBox.height) / 2

        XCTAssertEqual(beamTop, joistBottom, accuracy: 0.000_001)
    }

    func testFourBySixPostUsesItsRectangularActualCrossSection() throws {
        let beam = member("beam", .beam, CGPoint(x: -60, y: 0), CGPoint(x: 60, y: 0), .twoByTen)
        let post = FramingMember(
            id: "post",
            role: .post,
            start: .zero,
            end: .zero,
            nominalSize: .fourBySix,
            plyCount: 3
        )
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [beam, post])],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )

        let postNode = try XCTUnwrap(root.firstNode(named: "framing.post.post"))
        let postBox = try XCTUnwrap(postNode.geometry as? SCNBox)
        XCTAssertEqual(Double(postBox.width), 3.5 * inchesToMeters, accuracy: 0.000_001)
        XCTAssertEqual(Double(postBox.length), 5.5 * inchesToMeters, accuracy: 0.000_001)
    }

    func testEachBeamUsesOnlyTheJoistDepthAtItsOwnBearingLine() throws {
        let shallowJoist = member(
            "shallow-joist",
            .joist,
            CGPoint(x: -60, y: 0),
            CGPoint(x: 60, y: 0),
            .twoBySix
        )
        let shallowBeam = member(
            "shallow-beam",
            .beam,
            CGPoint(x: 0, y: -60),
            CGPoint(x: 0, y: 60),
            .twoByTen
        )
        let deepJoist = member(
            "deep-joist",
            .joist,
            CGPoint(x: -60, y: 240),
            CGPoint(x: 60, y: 240),
            .twoByTwelve
        )
        let deepBeam = member(
            "deep-beam",
            .beam,
            CGPoint(x: 0, y: 180),
            CGPoint(x: 0, y: 300),
            .twoByTen
        )
        let plan = FramingPlan(
            members: [FramingMemberSet(
                levelId: "",
                members: [shallowJoist, shallowBeam, deepJoist, deepBeam]
            )],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )

        for (joistID, beamID) in [
            ("shallow-joist", "shallow-beam"),
            ("deep-joist", "deep-beam"),
        ] {
            let joistNode = try XCTUnwrap(root.firstNode(named: "framing.joist.\(joistID)"))
            let beamNode = try XCTUnwrap(root.firstNode(named: "framing.beam.\(beamID)"))
            let joistBox = try XCTUnwrap(joistNode.geometry as? SCNBox)
            let beamBox = try XCTUnwrap(beamNode.geometry as? SCNBox)
            let joistBottom = Double(joistNode.position.y) - Double(joistBox.height) / 2
            let beamTop = Double(beamNode.position.y) + Double(beamBox.height) / 2
            XCTAssertEqual(beamTop, joistBottom, accuracy: 0.000_001)
        }
    }

    func testSuppressesSupportAssemblyWhenBeamBottomIsBelowFootingTop() {
        let joist = member("joist", .joist, CGPoint(x: -60, y: 0), CGPoint(x: 60, y: 0), .twoByEight)
        let beam = member("beam", .beam, CGPoint(x: -60, y: 0), CGPoint(x: 60, y: 0), .twoByTen)
        let post = member("post", .post, .zero, .zero, .sixBySix)
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [joist, beam, post])],
            generationSource: .manual
        )

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 0.1,
            vertices: [DeckVertex(id: "pad", position: .zero, footingType: .concretePad)]
        )

        XCTAssertNil(root.firstNode(named: "framing.post.post"))
        XCTAssertNil(root.firstNode(named: "framing.footing.post"))
    }

    func testSkipsNonFiniteMembersAndRejectsNonFiniteProjectionInputs() {
        let invalidJoist = member(
            "invalid-joist",
            .joist,
            .zero,
            CGPoint(x: CGFloat.infinity, y: 0),
            .twoByEight
        )
        let invalidPost = member(
            "invalid-post",
            .post,
            .zero,
            CGPoint(x: CGFloat.nan, y: 0),
            .sixBySix
        )
        let beam = member("beam", .beam, CGPoint(x: -60, y: 0), CGPoint(x: 60, y: 0), .twoByTen)
        let plan = FramingPlan(
            members: [FramingMemberSet(levelId: "", members: [invalidJoist, invalidPost, beam])],
            generationSource: .manual
        )

        let memberRoot = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )
        let invalidScaleRoot = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: Double.nan,
            center: .zero,
            deckElevationMeters: 2,
            vertices: []
        )
        let invalidCenterRoot = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: CGPoint(x: CGFloat.infinity, y: 0),
            deckElevationMeters: 2,
            vertices: []
        )
        let invalidElevationRoot = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: 1,
            center: .zero,
            deckElevationMeters: Float.infinity,
            vertices: []
        )

        XCTAssertNil(memberRoot.firstNode(named: "framing.joist.invalid-joist"))
        XCTAssertNil(memberRoot.firstNode(named: "framing.post.invalid-post"))
        XCTAssertNil(memberRoot.firstNode(named: "framing.footing.invalid-post"))
        XCTAssertTrue(invalidScaleRoot.nodes(withPrefix: "framing.").isEmpty)
        XCTAssertTrue(invalidCenterRoot.nodes(withPrefix: "framing.").isEmpty)
        XCTAssertTrue(invalidElevationRoot.nodes(withPrefix: "framing.").isEmpty)
    }

    private func member(
        _ id: String,
        _ role: FramingRole,
        _ start: CGPoint,
        _ end: CGPoint,
        _ size: LumberSize
    ) -> FramingMember {
        FramingMember(id: id, role: role, start: start, end: end, nominalSize: size)
    }
}

private extension SCNNode {
    func firstNode(named target: String) -> SCNNode? {
        if name == target { return self }
        return childNodes.lazy.compactMap { $0.firstNode(named: target) }.first
    }

    func nodes(withPrefix prefix: String) -> [SCNNode] {
        let own = name?.hasPrefix(prefix) == true ? [self] : []
        return own + childNodes.flatMap { $0.nodes(withPrefix: prefix) }
    }
}
