// OPS/OPSTests/Measurement/OpeningClassifierTests.swift

import XCTest
import CoreGraphics
import simd
@testable import OPS

final class OpeningClassifierTests: XCTestCase {

    // 1000×1000 photo with the camera looking straight down −Z at the world origin.
    private let intrinsics = DimensionsData.Intrinsics(
        fx: 1000, fy: 1000, cx: 500, cy: 500,
        imageWidth: 1000, imageHeight: 1000
    )
    private let photoSize = CGSize(width: 1000, height: 1000)

    // Camera frame == world frame (identity worldToCamera) makes the geometry
    // trivial: any face vertex with z=2 projects to (cx, cy) + 1000 * (x/2, y/2).
    private let identityW2C: simd_float4x4 = matrix_identity_float4x4

    /// Build a planar quad (z = depth) at world (X = [-w/2, w/2], Y = [-h/2, h/2])
    /// classified as `cls`. Returns the two triangles that tessellate it.
    private func quad(width w: Float, height h: Float, depth z: Float,
                      classification cls: MeshFaceSnapshot.Classification) -> [MeshFaceSnapshot] {
        let hw = w / 2, hh = h / 2
        let v00 = SIMD3<Float>(-hw, -hh, z)
        let v10 = SIMD3<Float>( hw, -hh, z)
        let v11 = SIMD3<Float>( hw,  hh, z)
        let v01 = SIMD3<Float>(-hw,  hh, z)
        return [
            MeshFaceSnapshot(v0: v00, v1: v10, v2: v11, classification: cls),
            MeshFaceSnapshot(v0: v00, v1: v11, v2: v01, classification: cls),
        ]
    }

    // MARK: - 1. Single window cluster → exactly one window opening

    func test_singleRectangularWindowCluster_returnsOneWindowOpening() {
        // 0.6 m wide × 1.2 m tall window at z = 2 m.
        let faces = quad(width: 0.6, height: 1.2, depth: 2.0, classification: .window)
        let snap = AnchorSnapshot(faces: faces, worldToCamera: identityW2C)

        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)

        XCTAssertEqual(openings.count, 1)
        let o = openings[0]
        XCTAssertEqual(o.type, .window)
        XCTAssertGreaterThan(o.classificationConfidence, 0.9)

        // Polygon: window spans 0.6 m at 2 m depth with fx=1000 → 300 px wide
        // around centre 500. Expect (350,?) and (650,?) horizontally.
        // Vertically: 1.2 m / 2 m * 1000 = 600 px around centre → (?,200) (?,800).
        let p = o.boundingPolygon
        XCTAssertEqual(p[0].x, 350, accuracy: 1)
        XCTAssertEqual(p[1].x, 650, accuracy: 1)
        XCTAssertEqual(p[0].y, 200, accuracy: 1)
        XCTAssertEqual(p[3].y, 800, accuracy: 1)
    }

    // MARK: - 2. Single door cluster → exactly one door opening

    func test_singleRectangularDoorCluster_returnsOneDoorOpening() {
        // Standard 0.9 m × 2.0 m door at z = 3 m.
        let faces = quad(width: 0.9, height: 2.0, depth: 3.0, classification: .door)
        let snap = AnchorSnapshot(faces: faces, worldToCamera: identityW2C)

        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)

        XCTAssertEqual(openings.count, 1)
        XCTAssertEqual(openings[0].type, .door)
        // 4 corners returned.
        XCTAssertEqual(openings[0].cornersCameraFrame.count, 4)
        // Plane normal should be ±(0,0,1) since face is in z = 3 plane.
        XCTAssertEqual(abs(openings[0].planeNormal.z), 1.0, accuracy: 1e-3)
    }

    // MARK: - 3. Empty / no classified faces → no openings

    func test_anchorSnapshotWithNoOpeningFaces_returnsEmpty() {
        let walls = quad(width: 4.0, height: 3.0, depth: 2.0, classification: .wall)
        let snap = AnchorSnapshot(faces: walls, worldToCamera: identityW2C)
        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)
        XCTAssertTrue(openings.isEmpty)
    }

    // MARK: - 4. Tiny / noise cluster below threshold → no opening

    func test_tinyClusterBelowAreaThreshold_returnsEmpty() {
        // 5 cm × 5 cm patch → 0.0025 m², below the 0.05 m² floor.
        let tiny = quad(width: 0.05, height: 0.05, depth: 2.0, classification: .window)
        let snap = AnchorSnapshot(faces: tiny, worldToCamera: identityW2C)
        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)
        XCTAssertTrue(openings.isEmpty)
    }

    // MARK: - 5. Both a window and a door present → two openings, distinct types

    func test_windowAndDoorCluster_returnsBoth() {
        var faces = quad(width: 0.6, height: 1.2, depth: 2.0, classification: .window)
        faces += quad(width: 0.9, height: 2.0, depth: 3.0, classification: .door)
        let snap = AnchorSnapshot(faces: faces, worldToCamera: identityW2C)

        let openings = OpeningClassifier.classify(anchors: snap,
                                                  intrinsics: intrinsics,
                                                  photoSize: photoSize)

        XCTAssertEqual(openings.count, 2)
        let types = Set(openings.map(\.type))
        XCTAssertEqual(types, Set([.window, .door]))
    }
}
