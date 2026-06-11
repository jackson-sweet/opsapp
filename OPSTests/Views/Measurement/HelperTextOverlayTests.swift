//
//  HelperTextOverlayTests.swift
//  OPSTests
//
//  Verifies the progressive helper states from spec §5.1 — both the
//  literal copy (the spec table is canonical) and the foreground color
//  ladder. Acts as a copy-regression guard so future edits to the spec
//  flow through this test rather than silently drifting in the UI.
//

import XCTest
import SwiftUI
@testable import OPS

final class HelperTextOverlayTests: XCTestCase {

    typealias S = HelperTextOverlay.HelperState

    // MARK: - Copy (spec §5.1 helper-text table)

    func test_initializing_copy_matches_spec() {
        XCTAssertEqual(S.initializing.copy, "INITIALIZING …")
    }

    func test_aim_at_opening_copy_matches_spec() {
        XCTAssertEqual(S.aimAtOpening.copy, "AIM AT OPENING")
    }

    func test_searching_copy_matches_spec() {
        XCTAssertEqual(S.searching.copy, "SEARCHING")
    }

    func test_wall_detected_copy_matches_spec() {
        XCTAssertEqual(S.wallDetected.copy, "WALL DETECTED")
    }

    func test_opening_locked_copy_matches_spec() {
        XCTAssertEqual(S.openingLocked.copy, "OPENING LOCKED")
    }

    func test_calibration_copy_matches_spec() {
        XCTAssertEqual(S.calibration.copy, "CALIBRATE · PLACE CARD ON SURFACE")
    }

    func test_captured_flash_includes_interpunct_separator() {
        // §5.1 mandates `·` interpunct (never em-dash), and the JetBrains Mono
        // duration is a literal `0.07s` per the spec table.
        XCTAssertEqual(S.capturedFlash.copy, "CAPTURED · 0.07S")
        XCTAssertTrue(S.capturedFlash.copy.contains("·"))
        XCTAssertFalse(S.capturedFlash.copy.contains("—"))
    }

    func test_annotationDepthMiss_uses_catalog_error_label() {
        // The depth-miss feedback folded into the canonical Toast system during
        // the feedback consolidation; its copy now lives in the Feedback catalog.
        XCTAssertEqual(
            Feedback.Err.noDepth,
            "// NO DEPTH HERE — AIM AT A SOLID SURFACE"
        )
    }

    func test_calibrationReferenceNotFound_copy_matches_spec() {
        XCTAssertEqual(
            DimensionedCaptureView.ErrorToast.referenceNotFound.copy,
            "// ERROR — REFERENCE NOT FOUND · INCREASE LIGHT · RETRY"
        )
        XCTAssertTrue(DimensionedCaptureView.ErrorToast.referenceNotFound.includesUseUncalibrated)
    }

    // MARK: - Color ladder

    func test_initializing_color_is_text2_secondary() {
        XCTAssertEqual(S.initializing.foreground, OPSStyle.Colors.text2)
    }

    func test_aim_at_opening_color_is_text2_secondary() {
        XCTAssertEqual(S.aimAtOpening.foreground, OPSStyle.Colors.text2)
    }

    func test_searching_color_is_text2_secondary() {
        XCTAssertEqual(S.searching.foreground, OPSStyle.Colors.text2)
    }

    func test_wall_detected_promotes_to_primary_text() {
        XCTAssertEqual(S.wallDetected.foreground, OPSStyle.Colors.text)
    }

    func test_opening_locked_promotes_to_olive_success() {
        // §3.6 — olive is the "positive / completed" earth tone, used here as
        // a confirmation that the auto-detect classifier has converged.
        XCTAssertEqual(S.openingLocked.foreground, OPSStyle.Colors.olive)
    }

    func test_calibration_uses_attention_tan() {
        XCTAssertEqual(S.calibration.foreground, OPSStyle.Colors.tan)
    }

    func test_captured_flash_reads_as_neutral_primary_text() {
        // Capture is a *commitment* beat, paired with the shutter haptic.
        // Not a status color — stays in the primary `text` ladder so the
        // chip reads cleanly during the 1.5 s hold before dismiss.
        XCTAssertEqual(S.capturedFlash.foreground, OPSStyle.Colors.text)
    }

    // MARK: - Voice prefix invariant

    func test_no_state_includes_emoji() {
        // OPS brand rule — never emoji on chips. Any character > U+1F000
        // would imply pictographs slipping in.
        for state in S.allCases {
            for scalar in state.copy.unicodeScalars {
                XCTAssertLessThan(
                    scalar.value, 0x1F000,
                    "State \(state) contains a pictograph scalar: U+\(String(scalar.value, radix: 16))"
                )
            }
        }
    }

    func test_all_states_are_present_in_enum_order() {
        // Locks the enum to the §5.1 progression so a future refactor can't
        // silently drop a state. The order matters — it's the temporal flow.
        XCTAssertEqual(S.allCases, [
            .initializing, .aimAtOpening, .searching,
            .wallDetected, .openingLocked, .calibration,
            .capturedFlash
        ])
    }
}
