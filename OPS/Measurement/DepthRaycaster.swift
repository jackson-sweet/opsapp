//
//  DepthRaycaster.swift
//  OPS
//
//  Pure-math raycaster: photo-pixel + depth + intrinsics → 3D point in the
//  camera coordinate frame at shutter time (+X right, +Y down, +Z forward —
//  standard pinhole convention). Callers can transform to ARKit world frame
//  via the inverse of `AnchorSnapshot.worldToCamera` when needed.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.3
//

import Foundation
import CoreGraphics

public struct DepthRaycaster {

    public let intrinsics: DimensionsData.Intrinsics
    public let depth: DepthMap
    public let photoSize: CGSize

    public init(intrinsics: DimensionsData.Intrinsics, depth: DepthMap, photoSize: CGSize) {
        self.intrinsics = intrinsics
        self.depth = depth
        self.photoSize = photoSize
    }

    /// Raycast a single photo-pixel back into the camera frame.
    public func worldPoint(atPhotoPixel pixel: CGPoint) -> DimensionsData.Point3? {
        guard pixel.x >= 0, pixel.y >= 0,
              pixel.x <= photoSize.width, pixel.y <= photoSize.height else {
            return nil
        }
        guard let d = depth.depth(atPhotoPixel: Double(pixel.x),
                                  py: Double(pixel.y),
                                  photoWidth: Double(photoSize.width),
                                  photoHeight: Double(photoSize.height)) else {
            return nil
        }
        let dz = Double(d)
        let x = (Double(pixel.x) - intrinsics.cx) * dz / intrinsics.fx
        let y = (Double(pixel.y) - intrinsics.cy) * dz / intrinsics.fy
        return DimensionsData.Point3(x: x, y: y, z: dz)
    }

    /// Two-tap manual linear measurement. Both pixels must resolve to valid
    /// world points or this returns `nil`.
    public func linearMeasurement(from a: CGPoint, to b: CGPoint,
                                  label: String,
                                  primaryDisplayUnit: DimensionsData.Measurement.DisplayUnit = .imperialFraction,
                                  source: DimensionsData.Measurement.MeasurementSource = .manual) -> DimensionsData.Measurement? {
        guard let pa = worldPoint(atPhotoPixel: a),
              let pb = worldPoint(atPhotoPixel: b) else {
            return nil
        }
        let dx = pa.x - pb.x
        let dy = pa.y - pb.y
        let dz = pa.z - pb.z
        let dist: Double = (dx * dx + dy * dy + dz * dz).squareRoot()
        return DimensionsData.Measurement(
            type: .linear,
            label: label,
            worldPoints: [pa, pb],
            imagePoints: [
                DimensionsData.Point2(x: Double(a.x), y: Double(a.y)),
                DimensionsData.Point2(x: Double(b.x), y: Double(b.y))
            ],
            valueMeters: dist,
            primaryDisplayUnit: primaryDisplayUnit,
            labelPlacement: .init(side: .north, leaderLengthPx: 60),
            source: source
        )
    }
}

/// Intersects camera rays with a calibrated reference-object plane. This is
/// the non-LiDAR manual path: accurate only for points on the same plane as the
/// detected card/OPS marker, so callers must pair it with the COPLANAR ONLY UI.
public struct PlaneRaycaster {

    public let intrinsics: DimensionsData.Intrinsics
    public let photoSize: CGSize
    public let planeNormal: DimensionsData.Point3
    public let planeOffset: Double
    public let scaleFactor: Double

    public init(
        intrinsics: DimensionsData.Intrinsics,
        photoSize: CGSize,
        planeNormal: DimensionsData.Point3,
        planeOffset: Double,
        scaleFactor: Double = 1.0
    ) {
        self.intrinsics = intrinsics
        self.photoSize = photoSize
        self.planeNormal = planeNormal
        self.planeOffset = planeOffset
        self.scaleFactor = scaleFactor
    }

    public func worldPoint(atPhotoPixel pixel: CGPoint) -> DimensionsData.Point3? {
        guard pixel.x >= 0, pixel.y >= 0,
              pixel.x <= photoSize.width, pixel.y <= photoSize.height else {
            return nil
        }

        let ray = DimensionsData.Point3(
            x: (Double(pixel.x) - intrinsics.cx) / intrinsics.fx,
            y: (Double(pixel.y) - intrinsics.cy) / intrinsics.fy,
            z: 1
        )
        let denominator = planeNormal.x * ray.x
            + planeNormal.y * ray.y
            + planeNormal.z * ray.z
        guard abs(denominator) > 1e-9 else { return nil }

        let t = -planeOffset / denominator
        guard t.isFinite, t > 0 else { return nil }

        return DimensionsData.Point3(
            x: ray.x * t * scaleFactor,
            y: ray.y * t * scaleFactor,
            z: ray.z * t * scaleFactor
        )
    }

    public func linearMeasurement(
        from a: CGPoint,
        to b: CGPoint,
        label: String,
        primaryDisplayUnit: DimensionsData.Measurement.DisplayUnit = .imperialFraction,
        source: DimensionsData.Measurement.MeasurementSource = .manual
    ) -> DimensionsData.Measurement? {
        guard let pa = worldPoint(atPhotoPixel: a),
              let pb = worldPoint(atPhotoPixel: b) else {
            return nil
        }
        let dx = pa.x - pb.x
        let dy = pa.y - pb.y
        let dz = pa.z - pb.z
        let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
        return DimensionsData.Measurement(
            type: .linear,
            label: label,
            worldPoints: [pa, pb],
            imagePoints: [
                DimensionsData.Point2(x: Double(a.x), y: Double(a.y)),
                DimensionsData.Point2(x: Double(b.x), y: Double(b.y))
            ],
            valueMeters: dist,
            primaryDisplayUnit: primaryDisplayUnit,
            labelPlacement: .init(side: .north, leaderLengthPx: 60),
            source: source
        )
    }
}
