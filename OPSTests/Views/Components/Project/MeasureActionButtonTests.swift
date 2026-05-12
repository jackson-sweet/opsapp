//
//  MeasureActionButtonTests.swift
//  OPSTests
//
//  Phase G — visibility-gate truth table for `MeasureActionButton`.
//
//  The button renders only when BOTH:
//    1. `feature.measurement.dimensioned_capture` is enabled, AND
//    2. The device capability is `.lidar` or `.visual` (NOT `.noDepth`)
//
//  Six scenarios (flag × capability) exercise the full truth table.
//
//  Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.1 §10.3
//

import XCTest
@testable import OPS

final class MeasureActionButtonTests: XCTestCase {

    // MARK: - Flag ON paths

    func testRendersWhenFlagOnAndLiDAR() {
        XCTAssertTrue(
            MeasureActionButton.shouldRender(flagEnabled: true, capability: .lidar),
            "MEASURE entry must render for LiDAR devices when the flag is on"
        )
    }

    func testRendersWhenFlagOnAndVisualSLAM() {
        XCTAssertTrue(
            MeasureActionButton.shouldRender(flagEnabled: true, capability: .visual),
            "MEASURE entry must render for visual-SLAM-only devices (non-LiDAR iPhones) when the flag is on"
        )
    }

    func testHiddenWhenFlagOnAndNoDepth() {
        XCTAssertFalse(
            MeasureActionButton.shouldRender(flagEnabled: true, capability: .noDepth),
            "MEASURE entry must stay hidden on devices without AR support, even when the flag is on"
        )
    }

    // MARK: - Flag OFF paths — should always hide regardless of capability

    func testHiddenWhenFlagOffAndLiDAR() {
        XCTAssertFalse(
            MeasureActionButton.shouldRender(flagEnabled: false, capability: .lidar),
            "Feature flag must override device capability — LiDAR devices stay hidden when flag is off"
        )
    }

    func testHiddenWhenFlagOffAndVisualSLAM() {
        XCTAssertFalse(
            MeasureActionButton.shouldRender(flagEnabled: false, capability: .visual),
            "Feature flag must override device capability — visual-SLAM devices stay hidden when flag is off"
        )
    }

    func testHiddenWhenFlagOffAndNoDepth() {
        XCTAssertFalse(
            MeasureActionButton.shouldRender(flagEnabled: false, capability: .noDepth),
            "Both gates closed → entry hidden"
        )
    }
}
