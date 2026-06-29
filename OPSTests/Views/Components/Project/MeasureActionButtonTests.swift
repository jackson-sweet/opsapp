//
//  MeasureActionButtonTests.swift
//  OPSTests
//
//  Phase G — visibility-gate truth table for `MeasureActionButton`.
//
//  Release builds fail closed when `feature.measurement.dimensioned_capture`
//  is off. Debug/dev builds keep the entry visible so the hardware and flag
//  state can be inspected without a remote flag flip.
//
//  Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.1 §10.3
//

import XCTest
@testable import OPS

final class MeasureActionButtonTests: XCTestCase {

    // MARK: - Flag ON paths

    func testRendersWhenFlagOnAndLiDAR() {
        XCTAssertTrue(
            MeasureActionButton.shouldRender(
                flagEnabled: true,
                capability: .lidar,
                developerMode: false
            ),
            "MEASURE entry must render for LiDAR devices when the flag is on"
        )
    }

    func testRendersWhenFlagOnAndVisualSLAM() {
        XCTAssertTrue(
            MeasureActionButton.shouldRender(
                flagEnabled: true,
                capability: .visual,
                developerMode: false
            ),
            "MEASURE entry must render for visual-SLAM-only devices (non-LiDAR iPhones) when the flag is on"
        )
    }

    func testFlagOnAndNoDepthShowsHardwareLimitation() {
        XCTAssertTrue(
            MeasureActionButton.shouldRender(
                flagEnabled: true,
                capability: .noDepth,
                developerMode: false
            ),
            "MEASURE entry should explain unsupported hardware instead of disappearing when the rollout flag is on"
        )
        XCTAssertEqual(
            MeasureActionButton.entryState(
                flagEnabled: true,
                capability: .noDepth,
                developerMode: false
            ),
            .unavailable(.hardwareUnsupported)
        )
    }

    // MARK: - Flag OFF release paths — fail closed

    func testHiddenWhenFlagOffAndLiDAR() {
        XCTAssertFalse(
            MeasureActionButton.shouldRender(
                flagEnabled: false,
                capability: .lidar,
                developerMode: false
            ),
            "Release builds must stay hidden when the remote flag is off"
        )
    }

    func testHiddenWhenFlagOffAndVisualSLAM() {
        XCTAssertFalse(
            MeasureActionButton.shouldRender(
                flagEnabled: false,
                capability: .visual,
                developerMode: false
            ),
            "Release builds must stay hidden when the remote flag is off"
        )
    }

    func testHiddenWhenFlagOffAndNoDepth() {
        XCTAssertFalse(
            MeasureActionButton.shouldRender(
                flagEnabled: false,
                capability: .noDepth,
                developerMode: false
            ),
            "Release builds must stay hidden when the remote flag is off"
        )
    }

    // MARK: - Flag OFF debug paths — obvious test path

    func testDebugFlagOffLiDARRendersWithDeveloperOverride() {
        XCTAssertEqual(
            MeasureActionButton.entryState(
                flagEnabled: false,
                capability: .lidar,
                developerMode: true
            ),
            .capture(developerFlagOverride: true)
        )
    }

    func testDebugFlagOffVisualRendersWithDeveloperOverride() {
        XCTAssertEqual(
            MeasureActionButton.entryState(
                flagEnabled: false,
                capability: .visual,
                developerMode: true
            ),
            .capture(developerFlagOverride: true)
        )
    }

    func testDebugFlagOffNoDepthShowsCombinedLimitation() {
        XCTAssertEqual(
            MeasureActionButton.entryState(
                flagEnabled: false,
                capability: .noDepth,
                developerMode: true
            ),
            .unavailable(.featureFlagAndHardware)
        )
    }
}
