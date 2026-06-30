import CoreGraphics
import SceneKit
import XCTest
@testable import DeckKit

final class DeckScenePhase6RenderTests: XCTestCase {
    func testPatternMeshIsSingleSurfaceGeometry() throws {
        let spec = SurfacePatternSpec(
            surfaceId: "surface-main",
            pattern: .diagonal,
            boardAngleDegrees: 45,
            pictureFrameCourses: 0
        )

        let geometry = try XCTUnwrap(DeckPatternMeshBuilder.surfaceMesh(
            polygon: Self.rectangle,
            scaleFactor: 1,
            spec: spec,
            boardWidthInches: 5.5,
            yHeightMeters: 1.2
        ))

        XCTAssertEqual(geometry.name, "deck_pattern.diagonal")
        XCTAssertEqual(geometry.elements.count, 1)
        XCTAssertEqual(geometry.materials.count, 1)
        XCTAssertEqual(geometry.firstMaterial?.name, "deck_pattern.diagonal.texture")
    }

    func testPatternNodeDoesNotGeneratePerBoardChildren() throws {
        let spec = SurfacePatternSpec(
            surfaceId: "surface-main",
            pattern: .pictureFrame,
            boardAngleDegrees: 0,
            pictureFrameCourses: 2
        )

        let node = try XCTUnwrap(DeckPatternMeshBuilder.surfaceNode(
            polygon: Self.rectangle,
            scaleFactor: 1,
            spec: spec,
            boardWidthInches: 5.5,
            yHeightMeters: 0.9
        ))

        XCTAssertEqual(node.name, "deck_pattern.surface.surface-main")
        XCTAssertEqual(node.childNodes.count, 0)
        XCTAssertEqual(node.geometry?.name, "deck_pattern.picture_frame")
        XCTAssertEqual(node.geometry?.firstMaterial?.name, "deck_pattern.picture_frame.texture")
    }

    func testOverheadNodesShareRepeatedMemberGeometry() throws {
        let structure = OverheadStructure(
            id: "pergola-1",
            kind: .pergola,
            footprint: Self.rectangle,
            framing: Self.repeatedRafters(count: 10),
            shadePercent: 45
        )

        let root = OverheadSceneNodes.nodes(
            for: structure,
            scaleFactor: 1,
            center: CGPoint(x: 96, y: 72),
            deckElevationMeters: 1.2
        )
        let rafters = root.allNodes(namedPrefix: "overhead.member.joist.")

        XCTAssertEqual(root.name, DeckSceneLayerToggle.overheadLayerNodeName)
        XCTAssertEqual(rafters.count, 10)
        let firstGeometry = try XCTUnwrap(rafters.first?.geometry)
        XCTAssertTrue(rafters.dropFirst().allSatisfy { $0.geometry === firstGeometry })
    }

    func testLayerToggleHidesOverheadOnly() throws {
        let sceneRoot = SCNNode()
        let decking = SCNNode()
        decking.name = FramingLayer.decking.layerNodeName
        let overhead = SCNNode()
        overhead.name = DeckSceneLayerToggle.overheadLayerNodeName
        sceneRoot.addChildNode(decking)
        sceneRoot.addChildNode(overhead)

        DeckSceneLayerToggle.apply(overheadVisible: false, to: sceneRoot)

        XCTAssertFalse(decking.isHidden)
        XCTAssertTrue(overhead.isHidden)

        DeckSceneLayerToggle.apply(overheadVisible: true, to: sceneRoot)

        XCTAssertFalse(decking.isHidden)
        XCTAssertFalse(overhead.isHidden)
    }

    func testSnapshotHarnessAttachesPatternAndOverheadScene() throws {
        let root = SCNNode()
        let patternSpec = SurfacePatternSpec(
            surfaceId: "surface-main",
            pattern: .diagonal,
            boardAngleDegrees: 45,
            pictureFrameCourses: 1
        )
        let surface = try XCTUnwrap(DeckPatternMeshBuilder.surfaceNode(
            polygon: Self.rectangleMeters,
            scaleFactor: 1,
            spec: patternSpec,
            boardWidthInches: 5.5,
            yHeightMeters: 0.9
        ))
        root.addChildNode(surface)

        let overhead = OverheadSceneNodes.nodes(
            for: Self.snapshotOverheadStructure,
            scaleFactor: 1,
            center: CGPoint(x: 96, y: 72),
            deckElevationMeters: 0.9
        )
        root.addChildNode(overhead)

        XCTAssertEqual(root.childNode(withName: "deck_pattern.surface.surface-main", recursively: true), surface)
        XCTAssertEqual(overhead.childNodes.count, 12)

        #if canImport(Metal)
        try renderAndAttachPhase6Scene(root: root)
        #endif
    }

    private static let rectangle = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 192, y: 0),
        CGPoint(x: 192, y: 144),
        CGPoint(x: 0, y: 144),
    ]

    private static let rectangleMeters = rectangle.map {
        CGPoint(
            x: (Double($0.x) - 96) / 39.3701,
            y: (Double($0.y) - 72) / 39.3701
        )
    }

    private static let snapshotOverheadStructure = OverheadStructure(
        id: "pergola-snapshot",
        kind: .pergola,
        footprint: rectangle,
        framing: snapshotOverheadMembers(),
        shadePercent: 40
    )

    private static func repeatedRafters(count: Int) -> [FramingMember] {
        (0..<count).map { index in
            FramingMember(
                id: "rafter-\(index)",
                role: .joist,
                start: CGPoint(x: 0, y: Double(index) * 12),
                end: CGPoint(x: 192, y: Double(index) * 12),
                nominalSize: .twoBySix,
                plyCount: 1,
                species: .douglasFirLarch,
                grade: .no2
            )
        }
    }

    private static func snapshotOverheadMembers() -> [FramingMember] {
        let posts = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 192, y: 0),
            CGPoint(x: 192, y: 144),
            CGPoint(x: 0, y: 144),
        ].enumerated().map { index, point in
            FramingMember(
                id: "post-\(index)",
                role: .post,
                start: point,
                end: point,
                nominalSize: .sixBySix,
                plyCount: 1,
                species: .douglasFirLarch,
                grade: .no2
            )
        }

        let beams = [
            ("beam-front", CGPoint(x: 0, y: 0), CGPoint(x: 192, y: 0)),
            ("beam-back", CGPoint(x: 0, y: 144), CGPoint(x: 192, y: 144)),
            ("beam-left", CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 144)),
            ("beam-right", CGPoint(x: 192, y: 0), CGPoint(x: 192, y: 144)),
        ].map { id, start, end in
            FramingMember(
                id: id,
                role: .beam,
                start: start,
                end: end,
                nominalSize: .twoByTen,
                plyCount: 2,
                species: .douglasFirLarch,
                grade: .no2
            )
        }

        let joists = (0..<4).map { index in
            FramingMember(
                id: "joist-\(index)",
                role: .joist,
                start: CGPoint(x: 24 + index * 48, y: 0),
                end: CGPoint(x: 24 + index * 48, y: 144),
                nominalSize: .twoBySix,
                plyCount: 1,
                species: .douglasFirLarch,
                grade: .no2
            )
        }

        return posts + beams + joists
    }
}

private extension SCNNode {
    func allNodes(namedPrefix prefix: String) -> [SCNNode] {
        var matches: [SCNNode] = []
        if let name, name.hasPrefix(prefix) {
            matches.append(self)
        }
        for child in childNodes {
            matches.append(contentsOf: child.allNodes(namedPrefix: prefix))
        }
        return matches
    }
}

#if canImport(Metal)
import Metal

private func renderAndAttachPhase6Scene(root: SCNNode) throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw XCTSkip("No Metal device available for SceneKit Phase 6 snapshot")
    }

    let scene = SCNScene()
    scene.rootNode.addChildNode(root)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 500
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    scene.rootNode.addChildNode(ambientNode)

    let directional = SCNLight()
    directional.type = .directional
    directional.intensity = 900
    let directionalNode = SCNNode()
    directionalNode.light = directional
    directionalNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
    scene.rootNode.addChildNode(directionalNode)

    let camera = SCNCamera()
    camera.fieldOfView = 55
    camera.zNear = 0.01
    camera.zFar = 200
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(4, 3.2, 5)
    cameraNode.look(at: SCNVector3(0, 1.8, 0))
    scene.rootNode.addChildNode(cameraNode)

    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = cameraNode
    renderer.autoenablesDefaultLighting = false

    let image = renderer.snapshot(
        atTime: 0,
        with: CGSize(width: 640, height: 420),
        antialiasingMode: .multisampling4X
    )

    #if canImport(UIKit)
    let data = try XCTUnwrap(image.pngData())
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
    #elseif canImport(AppKit)
    let data = try XCTUnwrap(image.tiffRepresentation)
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.tiff")
    #endif
    XCTAssertGreaterThan(data.count, 1_000)
    attachment.name = "phase-6-pattern-overhead-scene"
    attachment.lifetime = .keepAlways
    XCTContext.runActivity(named: "Phase 6 Pattern And Overhead Snapshot") { activity in
        activity.add(attachment)
    }
}
#endif
