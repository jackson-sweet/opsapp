//
//  DimensionedCalibrationSession.swift
//  OPS
//
//  Preserves the annotation state while the operator leaves the photo viewer
//  to recapture a reference object for calibration.
//

import Foundation

public struct DimensionedResolvedAnnotation {
    public let handoff: DimensionedAnnotationHandoff
    public let dimensions: DimensionsData
    public let coplanarOnly: Bool

    public var initialCalibration: DimensionsData.Calibration {
        dimensions.calibration
    }

    public init(
        handoff: DimensionedAnnotationHandoff,
        dimensions: DimensionsData,
        coplanarOnly: Bool
    ) {
        self.handoff = handoff
        self.dimensions = dimensions
        self.coplanarOnly = coplanarOnly
    }
}

public struct DimensionedCalibrationSession {
    public let originalHandoff: DimensionedAnnotationHandoff
    public let originalDimensions: DimensionsData
    public let originalCoplanarOnly: Bool

    public init(
        originalHandoff: DimensionedAnnotationHandoff,
        originalDimensions: DimensionsData,
        originalCoplanarOnly: Bool
    ) {
        self.originalHandoff = originalHandoff
        self.originalDimensions = originalDimensions
        self.originalCoplanarOnly = originalCoplanarOnly
    }

    public func cancelledAnnotation() -> DimensionedResolvedAnnotation {
        DimensionedResolvedAnnotation(
            handoff: originalHandoff,
            dimensions: originalDimensions,
            coplanarOnly: originalCoplanarOnly
        )
    }

    public func calibratedAnnotation(
        with result: CalibrationResult
    ) -> DimensionedResolvedAnnotation {
        var updated = originalDimensions
        updated.calibration = DimensionsData.Calibration(
            method: .referenceObject,
            referenceObject: result.referenceObject,
            scaleFactor: result.scaleFactor,
            estimatedAccuracyMeters: result.accuracyMeters
        )
        return DimensionedResolvedAnnotation(
            handoff: originalHandoff,
            dimensions: updated,
            coplanarOnly: result.coplanarOnly
        )
    }
}
