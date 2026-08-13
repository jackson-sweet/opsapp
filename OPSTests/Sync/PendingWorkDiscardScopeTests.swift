//
//  PendingWorkDiscardScopeTests.swift
//  OPSTests
//
//  The PENDING WORK screen is a SYNC-RECOVERY surface: its rows are queued
//  SENDS. Swiping DELETE there means "stop trying to send this" — never "delete
//  the record". Bug f7431c17 proved the difference in the field: an operator
//  swiped one stuck identity-draft send and the app cancelled the entire parent
//  site visit — a COMPLETED visit holding real completion notes — tombstoning
//  both capture artifacts and ten checklist answers and enqueueing durable
//  soft-DELETE operations for every one of them. The server copy had to be
//  restored by hand.
//
//  These tests pin the corrected contract end to end:
//    · declining a work unit touches ZERO model rows and enqueues ZERO deletes;
//    · the declined row actually leaves the live sections;
//    · the decline STICKS — orphan recovery does not re-create the operation
//      seconds later, including for media work, which is not gated on
//      `needsSync` and therefore cannot be stopped by clearing that flag;
//    · a send already in flight refuses the decline outright;
//    · the inbound checklist-canonicalization merge treats a declined operation
//      as RESOLVED (same class as completed) instead of aborting on an unknown
//      lifecycle.
//
//  SwiftData gotcha honoured here: a `#Predicate` fetch of `SyncOperation`
//  TRAPS (uncatchable EXC_BREAKPOINT) against a table that has never held a
//  row, and every path below runs one. `makeContainer` seeds an inert warm-up
//  operation so the table exists before any test touches it.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PendingWorkDiscardScopeTests: XCTestCase {

    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let userId = "310fbd03-4ffd-4432-b502-e20aff43d548"
    private let visitId = "2091c595-1d2c-4a3f-9a7b-6f4a0e8c1d20"

    // MARK: - The regression (bug f7431c17)

    /// The exact field scenario: a COMPLETED, already-synced visit with two
    /// captures, ten checklist answers and one identity draft, whose ONLY queue
    /// record is a single stuck identity-draft create. Declining it must leave
    /// every stored row untouched and must never enqueue a delete.
    func test_decliningQueuedSends_leavesTheCompletedVisitAndEveryCaptureIntact() throws {
        let context = try makeContext()
        let fixture = try seedCompletedSyncedVisit(in: context)
        let stuck = try makeOperation(
            entityType: .siteVisitIdentityDraft,
            entityId: fixture.draft.id,
            operationType: "create",
            status: "failed"
        )
        stuck.retryCount = 20
        stuck.lastAttemptedAt = Date(timeIntervalSince1970: 900)
        stuck.lastError = "23503 insert or update violates foreign key constraint"
        context.insert(stuck)
        try context.save()

        let bundle = try XCTUnwrap(
            liveBundles(in: context).first,
            "a lone stuck identity-draft send must still render as one work-unit row"
        )
        XCTAssertEqual(bundle.syncOperationIds, [stuck.id])

        XCTAssertTrue(PendingWorkDecline.queuedSends(bundle, in: context))

        // The visit is exactly as the operator left it.
        let visit = try XCTUnwrap(fetchVisit(in: context))
        XCTAssertEqual(visit.status, .completed)
        XCTAssertNil(visit.deletedAt)
        XCTAssertEqual(visit.completedAt, fixture.completedAt)
        XCTAssertEqual(visit.notes, fixture.notes)
        XCTAssertFalse(visit.needsSync)

        // Every captured item survives, untombstoned.
        let artifacts = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        XCTAssertEqual(artifacts.count, 2)
        XCTAssertTrue(artifacts.allSatisfy { $0.deletedAt == nil })
        let answers = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
        XCTAssertEqual(answers.count, 10)
        XCTAssertTrue(answers.allSatisfy { $0.deletedAt == nil })
        let drafts = try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
        XCTAssertEqual(drafts.count, 1)
        XCTAssertNil(drafts[0].deletedAt)

        // No tombstone ever reaches the server.
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertTrue(
            operations.allSatisfy { $0.operationType != "delete" },
            "declining a queued send must never enqueue a soft-delete"
        )
        XCTAssertEqual(operations.count, 2, "warm-up row + the one stuck send")

        // And the stuck send is terminal-declined, with its failure state cleared.
        XCTAssertEqual(stuck.status, "declined")
        XCTAssertNil(stuck.lastError)
        XCTAssertNil(stuck.lastAttemptedAt)
        XCTAssertNil(stuck.completedAt)
    }

    /// The row the operator swiped has to actually leave. It used to come
    /// straight back, because the discard enqueued fresh delete operations that
    /// re-populated the very same work unit.
    func test_declinedWorkUnitLeavesTheAttentionAndSendingSections() throws {
        let context = try makeContext()
        let fixture = try seedCompletedSyncedVisit(in: context)
        let stuck = try makeOperation(
            entityType: .siteVisitIdentityDraft,
            entityId: fixture.draft.id,
            operationType: "create",
            status: "failed"
        )
        context.insert(stuck)
        try context.save()

        let bundle = try XCTUnwrap(liveBundles(in: context).first)
        let inventoryBefore = try liveInventory(in: context)
        XCTAssertTrue(
            PendingWorkDecline.itemRemains(id: bundle.id, in: inventoryBefore),
            "precondition: the stuck work unit is standing in a live section"
        )

        XCTAssertTrue(PendingWorkDecline.queuedSends(bundle, in: context))

        let inventoryAfter = try liveInventory(in: context)
        XCTAssertFalse(
            (inventoryAfter.attention + inventoryAfter.sending)
                .contains { $0.id == bundle.id }
        )
        XCTAssertFalse(PendingWorkDecline.itemRemains(id: bundle.id, in: inventoryAfter))
    }

    /// A capture the operator never finished still belongs in DRAFTS once its
    /// sends are declined — that is a real, different state, not the row
    /// refusing to leave. `itemRemains` must not read it as failure.
    func test_declinedWorkUnitMayReappearAsADraftWithoutCountingAsStillPresent() throws {
        let context = try makeContext()
        let fixture = try seedCompletedSyncedVisit(in: context)
        let stuck = try makeOperation(
            entityType: .siteVisitIdentityDraft,
            entityId: fixture.draft.id,
            operationType: "create",
            status: "failed"
        )
        context.insert(stuck)
        try context.save()

        let bundle = try XCTUnwrap(liveBundles(in: context).first)
        XCTAssertTrue(PendingWorkDecline.queuedSends(bundle, in: context))

        let inventory = try liveInventory(in: context)
        XCTAssertEqual(
            inventory.drafts.map(\.id), [fixture.draft.id],
            "the unfinished capture is still resumable from DRAFTS"
        )
        XCTAssertFalse(PendingWorkDecline.itemRemains(id: fixture.draft.id, in: inventory))
    }

    // MARK: - The decline has to stick

    /// `recoverOrphanedWrites` runs before every outbound drain. If a declined
    /// operation did not read as unresolved, it would be re-created within
    /// seconds and the row would come straight back.
    func test_declinedOperationIsNotRecreatedByOrphanRecovery() throws {
        let context = try makeContext()
        let fixture = try seedCompletedSyncedVisit(in: context)
        fixture.draft.needsSync = true
        let declined = try makeOperation(
            entityType: .siteVisitIdentityDraft,
            entityId: fixture.draft.id,
            operationType: "create",
            status: "declined"
        )
        context.insert(declined)
        try context.save()

        let before = try operationIds(in: context)
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let result = try coordinator.recoverOrphanedWrites()

        XCTAssertEqual(result.operationIds, [])
        XCTAssertEqual(try operationIds(in: context), before)
        XCTAssertEqual(declined.status, "declined")
    }

    /// Media operations are NOT gated on `needsSync` — the queue re-derives them
    /// from any artifact still holding a `local://` asset. Clearing a flag can
    /// never stop them; only treating the declined operation as unresolved can.
    func test_declinedMediaOperationIsNotRecreatedWhileTheAssetIsStillLocal() throws {
        let context = try makeContext()
        let fixture = try seedCompletedSyncedVisit(in: context)
        let artifact = fixture.artifacts[0]
        artifact.localAssetURL = "local://project_images/site-visit-capture.jpg"
        artifact.needsSync = false
        let declined = try makeOperation(
            entityType: .siteVisitArtifact,
            entityId: artifact.id,
            operationType: SiteVisitSyncOperation.mediaOperationType,
            status: "declined"
        )
        context.insert(declined)
        try context.save()

        let before = try operationIds(in: context)
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        let result = try coordinator.recoverOrphanedWrites()

        XCTAssertEqual(
            result.operationIds, [],
            "a declined media send must not be re-derived from the still-local asset"
        )
        XCTAssertEqual(try operationIds(in: context), before)
    }

    /// A genuine later edit is a revival, not a resurrection: the operator
    /// declined a SEND, not the record, so editing the record must send again.
    func test_aLaterEditRevivesADeclinedOperation() throws {
        let context = try makeContext()
        let fixture = try seedCompletedSyncedVisit(in: context)
        let declined = try makeOperation(
            entityType: .siteVisitIdentityDraft,
            entityId: fixture.draft.id,
            operationType: "create",
            status: "declined"
        )
        context.insert(declined)
        try context.save()

        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: context,
            companyId: companyId
        )
        try coordinator.commit {
            fixture.draft.contactName = "Charles Krusekopf"
            fixture.draft.touch()
        }

        XCTAssertEqual(declined.status, "pending")
        XCTAssertEqual(try operationIds(in: context).count, 2, "revived, not duplicated")
    }

    // MARK: - Work already in flight

    func test_workUnitWithAnInFlightSendRefusesTheDeclineAndMutatesNothing() throws {
        let context = try makeContext()
        let fixture = try seedCompletedSyncedVisit(in: context)
        let executing = try makeOperation(
            entityType: .siteVisitIdentityDraft,
            entityId: fixture.draft.id,
            operationType: "create",
            status: "inProgress"
        )
        let failed = try makeOperation(
            entityType: .siteVisitArtifact,
            entityId: fixture.artifacts[0].id,
            operationType: "update",
            status: "failed"
        )
        context.insert(executing)
        context.insert(failed)
        try context.save()

        let bundle = try XCTUnwrap(liveBundles(in: context).first)
        XCTAssertEqual(
            RecoveryItem.bundle(bundle).discardPolicy,
            .unavailable(.operationInProgress)
        )
        XCTAssertFalse(PendingWorkDecline.queuedSends(bundle, in: context))
        XCTAssertEqual(executing.status, "inProgress")
        XCTAssertEqual(
            failed.status, "failed",
            "a sibling send must not be declined behind an in-flight one"
        )
    }

    // MARK: - Inbound merge treats a declined send as resolved

    /// Checklist-id canonicalization fails closed on any lifecycle it does not
    /// recognise. A declined source operation is RESOLVED and inert — it must
    /// not abort the merge.
    func test_checklistCanonicalizationAcceptsADeclinedSourceOperation() throws {
        let context = try makeContext()
        context.insert(makeVisit())
        let localId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let local = makeAnswer(id: localId, fieldId: "width", label: "Local width")
        context.insert(local)
        let declined = try makeOperation(
            entityType: .siteVisitChecklistAnswer,
            entityId: localId,
            operationType: "create",
            status: "declined"
        )
        context.insert(declined)
        try context.save()

        let serverAnswer = try serverChecklistAnswer(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02",
            fieldId: "width"
        )
        XCTAssertNoThrow(
            try SiteVisitServerMerge.merge(
                checklistAnswer: serverAnswer,
                companyId: companyId,
                into: context,
                now: Date(timeIntervalSince1970: 5_000)
            )
        )
        XCTAssertEqual(local.id, serverAnswer.id, "the local answer takes the server identity")
        XCTAssertEqual(
            declined.entityId, localId,
            "a resolved send is never migrated onto the canonical id"
        )
        XCTAssertEqual(declined.status, "declined")
    }

    /// The same guard on the other side: a declined operation already sitting on
    /// the canonical id is not a collision.
    func test_checklistCanonicalizationAcceptsADeclinedCanonicalOperation() throws {
        let context = try makeContext()
        context.insert(makeVisit())
        let localId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let canonicalId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02"
        let local = makeAnswer(id: localId, fieldId: "width", label: "Local width")
        context.insert(local)
        let declined = try makeOperation(
            entityType: .siteVisitChecklistAnswer,
            entityId: canonicalId,
            operationType: "create",
            status: "declined"
        )
        context.insert(declined)
        try context.save()

        let serverAnswer = try serverChecklistAnswer(id: canonicalId, fieldId: "width")
        XCTAssertNoThrow(
            try SiteVisitServerMerge.merge(
                checklistAnswer: serverAnswer,
                companyId: companyId,
                into: context,
                now: Date(timeIntervalSince1970: 5_000)
            )
        )
        XCTAssertEqual(local.id, canonicalId)
        XCTAssertEqual(declined.status, "declined")
    }

    // MARK: - Fixtures

    private struct VisitFixture {
        let visit: SiteVisit
        let artifacts: [SiteVisitCaptureArtifact]
        let answers: [SiteVisitChecklistAnswer]
        let draft: SiteVisitIdentityDraft
        let completedAt: Date
        let notes: String
    }

    /// A finished, already-synced visit — the state the field bug destroyed.
    @discardableResult
    private func seedCompletedSyncedVisit(in context: ModelContext) throws -> VisitFixture {
        let completedAt = Date(timeIntervalSince1970: 800)
        let syncedAt = Date(timeIntervalSince1970: 810)
        let notes = "Rear deck rebuild — replace 12 joists, client signed off on cedar."

        let visit = makeVisit()
        visit.status = .completed
        visit.completedAt = completedAt
        visit.notes = notes
        visit.needsSync = false
        visit.lastSyncedAt = syncedAt
        context.insert(visit)

        let artifacts = (0..<2).map { index -> SiteVisitCaptureArtifact in
            let artifact = SiteVisitCaptureArtifact(
                siteVisitId: visitId,
                companyId: companyId,
                kind: .photo,
                source: .camera,
                localAssetURL: "https://cdn.example.com/site-visit/\(index).jpg",
                capturedAt: Date(timeIntervalSince1970: 700 + Double(index)),
                createdBy: userId,
                createdAt: Date(timeIntervalSince1970: 700 + Double(index))
            )
            artifact.needsSync = false
            artifact.lastSyncedAt = syncedAt
            context.insert(artifact)
            return artifact
        }

        let answers = (0..<10).map { index -> SiteVisitChecklistAnswer in
            let answer = SiteVisitChecklistAnswer(
                siteVisitId: visitId,
                companyId: companyId,
                opportunityId: nil,
                siteVisitTypeId: "estimate",
                fieldId: "field-\(index)",
                label: "Field \(index)",
                kind: .shortText,
                required: false,
                sortOrder: index,
                answerValue: SiteVisitChecklistValue(text: "Answer \(index)"),
                createdBy: userId,
                createdAt: Date(timeIntervalSince1970: 700 + Double(index))
            )
            answer.needsSync = false
            answer.lastSyncedAt = syncedAt
            context.insert(answer)
            return answer
        }

        let draft = SiteVisitIdentityDraft(
            siteVisitId: visitId,
            companyId: companyId,
            contactName: "Charles Krusekopf",
            address: "1420 Lyall St",
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 700)
        )
        draft.needsSync = false
        draft.lastSyncedAt = syncedAt
        context.insert(draft)

        try context.save()
        return VisitFixture(
            visit: visit,
            artifacts: artifacts,
            answers: answers,
            draft: draft,
            completedAt: completedAt,
            notes: notes
        )
    }

    private func makeVisit() -> SiteVisit {
        SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 600),
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 600)
        )
    }

    private func makeAnswer(
        id: String,
        fieldId: String,
        label: String
    ) -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            id: id,
            siteVisitId: visitId,
            companyId: companyId,
            opportunityId: nil,
            siteVisitTypeId: "estimate",
            fieldId: fieldId,
            label: label,
            kind: .measurement,
            required: true,
            sortOrder: 10,
            answerValue: SiteVisitChecklistValue(text: "12 ft"),
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 700)
        )
    }

    private func makeOperation(
        entityType: SyncEntityType,
        entityId: String,
        operationType: String,
        status: String
    ) throws -> SyncOperation {
        let operation = SyncOperation(
            entityType: entityType.rawValue,
            entityId: entityId.lowercased(),
            operationType: operationType,
            payload: try JSONEncoder().encode(
                SiteVisitSyncOperation.Payload(
                    companyId: companyId,
                    siteVisitId: visitId,
                    entityId: entityId
                )
            ),
            changedFields: ["answer_value"],
            priority: 1
        )
        operation.status = status
        operation.createdAt = Date(timeIntervalSince1970: 900)
        return operation
    }

    private func serverChecklistAnswer(
        id: String,
        fieldId: String
    ) throws -> SiteVisitChecklistAnswerDTO {
        try JSONDecoder().decode(
            SiteVisitChecklistAnswerDTO.self,
            from: Data("""
            {
              "id":"\(id)",
              "site_visit_id":"\(visitId)",
              "company_id":"\(companyId)",
              "field_id":"\(fieldId)",
              "label":"Width",
              "kind":"measurement",
              "required":true,
              "sort_order":10,
              "answer_value":{"text":"12 ft","artifactIds":[]},
              "created_by":"\(userId)",
              "created_at":"2026-07-31T18:12:46Z",
              "updated_at":"2026-07-31T18:12:46Z"
            }
            """.utf8)
        )
    }

    // MARK: - Live inventory (the real builder, minus the screen's singletons)

    /// Maps the live store into the pure builder exactly as
    /// `RecoveryInventory.load` does, without reaching for the recovery vault,
    /// the autocreate queue, or UserDefaults.
    private func liveInventory(in context: ModelContext) throws -> RecoveryInventory {
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
            .map(SyncOpSnapshot.init(from:))
        let drafts = try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter { $0.opportunityId == nil || $0.lastCommittedAt == nil }
            .map(DraftSnapshot.init(from:))
        let artifacts = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter { $0.deletedAt == nil }
            .map(ArtifactSnapshot.init(from:))
        let answers = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter { $0.deletedAt == nil }
            .map(ChecklistAnswerSnapshot.init(from:))
        return RecoveryInventory.build(
            ops: operations,
            autocreates: [],
            photos: [],
            drafts: drafts,
            artifacts: artifacts,
            answers: answers,
            orphans: [],
            now: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func liveBundles(in context: ModelContext) throws -> [SiteVisitBundle] {
        let inventory = try liveInventory(in: context)
        return (inventory.attention + inventory.sending).compactMap {
            if case .bundle(let bundle) = $0 { return bundle }
            return nil
        }
    }

    private func fetchVisit(in context: ModelContext) throws -> SiteVisit? {
        try context.fetch(FetchDescriptor<SiteVisit>()).first
    }

    private func operationIds(in context: ModelContext) throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<SyncOperation>()).map(\.id))
    }

    // MARK: - Container

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )

        // A #Predicate fetch of SyncOperation TRAPS (uncatchable EXC_BREAKPOINT
        // inside SwiftData) against a store whose operation table has never held
        // a row — see the note on ProjectCacheMerge.operations. Every path under
        // test runs such a fetch, so materialize the table with an inert row
        // scoped to no real entity.
        let warmup = ModelContext(container)
        warmup.insert(
            SyncOperation(
                entityType: "pendingWorkDeclineWarmup",
                entityId: "pendingWorkDeclineWarmup",
                operationType: "update",
                payload: Data("{}".utf8),
                changedFields: []
            )
        )
        try warmup.save()

        return ModelContext(container)
    }
}
