//
//  CapabilityDetectionTests.swift
//  OPSTests
//
//  Pure detection logic — no AR session, no AVCapture. Verifies the
//  capability-mapping truth table from
//  ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.8.
//

import XCTest
@testable import OPS

final class CapabilityDetectionTests: XCTestCase {

    func test_lidar_with_ar_and_mesh_yields_lidar_with_autoDetect() {
        let result = CaptureCapability.detect(
            lidarSupported: true, arSupported: true, meshSupported: true
        )
        XCTAssertEqual(result.capability, .lidar)
        XCTAssertTrue(result.supportsAutoDetect)
    }

    func test_lidar_with_ar_no_mesh_yields_lidar_without_autoDetect() {
        let result = CaptureCapability.detect(
            lidarSupported: true, arSupported: true, meshSupported: false
        )
        XCTAssertEqual(result.capability, .lidar)
        XCTAssertFalse(result.supportsAutoDetect)
    }

    func test_no_lidar_with_ar_yields_visual() {
        let result = CaptureCapability.detect(
            lidarSupported: false, arSupported: true, meshSupported: false
        )
        XCTAssertEqual(result.capability, .visual)
        XCTAssertFalse(result.supportsAutoDetect)
    }

    func test_no_lidar_with_ar_and_mesh_still_visual() {
        // Mesh-with-classification is meaningless without LiDAR — visual SLAM
        // can detect planes but cannot classify rectangular openings reliably.
        let result = CaptureCapability.detect(
            lidarSupported: false, arSupported: true, meshSupported: true
        )
        XCTAssertEqual(result.capability, .visual)
        XCTAssertFalse(result.supportsAutoDetect)
    }

    func test_no_ar_yields_noDepth_regardless_of_other_flags() {
        let withLidarFlag = CaptureCapability.detect(
            lidarSupported: true, arSupported: false, meshSupported: false
        )
        XCTAssertEqual(withLidarFlag.capability, .noDepth)
        XCTAssertFalse(withLidarFlag.supportsAutoDetect)

        let bareDevice = CaptureCapability.detect(
            lidarSupported: false, arSupported: false, meshSupported: false
        )
        XCTAssertEqual(bareDevice.capability, .noDepth)
        XCTAssertFalse(bareDevice.supportsAutoDetect)
    }

    func test_live_detection_returns_a_valid_capability() {
        // On real hardware this will report the actual capability;
        // on CI/simulator it falls back to .visual or .noDepth. Either way
        // the live detect() must return one of the three documented states.
        let result = CaptureCapability.detect()
        XCTAssertTrue(
            [CaptureCapability.lidar, .visual, .noDepth].contains(result.capability),
            "detect() returned unexpected capability \(result.capability)"
        )
    }
}
