//
//  DimensionedPhotoSyncManagerTests.swift
//  OPSTests
//
//  Phase F — verifies the three-asset upload pipeline + annotation row insert.
//  Uses an in-process mock uploader and persister so the test runs without
//  network, S3, or Supabase.
//
//  Coverage:
//    1. Happy path — three uploads called with correct filename / folder /
//       content-type, project_photos + annotation row inserted, returned
//       PhotoAnnotation carries the right dimensions jsonb shape.
//    2. Retry path — first attempt fails per asset, second succeeds; manager
//       reports success overall.
//    3. Queue-for-retry — all attempts on one asset fail; manager throws
//       `queuedForRetry`, `lastQueuedAnnotation` is populated with local
//       paths and `needsSync = true`.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md
//      §7 (three-asset upload + retry)
//      §6 (queued-for-sync notification mapping — caller responsibility)
//

import SwiftData
import XCTest
@testable import OPS

final class DimensionedPhotoSyncManagerTests: XCTestCase {

    // MARK: - Fixtures

    private func fixtureDimensions() -> DimensionsData {
        DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(fx: 1593.4, fy: 1593.4,
                              cx: 1015.5, cy: 762.0,
                              imageWidth: 4032, imageHeight: 3024),
            measurements: [
                .init(type: .linear,
                      label: "Width",
                      worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0.9144, y: 0, z: 0)],
                      imagePoints: [.init(x: 100, y: 500), .init(x: 800, y: 500)],
                      valueMeters: 0.9144,
                      labelPlacement: .init(side: .north, leaderLengthPx: 60),
                      source: .auto)
            ]
        )
    }

    private func fixtureCaptured(captureID: UUID = UUID(),
                                 in directory: URL? = nil) throws -> CapturedAssets {
        let dir = directory ?? makeTempDir()
        let urls = CapturedAssets.in(directory: dir, captureID: captureID)
        let depthURL = try XCTUnwrap(urls.depthURL)
        try Data("FAKE_HEIC_BYTES".utf8).write(to: urls.heicURL)
        try Data("{\"meshAnchors\":[]}".utf8).write(to: urls.sidecarURL)
        try Data([0x00, 0x00, 0x80, 0x3F]).write(to: depthURL)
        return CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: .init(fx: 1593.4, fy: 1593.4,
                              cx: 1015.5, cy: 762.0,
                              imageWidth: 4032, imageHeight: 3024),
            arkitSnapshot: .init(meshAnchors: [],
                                 cameraIntrinsics: .init(fx: 1593.4, fy: 1593.4,
                                                         cx: 1015.5, cy: 762.0,
                                                         imageWidth: 4032, imageHeight: 3024),
                                 devicePose: Array(repeating: 0, count: 16),
                                 timestamp: Date(timeIntervalSince1970: 1_747_166_400)),
            captureID: captureID,
            captureFinishedAt: Date(timeIntervalSince1970: 1_747_166_400)
        )
    }

    private func fixtureVisualCaptured(captureID: UUID = UUID(),
                                       in directory: URL? = nil) throws -> CapturedAssets {
        let dir = directory ?? makeTempDir()
        let urls = CapturedAssets.in(
            directory: dir,
            captureID: captureID,
            includesDepthAsset: false
        )
        try Data("FAKE_HEIC_BYTES".utf8).write(to: urls.heicURL)
        try Data("{\"meshAnchors\":[]}".utf8).write(to: urls.sidecarURL)
        return CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: .init(fx: 1593.4, fy: 1593.4,
                              cx: 1015.5, cy: 762.0,
                              imageWidth: 4032, imageHeight: 3024),
            arkitSnapshot: .init(meshAnchors: [],
                                 cameraIntrinsics: .init(fx: 1593.4, fy: 1593.4,
                                                         cx: 1015.5, cy: 762.0,
                                                         imageWidth: 4032, imageHeight: 3024),
                                 devicePose: Array(repeating: 0, count: 16),
                                 timestamp: Date(timeIntervalSince1970: 1_747_166_400)),
            captureID: captureID,
            captureFinishedAt: Date(timeIntervalSince1970: 1_747_166_400)
        )
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dim-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([PhotoAnnotation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - 1. Happy path

    @MainActor
    func test_sync_uploadsThreeAssets_andInsertsAnnotationRow() async throws {
        let captureID = UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!
        let captured = try fixtureCaptured(captureID: captureID)
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister, notifier: NoopDimensionedNotificationDispatcher())

        let annotation = try await manager.sync(
            captured: captured,
            dimensions: fixtureDimensions(),
            projectId: "project-123",
            projectName: "Smith Residence",
            companyId: "company-abc",
            userId: "user-xyz"
        )

        // Three uploads, in the contractual order HEIC → sidecar → depth.
        XCTAssertEqual(uploader.calls.count, 3)
        XCTAssertEqual(uploader.calls[0].filename, "\(captureID.uuidString).heic")
        XCTAssertEqual(uploader.calls[0].contentType, "image/heic")
        XCTAssertEqual(uploader.calls[1].filename, "\(captureID.uuidString).metadata.json")
        XCTAssertEqual(uploader.calls[1].contentType, "application/json")
        XCTAssertEqual(uploader.calls[2].filename, "\(captureID.uuidString).depth.fp32")
        XCTAssertEqual(uploader.calls[2].contentType, "application/octet-stream")
        XCTAssertEqual(uploader.calls[0].folder, "measurements/company-abc/project-123")

        // project_photos row was inserted with source=measurement, default invisible.
        XCTAssertEqual(persister.projectPhotoInserts.count, 1)
        XCTAssertEqual(persister.projectPhotoInserts.first?.uploadedBy, "user-xyz")

        // Annotation row was inserted with the enriched dimensions blob.
        XCTAssertEqual(persister.annotationInserts.count, 1)
        let inserted = try XCTUnwrap(persister.annotationInserts.first)
        XCTAssertNotNil(inserted.dimensions.depthAssetUrl)
        XCTAssertNotNil(inserted.dimensions.sidecarMetadataUrl)
        XCTAssertEqual(inserted.photoUrl, uploader.calls[0].returnedURL)

        // Returned annotation reflects the inserted row + local cache paths.
        XCTAssertEqual(annotation.photoURL, uploader.calls[0].returnedURL)
        XCTAssertFalse(annotation.needsSync)
        XCTAssertNotNil(annotation.dimensions?.sidecarMetadataUrl)
        XCTAssertNotNil(annotation.dimensions?.depthAssetUrl)
        XCTAssertEqual(annotation.localDepthMapPath, captured.depthURL?.path)
        XCTAssertEqual(annotation.localSidecarPath, captured.sidecarURL.path)
        XCTAssertEqual(annotation.localCaptureFinishedAt, captured.captureFinishedAt)
    }

    @MainActor
    func test_sync_visualCapture_uploadsHeicAndSidecarOnly() async throws {
        let captureID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let captured = try fixtureVisualCaptured(captureID: captureID)
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister, notifier: NoopDimensionedNotificationDispatcher())

        let annotation = try await manager.sync(
            captured: captured,
            dimensions: DimensionsData(
                captureMode: .visual,
                calibration: .init(method: .none, estimatedAccuracyMeters: 0.05),
                intrinsics: captured.intrinsics
            ),
            projectId: "project-123",
            projectName: "Smith Residence",
            companyId: "company-abc",
            userId: "user-xyz"
        )

        XCTAssertEqual(uploader.calls.count, 2)
        XCTAssertEqual(uploader.calls[0].filename, "\(captureID.uuidString).heic")
        XCTAssertEqual(uploader.calls[1].filename, "\(captureID.uuidString).metadata.json")
        XCTAssertNil(persister.annotationInserts.first?.dimensions.depthAssetUrl)
        XCTAssertNotNil(persister.annotationInserts.first?.dimensions.sidecarMetadataUrl)
        XCTAssertNil(annotation.localDepthMapPath)
        XCTAssertNil(annotation.dimensions?.depthAssetUrl)
    }

    @MainActor
    func test_sync_rejectsLidarDimensionsWhenStandaloneDepthAssetIsMissing() async throws {
        let captured = try fixtureVisualCaptured()
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister, notifier: NoopDimensionedNotificationDispatcher())

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "project-123",
                projectName: "Smith Residence",
                companyId: "company-abc",
                userId: "user-xyz"
            )
            XCTFail("Expected missingRequiredDepthAsset for LiDAR dimensions without a depth file")
        } catch let error as DimensionedSyncError {
            switch error {
            case .missingRequiredDepthAsset:
                break
            default:
                XCTFail("Wrong error case: \(error)")
            }
        }

        XCTAssertEqual(uploader.calls.count, 0)
        XCTAssertEqual(persister.annotationInserts.count, 0)
    }

    // MARK: - 2. Retry path

    @MainActor
    func test_sync_retriesOnTransientFailure_thenSucceeds() async throws {
        let captured = try fixtureCaptured()
        let uploader = RecordingUploader(plan: .failThenSucceed(failCount: 1))
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister, notifier: NoopDimensionedNotificationDispatcher())

        let annotation = try await manager.sync(
            captured: captured,
            dimensions: fixtureDimensions(),
            projectId: "p",
            projectName: "n",
            companyId: "c",
            userId: "u"
        )

        // 3 asset uploads × (1 fail + 1 success) = 6 attempts total.
        XCTAssertEqual(uploader.calls.count, 6)
        XCTAssertEqual(persister.annotationInserts.count, 1)
        XCTAssertFalse(annotation.needsSync)
    }

    // MARK: - 3. Queue-for-retry path

    @MainActor
    func test_sync_queuesForRetryWhenAllAttemptsFail() async throws {
        let captured = try fixtureCaptured()
        let uploader = RecordingUploader(plan: .alwaysFail)
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister, notifier: NoopDimensionedNotificationDispatcher())

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "p",
                projectName: "n",
                companyId: "c",
                userId: "u"
            )
            XCTFail("Expected queuedForRetry error")
        } catch let error as DimensionedSyncError {
            switch error {
            case .queuedForRetry: break
            default: XCTFail("Wrong error case: \(error)")
            }
        }

        // The manager should NOT have reached the persister — the asset uploads
        // exhausted their retries.
        XCTAssertEqual(persister.annotationInserts.count, 0)

        // A stub annotation should be parked on the manager's lastQueuedAnnotation
        // slot with local paths and needsSync = true.
        let queued = try XCTUnwrap(DimensionedPhotoSyncManager.lastQueuedAnnotation,
                                   "Expected lastQueuedAnnotation to be populated for the caller to insert locally")
        XCTAssertTrue(queued.needsSync)
        XCTAssertEqual(queued.localDepthMapPath, captured.depthURL?.path)
        XCTAssertEqual(queued.localSidecarPath, captured.sidecarURL.path)
        XCTAssertNotNil(queued.dimensions)
        DimensionedPhotoSyncManager.lastQueuedAnnotation = nil
    }

    @MainActor
    func test_sync_throwsAnnotationInsertFailed_whenPersisterFails() async throws {
        let captured = try fixtureCaptured()
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister(failAnnotationInsert: true)
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister, notifier: NoopDimensionedNotificationDispatcher())

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "p",
                projectName: "n",
                companyId: "c",
                userId: "u"
            )
            XCTFail("Expected annotationInsertFailed error")
        } catch let error as DimensionedSyncError {
            switch error {
            case .annotationInsertFailed: break
            default: XCTFail("Wrong error case: \(error)")
            }
        }

        let queued = try XCTUnwrap(DimensionedPhotoSyncManager.lastQueuedAnnotation)
        XCTAssertTrue(queued.needsSync)
        XCTAssertEqual(queued.photoURL, uploader.calls[0].returnedURL,
                       "Once the HEIC has uploaded, the queued stub should reference the remote URL so retry only re-inserts the annotation row")
        DimensionedPhotoSyncManager.lastQueuedAnnotation = nil
    }

    @MainActor
    func test_syncPendingDimensionsRetriesQueuedCaptureAfterAnnotationViewDismisses() async throws {
        let captureID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let captured = try fixtureCaptured(captureID: captureID)
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let queued = PhotoAnnotation(
            id: "local-\(captureID.uuidString)",
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

        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(
            uploader: uploader,
            persister: persister,
            notifier: NoopDimensionedNotificationDispatcher()
        )

        await manager.syncPendingDimensions(modelContext: context)

        XCTAssertEqual(uploader.calls.count, 3)
        XCTAssertEqual(uploader.calls[0].filename, "\(captureID.uuidString).heic")
        XCTAssertEqual(uploader.calls[1].filename, "\(captureID.uuidString).metadata.json")
        XCTAssertEqual(uploader.calls[2].filename, "\(captureID.uuidString).depth.fp32")
        XCTAssertEqual(persister.projectPhotoInserts.count, 1)
        XCTAssertEqual(persister.annotationInserts.count, 1)

        let annotations = try context.fetch(FetchDescriptor<PhotoAnnotation>())
        XCTAssertEqual(annotations.count, 1)
        let retried = try XCTUnwrap(annotations.first)
        XCTAssertEqual(retried.id, "server-id-1")
        XCTAssertEqual(retried.photoURL, uploader.calls[0].returnedURL)
        XCTAssertFalse(retried.needsSync)
        XCTAssertNotNil(retried.lastSyncedAt)
        XCTAssertEqual(retried.dimensions?.sidecarMetadataUrl, uploader.calls[1].returnedURL)
        XCTAssertEqual(retried.dimensions?.depthAssetUrl, uploader.calls[2].returnedURL)
        XCTAssertEqual(retried.localDepthMapPath, captured.depthURL?.path)
        XCTAssertEqual(retried.localSidecarPath, captured.sidecarURL.path)
        XCTAssertEqual(retried.localCaptureFinishedAt, captured.captureFinishedAt)
    }

    // MARK: - 4. Notification firing (spec §6)

    @MainActor
    func test_sync_firesCapturedNotification_onSuccessWithDetectedOpening() async throws {
        let captureID = UUID()
        let captured = try fixtureCaptured(captureID: captureID)
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister()
        let notifier = RecordingNotifier()
        let manager = DimensionedPhotoSyncManager(
            uploader: uploader,
            persister: persister,
            notifier: notifier
        )

        let dims = fixtureDimensionsWithOpening()

        _ = try await manager.sync(
            captured: captured,
            dimensions: dims,
            projectId: "project-123",
            projectName: "Smith Residence",
            companyId: "company-abc",
            userId: "user-xyz"
        )

        let capturedCalls = await notifier.capturedCalls()
        XCTAssertEqual(capturedCalls.count, 1)
        let call = try XCTUnwrap(capturedCalls.first)
        XCTAssertEqual(call.projectName, "Smith Residence")
        XCTAssertEqual(call.projectId, "project-123")
        XCTAssertEqual(call.userId, "user-xyz")
        XCTAssertEqual(call.companyId, "company-abc")
        if case let .opening(w, h, type, sill) = call.summary {
            XCTAssertEqual(w, 36)
            XCTAssertEqual(h, 60)
            XCTAssertEqual(type, .window)
            XCTAssertEqual(sill, 28)
        } else {
            XCTFail("Expected opening summary, got \(call.summary)")
        }
        let pendingSyncCalls = await notifier.pendingSyncCalls()
        XCTAssertEqual(pendingSyncCalls.count, 0)
    }

    @MainActor
    func test_sync_firesPendingSync_whenUploadFailsCompletely() async throws {
        let captured = try fixtureCaptured()
        let uploader = RecordingUploader(plan: .alwaysFail)
        let persister = RecordingPersister()
        let notifier = RecordingNotifier()
        let manager = DimensionedPhotoSyncManager(
            uploader: uploader,
            persister: persister,
            notifier: notifier
        )

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "p",
                projectName: "n",
                companyId: "c",
                userId: "u"
            )
            XCTFail("Expected queuedForRetry")
        } catch is DimensionedSyncError {
            let pendingSyncCalls = await notifier.pendingSyncCalls()
            XCTAssertEqual(pendingSyncCalls.count, 1)
            XCTAssertEqual(pendingSyncCalls.first?.queueDepth, 1)
            XCTAssertEqual(pendingSyncCalls.first?.projectId, "p")
            let capturedCalls = await notifier.capturedCalls()
            XCTAssertEqual(capturedCalls.count, 0)
        }
        DimensionedPhotoSyncManager.lastQueuedAnnotation = nil
    }

    // MARK: - Fixture: dimensions with one detected opening
    //
    // A 36"×60" window with a 28" sill, rounded to whole inches at the metre
    // boundary. Matches the spec §6 example body
    // `[PROJECT] · 36″×60″ WINDOW · SILL 28″` so the captured-fires test
    // exercises the same path live code uses.

    private func fixtureDimensionsWithOpening() -> DimensionsData {
        let widthMeters = 36.0 * 0.0254
        let heightMeters = 60.0 * 0.0254
        let sillMeters = 28.0 * 0.0254

        let widthMeasurement = DimensionsData.Measurement(
            type: .linear, label: "Width",
            worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: widthMeters, y: 0, z: 0)],
            imagePoints: [.init(x: 100, y: 500), .init(x: 800, y: 500)],
            valueMeters: widthMeters,
            labelPlacement: .init(side: .north, leaderLengthPx: 60),
            source: .auto
        )
        let heightMeasurement = DimensionsData.Measurement(
            type: .linear, label: "Height",
            worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0, y: heightMeters, z: 0)],
            imagePoints: [.init(x: 100, y: 500), .init(x: 100, y: 200)],
            valueMeters: heightMeters,
            labelPlacement: .init(side: .east, leaderLengthPx: 60),
            source: .auto
        )
        let sillMeasurement = DimensionsData.Measurement(
            type: .linear, label: "Sill height",
            worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 0, y: sillMeters, z: 0)],
            imagePoints: [.init(x: 100, y: 600), .init(x: 100, y: 500)],
            valueMeters: sillMeters,
            labelPlacement: .init(side: .south, leaderLengthPx: 60),
            source: .auto
        )
        let opening = DimensionsData.Opening(
            type: .window,
            boundingPolygon: [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1), .init(x: 0, y: 1)],
            classificationConfidence: 0.95,
            measurementIds: [widthMeasurement.id, heightMeasurement.id, sillMeasurement.id]
        )
        return DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(fx: 1593.4, fy: 1593.4,
                              cx: 1015.5, cy: 762.0,
                              imageWidth: 4032, imageHeight: 3024),
            measurements: [widthMeasurement, heightMeasurement, sillMeasurement],
            openings: [opening]
        )
    }

    @MainActor
    func test_sync_throwsMissingLocalAsset_whenFileMissing() async throws {
        let captured = CapturedAssets(
            heicURL: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).heic"),
            depthURL: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).depth.fp32"),
            sidecarURL: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).metadata.json"),
            intrinsics: .init(fx: 1, fy: 1, cx: 0, cy: 0, imageWidth: 1, imageHeight: 1),
            arkitSnapshot: .init(meshAnchors: [],
                                 cameraIntrinsics: .init(fx: 1, fy: 1, cx: 0, cy: 0,
                                                         imageWidth: 1, imageHeight: 1),
                                 devicePose: Array(repeating: 0, count: 16),
                                 timestamp: Date()),
            captureID: UUID(),
            captureFinishedAt: Date()
        )
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister, notifier: NoopDimensionedNotificationDispatcher())

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "p",
                projectName: "n",
                companyId: "c",
                userId: "u"
            )
            XCTFail("Expected missingLocalAsset error")
        } catch let error as DimensionedSyncError {
            switch error {
            case .missingLocalAsset: break
            default: XCTFail("Wrong error case: \(error)")
            }
        }
        XCTAssertEqual(uploader.calls.count, 0)
    }
}

// MARK: - Recording mocks

private final class RecordingUploader: DimensionedAssetUploader, @unchecked Sendable {

    enum Plan {
        case alwaysSucceed
        case alwaysFail
        /// Fails `failCount` times per asset, then succeeds.
        case failThenSucceed(failCount: Int)
    }

    struct Call {
        let filename: String
        let folder: String
        let contentType: String
        let returnedURL: String
    }

    let plan: Plan
    private(set) var calls: [Call] = []
    private var failuresByFilename: [String: Int] = [:]

    init(plan: Plan) {
        self.plan = plan
    }

    func uploadAsset(
        _ data: Data,
        filename: String,
        folder: String,
        contentType: String
    ) async throws -> String {
        switch plan {
        case .alwaysSucceed:
            let url = "https://test.example/\(folder)/\(filename)"
            calls.append(.init(filename: filename, folder: folder,
                               contentType: contentType, returnedURL: url))
            return url

        case .alwaysFail:
            calls.append(.init(filename: filename, folder: folder,
                               contentType: contentType,
                               returnedURL: ""))
            throw UploadError.s3Error(statusCode: 500)

        case .failThenSucceed(let failCount):
            let prior = failuresByFilename[filename] ?? 0
            calls.append(.init(filename: filename, folder: folder,
                               contentType: contentType,
                               returnedURL: prior < failCount ? "" :
                                "https://test.example/\(folder)/\(filename)"))
            if prior < failCount {
                failuresByFilename[filename] = prior + 1
                throw UploadError.s3Error(statusCode: 500)
            }
            return "https://test.example/\(folder)/\(filename)"
        }
    }
}

private final class RecordingPersister: DimensionedAnnotationPersister, @unchecked Sendable {

    struct PhotoInsert {
        let url: String
        let projectId: String
        let companyId: String
        let uploadedBy: String
        let takenAt: Date
    }

    struct AnnotationInsert {
        let photoUrl: String
        let projectId: String
        let companyId: String
        let authorId: String
        let dimensions: DimensionsData
    }

    private(set) var projectPhotoInserts: [PhotoInsert] = []
    private(set) var annotationInserts: [AnnotationInsert] = []
    let failAnnotationInsert: Bool

    init(failAnnotationInsert: Bool = false) {
        self.failAnnotationInsert = failAnnotationInsert
    }

    func insertProjectPhotoRow(
        url: String,
        projectId: String,
        companyId: String,
        uploadedBy: String,
        takenAt: Date
    ) async throws {
        projectPhotoInserts.append(.init(
            url: url, projectId: projectId, companyId: companyId,
            uploadedBy: uploadedBy, takenAt: takenAt
        ))
    }

    func insertAnnotationRow(
        photoUrl: String,
        projectId: String,
        companyId: String,
        authorId: String,
        dimensions: DimensionsData
    ) async throws -> InsertedAnnotation {
        if failAnnotationInsert {
            throw NSError(domain: "test.persister", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "simulated insert failure"])
        }
        annotationInserts.append(.init(
            photoUrl: photoUrl, projectId: projectId, companyId: companyId,
            authorId: authorId, dimensions: dimensions
        ))
        return InsertedAnnotation(
            id: "server-id-\(annotationInserts.count)",
            createdAt: Date(timeIntervalSince1970: 1_747_166_400)
        )
    }
}

// MARK: - RecordingNotifier (spec §6 verification)

/// Records each dispatcher call into typed arrays for assertion. Implemented as
/// an `actor` so the Sendable protocol can be satisfied without unchecked
/// concurrency annotations — matches the lightweight test-double style used
/// elsewhere in this file.
private actor RecordingNotifier: DimensionedNotificationDispatcher {

    struct CapturedCall: Equatable {
        let userId: String
        let companyId: String
        let projectId: String
        let projectName: String
        let summary: MeasurementNotificationCopy.CapturedBodySummary
        let photoAnnotationId: String
    }
    struct PendingSyncCall: Equatable {
        let userId: String
        let companyId: String
        let projectId: String?
        let queueDepth: Int
    }
    struct SyncFailedCall: Equatable {
        let userId: String
        let companyId: String
        let projectId: String
        let projectName: String
        let photoAnnotationId: String
    }

    private var _capturedCalls: [CapturedCall] = []
    private var _pendingSyncCalls: [PendingSyncCall] = []
    private var _syncFailedCalls: [SyncFailedCall] = []

    func capturedCalls() -> [CapturedCall] { _capturedCalls }
    func pendingSyncCalls() -> [PendingSyncCall] { _pendingSyncCalls }
    func syncFailedCalls() -> [SyncFailedCall] { _syncFailedCalls }

    func dispatchCaptured(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        summary: MeasurementNotificationCopy.CapturedBodySummary,
        photoAnnotationId: String
    ) async {
        _capturedCalls.append(.init(
            userId: userId, companyId: companyId,
            projectId: projectId, projectName: projectName,
            summary: summary, photoAnnotationId: photoAnnotationId
        ))
    }

    func dispatchPendingSync(
        userId: String,
        companyId: String,
        projectId: String?,
        queueDepth: Int
    ) async {
        _pendingSyncCalls.append(.init(
            userId: userId, companyId: companyId,
            projectId: projectId, queueDepth: queueDepth
        ))
    }

    func dispatchSyncFailed(
        userId: String,
        companyId: String,
        projectId: String,
        projectName: String,
        photoAnnotationId: String
    ) async {
        _syncFailedCalls.append(.init(
            userId: userId, companyId: companyId,
            projectId: projectId, projectName: projectName,
            photoAnnotationId: photoAnnotationId
        ))
    }
}
