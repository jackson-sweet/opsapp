//
//  MeasurementNotificationTests.swift
//  OPSTests
//
//  Phase G — body-string verbatim assertions for the 3 LiDAR notification
//  types. The exact strings are part of the public spec (§6) and the iOS
//  rail / web rail / push payload all consume them. Drift here is a UX
//  regression — these tests fail loud.
//
//  Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §6
//

import XCTest
@testable import OPS

final class MeasurementNotificationTests: XCTestCase {

    // MARK: - measurement_captured — spec §6

    func testCapturedBodyForOpening() {
        // Spec example verbatim:
        //   [PROJECT_NAME] · 36″×60″ WINDOW · SILL 28″
        let body = MeasurementNotificationCopy.capturedBody(
            projectName: "Smith Renovation",
            summary: .opening(widthInches: 36, heightInches: 60, type: .window, sillInches: 28)
        )
        XCTAssertEqual(body, "SMITH RENOVATION · 36″×60″ WINDOW · SILL 28″")
    }

    func testCapturedBodyForWallSection() {
        // Spec example verbatim:
        //   [PROJECT_NAME] · WALL SECTION · 14′6″ × 8′
        let body = MeasurementNotificationCopy.capturedBody(
            projectName: "Smith Renovation",
            summary: .wallSection(widthFeet: 14, widthInches: 6, heightFeet: 8)
        )
        XCTAssertEqual(body, "SMITH RENOVATION · WALL SECTION · 14′6″ × 8′")
    }

    func testCapturedTitleVerbatim() {
        XCTAssertEqual(MeasurementNotificationCopy.capturedTitle, "// MEASUREMENT SAVED")
    }

    // MARK: - measurement_pending_sync — spec §6

    func testPendingSyncBodySingular() {
        // Spec verbatim: `1 MEASUREMENT · WILL UPLOAD ON SIGNAL`
        XCTAssertEqual(
            MeasurementNotificationCopy.pendingSyncBody(count: 1),
            "1 MEASUREMENT · WILL UPLOAD ON SIGNAL"
        )
    }

    func testPendingSyncBodyPlural() {
        // Spec verbatim: `3 MEASUREMENTS · WILL UPLOAD ON SIGNAL`
        XCTAssertEqual(
            MeasurementNotificationCopy.pendingSyncBody(count: 3),
            "3 MEASUREMENTS · WILL UPLOAD ON SIGNAL"
        )
    }

    func testPendingSyncTitleVerbatim() {
        XCTAssertEqual(MeasurementNotificationCopy.pendingSyncTitle, "// SYNC QUEUED")
    }

    // MARK: - measurement_sync_failed — spec §6

    func testSyncFailedBody() {
        // Spec verbatim: `[PROJECT_NAME] · MEASUREMENT NOT UPLOADED · RETRY`
        let body = MeasurementNotificationCopy.syncFailedBody(projectName: "Smith Renovation")
        XCTAssertEqual(body, "SMITH RENOVATION · MEASUREMENT NOT UPLOADED · RETRY")
    }

    func testSyncFailedTitleVerbatim() {
        XCTAssertEqual(MeasurementNotificationCopy.syncFailedTitle, "// ERROR — SYNC FAILED")
    }

    func testRetryActionLabel() {
        XCTAssertEqual(MeasurementNotificationCopy.retryLabel, "RETRY")
    }

    func testViewActionLabel() {
        XCTAssertEqual(MeasurementNotificationCopy.viewLabel, "VIEW")
    }

    // MARK: - Type constants — must match `notifications.type` text values verbatim

    func testTypeConstantsMatchSpec() {
        XCTAssertEqual(MeasurementNotificationType.captured, "measurement_captured")
        XCTAssertEqual(MeasurementNotificationType.pendingSync, "measurement_pending_sync")
        XCTAssertEqual(MeasurementNotificationType.syncFailed, "measurement_sync_failed")
    }

    // MARK: - Feature flag slug — must match `feature_flags.slug` verbatim

    func testFeatureFlagSlug() {
        XCTAssertEqual(
            MeasurementFlag.dimensionedCapture,
            "feature.measurement.dimensioned_capture"
        )
    }
}
