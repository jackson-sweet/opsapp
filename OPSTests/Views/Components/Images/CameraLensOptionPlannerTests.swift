//
//  CameraLensOptionPlannerTests.swift
//  OPSTests
//
//  Regression coverage for native lens/zoom choices in the project camera.
//

import XCTest
@testable import OPS

final class CameraLensOptionPlannerTests: XCTestCase {

    func testPlannerBuildsNativeLensStopsFromDeviceCapabilities() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 0.5,
            maxZoom: 8,
            switchOverZoomFactors: [1, 2]
        )

        XCTAssertEqual(options.map(\.label), ["0.5x", "1x", "2x", "3x"])
        XCTAssertEqual(options.map(\.zoomFactor), [0.5, 1, 2, 3])
    }

    func testPlannerClampsUnavailableStopsAndDeduplicatesNearbyValues() {
        let options = CameraLensOptionPlanner.options(
            minZoom: 1,
            maxZoom: 2.2,
            switchOverZoomFactors: [1.01, 2.0, 2.02, 3.0]
        )

        XCTAssertEqual(options.map(\.label), ["1x", "2x"])
        XCTAssertEqual(options.map(\.zoomFactor), [1, 2])
    }
}
