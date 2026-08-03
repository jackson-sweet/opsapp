//
//  SiteVisitRecoveryVaultTests.swift
//  OPSTests
//
//  Forced logout must preserve unsent field work without exposing it to the
//  next account that signs into the same phone.
//

import CryptoKit
import SwiftData
import XCTest
@testable import OPS

final class SiteVisitRecoveryVaultTests: XCTestCase {
    private let userID = "310fbd03-4ffd-4432-b502-e20aff43d548"
    private let companyID = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let visitID = "d6ec5372-607f-4dc1-8733-c52f14e2d4e2"

    @MainActor
    func test_forcedLogoutArchiveRestoresOnlyToExactIdentityAndRestoresMedia() throws {
        let root = try makeTemporaryDirectory()
        let mediaRoot = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mediaRoot,
            withIntermediateDirectories: true
        )
        let mediaID = "local://project_images/site-visit.jpg"
        let mediaURL = mediaRoot.appendingPathComponent("site-visit.jpg")
        let originalMedia = Data("field-photo-bytes".utf8)
        try originalMedia.write(to: mediaURL)
        let vault = makeVault(root: root) { localID in
            localID == mediaID ? mediaURL : nil
        }
        let container = try makeContainer()
        let context = container.mainContext
        let visit = SiteVisit(
            id: visitID,
            companyId: companyID,
            status: .inProgress,
            createdBy: userID
        )
        visit.notes = "Unsent scope notes"
        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: visitID,
            companyId: companyID,
            kind: .photo,
            source: .camera,
            localAssetURL: mediaID,
            createdBy: userID
        )
        let answer = SiteVisitChecklistAnswer(
            siteVisitId: visitID,
            companyId: companyID,
            opportunityId: nil,
            siteVisitTypeId: "estimate",
            fieldId: "scope",
            label: "Scope",
            kind: .shortText,
            required: true,
            sortOrder: 1,
            answerValue: SiteVisitChecklistValue(text: "Replace railing"),
            createdBy: userID
        )
        let draft = SiteVisitIdentityDraft(
            siteVisitId: visitID,
            companyId: companyID,
            contactName: "Taylor",
            preferredEmail: "taylor@example.com",
            address: "123 Main St",
            createdBy: userID
        )
        context.insert(visit)
        context.insert(artifact)
        context.insert(answer)
        context.insert(draft)
        let operation = try makeParentOperation(visit)
        context.insert(operation)
        try context.save()

        let archived = try vault.captureUnsentWork(
            from: context,
            userId: userID,
            companyId: companyID,
            removeOriginalMedia: true
        )

        XCTAssertEqual(archived, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
        let vaultRoot = root.appendingPathComponent("vault", isDirectory: true)
        let encryptedFiles = try XCTUnwrap(
            FileManager.default.enumerator(at: vaultRoot, includingPropertiesForKeys: nil)?
                .allObjects as? [URL]
        ).filter { !$0.hasDirectoryPath }
        let encryptedBytes = try encryptedFiles.reduce(into: Data()) {
            $0.append(try Data(contentsOf: $1))
        }
        XCTAssertNil(encryptedBytes.range(of: Data("Unsent scope notes".utf8)))
        XCTAssertNil(encryptedBytes.range(of: Data("taylor@example.com".utf8)))
        XCTAssertNil(encryptedBytes.range(of: originalMedia))
        try deleteAllSiteVisitRows(in: context)

        let foreignRestore = try vault.restore(
            into: context,
            userId: "2d43c7bc-8484-47f6-a2e5-9896e40cf72d",
            companyId: companyID
        )
        XCTAssertEqual(foreignRestore, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertEqual(
            vault.summaries(
                userId: "2d43c7bc-8484-47f6-a2e5-9896e40cf72d",
                companyId: companyID
            ).count,
            0
        )

        let restored = try vault.restore(
            into: context,
            userId: userID,
            companyId: companyID
        )

        XCTAssertEqual(restored, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisit>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisitCaptureArtifact>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisitChecklistAnswer>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisitIdentityDraft>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SyncOperation>()), 1)
        XCTAssertEqual(try Data(contentsOf: mediaURL), originalMedia)
        XCTAssertTrue(vault.summaries(userId: userID, companyId: companyID).isEmpty)
    }

    @MainActor
    func test_quarantineIsDurableIdempotentAndInvisibleToWrongAccount() throws {
        let root = try makeTemporaryDirectory()
        let vault = makeVault(root: root) { _ in nil }
        let container = try makeContainer()
        let context = container.mainContext
        let foreignCompany = "67ffc0b9-662c-42ea-b935-d6a78b778cc3"
        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: visitID,
            companyId: foreignCompany,
            kind: .note,
            source: .keyboard,
            body: "Old account field note",
            createdBy: userID
        )
        context.insert(artifact)
        try context.save()
        let quarantine = SiteVisitOrphanQuarantine(
            id: "site-visit-quarantine:foreign_company:\(foreignCompany):\(visitID)",
            userId: userID,
            companyId: foreignCompany,
            siteVisitId: visitID,
            reason: .foreignCompany,
            childIds: [artifact.id],
            createdAt: artifact.createdAt
        )

        try vault.recordQuarantine(quarantine, from: context)
        try vault.recordQuarantine(quarantine, from: context)

        XCTAssertEqual(vault.summaries(userId: userID, companyId: foreignCompany).count, 1)
        XCTAssertTrue(vault.summaries(userId: userID, companyId: companyID).isEmpty)
        XCTAssertTrue(
            vault.summaries(
                userId: "2d43c7bc-8484-47f6-a2e5-9896e40cf72d",
                companyId: foreignCompany
            ).isEmpty
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisitCaptureArtifact>()), 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    @MainActor
    func test_explicitQuarantineDiscardRemovesExactOrphanSourceAndMediaButKeepsParent() throws {
        let root = try makeTemporaryDirectory()
        let mediaRoot = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        let mediaID = "local://project_images/quarantined.jpg"
        let mediaURL = mediaRoot.appendingPathComponent("quarantined.jpg")
        try Data("quarantined-photo".utf8).write(to: mediaURL)
        let vault = makeVault(root: root) { $0 == mediaID ? mediaURL : nil }
        let container = try makeContainer()
        let context = container.mainContext
        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: visitID,
            companyId: companyID,
            kind: .photo,
            source: .camera,
            localAssetURL: mediaID,
            createdBy: userID
        )
        let answer = SiteVisitChecklistAnswer(
            siteVisitId: visitID,
            companyId: companyID,
            opportunityId: nil,
            siteVisitTypeId: "estimate",
            fieldId: "scope",
            label: "Scope",
            kind: .shortText,
            required: true,
            sortOrder: 1,
            createdBy: userID
        )
        let draft = SiteVisitIdentityDraft(
            siteVisitId: visitID,
            companyId: companyID,
            contactName: "Taylor",
            createdBy: userID
        )
        context.insert(artifact)
        context.insert(answer)
        context.insert(draft)

        let operation = SyncOperation(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: visitID,
            operationType: SiteVisitSyncOperation.completionOperationType,
            payload: try JSONEncoder().encode(
                SiteVisitSyncOperation.Payload(
                    companyId: companyID,
                    siteVisitId: visitID,
                    entityId: visitID,
                    completion: SiteVisitCompletionPayload(
                        notes: nil,
                        measurements: nil,
                        photos: [],
                        internalNotes: nil
                    )
                )
            ),
            changedFields: ["status"]
        )
        context.insert(operation)
        try context.save()

        let quarantine = SiteVisitOrphanQuarantine(
            id: "site-visit-quarantine:malformed_identity:\(companyID):\(visitID)",
            userId: userID,
            companyId: companyID,
            siteVisitId: visitID,
            reason: .malformedIdentity,
            childIds: [artifact.id, answer.id, draft.id],
            createdAt: artifact.createdAt
        )
        try vault.recordQuarantine(quarantine, from: context)
        operation.status = "quarantined"

        // A valid parent may arrive from another device after quarantine. The
        // explicit discard owns only the orphan source, never that cloud parent.
        context.insert(SiteVisit(id: visitID, companyId: companyID, createdBy: userID))
        let foreignArtifact = SiteVisitCaptureArtifact(
            siteVisitId: visitID,
            companyId: "67ffc0b9-662c-42ea-b935-d6a78b778cc3",
            kind: .note,
            source: .keyboard,
            body: "Another company",
            createdBy: userID
        )
        context.insert(foreignArtifact)
        try context.save()

        let wrongIdentityDiscarded = try vault.discardQuarantinedWork(
            id: quarantine.id,
            userId: "2d43c7bc-8484-47f6-a2e5-9896e40cf72d",
            companyId: companyID,
            siteVisitId: visitID,
            from: context
        )
        XCTAssertFalse(wrongIdentityDiscarded)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisitCaptureArtifact>()), 2)

        let discarded = try vault.discardQuarantinedWork(
            id: quarantine.id,
            userId: userID,
            companyId: companyID,
            siteVisitId: visitID,
            from: context
        )

        XCTAssertTrue(discarded)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisit>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).map(\.id), [foreignArtifact.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertTrue(vault.summaries(userId: userID, companyId: companyID).isEmpty)
    }

    @MainActor
    func test_unsentDetectionIncludesChildrenAndOperationsWithoutAParent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(
            SiteVisitIdentityDraft(
                siteVisitId: visitID,
                companyId: companyID,
                contactName: "Taylor",
                createdBy: userID
            )
        )
        try context.save()

        XCTAssertEqual(
            try SiteVisitRecoveryVault.unsentVisitIds(
                in: context,
                companyId: companyID
            ),
            [visitID]
        )
    }

    @MainActor
    func test_logoutMediaCleanupRemovesEveryCurrentCompanyVisitFileOnly() throws {
        let root = try makeTemporaryDirectory()
        let mediaRoot = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        let syncedID = "local://project_images/synced.jpg"
        let unsentID = "local://project_images/unsent.jpg"
        let foreignID = "local://project_images/foreign.jpg"
        let urls = [
            syncedID: mediaRoot.appendingPathComponent("synced.jpg"),
            unsentID: mediaRoot.appendingPathComponent("unsent.jpg"),
            foreignID: mediaRoot.appendingPathComponent("foreign.jpg"),
        ]
        for url in urls.values { try Data("photo".utf8).write(to: url) }
        let vault = makeVault(root: root) { urls[$0] }
        let container = try makeContainer()
        let context = container.mainContext

        let synced = SiteVisitCaptureArtifact(
            siteVisitId: visitID,
            companyId: companyID,
            kind: .photo,
            source: .camera,
            localAssetURL: syncedID,
            createdBy: userID
        )
        synced.needsSync = false
        synced.lastSyncedAt = Date()
        context.insert(synced)
        context.insert(
            SiteVisitCaptureArtifact(
                siteVisitId: visitID,
                companyId: companyID,
                kind: .photo,
                source: .camera,
                localAssetURL: unsentID,
                createdBy: userID
            )
        )
        context.insert(
            SiteVisitCaptureArtifact(
                siteVisitId: visitID,
                companyId: "67ffc0b9-662c-42ea-b935-d6a78b778cc3",
                kind: .photo,
                source: .camera,
                localAssetURL: foreignID,
                createdBy: userID
            )
        )
        try context.save()

        try vault.removeLiveMedia(in: context, companyId: companyID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(urls[syncedID]).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(urls[unsentID]).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(urls[foreignID]).path))
    }

    @MainActor
    func test_logoutWipeDeletesAllFourVisitModelsChildrenFirst() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let visit = SiteVisit(id: visitID, companyId: companyID, createdBy: userID)
        context.insert(visit)
        context.insert(
            SiteVisitCaptureArtifact(
                siteVisitId: visitID,
                companyId: companyID,
                kind: .note,
                source: .keyboard,
                body: "Scope",
                createdBy: userID
            )
        )
        context.insert(
            SiteVisitChecklistAnswer(
                siteVisitId: visitID,
                companyId: companyID,
                opportunityId: nil,
                siteVisitTypeId: "estimate",
                fieldId: "scope",
                label: "Scope",
                kind: .shortText,
                required: true,
                sortOrder: 1,
                createdBy: userID
            )
        )
        context.insert(
            SiteVisitIdentityDraft(
                siteVisitId: visitID,
                companyId: companyID,
                createdBy: userID
            )
        )
        context.insert(try makeParentOperation(visit))
        try context.save()

        try DataController.deleteSiteVisitDataForLogout(in: context)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).isEmpty)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func makeVault(
        root: URL,
        resolver: @escaping (String) -> URL?
    ) -> SiteVisitRecoveryVault {
        SiteVisitRecoveryVault(
            rootDirectory: root.appendingPathComponent("vault", isDirectory: true),
            keyProvider: { Data(repeating: 0xA7, count: 32) },
            mediaURLResolver: resolver
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeParentOperation(_ visit: SiteVisit) throws -> SyncOperation {
        let specification = SiteVisitSyncOperation.parent(visit)
        return SyncOperation(
            entityType: specification.entityType.rawValue,
            entityId: specification.entityId,
            operationType: specification.operationType,
            payload: try JSONEncoder().encode(specification.payload),
            changedFields: specification.changedFields
        )
    }

    @MainActor
    private func deleteAllSiteVisitRows(in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<SyncOperation>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SiteVisit>()) { context.delete(row) }
        try context.save()
    }
}
