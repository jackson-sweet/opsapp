//
//  CapabilityChipTests.swift
//  OPSTests
//
//  Verifies the spec §3.6 / §3.8 capability-chip rendering surface — the
//  exact copy strings and the earth-tone color mapping (no emoji per OPS
//  brand). Functions as a snapshot test in spirit without requiring the
//  SnapshotTesting SPM dependency (not currently linked into OPSTests).
//

import XCTest
import SwiftUI
@testable import OPS

final class CapabilityChipTests: XCTestCase {

    // MARK: - Copy

    func test_lidar_displays_uppercase_LIDAR() {
        let chip = CapabilityChip(capability: .lidar)
        XCTAssertEqual(chip.displayLabel, "LIDAR")
    }

    func test_visual_displays_uppercase_VISUAL() {
        let chip = CapabilityChip(capability: .visual)
        XCTAssertEqual(chip.displayLabel, "VISUAL")
    }

    func test_noDepth_displays_NO_DEPTH_with_space() {
        let chip = CapabilityChip(capability: .noDepth)
        // The spec table is explicit — `NO DEPTH` with a space, not `NODEPTH`.
        XCTAssertEqual(chip.displayLabel, "NO DEPTH")
    }

    // MARK: - Foreground color mapping (spec §3.6 chip color column)

    func test_lidar_foreground_is_olive() {
        let chip = CapabilityChip(capability: .lidar)
        XCTAssertEqual(chip.foreground, OPSStyle.Colors.olive)
    }

    func test_visual_foreground_is_tan() {
        let chip = CapabilityChip(capability: .visual)
        XCTAssertEqual(chip.foreground, OPSStyle.Colors.tan)
    }

    func test_noDepth_foreground_is_textMute() {
        let chip = CapabilityChip(capability: .noDepth)
        XCTAssertEqual(chip.foreground, OPSStyle.Colors.textMute)
    }

    // MARK: - Border + background — earth-tone soft fill pattern

    func test_lidar_uses_olive_soft_fill_and_olive_line_border() {
        let chip = CapabilityChip(capability: .lidar)
        XCTAssertEqual(chip.background, OPSStyle.Colors.oliveSoft)
        XCTAssertEqual(chip.border, OPSStyle.Colors.oliveLine)
    }

    func test_visual_uses_tan_soft_fill_and_tan_line_border() {
        let chip = CapabilityChip(capability: .visual)
        XCTAssertEqual(chip.background, OPSStyle.Colors.tanSoft)
        XCTAssertEqual(chip.border, OPSStyle.Colors.tanLine)
    }

    func test_noDepth_uses_neutral_line_border() {
        let chip = CapabilityChip(capability: .noDepth)
        XCTAssertEqual(chip.border, OPSStyle.Colors.line)
    }
}
