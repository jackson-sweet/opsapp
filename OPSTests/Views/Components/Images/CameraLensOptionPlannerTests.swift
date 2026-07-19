//
//  CameraLensOptionPlannerTests.swift
//  OPSTests
//
//  Regression coverage for native lens/zoom choices in the standardized
//  batch camera. Bug 56c37df2 — labels must be the user-facing
//  magnification the native Camera app shows, not raw zoom factors.
//
//  The hardware-shaped cases below use the RAW values AVFoundation
//  reports for each device class: virtual devices anchor raw factor 1.0
//  to their widest lens, so on ultra-wide hardware the 1x wide lens
//  engages at the first switch-over factor (2.0 on every ultra-wide
//  iPhone to date).
//

import XCTest
@testable import OPS

final class CameraLensOptionPlannerTests: XCTestCase {

    // MARK: - Hardware-shaped device classes

    /// iPhone Pro triple camera (e.g. 15 Pro): ultra-wide + wide + 3x tele.
    /// Raw switch-overs [2, 6]; wide lens engages at raw 2.0.
    func testTripleCameraLabelsMatchNativeCameraMagnifications() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 16,
            switchOverZoomFactors: [2, 6],
            wideLensZoomFactor: 2
        )

        XCTAssertEqual(options.map(\.label), ["0.5x", "1x", "2x", "3x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2, 4, 6])
    }

    /// iPhone dual-wide camera (e.g. 16): ultra-wide + wide.
    /// Raw switch-over [2]; wide lens engages at raw 2.0.
    func testDualWideCameraLabelsMatchNativeCameraMagnifications() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 16,
            switchOverZoomFactors: [2],
            wideLensZoomFactor: 2
        )

        XCTAssertEqual(options.map(\.label), ["0.5x", "1x", "2x", "3x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2, 4, 6])
    }

    /// iPhone Pro Max 5x tele (e.g. 16 Pro Max): raw switch-overs [2, 10].
    /// The tele stop must surface as its true 5x magnification.
    func testFiveXTelephotoSurfacesAsFiveX() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 16,
            switchOverZoomFactors: [2, 10],
            wideLensZoomFactor: 2
        )

        XCTAssertEqual(options.map(\.label), ["0.5x", "1x", "2x", "3x", "5x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2, 4, 6, 10])
    }

    /// Wide + tele dual camera with no ultra-wide (e.g. iPhone X): raw
    /// factor space is already anchored to the wide lens, so labels equal
    /// raw factors and the 2x stop lands on the tele switch-over.
    func testWideTeleDualCameraKeepsWideAnchoredLabels() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 8,
            switchOverZoomFactors: [2],
            wideLensZoomFactor: 1
        )

        XCTAssertEqual(options.map(\.label), ["1x", "2x", "3x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2, 3])
    }

    /// Single wide lens (e.g. SE): digital crop stops only.
    func testSingleLensOffersDigitalCropStops() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 8,
            switchOverZoomFactors: [],
            wideLensZoomFactor: 1
        )

        XCTAssertEqual(options.map(\.label), ["1x", "2x", "3x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2, 3])
    }

    // MARK: - Selection behavior

    /// The zoom factor handed back for a stop must be the RAW device
    /// factor, so tapping "1x" on ultra-wide hardware drives the device
    /// to the wide lens (raw 2.0), not the ultra-wide (raw 1.0).
    func testOneXStopDrivesRawWideLensFactorOnUltraWideHardware() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 16,
            switchOverZoomFactors: [2, 6],
            wideLensZoomFactor: 2
        )

        let oneX = options.first(where: { $0.label == "1x" })
        XCTAssertEqual(oneX?.zoomFactor, 2)
    }

    // MARK: - Range + dedupe defenses

    func testPlannerClampsUnavailableStopsAndDeduplicatesNearbyValues() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 2.2,
            switchOverZoomFactors: [1.01, 2.0, 2.02, 3.0]
        )

        XCTAssertEqual(options.map(\.label), ["1x", "2x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2])
    }

    /// Stops beyond the raw ceiling are dropped even in user space — a
    /// 5x tele (raw 10) cannot be offered when the format caps at raw 8.
    func testStopsBeyondRawCeilingAreDropped() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 8,
            switchOverZoomFactors: [2, 10],
            wideLensZoomFactor: 2
        )

        XCTAssertEqual(options.map(\.label), ["0.5x", "1x", "2x", "3x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2, 4, 6])
    }

    /// Degenerate baseline input falls back to raw labeling instead of
    /// dividing by zero.
    func testDegenerateWideLensFactorFallsBackToRawSpace() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 8,
            switchOverZoomFactors: [],
            wideLensZoomFactor: 0
        )

        XCTAssertEqual(options.map(\.label), ["1x", "2x", "3x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2, 3])
    }
}
