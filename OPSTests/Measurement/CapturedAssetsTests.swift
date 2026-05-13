//
//  CapturedAssetsTests.swift
//  OPSTests
//
//  Verifies the on-disk asset descriptor + sidecar JSON shape. No AR session
//  is required — these are pure data round-trip tests.
//

import XCTest
@testable import OPS

final class CapturedAssetsTests: XCTestCase {

    // MARK: - ARKitSnapshot Codable round-trip

    func test_arkit_snapshot_round_trips_through_json() throws {
        let snapshot = ARKitSnapshot(
            meshAnchors: [
                ARKitSnapshot.MeshAnchorPayload(
                    identifier: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    transform: Array(repeating: 0, count: 16),
                    vertexCount: 1024,
                    faceCount: 2048,
                    classifications: ["wall": 800, "window": 200]
                )
            ],
            cameraIntrinsics: DimensionsData.Intrinsics(
                fx: 1593.4, fy: 1593.4, cx: 1015.5, cy: 762.0,
                imageWidth: 4032, imageHeight: 3024
            ),
            devicePose: Array(repeating: 1, count: 16),
            timestamp: Date(timeIntervalSince1970: 1_715_000_000)
        )

        let encoded = try ARKitSnapshot.jsonEncoder.encode(snapshot)
        let decoded = try ARKitSnapshot.jsonDecoder.decode(ARKitSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
    }

    func test_sidecar_json_uses_snake_case_keys() throws {
        let snapshot = ARKitSnapshot(
            meshAnchors: [],
            cameraIntrinsics: DimensionsData.Intrinsics(
                fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1
            ),
            devicePose: Array(repeating: 0, count: 16),
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let data = try ARKitSnapshot.jsonEncoder.encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"mesh_anchors\""), "expected snake_case key, got: \(json)")
        XCTAssertTrue(json.contains("\"camera_intrinsics\""))
        XCTAssertTrue(json.contains("\"device_pose\""))
    }

    func test_mesh_anchor_transform_must_have_16_elements() {
        // 4x4 column-major matrix. Anything else is meaningless.
        let valid = ARKitSnapshot.MeshAnchorPayload(
            identifier: UUID(), transform: Array(repeating: 0, count: 16),
            vertexCount: 0, faceCount: 0, classifications: [:]
        )
        XCTAssertEqual(valid.transform.count, 16)
    }

    // MARK: - CapturedAssets URL conventions

    func test_captured_assets_in_a_directory_share_uuid_basename() {
        let captureID = UUID()
        let directory = URL(fileURLWithPath: "/tmp/test-captures")

        let assets = CapturedAssets.in(directory: directory, captureID: captureID)

        XCTAssertEqual(assets.heicURL.lastPathComponent, "\(captureID.uuidString).heic")
        XCTAssertEqual(assets.depthURL?.lastPathComponent, "\(captureID.uuidString).depth.fp32")
        XCTAssertEqual(assets.sidecarURL.lastPathComponent, "\(captureID.uuidString).metadata.json")
    }

    func test_captured_assets_default_directory_is_inside_documents() {
        let directory = CapturedAssets.defaultDirectory()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        XCTAssertTrue(
            directory.path.hasPrefix(documents.path),
            "default directory \(directory.path) is not under documents \(documents.path)"
        )
        XCTAssertEqual(directory.lastPathComponent, "lidar-captures")
    }
}
