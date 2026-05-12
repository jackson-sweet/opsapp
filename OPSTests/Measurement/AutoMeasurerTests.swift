// OPS/OPSTests/Measurement/AutoMeasurerTests.swift

import XCTest
import CoreGraphics
import simd
@testable import OPS

final class AutoMeasurerTests: XCTestCase {

    private let intrinsics = DimensionsData.Intrinsics(
        fx: 1000, fy: 1000, cx: 500, cy: 500,
        imageWidth: 1000, imageHeight: 1000
    )
    private let photoSize = CGSize(width: 1000, height: 1000)

    private func quad(width w: Float, height h: Float,
                      centre c: SIMD3<Float>,
                      classification cls: MeshFaceSnapshot.Classification,
                      normal n: SIMD3<Float> = SIMD3<Float>(0, 0, -1)) -> [MeshFaceSnapshot] {
        // Build a quad whose plane normal == `n` and centre == `c`. Width is
        // along the basis perpendicular to `n` and the world up axis.
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(up, n))
        let down  = simd_normalize(simd_cross(n, right))
        let hw = w / 2, hh = h / 2
        let v00 = c - hw * right - hh * down
        let v10 = c + hw * right - hh * down
        let v11 = c + hw * right + hh * down
        let v01 = c - hw * right + hh * down
        return [
            MeshFaceSnapshot(v0: v00, v1: v10, v2: v11, classification: cls),
            MeshFaceSnapshot(v0: v00, v1: v11, v2: v01, classification: cls)
        ]
    }

    // MARK: - 1. Window with floor mesh present → 4 measurements

    func test_windowWithFloorBelow_returns4Measurements_includingSill() {
        // Window 0.6 m × 1.2 m at z = 2 m, centered on the optical axis.
        // In camera frame (identity worldToCamera), the window's bottom edge
        // is at y = +0.6.
        var faces = quad(width: 0.6, height: 1.2,
                         centre: SIMD3<Float>(0, 0, 2),
                         classification: .window)
        // Floor patch 0.4 m below the bottom of the window, at y = 1.0.
        faces += quad(width: 1.5, height: 1.5,
                      centre: SIMD3<Float>(0, 1.0, 2),
                      classification: .floor,
                      normal: SIMD3<Float>(0, -1, 0))   // up-facing floor
        // Surrounding wall behind/around the window, slightly closer to camera (recess).
        faces += quad(width: 3.0, height: 2.5,
                      centre: SIMD3<Float>(0, 0, 1.95),
                      classification: .wall)

        let snap = AnchorSnapshot(faces: faces)
        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)
        XCTAssertEqual(openings.count, 1)
        let result = AutoMeasurer.measure(opening: openings[0],
                                          anchors: snap,
                                          photoSize: photoSize)
        XCTAssertEqual(result.allMeasurements.count, 4,
                       "Expected W, H, sill, depth (4 measurements)")
        XCTAssertNotNil(result.sillHeight)
        XCTAssertNil(result.sillUnavailableReason)
        XCTAssertNotNil(result.openingDepth)
        XCTAssertFalse(result.depthUnavailable)

        // Sill height should be ~0.4 m (window bottom at y=0.6, floor at y=1.0).
        XCTAssertEqual(result.sillHeight!.valueMeters, 0.4, accuracy: 0.05)
        // Width ≈ 0.6 m, Height ≈ 1.2 m.
        XCTAssertEqual(result.width.valueMeters, 0.6, accuracy: 0.02)
        XCTAssertEqual(result.height.valueMeters, 1.2, accuracy: 0.02)
        // Depth: wall is at z=1.95, opening centroid at z=2.0 → ~0.05 m.
        XCTAssertEqual(result.openingDepth!.valueMeters, 0.05, accuracy: 0.02)

        XCTAssertEqual(result.width.source, .auto)
        XCTAssertEqual(result.width.label, "Width")
        XCTAssertEqual(result.height.label, "Height")
        XCTAssertEqual(result.sillHeight!.label, "Sill Height")
        XCTAssertEqual(result.openingDepth!.label, "Opening Depth")
    }

    // MARK: - 2. Door without floor mesh → 3 measurements (sill omitted)

    func test_doorWithoutFloor_returns3Measurements_sillUnavailable() {
        var faces = quad(width: 0.9, height: 2.0,
                         centre: SIMD3<Float>(0, 0, 3),
                         classification: .door)
        // Wall context but NO floor faces.
        faces += quad(width: 3.0, height: 3.0,
                      centre: SIMD3<Float>(0, 0, 2.93),
                      classification: .wall)

        let snap = AnchorSnapshot(faces: faces)
        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)
        XCTAssertEqual(openings.count, 1)
        let result = AutoMeasurer.measure(opening: openings[0],
                                          anchors: snap,
                                          photoSize: photoSize)
        XCTAssertEqual(result.allMeasurements.count, 3,
                       "Expected W, H, depth (sill unavailable)")
        XCTAssertNil(result.sillHeight)
        XCTAssertEqual(result.sillUnavailableReason, .noFloorMeshNearby)
        XCTAssertNotNil(result.openingDepth)
    }

    // MARK: - 3. Floor present but too far below → sill still skipped (no false gravity fallback)

    func test_windowWithFloorTooFarBelow_skipsSill_ratherThanFallingBackToGravity() {
        // Floor 1.0 m below the opening's bottom — well past the 0.5 m gate.
        var faces = quad(width: 0.6, height: 1.2,
                         centre: SIMD3<Float>(0, 0, 2),
                         classification: .window)
        faces += quad(width: 1.5, height: 1.5,
                      centre: SIMD3<Float>(0, 1.6, 2),   // y = 1.6 → 1.0 m below window bottom (y=0.6)
                      classification: .floor,
                      normal: SIMD3<Float>(0, -1, 0))
        faces += quad(width: 3.0, height: 2.5,
                      centre: SIMD3<Float>(0, 0, 1.95),
                      classification: .wall)
        let snap = AnchorSnapshot(faces: faces)
        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)
        XCTAssertEqual(openings.count, 1)
        let result = AutoMeasurer.measure(opening: openings[0],
                                          anchors: snap,
                                          photoSize: photoSize)
        XCTAssertNil(result.sillHeight)
        XCTAssertEqual(result.sillUnavailableReason, .noFloorMeshNearby)
        // Spec §3.3 honest limitation: do NOT fall back to gravity-aligned plane.
        // No misleading "height-from-camera" measurement may sneak into allMeasurements.
        XCTAssertFalse(result.allMeasurements.contains(where: { $0.label == "Sill Height" }))
    }
}
