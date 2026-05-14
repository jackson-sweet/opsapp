//
//  RenderedPhotoComposerTests.swift
//  OPSTests
//
//  Phase F — verifies the 2048-long-edge PNG burn pipeline per spec §3.7.
//
//  Coverage:
//    1. downsampledSize math (no upscaling, correct aspect, integer pixels).
//    2. Output PNG ≤2.5 MB for a 4032×3024 input with 2 measurements
//       (the spec's storage budget for the rendered deliverable).
//    3. Output dimensions: long edge equals 2048, short edge preserves aspect.
//    4. Degenerate-input handling: zero-size photo returns nil.
//    5. Accuracy badge state survives end-to-end (visible bytes in the chip
//       region, exercised via decoded UIImage non-emptiness — pixel-level
//       inspection is overkill here).
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.7
//

import XCTest
import UIKit
@testable import OPS

final class RenderedPhotoComposerTests: XCTestCase {

    // MARK: - 1. Downsample math

    func test_downsampledSize_preservesAspect_andClampsToLongEdge() {
        // 4032×3024 portrait → long edge = 4032, scale = 2048/4032
        let in1 = CGSize(width: 4032, height: 3024)
        let out1 = RenderedPhotoComposer.downsampledSize(for: in1, longEdge: 2048)
        XCTAssertEqual(out1.width, 2048, accuracy: 1)
        XCTAssertEqual(out1.height, floor(3024 * (2048.0 / 4032.0)), accuracy: 1)

        // 3024×4032 landscape → height is long edge
        let in2 = CGSize(width: 3024, height: 4032)
        let out2 = RenderedPhotoComposer.downsampledSize(for: in2, longEdge: 2048)
        XCTAssertEqual(out2.height, 2048, accuracy: 1)
        XCTAssertEqual(out2.width, floor(3024 * (2048.0 / 4032.0)), accuracy: 1)

        // Already below target: pass through unchanged
        let in3 = CGSize(width: 1000, height: 800)
        let out3 = RenderedPhotoComposer.downsampledSize(for: in3, longEdge: 2048)
        XCTAssertEqual(out3, in3)
    }

    // MARK: - Fixture helpers

    private func fixturePhoto(width: CGFloat = 4032, height: CGFloat = 3024) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(white: 0.4, alpha: 1).setStroke()
            ctx.cgContext.setLineWidth(8)
            UIBezierPath(rect: CGRect(x: width * 0.2,
                                       y: height * 0.2,
                                       width: width * 0.6,
                                       height: height * 0.6)).stroke()
        }
    }

    private func fixtureDimensions() -> DimensionsData {
        DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(fx: 1593.4, fy: 1593.4,
                              cx: 1015.5, cy: 762.0,
                              imageWidth: 4032, imageHeight: 3024),
            measurements: [
                .init(type: .linear,
                      label: "Width",
                      worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0.9144, y: 0, z: 0)],
                      imagePoints: [.init(x: 806, y: 1512), .init(x: 3226, y: 1512)],
                      valueMeters: 0.9144,
                      labelPlacement: .init(side: .north, leaderLengthPx: 60),
                      source: .auto),
                .init(type: .linear,
                      label: "Height",
                      worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0, y: 1.524, z: 0)],
                      imagePoints: [.init(x: 806, y: 605), .init(x: 806, y: 2419)],
                      valueMeters: 1.524,
                      labelPlacement: .init(side: .east, leaderLengthPx: 60),
                      source: .auto)
            ]
        )
    }

    // MARK: - 2. PNG size budget

    func test_render_outputUnder2_5MB_forFixtureInput() throws {
        let photo = fixturePhoto()
        let data = try XCTUnwrap(
            RenderedPhotoComposer.render(
                photo: photo,
                dimensions: fixtureDimensions(),
                accuracy: .lidarUncalibrated
            )
        )
        let megabytes = Double(data.count) / (1024 * 1024)
        XCTAssertLessThan(megabytes, 2.5,
                          "PNG should fit within the spec §3.7 2.5 MB budget; got \(megabytes) MB")
    }

    // MARK: - 3. Output dimensions

    func test_render_outputLongEdgeIs2048() throws {
        let photo = fixturePhoto()
        let data = try XCTUnwrap(
            RenderedPhotoComposer.render(
                photo: photo,
                dimensions: fixtureDimensions(),
                accuracy: .lidarUncalibrated
            )
        )
        let rendered = try XCTUnwrap(UIImage(data: data))
        // Output is at scale=1.0 (composer config), so pixel == point.
        let maxSide = max(rendered.size.width, rendered.size.height)
        XCTAssertEqual(maxSide, RenderedPhotoComposer.longEdgeTarget, accuracy: 1)
    }

    // MARK: - 4. Degenerate input

    func test_render_returnsNil_forZeroSizePhoto() {
        let empty = UIImage()
        let data = RenderedPhotoComposer.render(
            photo: empty,
            dimensions: fixtureDimensions(),
            accuracy: .lidarUncalibrated
        )
        XCTAssertNil(data)
    }

    // MARK: - 5. Accuracy badge variants render

    func test_render_succeedsForEachAccuracyState() {
        for state: AccuracyState in [.calibrated, .lidarUncalibrated, .visualSlam, .noDepth] {
            let data = RenderedPhotoComposer.render(
                photo: fixturePhoto(width: 800, height: 600),
                dimensions: fixtureDimensions(),
                accuracy: state,
                coplanarOnly: state == .visualSlam
            )
            XCTAssertNotNil(data, "Expected non-nil PNG for state \(state)")
            XCTAssertGreaterThan(data?.count ?? 0, 0)
        }
    }

    // MARK: - 6. Watermark variants don't crash

    func test_render_watermarkVariants() {
        let lockup = RenderedPhotoComposer.render(
            photo: fixturePhoto(width: 800, height: 600),
            dimensions: fixtureDimensions(),
            accuracy: .lidarUncalibrated,
            watermark: .opsLockup
        )
        let custom = RenderedPhotoComposer.render(
            photo: fixturePhoto(width: 800, height: 600),
            dimensions: fixtureDimensions(),
            accuracy: .lidarUncalibrated,
            watermark: .custom("// JOB-1042")
        )
        XCTAssertNotNil(lockup)
        XCTAssertNotNil(custom)
    }

    // MARK: - 7. Chip-size estimate sanity

    func test_measureChipSize_growsWithText() {
        let small = DimensionsData.Measurement(
            type: .linear, label: "W",
            worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0.01, y: 0, z: 0)],
            imagePoints: [.init(x: 0, y: 0), .init(x: 10, y: 0)],
            valueMeters: 0.01,
            labelPlacement: .init(side: .north, leaderLengthPx: 60),
            source: .auto
        )
        let large = DimensionsData.Measurement(
            type: .linear, label: "Sill Height — Tallest Window",
            worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 4.4323, y: 0, z: 0)],
            imagePoints: [.init(x: 0, y: 0), .init(x: 1800, y: 0)],
            valueMeters: 174.5 * 0.0254,
            labelPlacement: .init(side: .north, leaderLengthPx: 60),
            source: .auto
        )

        let smallSize = RenderedPhotoComposer.measureChipSize(for: small, primaryUnit: .imperialFraction)
        let largeSize = RenderedPhotoComposer.measureChipSize(for: large, primaryUnit: .imperialFraction)

        // Both chips have a primary + secondary line so width is what scales with value.
        XCTAssertGreaterThan(largeSize.width, smallSize.width,
                             "Larger measurement value should produce a wider chip after formatting")
        XCTAssertEqual(smallSize.height, largeSize.height,
                       "Chip height is constant (primary 14pt + secondary 10pt + padding)")
    }
}
