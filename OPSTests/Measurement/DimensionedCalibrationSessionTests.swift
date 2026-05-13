//
//  DimensionedCalibrationSessionTests.swift
//  OPSTests
//
//  Regression coverage for the annotation -> CALIBRATE -> annotation loop.
//

import XCTest
import simd
@testable import OPS

final class DimensionedCalibrationSessionTests: XCTestCase {

    private let intrinsics = DimensionsData.Intrinsics(
        fx: 1000,
        fy: 1000,
        cx: 500,
        cy: 500,
        imageWidth: 1000,
        imageHeight: 1000
    )

    func test_cancelledCalibrationReopensOriginalAnnotationUnchanged() throws {
        let handoff = makeHandoff(capability: .lidar)
        let original = makeDimensions(
            calibration: DimensionsData.Calibration(
                method: .lidar,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.025
            )
        )
        let session = DimensionedCalibrationSession(
            originalHandoff: handoff,
            originalDimensions: original,
            originalCoplanarOnly: false,
            originalHasUnsavedChanges: false
        )

        let reopened = session.cancelledAnnotation()

        XCTAssertEqual(reopened.handoff.assets, handoff.assets)
        XCTAssertEqual(reopened.dimensions, original)
        XCTAssertEqual(reopened.initialCalibration, original.calibration)
        XCTAssertFalse(reopened.coplanarOnly)
        XCTAssertFalse(reopened.hasUnsavedChanges)
    }

    func test_cancelledCalibrationRestoresOriginalDirtyFlag() throws {
        let handoff = makeHandoff(capability: .lidar)
        let original = makeDimensions(
            calibration: DimensionsData.Calibration(
                method: .lidar,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.025
            )
        )
        let session = DimensionedCalibrationSession(
            originalHandoff: handoff,
            originalDimensions: original,
            originalCoplanarOnly: false,
            originalHasUnsavedChanges: true
        )

        let reopened = session.cancelledAnnotation()

        XCTAssertEqual(reopened.dimensions, original)
        XCTAssertTrue(reopened.hasUnsavedChanges)

        let presentation = DimensionedCaptureView.AnnotationPresentation(resolved: reopened)
        XCTAssertTrue(presentation.hasUnsavedChanges)
        XCTAssertEqual(presentation.existingDimensions, original)
    }

    func test_successfulLiDARCalibrationPreservesMeasurementsAndUpgradesCalibration() throws {
        let handoff = makeHandoff(capability: .lidar)
        let original = makeDimensions(
            calibration: DimensionsData.Calibration(
                method: .lidar,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.025
            )
        )
        let result = makeCalibrationResult(
            scaleFactor: 0.992,
            coplanarOnly: false,
            referenceObject: .opsMarker
        )
        let session = DimensionedCalibrationSession(
            originalHandoff: handoff,
            originalDimensions: original,
            originalCoplanarOnly: false,
            originalHasUnsavedChanges: true
        )

        let reopened = session.calibratedAnnotation(with: result)

        XCTAssertEqual(reopened.handoff.assets, handoff.assets)
        XCTAssertEqual(reopened.dimensions.measurements, original.measurements)
        XCTAssertEqual(reopened.dimensions.captureMode, original.captureMode)
        XCTAssertEqual(reopened.dimensions.calibration.method, .referenceObject)
        XCTAssertEqual(reopened.dimensions.calibration.referenceObject, .opsMarker)
        XCTAssertEqual(reopened.dimensions.calibration.scaleFactor, 0.992, accuracy: 1e-9)
        XCTAssertEqual(reopened.dimensions.calibration.estimatedAccuracyMeters, 0.005, accuracy: 1e-9)
        XCTAssertEqual(reopened.initialCalibration, reopened.dimensions.calibration)
        XCTAssertFalse(reopened.coplanarOnly)
        XCTAssertTrue(reopened.hasUnsavedChanges)
    }

    func test_successfulCalibrationReopensDirtyWhenOriginalWasClean() throws {
        let handoff = makeHandoff(capability: .lidar)
        let original = makeDimensions(
            calibration: DimensionsData.Calibration(
                method: .lidar,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.025
            )
        )
        let result = makeCalibrationResult(
            scaleFactor: 0.992,
            coplanarOnly: false,
            referenceObject: .opsMarker
        )
        let session = DimensionedCalibrationSession(
            originalHandoff: handoff,
            originalDimensions: original,
            originalCoplanarOnly: false,
            originalHasUnsavedChanges: false
        )

        let reopened = session.calibratedAnnotation(with: result)

        XCTAssertEqual(reopened.dimensions.measurements, original.measurements)
        XCTAssertEqual(reopened.dimensions.calibration.method, .referenceObject)
        XCTAssertTrue(reopened.hasUnsavedChanges)

        let presentation = DimensionedCaptureView.AnnotationPresentation(resolved: reopened)
        XCTAssertTrue(presentation.hasUnsavedChanges)
        XCTAssertEqual(presentation.existingDimensions?.calibration.method, .referenceObject)
    }

    func test_successfulVisualCalibrationMarksReopenedAnnotationCoplanarOnly() throws {
        let handoff = makeHandoff(capability: .visual)
        let original = makeDimensions(
            captureMode: .visual,
            calibration: DimensionsData.Calibration(
                method: .none,
                referenceObject: nil,
                scaleFactor: 1.0,
                estimatedAccuracyMeters: 0.05
            )
        )
        let result = makeCalibrationResult(
            scaleFactor: 1.018,
            coplanarOnly: true,
            referenceObject: .creditCard
        )
        let session = DimensionedCalibrationSession(
            originalHandoff: handoff,
            originalDimensions: original,
            originalCoplanarOnly: false,
            originalHasUnsavedChanges: false
        )

        let reopened = session.calibratedAnnotation(with: result)

        XCTAssertEqual(reopened.dimensions.measurements, original.measurements)
        XCTAssertEqual(reopened.dimensions.captureMode, .visual)
        XCTAssertEqual(reopened.dimensions.calibration.method, .referenceObject)
        XCTAssertEqual(reopened.dimensions.calibration.referenceObject, .creditCard)
        XCTAssertEqual(reopened.dimensions.calibration.scaleFactor, 1.018, accuracy: 1e-9)
        XCTAssertTrue(reopened.coplanarOnly)
        XCTAssertTrue(reopened.hasUnsavedChanges)
    }

    func test_calibratorTriesCreditCardThenOpsMarkerBeforeFailing() throws {
        var attempts: [ReferenceMarker] = []
        let expected = makeCalibrationResult(
            scaleFactor: 1.0,
            coplanarOnly: false,
            referenceObject: .opsMarker
        )

        let result = try ReferenceObjectCalibrator.firstSuccessfulCalibration(
            markers: [.creditCard, .opsMarker]
        ) { marker in
            attempts.append(marker)
            if marker == .creditCard {
                throw ReferenceObjectCalibratorError.noRectangleDetected
            }
            return expected
        }

        XCTAssertEqual(attempts, [.creditCard, .opsMarker])
        XCTAssertEqual(result.referenceObject, .opsMarker)
    }

    private func makeHandoff(
        capability: CaptureCapability
    ) -> DimensionedAnnotationHandoff {
        let captureID = UUID()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let urls = CapturedAssets.in(
            directory: directory,
            captureID: captureID,
            includesDepthAsset: capability == .lidar
        )
        let snapshot = ARKitSnapshot(
            meshAnchors: [],
            meshFaces: [],
            cameraIntrinsics: intrinsics,
            devicePose: [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1
            ],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let calibration = DimensionsData.Calibration(
            method: capability == .lidar ? .lidar : .none,
            referenceObject: nil,
            scaleFactor: 1.0,
            estimatedAccuracyMeters: capability == .lidar ? 0.025 : 0.05
        )
        let assets = CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: intrinsics,
            arkitSnapshot: snapshot,
            captureID: captureID,
            captureFinishedAt: Date(timeIntervalSince1970: 1)
        )
        return DimensionedAnnotationHandoff(
            assets: assets,
            preloadedDepthMap: nil,
            anchors: nil,
            detectedOpenings: [],
            initialCalibration: calibration,
            capability: capability,
            coplanarOnly: false
        )
    }

    private func makeDimensions(
        captureMode: DimensionsData.CaptureMode = .lidar,
        calibration: DimensionsData.Calibration
    ) -> DimensionsData {
        DimensionsData(
            captureMode: captureMode,
            calibration: calibration,
            intrinsics: intrinsics,
            depthAssetUrl: "file:///capture.depth.fp32",
            sidecarMetadataUrl: "file:///capture.metadata.json",
            measurements: [
                DimensionsData.Measurement(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                    type: .linear,
                    label: "Width",
                    worldPoints: [
                        .init(x: 0, y: 0, z: 2),
                        .init(x: 1, y: 0, z: 2)
                    ],
                    imagePoints: [
                        .init(x: 100, y: 200),
                        .init(x: 400, y: 200)
                    ],
                    valueMeters: 1.0,
                    primaryDisplayUnit: .imperialFraction,
                    labelPlacement: .init(side: .north, leaderLengthPx: 44),
                    source: .manual
                ),
                DimensionsData.Measurement(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                    type: .linear,
                    label: "Height",
                    worldPoints: [
                        .init(x: 1, y: 0, z: 2),
                        .init(x: 1, y: 1, z: 2)
                    ],
                    imagePoints: [
                        .init(x: 400, y: 200),
                        .init(x: 400, y: 600)
                    ],
                    valueMeters: 1.0,
                    primaryDisplayUnit: .imperialFraction,
                    labelPlacement: .init(side: .east, leaderLengthPx: 44),
                    source: .manual
                )
            ],
            openings: []
        )
    }

    private func makeCalibrationResult(
        scaleFactor: Double,
        coplanarOnly: Bool,
        referenceObject: DimensionsData.Calibration.ReferenceObject
    ) -> CalibrationResult {
        CalibrationResult(
            markerPose: simd_double4x4(diagonal: SIMD4<Double>(1, 1, 1, 1)),
            markerPlaneNormal: SIMD3<Double>(0, 0, 1),
            markerPlaneOffset: -1,
            scaleFactor: scaleFactor,
            accuracyMeters: 0.005,
            coplanarOnly: coplanarOnly,
            referenceObject: referenceObject
        )
    }
}
