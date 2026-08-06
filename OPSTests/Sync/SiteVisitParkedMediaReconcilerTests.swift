//
//  SiteVisitParkedMediaReconcilerTests.swift
//  OPSTests
//
//  Settling media uploads that parked because their local bytes were missing.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitParkedMediaReconcilerTests: XCTestCase {
    private var liveContainers: [ModelContainer] = []

    private let companyId = "11111111-1111-4111-8111-111111111111"
    private let userId = "22222222-2222-4222-8222-222222222222"
    private let visitId = "33333333-3333-4333-8333-333333333333"
    private let artifactId = "44444444-4444-4444-8444-444444444444"

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    func test_parkedOperationWithAbsentFileIsClearedAndCompleted() throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        context.insert(artifact)
        let media = try insertParkedMediaOperation(for: artifact, in: context)

        let resolved = SiteVisitParkedMediaReconciler.reconcile(
            in: context,
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolved, 1)
        XCTAssertEqual(media.status, "completed")
        XCTAssertNil(media.lastError)
        XCTAssertNil(artifact.localAssetURL, "A dead pointer must not survive")
        XCTAssertTrue(artifact.needsSync, "Cleared state must reach the server")
    }

    func test_parkedOperationWithPresentFileIsHandedBackForAnotherAttempt() throws {
        // The pre-fix build could not tell a locked (unreadable) file from a
        // deleted one, so a perfectly good photo could park. Those must be
        // rescued, not written off.
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        context.insert(artifact)
        let media = try insertParkedMediaOperation(for: artifact, in: context)

        let resolved = SiteVisitParkedMediaReconciler.reconcile(
            in: context,
            fileExists: { _ in true }
        )

        XCTAssertEqual(resolved, 1)
        XCTAssertEqual(media.status, "pending", "A present file deserves another attempt")
        XCTAssertEqual(media.retryCount, 0)
        XCTAssertNil(media.lastError)
        XCTAssertEqual(
            artifact.localAssetURL,
            "local://project_images/original.jpg",
            "A recoverable photo must keep its pointer"
        )
    }

    func test_parkedOperationParkedForAnotherReasonIsLeftAlone() throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        context.insert(artifact)
        let media = try insertParkedMediaOperation(for: artifact, in: context)
        media.lastError = "Unexpected sync error: something else entirely"

        let resolved = SiteVisitParkedMediaReconciler.reconcile(
            in: context,
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolved, 0)
        XCTAssertEqual(media.status, "parked", "Only missing-media parks are ours to settle")
        XCTAssertEqual(artifact.localAssetURL, "local://project_images/original.jpg")
    }

    func test_mixedArtifactRetiresOnlyTheAbsentVariant() throws {
        let context = try makeContainer().mainContext
        let artifact = makeArtifact()
        artifact.renderedAssetURL = "local://project_images/rendered.jpg"
        context.insert(artifact)
        let media = try insertParkedMediaOperation(for: artifact, in: context)

        // Only the rendered markup survived on disk.
        let resolved = SiteVisitParkedMediaReconciler.reconcile(
            in: context,
            fileExists: { $0.contains("rendered") }
        )

        XCTAssertEqual(resolved, 1)
        XCTAssertNil(artifact.localAssetURL, "The absent original is retired")
        XCTAssertEqual(
            artifact.renderedAssetURL,
            "local://project_images/rendered.jpg",
            "The surviving file is preserved"
        )
        XCTAssertEqual(media.status, "pending", "Real work remains, so it retries")
    }

    // MARK: - Fixtures

    private func makeArtifact() -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: "local://project_images/original.jpg",
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func insertParkedMediaOperation(
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
        operation.status = "parked"
        operation.lastError =
            "Unexpected sync error: \(SiteVisitParkedMediaReconciler.missingMediaMarker):"
            + " local://project_images/original.jpg"
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
