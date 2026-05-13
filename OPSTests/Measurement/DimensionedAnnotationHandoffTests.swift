//
//  DimensionedAnnotationHandoffTests.swift
//  OPSTests
//
//  Focused seam tests for the LiDAR capture -> annotation handoff.
//

import XCTest
import simd
@testable import OPS

final class DimensionedAnnotationHandoffTests: XCTestCase {

    private let intrinsics = DimensionsData.Intrinsics(
        fx: 1000, fy: 1000, cx: 500, cy: 500,
        imageWidth: 1000, imageHeight: 1000
    )

    private let identityPose: [Float] = [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    ]

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DimensionedAnnotationHandoffTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_lidarCaptureWithDetectedOpening_passesDepthAnchorsAndOpeningsIntoAnnotation() throws {
        var faces = quad(
            width: 0.6,
            height: 1.2,
            centre: SIMD3<Float>(0, 0, 2),
            classification: .window
        )
        faces += quad(
            width: 3.0,
            height: 2.5,
            centre: SIMD3<Float>(0, 0, 1.95),
            classification: .wall
        )
        let assets = try makeAssets(faces: faces, includesDepth: true)

        let handoff = DimensionedAnnotationHandoffBuilder.build(
            assets: assets,
            capability: .lidar
        )

        XCTAssertEqual(handoff.capability, .lidar)
        XCTAssertNotNil(handoff.preloadedDepthMap)
        XCTAssertEqual(handoff.preloadedDepthMap?.width, 768)
        XCTAssertEqual(handoff.preloadedDepthMap?.height, 2)
        XCTAssertNotNil(handoff.anchors)
        XCTAssertEqual(handoff.detectedOpenings.count, 1)
        XCTAssertTrue(handoff.hasAuto)
    }

    func test_lidarCaptureWithNoDetectedOpening_stillBuildsManualAnnotationHandoff() throws {
        let faces = quad(
            width: 3.0,
            height: 2.5,
            centre: SIMD3<Float>(0, 0, 2),
            classification: .wall
        )
        let assets = try makeAssets(faces: faces, includesDepth: true)

        let handoff = DimensionedAnnotationHandoffBuilder.build(
            assets: assets,
            capability: .lidar
        )

        XCTAssertEqual(handoff.assets, assets)
        XCTAssertEqual(handoff.capability, .lidar)
        XCTAssertNotNil(handoff.preloadedDepthMap)
        XCTAssertNotNil(handoff.anchors)
        XCTAssertTrue(handoff.detectedOpenings.isEmpty)
        XCTAssertFalse(handoff.hasAuto)
        XCTAssertTrue(handoff.hasCalibrate)
    }

    func test_visualCaptureDoesNotLoadDepthOrRunAutoDetect() throws {
        let faces = quad(
            width: 0.6,
            height: 1.2,
            centre: SIMD3<Float>(0, 0, 2),
            classification: .window
        )
        let assets = try makeAssets(faces: faces, includesDepth: false)

        let handoff = DimensionedAnnotationHandoffBuilder.build(
            assets: assets,
            capability: .visual
        )

        XCTAssertEqual(handoff.capability, .visual)
        XCTAssertNil(handoff.preloadedDepthMap)
        XCTAssertNil(handoff.anchors)
        XCTAssertTrue(handoff.detectedOpenings.isEmpty)
        XCTAssertFalse(handoff.hasAuto)
        XCTAssertTrue(handoff.hasCalibrate)
        XCTAssertEqual(handoff.initialCalibration.method, .none)
    }

    private func makeAssets(
        faces: [ARKitSnapshot.MeshFacePayload],
        includesDepth: Bool
    ) throws -> CapturedAssets {
        let captureID = UUID()
        let urls = CapturedAssets.in(
            directory: tempDir,
            captureID: captureID,
            includesDepthAsset: includesDepth
        )
        try Data([0x01]).write(to: urls.heicURL)
        if let depthURL = urls.depthURL {
            try writeDepthFixture(to: depthURL)
        }
        let snapshot = ARKitSnapshot(
            meshAnchors: [],
            meshFaces: faces,
            cameraIntrinsics: intrinsics,
            devicePose: identityPose,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        try CaptureAssetWriter.writeSidecar(snapshot: snapshot, to: urls.sidecarURL)
        return CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: intrinsics,
            arkitSnapshot: snapshot,
            captureID: captureID,
            captureFinishedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func writeDepthFixture(to url: URL) throws {
        let values = Array(repeating: Float(2), count: 768 * 2)
        let data = values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try data.write(to: url)
    }

    private func quad(
        width w: Float,
        height h: Float,
        centre c: SIMD3<Float>,
        classification cls: MeshFaceSnapshot.Classification,
        normal n: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    ) -> [ARKitSnapshot.MeshFacePayload] {
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(up, n))
        let down = simd_normalize(simd_cross(n, right))
        let hw = w / 2
        let hh = h / 2
        let v00 = c - hw * right - hh * down
        let v10 = c + hw * right - hh * down
        let v11 = c + hw * right + hh * down
        let v01 = c - hw * right + hh * down
        return [
            ARKitSnapshot.MeshFacePayload(v0: v00, v1: v10, v2: v11, classification: cls),
            ARKitSnapshot.MeshFacePayload(v0: v00, v1: v11, v2: v01, classification: cls)
        ]
    }
}
