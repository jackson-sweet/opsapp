//
//  DimensionedCalibrationResolver.swift
//  OPS
//
//  Runs reference-object calibration from persisted capture assets without
//  inheriting SwiftUI view actor isolation.
//

import CoreGraphics
import Foundation
import ImageIO

enum DimensionedCalibrationResolverError: Error {
    case photoUnavailable
}

enum DimensionedCalibrationResolver {
    static func calibrationResult(
        from assets: CapturedAssets,
        hasLiDAR: Bool
    ) throws -> CalibrationResult {
        let image = try loadCalibrationImage(from: assets.heicURL)
        return try ReferenceObjectCalibrator.calibrate(
            image: image,
            intrinsics: assets.intrinsics,
            hasLiDAR: hasLiDAR
        )
    }

    private static func loadCalibrationImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DimensionedCalibrationResolverError.photoUnavailable
        }
        return image
    }
}
