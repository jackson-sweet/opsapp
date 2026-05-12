//
//  OpeningClassifier.swift
//  OPS
//
//  Identifies rectangular openings (windows, doors) from a mesh-classified
//  ARKit snapshot. Operates in pure math — no Vision call here. Phase D may
//  layer a Vision-contour pass on top of this to refine the bounding polygon
//  with photo-pixel evidence; v1 ships with mesh-only classification.
//
//  Output coordinates are in the *photo's top-left-origin pixel space* so the
//  results align with `DimensionsData.Opening.boundingPolygon` straight away.
//  3D corners are reported in the camera frame at shutter time so downstream
//  measurement code can call `DepthRaycaster.linearMeasurement` against them.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.3 §3.8
//

import Foundation
import CoreGraphics
import simd

public struct DetectedOpening: Equatable {
    public let id: UUID
    public let type: DimensionsData.Opening.OpeningType
    public let classificationConfidence: Double
    /// Bounding polygon in photo pixel space (top-left origin), 4 corners in
    /// the order [top-left, top-right, bottom-right, bottom-left].
    public let boundingPolygon: [DimensionsData.Point2]
    /// Same 4 corners in camera frame (metres). Same order as
    /// `boundingPolygon`. Use these directly with `DepthRaycaster` outputs.
    public let cornersCameraFrame: [SIMD3<Double>]
    /// Unit plane normal in camera frame.
    public let planeNormal: SIMD3<Double>
    /// Plane offset so that `dot(normal, p) + offset = 0` for points on the plane.
    public let planeOffset: Double
}

public struct OpeningClassifier {

    /// Minimum total face area (m²) to treat a classification cluster as a
    /// real opening rather than mesh noise.
    public static let minAreaSquareMetres: Float = 0.05   // ~ a fist-sized patch

    public static func classify(
        anchors: AnchorSnapshot,
        intrinsics: DimensionsData.Intrinsics,
        photoSize: CGSize
    ) -> [DetectedOpening] {
        let groups: [(DimensionsData.Opening.OpeningType, [MeshFaceSnapshot])] = [
            (.window, anchors.faces.filter { $0.classification == .window }),
            (.door,   anchors.faces.filter { $0.classification == .door }),
        ]
        var results: [DetectedOpening] = []
        for (type, faces) in groups {
            guard !faces.isEmpty else { continue }
            let totalArea = faces.reduce(Float(0)) { $0 + $1.area }
            guard totalArea >= minAreaSquareMetres else { continue }
            guard let opening = buildOpening(
                from: faces,
                type: type,
                totalArea: totalArea,
                worldToCamera: anchors.worldToCamera,
                intrinsics: intrinsics,
                photoSize: photoSize
            ) else { continue }
            results.append(opening)
        }
        return results
    }

    // MARK: - Private helpers

    private static func buildOpening(
        from faces: [MeshFaceSnapshot],
        type: DimensionsData.Opening.OpeningType,
        totalArea: Float,
        worldToCamera: simd_float4x4,
        intrinsics: DimensionsData.Intrinsics,
        photoSize: CGSize
    ) -> DetectedOpening? {
        // 1. Area-weighted normal in world frame.
        var weightedNormalWorld = SIMD3<Float>(repeating: 0)
        for f in faces {
            weightedNormalWorld += f.area * f.normal
        }
        guard simd_length(weightedNormalWorld) > 1e-6 else { return nil }
        let normalWorld = simd_normalize(weightedNormalWorld)

        // 2. Build the rotation block of worldToCamera to express the normal
        // in camera frame.
        let rotW2C = simd_float3x3(
            SIMD3<Float>(worldToCamera.columns.0.x, worldToCamera.columns.0.y, worldToCamera.columns.0.z),
            SIMD3<Float>(worldToCamera.columns.1.x, worldToCamera.columns.1.y, worldToCamera.columns.1.z),
            SIMD3<Float>(worldToCamera.columns.2.x, worldToCamera.columns.2.y, worldToCamera.columns.2.z)
        )
        let normalCam = simd_normalize(rotW2C * normalWorld)

        // 3. All vertices of the cluster in camera frame.
        var verticesCam: [SIMD3<Double>] = []
        verticesCam.reserveCapacity(faces.count * 3)
        for f in faces {
            for v in [f.v0, f.v1, f.v2] {
                let vh = SIMD4<Float>(v.x, v.y, v.z, 1)
                let cam = worldToCamera * vh
                verticesCam.append(SIMD3<Double>(Double(cam.x), Double(cam.y), Double(cam.z)))
            }
        }

        // 4. Plane offset in camera frame (using cluster centroid).
        let centroid = verticesCam.reduce(SIMD3<Double>.zero, +) / Double(verticesCam.count)
        let normalCamD = SIMD3<Double>(Double(normalCam.x), Double(normalCam.y), Double(normalCam.z))
        let planeOffset = -simd_dot(normalCamD, centroid)

        // 5. Project all vertices to photo pixels. Skip any behind the camera.
        var pixels: [SIMD2<Double>] = []
        pixels.reserveCapacity(verticesCam.count)
        for v in verticesCam {
            guard v.z > 1e-6 else { continue }
            let u = intrinsics.fx * v.x / v.z + intrinsics.cx
            let p = intrinsics.fy * v.y / v.z + intrinsics.cy
            pixels.append(SIMD2<Double>(u, p))
        }
        guard !pixels.isEmpty else { return nil }

        // 6. Axis-aligned bounding rectangle in pixel space.
        var uMin = Double.infinity, uMax = -Double.infinity
        var vMin = Double.infinity, vMax = -Double.infinity
        for p in pixels {
            if p.x < uMin { uMin = p.x }
            if p.x > uMax { uMax = p.x }
            if p.y < vMin { vMin = p.y }
            if p.y > vMax { vMax = p.y }
        }
        // Clamp to photo bounds — the polygon represents an on-screen region.
        uMin = max(0, uMin); vMin = max(0, vMin)
        uMax = min(Double(photoSize.width), uMax)
        vMax = min(Double(photoSize.height), vMax)
        guard uMax > uMin, vMax > vMin else { return nil }

        let polygon: [DimensionsData.Point2] = [
            .init(x: uMin, y: vMin),
            .init(x: uMax, y: vMin),
            .init(x: uMax, y: vMax),
            .init(x: uMin, y: vMax),
        ]

        // 7. Lift the 4 pixel corners back onto the plane.
        let corners3D = polygon.compactMap { pt -> SIMD3<Double>? in
            return intersectRayWithPlane(
                pixelU: pt.x, pixelV: pt.y,
                intrinsics: intrinsics,
                planeNormal: normalCamD,
                planeOffset: planeOffset
            )
        }
        guard corners3D.count == 4 else { return nil }

        // 8. Heuristic confidence: scale with cluster area, saturating at 0.1 m².
        let confidence = min(1.0, Double(totalArea) / 0.1)

        return DetectedOpening(
            id: UUID(),
            type: type,
            classificationConfidence: confidence,
            boundingPolygon: polygon,
            cornersCameraFrame: corners3D,
            planeNormal: normalCamD,
            planeOffset: planeOffset
        )
    }

    /// Intersect the pixel ray from the camera origin through (u, v) with the
    /// plane `dot(normal, p) + offset = 0`. Returns the 3D point in camera
    /// frame, or `nil` for a degenerate (parallel) intersection.
    static func intersectRayWithPlane(
        pixelU u: Double, pixelV v: Double,
        intrinsics: DimensionsData.Intrinsics,
        planeNormal n: SIMD3<Double>,
        planeOffset d: Double
    ) -> SIMD3<Double>? {
        let rx = (u - intrinsics.cx) / intrinsics.fx
        let ry = (v - intrinsics.cy) / intrinsics.fy
        let ray = SIMD3<Double>(rx, ry, 1)
        let denom = simd_dot(n, ray)
        guard abs(denom) > 1e-9 else { return nil }
        let t = -d / denom
        guard t > 0 else { return nil }
        return ray * t
    }
}
