//
//  SiteVisitMediaSyncManagerTests.swift
//  OPSTests
//
//  Crash-safe, per-variant upload progress for pre-project site-visit media.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitMediaSyncManagerTests: XCTestCase {
    private var liveContainers: [ModelContainer] = []

    private let companyId = "11111111-1111-4111-8111-111111111111"
    private let userId = "22222222-2222-4222-8222-222222222222"
    private let visitId = "33333333-3333-4333-8333-333333333333"
    private let artifactId = "44444444-4444-4444-8444-444444444444"

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    func test_partialFailurePersistsCompletedVariantAndQueuesURLUpsertBehindMedia() async throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        artifact.lastSyncedAt = Date()
        context.insert(artifact)
        let media = try insertMediaOperation(for: artifact, in: context)
        media.status = "inProgress"

        var attempted: [SiteVisitArtifactVariant] = []
        let manager = SiteVisitMediaSyncManager(
            uploader: { _, _, variant, _, _ in
                attempted.append(variant)
                if variant == .rendered { throw URLError(.networkConnectionLost) }
                return "https://cdn.ops.test/\(variant.rawValue).jpg"
            },
            loader: { _ in (Data([1, 2, 3]), "image/jpeg") }
        )

        do {
            try await manager.uploadPendingMedia(
                artifactId: artifactId,
                mediaOperation: media,
                context: context
            )
            XCTFail("Expected the rendered upload to fail")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        }

        XCTAssertEqual(attempted, [.original, .rendered])
        XCTAssertEqual(artifact.localAssetURL, "https://cdn.ops.test/original.jpg")
        XCTAssertEqual(artifact.renderedAssetURL, "local://project_images/rendered.jpg")
        XCTAssertEqual(artifact.thumbnailURL, "local://project_images/thumb.jpg")
        XCTAssertTrue(artifact.needsSync)

        let update = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SyncOperation>()).first {
                $0.id != media.id && $0.operationType == "update"
            }
        )
        XCTAssertEqual(update.entityType, SyncEntityType.siteVisitArtifact.rawValue)
        XCTAssertEqual(update.dependsOnId, media.id.uuidString.lowercased())
    }

    func test_restartSkipsPersistedRemoteVariantAndUploadsOnlyRemainingFiles() async throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        artifact.localAssetURL = "https://cdn.ops.test/original.jpg"
        artifact.lastSyncedAt = Date()
        context.insert(artifact)
        let media = try insertMediaOperation(for: artifact, in: context)
        media.status = "inProgress"

        var attempted: [SiteVisitArtifactVariant] = []
        let manager = SiteVisitMediaSyncManager(
            uploader: { _, _, variant, _, _ in
                attempted.append(variant)
                return "https://cdn.ops.test/\(variant.rawValue).jpg"
            },
            loader: { _ in (Data([4, 5, 6]), "image/jpeg") }
        )

        try await manager.uploadPendingMedia(
            artifactId: artifactId,
            mediaOperation: media,
            context: context
        )

        XCTAssertEqual(attempted, [.rendered, .thumbnail])
        XCTAssertEqual(artifact.renderedAssetURL, "https://cdn.ops.test/rendered.jpg")
        XCTAssertEqual(artifact.thumbnailURL, "https://cdn.ops.test/thumbnail.jpg")
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SyncOperation>()).filter {
                $0.id != media.id && $0.operationType == "update"
            }.count,
            1
        )
    }

    func test_duplicateDrainWithOnlyRemoteURLsIsNoOp() async throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        artifact.localAssetURL = "https://cdn.ops.test/original.jpg"
        artifact.renderedAssetURL = "https://cdn.ops.test/rendered.jpg"
        artifact.thumbnailURL = "https://cdn.ops.test/thumbnail.jpg"
        context.insert(artifact)
        let media = try insertMediaOperation(for: artifact, in: context)

        var uploadCount = 0
        let manager = SiteVisitMediaSyncManager(
            uploader: { _, _, _, _, _ in uploadCount += 1; return "" },
            loader: { _ in throw URLError(.fileDoesNotExist) }
        )

        try await manager.uploadPendingMedia(
            artifactId: artifactId,
            mediaOperation: media,
            context: context
        )

        XCTAssertEqual(uploadCount, 0)
    }

    // MARK: - Permanently gone vs temporarily unreadable
    //
    // A local capture's file is the ONLY copy until it uploads, so an ABSENT
    // file can never become present again — retiring it is correct. A file that
    // is on disk but unreadable right now (iOS Data Protection while the device
    // is locked during a background drain) must never be retired: that would
    // destroy the pointer to a photo that is perfectly fine.

    func test_absentFileClassifiesPermanentAndUnreadableFileClassifiesTransient() {
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: SiteVisitMediaSyncError.localFileMissing("gone")),
            .permanent
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitMediaSyncError.localFileUnreadable("locked")
            ),
            .transient
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(for: SiteVisitMediaSyncError.invalidRemoteURL("nope")),
            .permanent
        )
    }

    func test_loadAssetReportsUnreadableWhenFileExistsButCannotBeRead() throws {
        // A directory stands in for a Data-Protection-locked file: the path
        // exists, but reading it as file data fails.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unreadable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try SiteVisitMediaSyncManager.loadAssetForTesting(directory.path)
        ) { error in
            guard case SiteVisitMediaSyncError.localFileUnreadable = error else {
                return XCTFail("Expected .localFileUnreadable, got \(error)")
            }
        }
    }

    func test_loadAssetReportsMissingWhenFileIsAbsent() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).jpg").path

        XCTAssertThrowsError(
            try SiteVisitMediaSyncManager.loadAssetForTesting(absent)
        ) { error in
            guard case SiteVisitMediaSyncError.localFileMissing = error else {
                return XCTFail("Expected .localFileMissing, got \(error)")
            }
        }
    }

    func test_absentVariantIsRetiredAndOperationCompletesWithoutThrowing() async throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        context.insert(artifact)
        let media = try insertMediaOperation(for: artifact, in: context)

        var uploadCount = 0
        let manager = SiteVisitMediaSyncManager(
            uploader: { _, _, _, _, _ in uploadCount += 1; return "" },
            loader: { source in throw SiteVisitMediaSyncError.localFileMissing(source) }
        )

        // Must NOT throw: with no bytes anywhere there is nothing left to do,
        // so the operation is finished rather than parked forever.
        try await manager.uploadPendingMedia(
            artifactId: artifactId,
            mediaOperation: media,
            context: context
        )

        XCTAssertEqual(uploadCount, 0, "Nothing to upload when every file is gone")
        XCTAssertNil(artifact.localAssetURL, "Dead pointer must be cleared")
        XCTAssertNil(artifact.renderedAssetURL)
        XCTAssertNil(artifact.thumbnailURL)
        XCTAssertTrue(artifact.needsSync, "Cleared state must reach the server")
    }

    func test_unreadableVariantThrowsAndPreservesItsLocalPointer() async throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        context.insert(artifact)
        let media = try insertMediaOperation(for: artifact, in: context)

        let manager = SiteVisitMediaSyncManager(
            uploader: { _, _, _, _, _ in "" },
            loader: { source in throw SiteVisitMediaSyncError.localFileUnreadable(source) }
        )

        do {
            try await manager.uploadPendingMedia(
                artifactId: artifactId,
                mediaOperation: media,
                context: context
            )
            XCTFail("A temporarily unreadable file must not resolve the operation")
        } catch let error as SiteVisitMediaSyncError {
            guard case .localFileUnreadable = error else {
                return XCTFail("Expected .localFileUnreadable, got \(error)")
            }
        }

        XCTAssertEqual(
            artifact.localAssetURL,
            "local://project_images/original.jpg",
            "A readable-later photo must keep its pointer"
        )
    }

    func test_retiringOneArtifactNeverTouchesAnother() async throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        artifact.renderedAssetURL = nil
        artifact.thumbnailURL = nil
        context.insert(artifact)
        let healthy = SiteVisitCaptureArtifact(
            id: "55555555-5555-4555-8555-555555555555",
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: "local://project_images/present.jpg",
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        context.insert(healthy)
        let media = try insertMediaOperation(for: artifact, in: context)

        let manager = SiteVisitMediaSyncManager(
            uploader: { _, _, _, _, _ in "https://cdn.ops.test/ok.jpg" },
            loader: { source in throw SiteVisitMediaSyncError.localFileMissing(source) }
        )
        try await manager.uploadPendingMedia(
            artifactId: artifactId,
            mediaOperation: media,
            context: context
        )

        XCTAssertNil(artifact.localAssetURL)
        XCTAssertEqual(
            healthy.localAssetURL,
            "local://project_images/present.jpg",
            "Retiring one artifact must never touch another"
        )
    }

    func test_presignContractUsesExplicitTargetFieldsAndNoCallerFolder() throws {
        let items = try PresignedURLUploadService.siteVisitPresignQueryItems(
            siteVisitId: visitId,
            artifactId: artifactId,
            variant: .thumbnail,
            contentType: "image/jpeg",
            fileSize: 321
        )
        let values = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(values["targetType"], "site_visit")
        XCTAssertEqual(values["siteVisitId"], visitId)
        XCTAssertEqual(values["artifactId"], artifactId)
        XCTAssertEqual(values["variant"], "thumbnail")
        XCTAssertEqual(values["contentType"], "image/jpeg")
        XCTAssertEqual(values["fileSize"], "321")
        XCTAssertNil(values["folder"])
        XCTAssertNil(values["filename"])
    }

    private func makeArtifact() -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .dimensionedPhoto,
            source: .camera,
            localAssetURL: "local://project_images/original.jpg",
            renderedAssetURL: "local://project_images/rendered.jpg",
            thumbnailURL: "local://project_images/thumb.jpg",
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func insertMediaOperation(
        for artifact: SiteVisitCaptureArtifact,
        in context: ModelContext
    ) throws -> SyncOperation {
        let spec = SiteVisitSyncOperation.media(artifact)
        let operation = SyncOperation(
            entityType: spec.entityType.rawValue,
            entityId: spec.entityId,
            operationType: spec.operationType,
            payload: try JSONEncoder().encode(spec.payload),
            changedFields: spec.changedFields,
            priority: spec.priority
        )
        context.insert(operation)
        return operation
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        liveContainers.append(container)
        return container
    }
}
