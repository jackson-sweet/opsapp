//
//  ReferenceObjectCalibrator.swift
//  OPS
//
//  Reference-object precision calibration. Detects a credit card or printed
//  OPS marker in a still photo via Vision, solves planar PnP, and produces a
//  `CalibrationResult` carrying the marker's pose in the camera frame plus an
//  accuracy estimate.
//
//  Honest limitation (spec §3.8): on devices without LiDAR, the result is
//  flagged `coplanarOnly = true`. The calibrated scale is only accurate for
//  image points that lie on (or very near) the marker's plane. Out-of-plane
//  measurements regress to visual-SLAM accuracy.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.3 §3.8
//

import Foundation
import CoreGraphics
import simd
import Vision

public enum ReferenceMarker: Equatable {
    /// CR-80 ID card / credit card: 85.60 × 53.98 mm, aspect 1.586.
    /// Aspect tolerance band 1.55–1.62 per spec §3.3.
    case creditCard
    /// Custom OPS-printed marker: 100 × 100 mm square. Geometry defined in
    /// `OPS/Measurement/README.md`. Aspect 1.0.
    case opsMarker

    public var widthMeters: Double {
        switch self {
        case .creditCard: return 0.08560
        case .opsMarker:  return 0.10000
        }
    }
    public var heightMeters: Double {
        switch self {
        case .creditCard: return 0.05398
        case .opsMarker:  return 0.10000
        }
    }

    public var visionMinAspect: Float {
        switch self {
        case .creditCard: return 1.55
        case .opsMarker:  return 0.95
        }
    }
    public var visionMaxAspect: Float {
        switch self {
        case .creditCard: return 1.62
        case .opsMarker:  return 1.05
        }
    }

    /// Maps to the `DimensionsData.Calibration.ReferenceObject` enum for persistence.
    public var persistenceTag: DimensionsData.Calibration.ReferenceObject {
        switch self {
        case .creditCard: return .creditCard
        case .opsMarker:  return .opsMarker
        }
    }
}

public struct CalibrationResult {
    /// World-to-camera transform of the marker (marker-local frame → camera frame).
    public let markerPose: simd_double4x4
    /// Plane normal in the camera frame — the marker's outward face direction.
    public let markerPlaneNormal: SIMD3<Double>
    /// Signed offset so the marker plane equation in camera frame is
    /// `dot(normal, p) + offset = 0`.
    public let markerPlaneOffset: Double
    /// Multiplicative scale correction for subsequent measurements. `1.0` when
    /// no correction is appropriate (current default — Phase D will compare
    /// against LiDAR depth at the marker location for true correction).
    public let scaleFactor: Double
    /// 1-sigma accuracy estimate, in metres. Spec §3.6: ±5 mm calibrated.
    public let accuracyMeters: Double
    /// `true` when calibration is only valid for image points coplanar with
    /// the marker. Always `true` on non-LiDAR devices. Spec §3.8.
    public let coplanarOnly: Bool
    public let referenceObject: DimensionsData.Calibration.ReferenceObject

    public init(markerPose: simd_double4x4,
                markerPlaneNormal: SIMD3<Double>,
                markerPlaneOffset: Double,
                scaleFactor: Double,
                accuracyMeters: Double,
                coplanarOnly: Bool,
                referenceObject: DimensionsData.Calibration.ReferenceObject) {
        self.markerPose = markerPose
        self.markerPlaneNormal = markerPlaneNormal
        self.markerPlaneOffset = markerPlaneOffset
        self.scaleFactor = scaleFactor
        self.accuracyMeters = accuracyMeters
        self.coplanarOnly = coplanarOnly
        self.referenceObject = referenceObject
    }
}

public enum ReferenceObjectCalibratorError: Error, Equatable {
    case noRectangleDetected
    case rectangleAspectOutOfBounds(detected: Float, expectedMin: Float, expectedMax: Float)
    case pnpFailed
}

public struct ReferenceObjectCalibrator {

    /// Calibrate from a still photo. Runs Vision rectangle detection then
    /// PnP. Synchronous — Vision exposes a sync API.
    public static func calibrate(
        image: CGImage,
        intrinsics: DimensionsData.Intrinsics,
        marker: ReferenceMarker,
        hasLiDAR: Bool
    ) throws -> CalibrationResult {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = marker.visionMinAspect
        request.maximumAspectRatio = marker.visionMaxAspect
        request.minimumSize = 0.05
        request.minimumConfidence = 0.6
        request.maximumObservations = 8

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            throw ReferenceObjectCalibratorError.noRectangleDetected
        }
        // Take the highest-confidence rectangle.
        let best = observations.max(by: { $0.confidence < $1.confidence })!
        let aspect = aspectRatio(of: best)
        guard aspect >= marker.visionMinAspect, aspect <= marker.visionMaxAspect else {
            throw ReferenceObjectCalibratorError.rectangleAspectOutOfBounds(
                detected: aspect,
                expectedMin: marker.visionMinAspect,
                expectedMax: marker.visionMaxAspect
            )
        }
        // Vision returns normalized [0,1] image coords with origin bottom-left.
        // Convert to top-left pixel space matching the intrinsics convention.
        let h = Double(image.height)
        let w = Double(image.width)
        let corners: [SIMD2<Double>] = [
            normalizedToPixel(best.bottomLeft,  width: w, height: h),
            normalizedToPixel(best.bottomRight, width: w, height: h),
            normalizedToPixel(best.topRight,    width: w, height: h),
            normalizedToPixel(best.topLeft,     width: w, height: h),
        ]
        return try calibrate(
            detectedCorners: corners,
            intrinsics: intrinsics,
            marker: marker,
            hasLiDAR: hasLiDAR
        )
    }

    /// Lower-level entry point: takes pre-detected corner pixels and skips
    /// Vision entirely. The corners must be ordered counter-clockwise starting
    /// from bottom-left in the *photo's top-left-origin pixel space* and must
    /// correspond to the marker corners ordered counter-clockwise starting at
    /// (-w/2, +h/2) in marker-local coordinates (the bottom-left visual
    /// corner in a y-down image is the +Y corner in marker-local since the
    /// marker's local frame uses +Y down to match the camera convention).
    public static func calibrate(
        detectedCorners: [SIMD2<Double>],
        intrinsics: DimensionsData.Intrinsics,
        marker: ReferenceMarker,
        hasLiDAR: Bool
    ) throws -> CalibrationResult {
        let hw = marker.widthMeters / 2
        let hh = marker.heightMeters / 2
        // Marker corners in marker-local 2D, counter-clockwise from bottom-left
        // in image-up orientation (matching Vision's `bottomLeft → bottomRight
        // → topRight → topLeft` order). Camera frame is +Y down, so a "bottom"
        // image corner sits at +Y in marker-local.
        let worldCorners: [SIMD2<Double>] = [
            SIMD2(-hw,  hh),
            SIMD2( hw,  hh),
            SIMD2( hw, -hh),
            SIMD2(-hw, -hh),
        ]
        let pose: simd_double4x4
        do {
            pose = try PnPSolver.solvePlanarPose(
                worldPoints: worldCorners,
                imagePoints: detectedCorners,
                intrinsics: intrinsics
            )
        } catch {
            throw ReferenceObjectCalibratorError.pnpFailed
        }

        // Marker plane in camera frame: third column of R (z-axis of marker
        // frame expressed in camera frame), passing through the translation.
        let r3 = SIMD3<Double>(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)
        let t = SIMD3<Double>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
        let n = simd_normalize(r3)
        let offset = -simd_dot(n, t)

        return CalibrationResult(
            markerPose: pose,
            markerPlaneNormal: n,
            markerPlaneOffset: offset,
            scaleFactor: 1.0,
            accuracyMeters: hasLiDAR ? 0.005 : 0.005, // ±5 mm in both, but…
            coplanarOnly: !hasLiDAR,                  // …non-LiDAR only valid on plane.
            referenceObject: marker.persistenceTag
        )
    }

    // MARK: - Helpers

    private static func aspectRatio(of obs: VNRectangleObservation) -> Float {
        let bl = obs.bottomLeft, br = obs.bottomRight, tl = obs.topLeft
        let width  = hypotf(Float(br.x - bl.x), Float(br.y - bl.y))
        let height = hypotf(Float(tl.x - bl.x), Float(tl.y - bl.y))
        guard height > 0 else { return 0 }
        return width / height
    }

    private static func normalizedToPixel(_ p: CGPoint, width: Double, height: Double) -> SIMD2<Double> {
        // Vision uses bottom-left origin, normalized [0,1]. Convert to top-left
        // pixel space so it matches the camera intrinsics.
        let u = Double(p.x) * width
        let v = (1.0 - Double(p.y)) * height
        return SIMD2<Double>(u, v)
    }
}
