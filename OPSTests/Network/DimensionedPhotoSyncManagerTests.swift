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
        try Data("FAKE_HEIC_BYTES".utf8).write(to: urls.heicURL)
        try Data("{\"meshAnchors\":[]}".utf8).write(to: urls.sidecarURL)
        try Data([0x00, 0x00, 0x80, 0x3F]).write(to: urls.depthURL)
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

    // MARK: - 1. Happy path

    @MainActor
    func test_sync_uploadsThreeAssets_andInsertsAnnotationRow() async throws {
        let captureID = UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!
        let captured = try fixtureCaptured(captureID: captureID)
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister)

        let annotation = try await manager.sync(
            captured: captured,
            dimensions: fixtureDimensions(),
            projectId: "project-123",
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
        XCTAssertEqual(annotation.localDepthMapPath, captured.depthURL.path)
        XCTAssertEqual(annotation.localSidecarPath, captured.sidecarURL.path)
        XCTAssertEqual(annotation.localCaptureFinishedAt, captured.captureFinishedAt)
    }

    // MARK: - 2. Retry path

    @MainActor
    func test_sync_retriesOnTransientFailure_thenSucceeds() async throws {
        let captured = try fixtureCaptured()
        let uploader = RecordingUploader(plan: .failThenSucceed(failCount: 1))
        let persister = RecordingPersister()
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister)

        let annotation = try await manager.sync(
            captured: captured,
            dimensions: fixtureDimensions(),
            projectId: "p",
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
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister)

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "p",
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
        XCTAssertEqual(queued.localDepthMapPath, captured.depthURL.path)
        XCTAssertEqual(queued.localSidecarPath, captured.sidecarURL.path)
        XCTAssertNotNil(queued.dimensions)
        DimensionedPhotoSyncManager.lastQueuedAnnotation = nil
    }

    @MainActor
    func test_sync_throwsAnnotationInsertFailed_whenPersisterFails() async throws {
        let captured = try fixtureCaptured()
        let uploader = RecordingUploader(plan: .alwaysSucceed)
        let persister = RecordingPersister(failAnnotationInsert: true)
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister)

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "p",
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
        let manager = DimensionedPhotoSyncManager(uploader: uploader, persister: persister)

        do {
            _ = try await manager.sync(
                captured: captured,
                dimensions: fixtureDimensions(),
                projectId: "p",
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
