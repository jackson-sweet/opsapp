//
//  CaptureAssetWriterTests.swift
//  OPSTests
//
//  Host-runnable persistence tests — only covers the sidecar JSON path, which
//  is pure data and works without a capture device. HEIC+disparity writing
//  requires real AVCapturePhoto / AVDepthData; covered by hardware integration
//  tests gated on `requiresLiDAR`.
//

import XCTest
@testable import OPS

final class CaptureAssetWriterTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureAssetWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_sidecar_round_trips_from_disk() throws {
        let snapshot = ARKitSnapshot(
            meshAnchors: [
                ARKitSnapshot.MeshAnchorPayload(
                    identifier: UUID(),
                    transform: Array(repeating: 1, count: 16),
                    vertexCount: 512,
                    faceCount: 1024,
                    classifications: ["wall": 400, "window": 112]
                )
            ],
            cameraIntrinsics: DimensionsData.Intrinsics(
                fx: 1593.4, fy: 1593.4, cx: 1015.5, cy: 762.0,
                imageWidth: 4032, imageHeight: 3024
            ),
            devicePose: Array(repeating: 0.5, count: 16),
            timestamp: Date(timeIntervalSince1970: 1_715_000_000)
        )

        let url = tempDir.appendingPathComponent("sidecar.json")
        try CaptureAssetWriter.writeSidecar(snapshot: snapshot, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let read = try Data(contentsOf: url)
        let decoded = try ARKitSnapshot.jsonDecoder.decode(ARKitSnapshot.self, from: read)
        XCTAssertEqual(decoded, snapshot)
    }

    func test_sidecar_write_is_atomic_overwrite() throws {
        let url = tempDir.appendingPathComponent("sidecar.json")

        // Initial snapshot
        let first = ARKitSnapshot(
            meshAnchors: [],
            cameraIntrinsics: DimensionsData.Intrinsics(fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1),
            devicePose: Array(repeating: 0, count: 16),
            timestamp: Date(timeIntervalSince1970: 0)
        )
        try CaptureAssetWriter.writeSidecar(snapshot: first, to: url)

        // Overwrite with different content
        let second = ARKitSnapshot(
            meshAnchors: [],
            cameraIntrinsics: DimensionsData.Intrinsics(fx: 99, fy: 99, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1),
            devicePose: Array(repeating: 0, count: 16),
            timestamp: Date(timeIntervalSince1970: 0)
        )
        try CaptureAssetWriter.writeSidecar(snapshot: second, to: url)

        let decoded = try ARKitSnapshot.jsonDecoder
            .decode(ARKitSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.cameraIntrinsics.fx, 99)
    }
}
