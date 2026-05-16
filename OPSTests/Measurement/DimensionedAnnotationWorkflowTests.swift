//
//  DimensionedAnnotationWorkflowTests.swift
//  OPSTests
//
//  Regression coverage for post-capture annotation save/exit continuity.
//

import SwiftData
import XCTest
@testable import OPS

final class DimensionedAnnotationWorkflowTests: XCTestCase {

    func test_manualMeasurementMarksAnnotationDirty() {
        XCTAssertTrue(
            DimensionedAnnotationWorkflow.dirtyAfterMeasurementCommit(previouslyDirty: false)
        )
    }

    func test_autoMeasurementWithResultsMarksAnnotationDirty() {
        XCTAssertTrue(
            DimensionedAnnotationWorkflow.dirtyAfterAutoMeasure(
                addedMeasurementCount: 4,
                previouslyDirty: false
            )
        )
    }

    func test_calibrationResultMarksAnnotationDirty() {
        XCTAssertTrue(
            DimensionedAnnotationWorkflow.dirtyAfterCalibrationResult(previouslyDirty: false)
        )
    }

    func test_closeWithCleanStateDismissesWithoutConfirmation() {
        XCTAssertEqual(
            DimensionedAnnotationWorkflow.closeDecision(
                hasUnsavedChanges: false,
                saveState: .idle
            ),
            .dismiss
        )
    }

    func test_closeWithDirtyStateRequiresConfirmation() {
        XCTAssertEqual(
            DimensionedAnnotationWorkflow.closeDecision(
                hasUnsavedChanges: true,
                saveState: .idle
            ),
            .confirmDiscard
        )
    }

    func test_closeWhileSavingRequiresConfirmation() {
        XCTAssertEqual(
            DimensionedAnnotationWorkflow.closeDecision(
                hasUnsavedChanges: false,
                saveState: .saving(copy: "// SAVING MEASUREMENTS")
            ),
            .confirmDiscard
        )
    }

    func test_calibrationOnlyDiscardSheetUsesCalibrationCopy() {
        XCTAssertEqual(
            CloseConfirmationSheetCopy.title(
                measurementCount: 0,
                includesCalibrationChange: true
            ),
            "// DISCARD CALIBRATION?"
        )
        XCTAssertEqual(
            CloseConfirmationSheetCopy.body(
                measurementCount: 0,
                includesCalibrationChange: true
            ),
            "CALIBRATION CHANGE HAS NOT BEEN SAVED. THIS CANNOT BE UNDONE."
        )
    }

    func test_saveFailureKeepsAnnotationDirtyAndExposesRetryCopy() {
        let result = DimensionedAnnotationWorkflow.saveFailureState()

        XCTAssertTrue(result.keepsOperatorInContext)
        XCTAssertTrue(result.leavesAnnotationDirty)
        XCTAssertEqual(result.saveState, .failed(copy: "// SAVE FAILED · RETRY"))
    }

    func test_queuedSaveClearsDirtyButKeepsRetryVisible() {
        let result = DimensionedAnnotationWorkflow.queuedSaveState()

        XCTAssertTrue(result.keepsOperatorInContext)
        XCTAssertFalse(result.leavesAnnotationDirty)
        XCTAssertEqual(result.saveState, .queued(copy: "// SYNC QUEUED · RETRY"))
    }

    @MainActor
    func test_queuedSavePersistsLocalAssetsAndDimensionsForRetry() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let captured = fixtureCaptured()
        let dimensions = fixtureDimensions()
        let queued = PhotoAnnotation(
            id: "local-\(captured.captureID.uuidString)",
            projectId: "project-123",
            companyId: "company-abc",
            photoURL: captured.heicURL.path,
            authorId: "user-xyz",
            createdAt: captured.captureFinishedAt
        )
        queued.dimensions = dimensions
        queued.localDepthMapPath = captured.depthURL?.path
        queued.localSidecarPath = captured.sidecarURL.path
        queued.localCaptureFinishedAt = captured.captureFinishedAt
        queued.needsSync = true
        DimensionedPhotoSyncManager.lastQueuedAnnotation = queued

        let persisted = try DimensionedCaptureSaveStore.persistQueuedAnnotation(
            captured: captured,
            modelContext: context
        )

        XCTAssertEqual(persisted.id, queued.id)
        XCTAssertTrue(persisted.needsSync)
        XCTAssertEqual(persisted.localDepthMapPath, captured.depthURL?.path)
        XCTAssertEqual(persisted.localSidecarPath, captured.sidecarURL.path)
        XCTAssertEqual(persisted.localCaptureFinishedAt, captured.captureFinishedAt)
        XCTAssertEqual(persisted.dimensions, Optional(dimensions))

        let queuedID = queued.id
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.id == queuedID }
        )
        let fetched = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertEqual(fetched.dimensions, Optional(dimensions))
        XCTAssertEqual(fetched.localSidecarPath, captured.sidecarURL.path)
        XCTAssertTrue(fetched.needsSync)
        XCTAssertNil(DimensionedPhotoSyncManager.lastQueuedAnnotation)
    }

    @MainActor
    func test_pendingDimensionedAnnotationCountsAsPendingSyncWork() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let captured = fixtureCaptured()
        let queued = PhotoAnnotation(
            id: DimensionedCaptureSaveStore.localQueuedAnnotationID(for: captured),
            projectId: "project-123",
            companyId: "company-abc",
            photoURL: captured.heicURL.path,
            authorId: "user-xyz",
            createdAt: captured.captureFinishedAt
        )
        queued.dimensions = fixtureDimensions()
        queued.localDepthMapPath = captured.depthURL?.path
        queued.localSidecarPath = captured.sidecarURL.path
        queued.localCaptureFinishedAt = captured.captureFinishedAt
        queued.needsSync = true
        context.insert(queued)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        XCTAssertEqual(syncEngine.pendingOperationCount, 1)
    }

    @MainActor
    func test_syncedSaveReplacesPriorQueuedCaptureInsteadOfDuplicating() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let captured = fixtureCaptured()
        let localID = "local-\(captured.captureID.uuidString)"
        let queued = PhotoAnnotation(
            id: localID,
            projectId: "project-123",
            companyId: "company-abc",
            photoURL: captured.heicURL.path,
            authorId: "user-xyz",
            createdAt: captured.captureFinishedAt
        )
        queued.needsSync = true
        context.insert(queued)
        try context.save()

        let synced = PhotoAnnotation(
            id: "server-annotation-1",
            projectId: "project-123",
            companyId: "company-abc",
            photoURL: "https://cdn.ops.test/measurements/photo.heic",
            authorId: "user-xyz",
            createdAt: captured.captureFinishedAt
        )
        synced.dimensions = fixtureDimensions()

        try DimensionedCaptureSaveStore.persistSyncedAnnotation(
            synced,
            captured: captured,
            modelContext: context
        )

        let all = try context.fetch(FetchDescriptor<PhotoAnnotation>())
        XCTAssertEqual(all.map(\.id), ["server-annotation-1"])
        XCTAssertFalse(try XCTUnwrap(all.first).needsSync)
    }

    private func fixtureCaptured() -> CapturedAssets {
        let captureID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let urls = CapturedAssets.in(
            directory: directory,
            captureID: captureID,
            includesDepthAsset: true
        )
        return CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: .init(
                fx: 1000,
                fy: 1000,
                cx: 500,
                cy: 500,
                imageWidth: 1000,
                imageHeight: 1000
            ),
            arkitSnapshot: .init(
                meshAnchors: [],
                cameraIntrinsics: .init(
                    fx: 1000,
                    fy: 1000,
                    cx: 500,
                    cy: 500,
                    imageWidth: 1000,
                    imageHeight: 1000
                ),
                devicePose: Array(repeating: 0, count: 16),
                timestamp: Date(timeIntervalSince1970: 1)
            ),
            captureID: captureID,
            captureFinishedAt: Date(timeIntervalSince1970: 1_747_166_400)
        )
    }

    private func fixtureDimensions() -> DimensionsData {
        DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(
                fx: 1000,
                fy: 1000,
                cx: 500,
                cy: 500,
                imageWidth: 1000,
                imageHeight: 1000
            ),
            depthAssetUrl: "file:///capture.depth.fp32",
            sidecarMetadataUrl: "file:///capture.metadata.json",
            measurements: [
                .init(
                    type: .linear,
                    label: "Manual",
                    worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                    imagePoints: [.init(x: 10, y: 10), .init(x: 200, y: 10)],
                    valueMeters: 1,
                    labelPlacement: .init(side: .north, leaderLengthPx: 60),
                    source: .manual
                )
            ]
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([PhotoAnnotation.self, SyncOperation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
