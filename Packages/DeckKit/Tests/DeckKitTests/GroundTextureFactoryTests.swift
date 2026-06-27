import CoreGraphics
import SceneKit
import XCTest
@testable import DeckKit

final class GroundTextureFactoryTests: XCTestCase {
    func test_groundMaterial_perCover_distinct() {
        let grass = GroundTextureFactory.material(for: .grass, spanMeters: 18)
        let gravel = GroundTextureFactory.material(for: .gravel, spanMeters: 18)

        XCTAssertNotEqual(grass.name, gravel.name)
        XCTAssertEqual(grass.diffuse.wrapS, .repeat)
        XCTAssertEqual(grass.diffuse.wrapT, .repeat)
        XCTAssertEqual(gravel.diffuse.wrapS, .repeat)
        XCTAssertEqual(gravel.diffuse.wrapT, .repeat)
        XCTAssertNotEqual(
            String(describing: grass.diffuse.contents),
            String(describing: gravel.diffuse.contents)
        )
    }

    func test_groundMaterial_concrete_isFlatTint() {
        let concrete = GroundTextureFactory.material(for: .concrete, spanMeters: 18)

        XCTAssertEqual(concrete.name, "ground.concrete.flat")
        XCTAssertNotEqual(concrete.diffuse.wrapS, .repeat)
        XCTAssertNotEqual(concrete.diffuse.wrapT, .repeat)
        XCTAssertNotNil(concrete.diffuse.contents)
    }

    func test_dominantCover_defaultsGrassWhenNoTerrain() {
        XCTAssertEqual(GroundTextureFactory.dominantCover(in: nil), .grass)
        XCTAssertEqual(GroundTextureFactory.dominantCover(in: TerrainModel()), .grass)
    }

    func test_dominantCover_usesLargestGroundZone() {
        let smallDirt = GroundZone(
            polygon: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 12, y: 0),
                CGPoint(x: 12, y: 12),
                CGPoint(x: 0, y: 12),
            ],
            cover: .dirt
        )
        let largePavers = GroundZone(
            polygon: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 40, y: 0),
                CGPoint(x: 40, y: 30),
                CGPoint(x: 0, y: 30),
            ],
            cover: .pavers
        )

        XCTAssertEqual(
            GroundTextureFactory.dominantCover(in: TerrainModel(groundCover: [smallDirt, largePavers])),
            .pavers
        )
    }

    func test_snapshot_groundCover_attaches() throws {
        let material = GroundTextureFactory.material(for: .gravel, spanMeters: 18)
        XCTAssertEqual(material.name, "ground.gravel.texture")

        #if canImport(Metal)
        try renderAndAttachGround(material: material)
        #endif
    }
}

#if canImport(Metal)
import Metal

private func renderAndAttachGround(material: SCNMaterial) throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw XCTSkip("No Metal device available for SceneKit ground snapshot")
    }

    let scene = SCNScene()
    let plane = SCNPlane(width: 8, height: 8)
    plane.firstMaterial = material
    let ground = SCNNode(geometry: plane)
    ground.eulerAngles.x = -.pi / 2
    scene.rootNode.addChildNode(ground)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 650
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    scene.rootNode.addChildNode(ambientNode)

    let camera = SCNCamera()
    camera.fieldOfView = 45
    camera.zNear = 0.01
    camera.zFar = 100
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 5, 6)
    cameraNode.look(at: SCNVector3(0, 0, 0))
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
    attachment.name = "ground-cover-gravel"
    attachment.lifetime = .keepAlways
    XCTContext.runActivity(named: "Ground Cover Snapshot") { activity in
        activity.add(attachment)
    }
}
#endif
