//
//  SiteVisitPersistenceCoordinatorTests.swift
//  OPSTests
//
//  Transaction and dependency guarantees for phone-authored site visits.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitPersistenceCoordinatorTests: XCTestCase {
    private enum FixtureError: Swift.Error {
        case encodingRejected
        case transactionRejected
    }

    private var liveContainers: [ModelContainer] = []

    private let companyId = "11111111-1111-1111-1111-111111111111"
    private let userId = "22222222-2222-2222-2222-222222222222"
    private let visitId = "33333333-3333-3333-3333-333333333333"
    private let artifactId = "44444444-4444-4444-4444-444444444444"

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    func test_createVisitCommitsParentAndCreateOperationTogether() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let visit = makeVisit()

        let result = try coordinator.commit {
            context.insert(visit)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisit>()).count, 1)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations[0].entityType, SyncEntityType.siteVisit.rawValue)
        XCTAssertEqual(operations[0].entityId, visitId)
        XCTAssertEqual(operations[0].operationType, "create")
        XCTAssertNil(operations[0].dependsOnId)
        XCTAssertEqual(result.operationIds, [operations[0].id])
    }

    func test_childCreateDependsOnParentAndRepeatedEditCoalesces() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let visit = makeVisit()
        let artifact = SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .note,
            source: .keyboard,
            body: "First",
            createdBy: userId
        )

        try coordinator.commit {
            context.insert(visit)
            context.insert(artifact)
        }

        var operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let parent = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.siteVisit.rawValue
        })
        let child = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.siteVisitArtifact.rawValue
        })
        XCTAssertEqual(child.dependsOnId, parent.id.uuidString.lowercased())

        try coordinator.commit {
            artifact.body = "Second"
            artifact.updatedAt = Date()
            artifact.needsSync = true
        }

        operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 2)
        XCTAssertEqual(
            operations.filter { $0.entityType == SyncEntityType.siteVisitArtifact.rawValue }.count,
            1
        )
    }

    func test_encodingFailureRollsBackModelAndOperation() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId,
            encodeOperation: { _ in throw FixtureError.encodingRejected }
        )

        XCTAssertThrowsError(
            try coordinator.commit {
                context.insert(self.makeVisit())
            }
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
    }

    func test_transactionFailureDoesNotReportACommittedVisit() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId,
            validateCommit: { throw FixtureError.transactionRejected }
        )

        XCTAssertThrowsError(
            try coordinator.commit {
                context.insert(self.makeVisit())
            }
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    func test_completionIsSeparateAndDependsOnCapturedGraphTail() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let visit = makeVisit()
        let artifact = SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .note,
            source: .keyboard,
            body: "Ready",
            createdBy: userId
        )

        let result = try coordinator.commit(completing: visit) {
            context.insert(visit)
            context.insert(artifact)
            visit.status = .completed
            visit.completedAt = Date()
            visit.needsSync = true
        }

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 3)
        let parent = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.siteVisit.rawValue
                && $0.operationType == "create"
        })
        let child = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.siteVisitArtifact.rawValue
        })
        let completion = try XCTUnwrap(operations.first {
            $0.operationType == SiteVisitSyncOperation.completionOperationType
        })
        XCTAssertEqual(child.dependsOnId, parent.id.uuidString.lowercased())
        XCTAssertEqual(completion.dependsOnId, child.id.uuidString.lowercased())
        XCTAssertEqual(result.completionOperationId, completion.id)
    }

    func test_mediaUploadFollowsArtifactAndCompletionFollowsMedia() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let visit = makeVisit()
        let artifact = SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: "local://project_images/photo.jpg",
            createdBy: userId
        )

        try coordinator.commit(completing: visit) {
            context.insert(visit)
            context.insert(artifact)
            visit.status = .completed
            visit.completedAt = Date()
        }

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 4)
        let parent = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.siteVisit.rawValue
                && $0.operationType == "create"
        })
        let artifactWrite = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.siteVisitArtifact.rawValue
                && $0.operationType == "create"
        })
        let media = try XCTUnwrap(operations.first {
            $0.operationType == SiteVisitSyncOperation.mediaOperationType
        })
        let completion = try XCTUnwrap(operations.first {
            $0.operationType == SiteVisitSyncOperation.completionOperationType
        })

        XCTAssertEqual(artifactWrite.dependsOnId, parent.id.uuidString.lowercased())
        XCTAssertEqual(media.dependsOnId, artifactWrite.id.uuidString.lowercased())
        XCTAssertEqual(completion.dependsOnId, media.id.uuidString.lowercased())
    }

    func test_orphanRecoveryIsCompanyScopedAndNeverRevivesParkedWork() throws {
        let context = try makeContainer().mainContext
        let parkedVisit = makeVisit()
        let foreignVisit = SiteVisit(
            id: "55555555-5555-5555-5555-555555555555",
            companyId: "66666666-6666-6666-6666-666666666666",
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_100),
            assigneeIds: [userId],
            createdBy: userId
        )
        let specification = SiteVisitSyncOperation.parent(parkedVisit)
        let parked = SyncOperation(
            entityType: specification.entityType.rawValue,
            entityId: specification.entityId,
            operationType: specification.operationType,
            payload: try JSONEncoder().encode(specification.payload),
            changedFields: specification.changedFields
        )
        parked.status = "parked"
        context.insert(parkedVisit)
        context.insert(foreignVisit)
        context.insert(parked)
        try context.save()

        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let result = try coordinator.recoverOrphanedWrites()

        XCTAssertTrue(result.operationIds.isEmpty)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations[0].id, parked.id)
        XCTAssertEqual(operations[0].status, "parked")
    }

    func test_bindingCompletedVisitQueuesUpdateThenNewCompletion() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let visit = makeVisit()

        try coordinator.commit(completing: visit) {
            context.insert(visit)
            visit.status = .completed
            visit.completedAt = Date()
        }
        for operation in try context.fetch(FetchDescriptor<SyncOperation>()) {
            operation.status = "completed"
        }
        visit.lastSyncedAt = Date()
        visit.needsSync = false
        try context.save()

        let result = try coordinator.commit(completing: visit) {
            visit.opportunityId = "55555555-5555-5555-5555-555555555555"
            visit.updatedAt = Date()
            visit.needsSync = true
        }

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let open = operations.filter { $0.status != "completed" }
        XCTAssertEqual(open.count, 2)
        let update = try XCTUnwrap(open.first { $0.operationType == "update" })
        let completion = try XCTUnwrap(open.first {
            $0.operationType == SiteVisitSyncOperation.completionOperationType
        })
        XCTAssertEqual(completion.dependsOnId, update.id.uuidString.lowercased())
        XCTAssertEqual(result.completionOperationId, completion.id)
    }

    func test_uppercaseLegacyOperationCoalescesWithoutForkingQueue() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        visit.id = visitId.uppercased()
        let existing = SyncOperation(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: visitId.uppercased(),
            operationType: "create",
            payload: Data("{}".utf8),
            changedFields: ["notes"]
        )
        context.insert(visit)
        context.insert(existing)
        try context.save()

        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        try coordinator.commit {
            visit.notes = "Canonical edit"
            visit.updatedAt = Date()
            visit.needsSync = true
        }

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations[0].id, existing.id)
        XCTAssertEqual(operations[0].entityId.lowercased(), visitId)
    }

    func test_historyHeavyEditDoesNotEncodeOrReviveOtherVisits() throws {
        let context = try makeContainer().mainContext
        var encodedEntities: [String] = []
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId,
            encodeOperation: { payload in
                encodedEntities.append(payload.entityId)
                return try JSONEncoder().encode(payload)
            })
        let target = makeVisit()
        try coordinator.commit { context.insert(target) }
        var stopped: [SyncOperation] = []
        for index in 0..<29 {
            let visit = SiteVisit(companyId: companyId, createdBy: userId)
            context.insert(visit)
            let photo = SiteVisitCaptureArtifact(siteVisitId: visit.id, companyId: companyId,
                kind: .photo, source: .camera, localAssetURL: "local://project_images/fixture-\(index).jpg")
            context.insert(photo)
            let spec = SiteVisitSyncOperation.media(photo)
            let op = SyncOperation(entityType: spec.entityType.rawValue, entityId: spec.entityId,
                operationType: spec.operationType, payload: try JSONEncoder().encode(spec.payload), changedFields: [])
            op.status = index.isMultiple(of: 2) ? "declined" : "parked"
            op.retryCount = 9
            op.lastError = "Fixture rejection"
            stopped.append(op)
            context.insert(op)
        }
        let otherIds = try context.fetch(FetchDescriptor<SiteVisit>()).map(\.id).filter { $0 != target.id }
        for index in 0..<120 {
            context.insert(SiteVisitCaptureArtifact(siteVisitId: otherIds[index % otherIds.count], companyId: companyId,
                kind: .note, source: .keyboard, body: "Synthetic historical note"))
        }
        for index in 0..<283 {
            context.insert(SiteVisitChecklistAnswer(siteVisitId: otherIds[index % otherIds.count], companyId: companyId,
                opportunityId: nil, siteVisitTypeId: nil, fieldId: "field-\(index)", label: "Synthetic field",
                kind: .shortText, required: false, sortOrder: index, answerValue: .text("Historical answer")))
        }
        for id in otherIds.prefix(25) {
            context.insert(SiteVisitIdentityDraft(siteVisitId: id, companyId: companyId, notes: "Synthetic identity note"))
        }
        for _ in 0..<2_625 {
            let op = SyncOperation(entityType: "siteVisit", entityId: UUID().uuidString.lowercased(),
                operationType: "update", payload: Data(), changedFields: [])
            op.status = "completed"
            context.insert(op)
        }
        try context.save()
        encodedEntities.removeAll()
        let result = try coordinator.commit {
            target.notes = "Only this visit changed"
            target.updatedAt = Date()
        }
        XCTAssertEqual(encodedEntities, [target.id])
        XCTAssertEqual(coordinator.lastChangedEntityCount, 1)
        XCTAssertEqual(coordinator.lastLoadedOperationCount, 1)
        XCTAssertEqual(result.operationIds.count, 1)
        XCTAssertTrue(stopped.allSatisfy { $0.status == "parked" || $0.status == "declined" })
        XCTAssertTrue(stopped.allSatisfy { $0.retryCount == 9 && $0.lastError == "Fixture rejection" })
    }

    func test_sharedLegacyWrapperRefusesPendingChangesBeforeInvokingMutation() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let visit = makeVisit()
        try coordinator.commit { context.insert(visit) }
        visit.notes = "Existing unsaved work"
        var invoked = false
        XCTAssertThrowsError(try coordinator.commit { invoked = true })
        XCTAssertFalse(invoked)
        XCTAssertEqual(visit.notes, "Existing unsaved work")
        XCTAssertTrue(context.hasChanges)
        let stored = try XCTUnwrap(ModelContext(context.container).fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertNil(stored.notes)
    }

    func test_isolatedTransactionPreservesUnrelatedPendingValuesAndStoredBaselineOnSuccessAndFailure() throws {
        for shouldFail in [false, true] {
            let context = try makeContainer().mainContext
            let target = makeVisit()
            let other = SiteVisit(companyId: companyId, createdBy: userId)
            other.notes = "Stored B"
            let answer = SiteVisitChecklistAnswer(siteVisitId: other.id, companyId: companyId,
                opportunityId: nil, siteVisitTypeId: nil, fieldId: "b", label: "B field",
                kind: .shortText, required: false, sortOrder: 0, answerValue: .text("Stored B answer"))
            context.insert(target); context.insert(other); context.insert(answer); try context.save()
            other.notes = "Pending B"
            answer.answerValue = .text("Pending B answer")
            let draft = SiteVisitIdentityDraft(siteVisitId: other.id, companyId: companyId, notes: "Pending B draft")
            context.insert(draft)
            let draftId = draft.id
            let isolated = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId,
                validateCommit: { if shouldFail { throw FixtureError.transactionRejected } }).isolatedSession()
            let targetId = target.id
            let owned = try XCTUnwrap(isolated.modelContext.fetch(FetchDescriptor<SiteVisit>(predicate: #Predicate { $0.id == targetId })).first)
            do {
                try isolated.commit { owned.notes = "Saved A" }
                XCTAssertFalse(shouldFail)
            } catch { XCTAssertTrue(shouldFail) }
            XCTAssertEqual(other.notes, "Pending B")
            XCTAssertEqual(answer.answerValue.text, "Pending B answer")
            XCTAssertEqual(draft.notes, "Pending B draft")
            XCTAssertTrue(context.insertedModelsArray.contains { ObjectIdentifier($0) == ObjectIdentifier(draft) })
            XCTAssertTrue(context.hasChanges)
            let fresh = ModelContext(context.container)
            let rows = try fresh.fetch(FetchDescriptor<SiteVisit>())
            XCTAssertEqual(rows.first { $0.id == other.id }?.notes, "Stored B")
            XCTAssertEqual(rows.first { $0.id == targetId }?.notes, shouldFail ? nil : "Saved A")
            XCTAssertEqual(try fresh.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first?.answerValue.text, "Stored B answer")
            XCTAssertFalse(try fresh.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).contains { $0.id == draftId })
            XCTAssertEqual(isolated.lastBoundarySnapshotCount, 1)
            // A later, deliberate save of B must not restore stale A data from
            // the caller's registered (but unmodified) original A instance.
            try context.save()
            let afterBSave = ModelContext(context.container)
            XCTAssertEqual(try afterBSave.fetch(FetchDescriptor<SiteVisit>()).first { $0.id == targetId }?.notes,
                shouldFail ? nil : "Saved A")
        }
    }

    func test_unsavedUnrelatedGraphDoesNotEnterOwnedBoundarySnapshotWork() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        context.insert(visit); try context.save()
        for index in 0..<1_000 {
            context.insert(SiteVisitIdentityDraft(siteVisitId: "unrelated-\(index)", companyId: companyId,
                notes: String(repeating: "Synthetic pending text ", count: 100)))
        }
        let isolated = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId).isolatedSession()
        let id = visit.id
        let owned = try XCTUnwrap(isolated.modelContext.fetch(FetchDescriptor<SiteVisit>(predicate: #Predicate { $0.id == id })).first)
        try isolated.commit { owned.notes = "One owned edit" }
        XCTAssertEqual(isolated.lastChangedEntityCount, 1)
        XCTAssertEqual(isolated.lastBoundarySnapshotCount, 1)
        XCTAssertEqual(context.insertedModelsArray.count, 1_000)
        XCTAssertEqual(try ModelContext(context.container).fetchCount(FetchDescriptor<SiteVisitIdentityDraft>()), 0)
    }

    func test_noMutationDoesNotReviveStoppedOperation() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let visit = makeVisit()
        try coordinator.commit { context.insert(visit) }
        let op = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first)
        op.status = "declined"
        try context.save()
        let result = try coordinator.commit {}
        XCTAssertTrue(result.operationIds.isEmpty)
        XCTAssertEqual(op.status, "declined")
    }

    func test_failedEditRematerializesHeldModelAndQueueReferences() throws {
        let context = try makeContainer().mainContext
        let initial = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let visit = makeVisit()
        try initial.commit { context.insert(visit) }
        let operation = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first)
        operation.status = "parked"
        operation.retryCount = 4
        try context.save()
        let failing = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId,
            validateCommit: { throw FixtureError.transactionRejected })
        XCTAssertThrowsError(try failing.commit { visit.notes = "Rejected edit" })
        XCTAssertNil(visit.notes)
        XCTAssertEqual(operation.status, "parked")
        XCTAssertEqual(operation.retryCount, 4)
    }

    func test_candidateScopedRecoveryDoesNotEnqueueOutsideExactVisitIds() throws {
        let context = try makeContainer().mainContext
        let target = makeVisit()
        let other = SiteVisit(companyId: companyId, createdBy: userId)
        context.insert(target); context.insert(other)
        let answer = SiteVisitChecklistAnswer(siteVisitId: other.id, companyId: companyId,
            opportunityId: nil, siteVisitTypeId: nil, fieldId: "outside", label: "Other field",
            kind: .shortText, required: false, sortOrder: 1)
        context.insert(answer); try context.save()
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let recovered = try coordinator.recoverOrphanedWrites(siteVisitIds: [target.id])
        XCTAssertEqual(recovered.operationIds.count, 1)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.map(\.entityId), [target.id])
    }

    func test_throwingMutationRestoresHeldReferenceBeforeQueueConstruction() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let visit = makeVisit()
        try coordinator.commit { context.insert(visit) }
        XCTAssertThrowsError(try coordinator.commit {
            visit.notes = "Rejected before queue construction"
            throw FixtureError.transactionRejected
        })
        XCTAssertNil(visit.notes)
    }

    func test_metadataEditDoesNotReviveStoppedMediaButNewMarkupDoes() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let visit = makeVisit()
        let artifact = SiteVisitCaptureArtifact(siteVisitId: visit.id, companyId: companyId,
            kind: .photo, source: .camera, localAssetURL: "local://project_images/original.jpg")
        try coordinator.commit { context.insert(visit); context.insert(artifact) }
        let media = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first {
            $0.operationType == SiteVisitSyncOperation.mediaOperationType
        })
        media.status = "declined"; media.retryCount = 6; try context.save()
        try coordinator.commit { artifact.includedInProjectReview = false }
        XCTAssertEqual(media.status, "declined")
        XCTAssertEqual(media.retryCount, 6)
        try coordinator.commit(revisedMediaArtifactIds: [artifact.id]) {
            artifact.renderedAssetURL = "local://project_images/new-markup.jpg"
        }
        XCTAssertEqual(media.status, "pending")
        XCTAssertEqual(media.retryCount, 0)
    }

    func testAttemptedChecklistPayloadSurvivesFailureAndNewEditWhileUnattemptedEditsCoalesce() throws {
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let visit = makeVisit()
        visit.needsSync = false; visit.lastSyncedAt = Date()
        context.insert(visit); try context.save()
        let answer = SiteVisitChecklistAnswer(siteVisitId: visitId, companyId: companyId, opportunityId: nil,
            siteVisitTypeId: nil, fieldId: "scope", label: "Scope", kind: .shortText, required: false, sortOrder: 1)
        try coordinator.commit { context.insert(answer); answer.answerValue = .text("one") }
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first { SiteVisitVersionedSync.handles($0) })
        try coordinator.commit { answer.answerValue = .text("two") }
        let coalesced = try context.fetch(FetchDescriptor<SyncOperation>()).filter { SiteVisitVersionedSync.handles($0) }
        XCTAssertEqual(coalesced.count, 1)
        XCTAssertEqual(coalesced[0].id, original.id)
        XCTAssertEqual(SiteVisitVersionedSync.command(original)?.rows[0].baseRevision, 0)
        let bytes = original.payload
        original.status = "parked"; original.siteVisitWriteAttemptedAt = Date(); try context.save()
        try coordinator.commit { answer.answerValue = .text("three") }
        let writes = try context.fetch(FetchDescriptor<SyncOperation>()).filter { SiteVisitVersionedSync.handles($0) }
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(original.payload, bytes)
        XCTAssertEqual(original.status, "parked")
        let next = try XCTUnwrap(writes.first { $0.id != original.id })
        XCTAssertEqual(next.dependsOnId, original.id.uuidString.lowercased())
        XCTAssertEqual(SiteVisitVersionedSync.command(next)?.rows[0].baseRevision, 0)
        XCTAssertEqual(SiteVisitVersionedSync.command(next)?.rows[0].values["answer_value"]?["text"], .string("three"))
    }

    func testCaptureAndCompletionRetainTheirEnqueuedActorAcrossAccountChange() throws {
        let previous = UserDefaults.standard.string(forKey: "currentUserId")
        defer { if let previous { UserDefaults.standard.set(previous, forKey: "currentUserId") } else { UserDefaults.standard.removeObject(forKey: "currentUserId") } }
        UserDefaults.standard.set(userId, forKey: "currentUserId")
        let context = try makeContainer().mainContext
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId)
        let visit = makeVisit()
        try coordinator.commit { context.insert(visit) }
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first)
        XCTAssertEqual(original.siteVisitWriteActorId, userId)
        let originalPayload = original.payload
        UserDefaults.standard.set("replacement-actor", forKey: "currentUserId")
        try coordinator.commit { visit.notes = "Changed locally" }
        XCTAssertEqual(original.siteVisitWriteActorId, userId)
        XCTAssertEqual(original.payload, originalPayload)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SyncOperation>()), 2)
        UserDefaults.standard.set(userId, forKey: "currentUserId")
        try coordinator.commit(completing: visit) { visit.status = .completed; visit.completedAt = Date() }
        let completion = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first { $0.operationType == SiteVisitSyncOperation.completionOperationType })
        XCTAssertEqual(completion.siteVisitWriteActorId, userId)
        UserDefaults.standard.set("replacement-actor", forKey: "currentUserId")
        completion.status = "parked"; try context.save()
        XCTAssertEqual(completion.siteVisitWriteActorId, userId)
    }

    private func makeVisit() -> SiteVisit {
        SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .scheduled,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
            assigneeIds: [userId],
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
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
