//
//  MeasurementInputs.swift
//  OPS
//
//  Input types consumed by the LiDAR measurement engine (Phase C). These types
//  describe the in-memory shape the engine needs at call time. Phase B's on-disk
//  `CapturedAssets` (URLs to HEIC + sidecar + raw depth) is a separate concept;
//  Phase D will adapt between them.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.2 §3.3
//

import Foundation
import CoreGraphics
import simd

/// A 2D depth map sampled at the depth sensor resolution (768×576 on LiDAR
/// devices). Values are perpendicular depth in metres (Z-distance from the
/// image plane, not ray length). `0` and non-finite values mark invalid /
/// unknown samples.
public struct DepthMap {
    public let width: Int
    public let height: Int
    /// Row-major Float32 depth in metres, `width * height` long.
    public let values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height, "depth buffer size mismatch")
        self.width = width
        self.height = height
        self.values = values
    }

    /// Sample depth at integer pixel coordinates in the depth map's own grid.
    /// Returns `nil` when out of bounds or the sample is invalid (≤0 or non-finite).
    public func depth(atX x: Int, y: Int) -> Float? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let v = values[y * width + x]
        guard v.isFinite, v > 0 else { return nil }
        return v
    }

    /// Sample depth at a coordinate expressed in the *photo* pixel space.
    /// Bi-linear interpolation handles the resolution mismatch between the
    /// 48 MP photo and the 768×576 depth map. Returns `nil` only when all
    /// four neighbouring samples are invalid.
    public func depth(atPhotoPixel px: Double, py: Double,
                      photoWidth: Double, photoHeight: Double) -> Float? {
        let nx = (px / photoWidth) * Double(width)
        let ny = (py / photoHeight) * Double(height)
        let x0 = Int(floor(nx))
        let y0 = Int(floor(ny))
        guard x0 >= 0, y0 >= 0, x0 < width, y0 < height else { return nil }
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = Float(nx - Double(x0))
        let ty = Float(ny - Double(y0))
        let v00 = values[y0 * width + x0]
        let v10 = values[y0 * width + x1]
        let v01 = values[y1 * width + x0]
        let v11 = values[y1 * width + x1]
        let valid = [v00, v10, v01, v11].filter { $0.isFinite && $0 > 0 }
        guard !valid.isEmpty else { return nil }
        if valid.count < 4 {
            return valid.reduce(0, +) / Float(valid.count)
        }
        let a = v00 * (1 - tx) + v10 * tx
        let b = v01 * (1 - tx) + v11 * tx
        return a * (1 - ty) + b * ty
    }
}

/// A single mesh face from the ARKit scene reconstruction, with its
/// classification label. Used by `OpeningClassifier` and `AutoMeasurer`.
public struct MeshFaceSnapshot: Equatable {
    public enum Classification: String, Codable, Equatable {
        case wall, floor, ceiling, table, seat, window, door, none
    }

    /// Triangle vertices in the capture-time ARKit world frame.
    public let v0: SIMD3<Float>
    public let v1: SIMD3<Float>
    public let v2: SIMD3<Float>
    public let classification: Classification

    public init(v0: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>,
                classification: Classification) {
        self.v0 = v0
        self.v1 = v1
        self.v2 = v2
        self.classification = classification
    }

    /// Right-hand-rule outward normal of the triangle.
    public var normal: SIMD3<Float> {
        simd_normalize(simd_cross(v1 - v0, v2 - v0))
    }

    public var centroid: SIMD3<Float> {
        (v0 + v1 + v2) / 3
    }

    /// Triangle area, used as a weighting term for plane fits.
    public var area: Float {
        0.5 * simd_length(simd_cross(v1 - v0, v2 - v0))
    }
}

/// Snapshot of the ARKit scene at shutter time — fine-grained mesh + gravity.
/// Captured before the ARKit → AVCapture session handoff. Phase B's
/// `ARKitSnapshot` is the *serialized* coarse form; this is the in-memory
/// fine-grained form the measurement engine consumes.
public struct AnchorSnapshot {
    public let faces: [MeshFaceSnapshot]
    /// Gravity-aligned up vector in the capture-time world frame.
    public let gravityUp: SIMD3<Float>
    /// 4×4 transform: world frame → camera frame at shutter.
    public let worldToCamera: simd_float4x4

    public init(faces: [MeshFaceSnapshot],
                gravityUp: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
                worldToCamera: simd_float4x4 = matrix_identity_float4x4) {
        self.faces = faces
        self.gravityUp = gravityUp
        self.worldToCamera = worldToCamera
    }

    /// All faces classified as wall.
    public var wallFaces: [MeshFaceSnapshot] {
        faces.filter { $0.classification == .wall }
    }

    /// All faces classified as floor.
    public var floorFaces: [MeshFaceSnapshot] {
        faces.filter { $0.classification == .floor }
    }
}
