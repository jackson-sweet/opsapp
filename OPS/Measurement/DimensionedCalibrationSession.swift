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
    public let hasUnsavedChanges: Bool

    public var initialCalibration: DimensionsData.Calibration {
        dimensions.calibration
    }

    public init(
        handoff: DimensionedAnnotationHandoff,
        dimensions: DimensionsData,
        coplanarOnly: Bool,
        hasUnsavedChanges: Bool
    ) {
        self.handoff = handoff
        self.dimensions = dimensions
        self.coplanarOnly = coplanarOnly
        self.hasUnsavedChanges = hasUnsavedChanges
    }
}

public struct DimensionedCalibrationSession {
    public let originalHandoff: DimensionedAnnotationHandoff
    public let originalDimensions: DimensionsData
    public let originalCoplanarOnly: Bool
    public let originalHasUnsavedChanges: Bool

    public init(
        originalHandoff: DimensionedAnnotationHandoff,
        originalDimensions: DimensionsData,
        originalCoplanarOnly: Bool,
        originalHasUnsavedChanges: Bool
    ) {
        self.originalHandoff = originalHandoff
        self.originalDimensions = originalDimensions
        self.originalCoplanarOnly = originalCoplanarOnly
        self.originalHasUnsavedChanges = originalHasUnsavedChanges
    }

    public func cancelledAnnotation() -> DimensionedResolvedAnnotation {
        DimensionedResolvedAnnotation(
            handoff: originalHandoff,
            dimensions: originalDimensions,
            coplanarOnly: originalCoplanarOnly,
            hasUnsavedChanges: originalHasUnsavedChanges
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
            estimatedAccuracyMeters: result.accuracyMeters,
            planeNormal: DimensionsData.Point3(
                x: result.markerPlaneNormal.x,
                y: result.markerPlaneNormal.y,
                z: result.markerPlaneNormal.z
            ),
            planeOffset: result.markerPlaneOffset
        )
        return DimensionedResolvedAnnotation(
            handoff: originalHandoff,
            dimensions: updated,
            coplanarOnly: result.coplanarOnly,
            hasUnsavedChanges: DimensionedAnnotationWorkflow
                .dirtyAfterCalibrationResult(previouslyDirty: originalHasUnsavedChanges)
        )
    }
}
