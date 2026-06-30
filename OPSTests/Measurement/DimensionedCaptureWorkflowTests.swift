//
//  DimensionedCaptureWorkflowTests.swift
//  OPSTests
//
//  Regression coverage for the field capture state machine. The operator must
//  be able to take a photo as soon as AR tracking is usable; wall/opening
//  detection improves confidence but must not block manual measurement.
//

import XCTest
@testable import OPS

final class DimensionedCaptureWorkflowTests: XCTestCase {

    func test_shutter_is_enabled_while_arkit_is_searching_for_planes() {
        XCTAssertTrue(
            DimensionedCaptureWorkflow.shutterEnabled(for: .searching),
            "Searching is the normal live-aim state on real devices; shutter must stay available for manual measurement."
        )
    }

    func test_shutter_waits_until_tracking_is_ready() {
        XCTAssertFalse(DimensionedCaptureWorkflow.shutterEnabled(for: .idle))
        XCTAssertFalse(DimensionedCaptureWorkflow.shutterEnabled(for: .warmingUp))
        XCTAssertFalse(DimensionedCaptureWorkflow.shutterEnabled(for: .capturing))
    }

    func test_center_reticle_is_visible_before_auto_lock() {
        XCTAssertTrue(DimensionedCaptureWorkflow.showsCenterReticle(for: .ready))
        XCTAssertTrue(DimensionedCaptureWorkflow.showsCenterReticle(for: .searching))
        XCTAssertTrue(DimensionedCaptureWorkflow.showsCenterReticle(for: .wallDetected))
    }

    func test_level_indicator_is_not_primary_precapture_target() {
        XCTAssertFalse(DimensionedCaptureWorkflow.showsLevelIndicator(for: .ready, userEnabled: true))
        XCTAssertFalse(DimensionedCaptureWorkflow.showsLevelIndicator(for: .searching, userEnabled: true))
        XCTAssertFalse(DimensionedCaptureWorkflow.showsLevelIndicator(for: .wallDetected, userEnabled: true))
    }
}
