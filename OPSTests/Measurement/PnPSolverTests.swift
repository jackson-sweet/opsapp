// OPS/OPSTests/Measurement/PnPSolverTests.swift

import XCTest
import simd
@testable import OPS

final class PnPSolverTests: XCTestCase {

    // Synthetic camera: 1000-pixel-square sensor, fx=fy=1000, principal point at centre.
    private let intrinsics = DimensionsData.Intrinsics(
        fx: 1000, fy: 1000, cx: 500, cy: 500,
        imageWidth: 1000, imageHeight: 1000
    )

    // Credit card outline, centred at marker-local origin (metres).
    private let halfW: Double = 0.0428    // 85.60 mm / 2
    private let halfH: Double = 0.02699   // 53.98 mm / 2

    private var cardWorld2D: [SIMD2<Double>] {
        [
            SIMD2(-halfW, -halfH),
            SIMD2( halfW, -halfH),
            SIMD2( halfW,  halfH),
            SIMD2(-halfW,  halfH),
        ]
    }
    private var cardWorld3D: [SIMD3<Double>] {
        cardWorld2D.map { SIMD3($0.x, $0.y, 0) }
    }

    // Project a world point through a world-to-camera pose using the intrinsics.
    private func project(_ world: SIMD3<Double>, pose: simd_double4x4) -> SIMD2<Double> {
        let worldH = SIMD4<Double>(world.x, world.y, world.z, 1)
        let cam = pose * worldH
        precondition(cam.z > 0, "point must be in front of camera")
        let u = intrinsics.fx * cam.x / cam.z + intrinsics.cx
        let v = intrinsics.fy * cam.y / cam.z + intrinsics.cy
        return SIMD2<Double>(u, v)
    }

    private func projectAll(pose: simd_double4x4) -> [SIMD2<Double>] {
        cardWorld3D.map { project($0, pose: pose) }
    }

    private func translation(_ pose: simd_double4x4) -> SIMD3<Double> {
        let c = pose.columns.3
        return SIMD3<Double>(c.x, c.y, c.z)
    }

    /// Frobenius distance between the rotation blocks of two 4×4 transforms.
    private func rotationDelta(_ a: simd_double4x4, _ b: simd_double4x4) -> Double {
        let cols: [(SIMD4<Double>, SIMD4<Double>)] = [
            (a.columns.0, b.columns.0),
            (a.columns.1, b.columns.1),
            (a.columns.2, b.columns.2),
        ]
        var s = 0.0
        for (ca, cb) in cols {
            let d0 = ca.x - cb.x
            let d1 = ca.y - cb.y
            let d2 = ca.z - cb.z
            s += d0 * d0 + d1 * d1 + d2 * d2
        }
        return s.squareRoot()
    }

    private func makePose(rotation: simd_double3x3, translation t: SIMD3<Double>) -> simd_double4x4 {
        let c0 = SIMD4<Double>(rotation.columns.0.x, rotation.columns.0.y, rotation.columns.0.z, 0)
        let c1 = SIMD4<Double>(rotation.columns.1.x, rotation.columns.1.y, rotation.columns.1.z, 0)
        let c2 = SIMD4<Double>(rotation.columns.2.x, rotation.columns.2.y, rotation.columns.2.z, 0)
        let c3 = SIMD4<Double>(t.x, t.y, t.z, 1)
        return simd_double4x4(columns: (c0, c1, c2, c3))
    }

    // MARK: - 1. Axis-aligned card directly in front of the camera

    func test_axisAlignedCard_recoversIdentityRotationAndKnownDepth() throws {
        let pose = makePose(rotation: matrix_identity_double3x3,
                            translation: SIMD3<Double>(0, 0, 0.5))
        let imagePts = projectAll(pose: pose)

        let solved = try PnPSolver.solvePlanarPose(
            worldPoints: cardWorld2D,
            imagePoints: imagePts,
            intrinsics: intrinsics
        )

        let t = translation(solved)
        XCTAssertEqual(t.x, 0.0, accuracy: 1e-6)
        XCTAssertEqual(t.y, 0.0, accuracy: 1e-6)
        XCTAssertEqual(t.z, 0.5, accuracy: 1e-6)
        // Rotation should be the identity within numeric tolerance.
        XCTAssertLessThan(rotationDelta(solved, pose), 1e-6)
    }

    // MARK: - 2. Card rotated 15° around the Y axis

    func test_rotatedCard_recoversYawRotation() throws {
        let theta = 15.0 * .pi / 180
        let c = cos(theta)
        let s = sin(theta)
        let R = simd_double3x3(rows: [
            SIMD3<Double>( c, 0,  s),
            SIMD3<Double>( 0, 1,  0),
            SIMD3<Double>(-s, 0,  c)
        ])
        let pose = makePose(rotation: R, translation: SIMD3<Double>(0, 0, 0.6))
        let imagePts = projectAll(pose: pose)

        let solved = try PnPSolver.solvePlanarPose(
            worldPoints: cardWorld2D,
            imagePoints: imagePts,
            intrinsics: intrinsics
        )

        let t = translation(solved)
        XCTAssertEqual(t.z, 0.6, accuracy: 1e-4)
        // Rotation matrix should match within reasonable numerical tolerance.
        XCTAssertLessThan(rotationDelta(solved, pose), 1e-4)
    }

    // MARK: - 3. Oblique perspective (combined rotation + off-axis translation)

    func test_obliquePerspective_recoversPoseWithinTolerance() throws {
        let yaw = 12.0 * .pi / 180
        let pitch = -8.0 * .pi / 180
        let cy = cos(yaw),   sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)
        let Ry = simd_double3x3(rows: [
            SIMD3<Double>( cy, 0,  sy),
            SIMD3<Double>(  0, 1,   0),
            SIMD3<Double>(-sy, 0,  cy)
        ])
        let Rx = simd_double3x3(rows: [
            SIMD3<Double>(1,   0,   0),
            SIMD3<Double>(0,  cp, -sp),
            SIMD3<Double>(0,  sp,  cp)
        ])
        let R = Rx * Ry
        let pose = makePose(rotation: R, translation: SIMD3<Double>(0.04, -0.02, 0.7))
        let imagePts = projectAll(pose: pose)

        let solved = try PnPSolver.solvePlanarPose(
            worldPoints: cardWorld2D,
            imagePoints: imagePts,
            intrinsics: intrinsics
        )

        let t = translation(solved)
        XCTAssertEqual(t.x,  0.04, accuracy: 1e-3)
        XCTAssertEqual(t.y, -0.02, accuracy: 1e-3)
        XCTAssertEqual(t.z,  0.7,  accuracy: 1e-3)
        XCTAssertLessThan(rotationDelta(solved, pose), 1e-3)
    }

    // MARK: - Error paths

    func test_wrongCorrespondenceCount_throws() {
        XCTAssertThrowsError(try PnPSolver.solvePlanarPose(
            worldPoints: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1)],   // 3 only
            imagePoints: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1)],
            intrinsics: intrinsics
        )) { err in
            XCTAssertEqual(err as? PnPSolverError, .wrongCorrespondenceCount(3))
        }
    }

    func test_collinearWorldPoints_throwsSingular() {
        // All 4 world points on a line — system is singular.
        let collinear: [SIMD2<Double>] = [
            SIMD2(0, 0), SIMD2(0.01, 0), SIMD2(0.02, 0), SIMD2(0.03, 0)
        ]
        let imagePts: [SIMD2<Double>] = [
            SIMD2(500, 500), SIMD2(520, 500), SIMD2(540, 500), SIMD2(560, 500)
        ]
        XCTAssertThrowsError(try PnPSolver.solvePlanarPose(
            worldPoints: collinear,
            imagePoints: imagePts,
            intrinsics: intrinsics
        ))
    }
}
