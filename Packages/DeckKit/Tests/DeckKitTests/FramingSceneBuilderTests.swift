import CoreGraphics
import SceneKit
import XCTest
@testable import DeckKit

final class FramingSceneBuilderTests: XCTestCase {
    func test_buildFramingNode_layerGroupsPresent() throws {
        let data = try Self.rectangleData()
        let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: data.effectiveScaleFactor,
            center: Self.center(of: data.vertices.map(\.position)),
            deckElevationMeters: Self.feetToMeters(Float(data.renderElevationFeetSingleLevel))
        )

        for layerName in ["layer.joists", "layer.beams", "layer.posts", "layer.rim"] {
            let layer = try XCTUnwrap(root.childNode(withName: layerName, recursively: false))
            XCTAssertGreaterThan(layer.childNodes.count, 0, "\(layerName) should contain rendered members")
        }
    }

    func test_joistCount_matchesPlan() throws {
        let data = try Self.rectangleData()
        let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())
        let expectedJoists = plan.members.flatMap(\.members).filter { $0.role == .joist }.count

        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: data.effectiveScaleFactor,
            center: Self.center(of: data.vertices.map(\.position)),
            deckElevationMeters: Self.feetToMeters(Float(data.renderElevationFeetSingleLevel))
        )

        let joistLayer = try XCTUnwrap(root.childNode(withName: "layer.joists", recursively: false))
        XCTAssertEqual(joistLayer.childNodes.count, expectedJoists)
    }

    func test_layerToggle_hidesGroup() throws {
        let data = try Self.rectangleData()
        let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())
        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: data.effectiveScaleFactor,
            center: Self.center(of: data.vertices.map(\.position)),
            deckElevationMeters: Self.feetToMeters(Float(data.renderElevationFeetSingleLevel))
        )

        let deckingLayer = SCNNode()
        deckingLayer.name = "layer.decking"
        deckingLayer.addChildNode(SCNNode())
        root.addChildNode(deckingLayer)

        FramingLayerToggle.apply([.decking, .posts], to: root)

        XCTAssertTrue(try XCTUnwrap(root.childNode(withName: "layer.joists", recursively: false)).isHidden)
        XCTAssertFalse(try XCTUnwrap(root.childNode(withName: "layer.posts", recursively: false)).isHidden)
        XCTAssertFalse(try XCTUnwrap(root.childNode(withName: "layer.decking", recursively: false)).isHidden)
    }

    func test_snapshotHarness_rendersNonEmptyScene() throws {
        let data = try Self.rectangleData()
        let plan = AutoFramingEngine.generate(from: data, preset: LoadPreset())
        let root = FramingSceneBuilder.buildFramingNode(
            framing: plan,
            levelId: "",
            scaleFactor: data.effectiveScaleFactor,
            center: Self.center(of: data.vertices.map(\.position)),
            deckElevationMeters: Self.feetToMeters(Float(data.renderElevationFeetSingleLevel))
        )

        XCTAssertGreaterThan(root.flattenedChildCount, 20)

        #if canImport(Metal)
        try renderAndAttach(root: root)
        #endif
    }

    private static func rectangleData() throws -> DeckDrawingData {
        var data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        data.overallElevation = 3
        return data
    }

    private static func center(of points: [CGPoint]) -> CGPoint {
        guard let first = points.first else { return .zero }
        let bounds = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private static func feetToMeters(_ feet: Float) -> Float {
        feet * 0.3048
    }
}

private extension SCNNode {
    var flattenedChildCount: Int {
        childNodes.reduce(childNodes.count) { total, child in
            total + child.flattenedChildCount
        }
    }
}

#if canImport(Metal)
import Metal

private func renderAndAttach(root: SCNNode) throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw XCTSkip("No Metal device available for SceneKit snapshot")
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
    cameraNode.position = SCNVector3(3, 2.2, 4)
    cameraNode.look(at: SCNVector3(0, 0.6, 0))
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
    attachment.name = "framing-scene-builder"
    attachment.lifetime = .keepAlways
    XCTContext.runActivity(named: "Framing Scene Snapshot") { activity in
        activity.add(attachment)
    }
}
#endif
