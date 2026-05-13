//
//  DimensionedAnnotationHandoff.swift
//  OPS
//
//  Adapts completed capture assets into the preloaded measurement inputs
//  consumed by DimensionedAnnotationView.
//

import CoreGraphics
import Foundation

public struct DimensionedAnnotationHandoff {
    public let assets: CapturedAssets
    public let preloadedDepthMap: DepthMap?
    public let anchors: AnchorSnapshot?
    public let detectedOpenings: [DetectedOpening]
    public let initialCalibration: DimensionsData.Calibration
    public let capability: CaptureCapability
    public let coplanarOnly: Bool

    public var hasAuto: Bool {
        preloadedDepthMap != nil && anchors != nil && !detectedOpenings.isEmpty
    }

    public var hasCalibrate: Bool {
        capability != .noDepth
    }
}

public enum DimensionedAnnotationHandoffBuilder {
    public static func build(
        assets: CapturedAssets,
        capability: CaptureCapability
    ) -> DimensionedAnnotationHandoff {
        let initialCalibration = initialCalibration(for: capability)

        guard capability == .lidar else {
            return DimensionedAnnotationHandoff(
                assets: assets,
                preloadedDepthMap: nil,
                anchors: nil,
                detectedOpenings: [],
                initialCalibration: initialCalibration,
                capability: capability,
                coplanarOnly: false
            )
        }

        let depth = DepthMapLoader.load(from: assets.depthURL)
        guard let anchors = AnchorSnapshot(arkitSnapshot: assets.arkitSnapshot) else {
            return DimensionedAnnotationHandoff(
                assets: assets,
                preloadedDepthMap: depth,
                anchors: nil,
                detectedOpenings: [],
                initialCalibration: initialCalibration,
                capability: capability,
                coplanarOnly: false
            )
        }

        let photoSize = CGSize(
            width: CGFloat(assets.intrinsics.imageWidth),
            height: CGFloat(assets.intrinsics.imageHeight)
        )
        let openings = OpeningClassifier.classify(
            anchors: anchors,
            intrinsics: assets.intrinsics,
            photoSize: photoSize
        )
        let measurableOpenings = depth == nil ? [] : openings.filter { opening in
            !AutoMeasurer.measure(
                opening: opening,
                anchors: anchors,
                photoSize: photoSize
            )
            .allMeasurements
            .isEmpty
        }

        return DimensionedAnnotationHandoff(
            assets: assets,
            preloadedDepthMap: depth,
            anchors: anchors,
            detectedOpenings: measurableOpenings,
            initialCalibration: initialCalibration,
            capability: capability,
            coplanarOnly: false
        )
    }

    private static func initialCalibration(
        for capability: CaptureCapability
    ) -> DimensionsData.Calibration {
        switch capability {
        case .lidar:
            return DimensionsData.Calibration(
                method: .lidar,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.025
            )
        case .visual:
            return DimensionsData.Calibration(
                method: .none,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.05
            )
        case .noDepth:
            return DimensionsData.Calibration(
                method: .none,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.05
            )
        }
    }
}
