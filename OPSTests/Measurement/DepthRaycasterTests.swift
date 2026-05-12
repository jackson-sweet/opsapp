// OPS/OPSTests/Measurement/DepthRaycasterTests.swift

import XCTest
import simd
@testable import OPS

final class DepthRaycasterTests: XCTestCase {

    // 1000×750 photo, 100×75 depth map, fx=fy=1000, principal point at image centre.
    // Lower-resolution depth on purpose to exercise bi-linear sampling.
    private let photoSize = CGSize(width: 1000, height: 750)
    private let depthSize = (w: 100, h: 75)
    private let intrinsics = DimensionsData.Intrinsics(
        fx: 1000, fy: 1000, cx: 500, cy: 375,
        imageWidth: 1000, imageHeight: 750
    )

    private func uniformDepth(_ value: Float) -> DepthMap {
        let count = depthSize.w * depthSize.h
        return DepthMap(width: depthSize.w, height: depthSize.h,
                        values: Array(repeating: value, count: count))
    }

    // 1. Centre of a uniform plane → world point on the optical axis at given depth
    func testCenterPixelOfUniformPlane_returnsCameraOrigin() {
        let raycaster = DepthRaycaster(intrinsics: intrinsics,
                                       depth: uniformDepth(2.0),
                                       photoSize: photoSize)
        let p = raycaster.worldPoint(atPhotoPixel: CGPoint(x: 500, y: 375))
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.x, 0.0, accuracy: 1e-4)
        XCTAssertEqual(p!.y, 0.0, accuracy: 1e-4)
        XCTAssertEqual(p!.z, 2.0, accuracy: 1e-4)
    }

    // 2. Sloped plane — depth ramps linearly across X
    func testSlopedPlane_recoversCorrectDepthAtTwoPoints() {
        var values = [Float](repeating: 0, count: depthSize.w * depthSize.h)
        for y in 0..<depthSize.h {
            for x in 0..<depthSize.w {
                let t = Float(x) / Float(depthSize.w - 1) // 0…1
                values[y * depthSize.w + x] = 1.0 + 2.0 * t
            }
        }
        let depth = DepthMap(width: depthSize.w, height: depthSize.h, values: values)
        let raycaster = DepthRaycaster(intrinsics: intrinsics, depth: depth, photoSize: photoSize)

        // Photo pixel (250, 375) → depth column ~24.5/100 of the way across → ~1.495 m
        let near = raycaster.worldPoint(atPhotoPixel: CGPoint(x: 250, y: 375))
        XCTAssertNotNil(near)
        XCTAssertEqual(near!.z, 1.495, accuracy: 0.05)

        // Photo pixel (750, 375) → ~2.510 m
        let far = raycaster.worldPoint(atPhotoPixel: CGPoint(x: 750, y: 375))
        XCTAssertNotNil(far)
        XCTAssertEqual(far!.z, 2.510, accuracy: 0.05)
    }

    // 3. Two-plane discontinuity (left half vs right half)
    func testTwoPlaneDiscontinuity_recoversCorrectDepthOnEachSide() {
        var values = [Float](repeating: 0, count: depthSize.w * depthSize.h)
        for y in 0..<depthSize.h {
            for x in 0..<depthSize.w {
                values[y * depthSize.w + x] = (x < depthSize.w / 2) ? 1.5 : 4.0
            }
        }
        let depth = DepthMap(width: depthSize.w, height: depthSize.h, values: values)
        let raycaster = DepthRaycaster(intrinsics: intrinsics, depth: depth, photoSize: photoSize)

        let left = raycaster.worldPoint(atPhotoPixel: CGPoint(x: 100, y: 375))
        XCTAssertNotNil(left)
        XCTAssertEqual(left!.z, 1.5, accuracy: 0.01)

        let right = raycaster.worldPoint(atPhotoPixel: CGPoint(x: 900, y: 375))
        XCTAssertNotNil(right)
        XCTAssertEqual(right!.z, 4.0, accuracy: 0.01)
    }

    // 4. Invalid depth → nil
    func testZeroDepth_returnsNil() {
        let raycaster = DepthRaycaster(intrinsics: intrinsics,
                                       depth: uniformDepth(0),
                                       photoSize: photoSize)
        let p = raycaster.worldPoint(atPhotoPixel: CGPoint(x: 500, y: 375))
        XCTAssertNil(p)
    }

    // 5. Out-of-bounds → nil; edge pixel still resolves
    func testOutOfBoundsPixel_returnsNil_edgePixelReturnsFinite() {
        let raycaster = DepthRaycaster(intrinsics: intrinsics,
                                       depth: uniformDepth(1.0),
                                       photoSize: photoSize)
        XCTAssertNil(raycaster.worldPoint(atPhotoPixel: CGPoint(x: -10, y: 100)))
        XCTAssertNil(raycaster.worldPoint(atPhotoPixel: CGPoint(x: 100, y: 5000)))

        let corner = raycaster.worldPoint(atPhotoPixel: CGPoint(x: 0, y: 0))
        XCTAssertNotNil(corner)
        XCTAssertEqual(corner!.z, 1.0, accuracy: 1e-4)
        XCTAssertEqual(corner!.x, -0.5, accuracy: 1e-4)
        XCTAssertEqual(corner!.y, -0.375, accuracy: 1e-4)
    }

    // Two-tap linear measurement on a uniform plane
    func testLinearMeasurement_betweenTwoPointsOnUniformPlane_equalsBaseline() {
        // 200 px gap at fx=1000, z=2 → 200 * 2 / 1000 = 0.4 m
        let raycaster = DepthRaycaster(intrinsics: intrinsics,
                                       depth: uniformDepth(2.0),
                                       photoSize: photoSize)
        let m = raycaster.linearMeasurement(from: CGPoint(x: 400, y: 375),
                                            to: CGPoint(x: 600, y: 375),
                                            label: "Width")
        XCTAssertNotNil(m)
        XCTAssertEqual(m!.valueMeters, 0.4, accuracy: 1e-4)
        XCTAssertEqual(m!.worldPoints.count, 2)
        XCTAssertEqual(m!.imagePoints.count, 2)
        XCTAssertEqual(m!.source, .manual)
        XCTAssertEqual(m!.type, .linear)
    }
}
