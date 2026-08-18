//
//  SiteVisitDeletedParentSettlementTests.swift
//  OPSTests
//
//  Deleted-parent settlement (SITE VISIT SYNC WEDGE): when the server says a
//  visit was deleted (`cannot_complete_deleted_site_visit`, errcode 55000), the
//  phone's queued chain for that visit can never land — child writes are
//  RLS-blocked once the parent carries deleted_at. The sweep must move the whole
//  chain into protected vault custody (operator-visible in PENDING WORK) instead
//  of leaving it to retry, park, or silently re-enqueue forever.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitDeletedParentSettlementTests: XCTestCase {
    private var liveContainers: [ModelContainer] = []

    private let companyId = "a1111111-1111-4111-8111-111111111111"
    private let userId = "a2222222-2222-4222-8222-222222222222"
    private let visitId = "a3333333-3333-4333-8333-333333333333"
    private let artifactId = "a4444444-4444-4444-8444-444444444444"
    private let draftId = "a5555555-5555-4555-8555-555555555555"
    private let answerId = "a6666666-6666-4666-8666-666666666666"
    private let otherVisitId = "b3333333-3333-4333-8333-333333333333"
    private let otherAnswerId = "b6666666-6666-4666-8666-666666666666"
    private let foreignCompanyId = "c1111111-1111-4111-8111-111111111111"

    /// The exact shape the outbound engines persist into `lastError` after a
    /// completion push dies on the server's deliberate raise.
    private let storedRejection =
        "[55000] cannot_complete_deleted_site_visit"

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Detection

    func test_detectionMatchesOnlyTheDeletedParentRaise() {
        XCTAssertTrue(
            SiteVisitDeletedParentSettlement.isDeletedParentRejection(
                SiteVisitRepositoryError.server(
                    code: "55000",
                    message: "cannot_complete_deleted_site_visit",
                    detail: nil,
                    hint: nil
                )
            )
        )
        // The sibling raise means the visit still exists (cancelled) — its
        // children remain writable, so it must NOT trigger chain settlement.
        XCTAssertFalse(
            SiteVisitDeletedParentSettlement.isDeletedParentRejection(
                SiteVisitRepositoryError.server(
                    code: "55000",
                    message: "cannot_complete_cancelled_site_visit",
                    detail: nil,
                    hint: nil
                )
            )
        )
        // Same name under a different errcode is not the server contract.
        XCTAssertFalse(
            SiteVisitDeletedParentSettlement.isDeletedParentRejection(
                SiteVisitRepositoryError.server(
                    code: "42501",
                    message: "cannot_complete_deleted_site_visit",
                    detail: nil,
                    hint: nil
                )
            )
        )
        XCTAssertFalse(
            SiteVisitDeletedParentSettlement.isDeletedParentRejection(
                SiteVisitRepositoryError.transport("offline")
            )
        )
    }

    func test_lastErrorMatcherRecognisesTheStoredRejection() {
        XCTAssertTrue(
            SiteVisitDeletedParentSettlement.indicatesDeletedParent(
                lastError: storedRejection
            )
        )
        XCTAssertTrue(
            SiteVisitDeletedParentSettlement.indicatesDeletedParent(
                lastError: storedRejection + " Detail: visit 2091c595"
            )
        )
        XCTAssertFalse(
            SiteVisitDeletedParentSettlement.indicatesDeletedParent(
                lastError: "[55000] cannot_complete_cancelled_site_visit"
            )
        )
        XCTAssertFalse(
            SiteVisitDeletedParentSettlement.indicatesDeletedParent(lastError: nil)
        )
    }

    // MARK: - Sweep

    func test_sweepQuarantinesTheWholeChainAndRecordsOnePacket() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        visit.needsSync = true
        let artifact = makeArtifact()
        let answer = makeAnswer()
        let draft = makeDraft()
        context.insert(visit)
        context.insert(artifact)
        context.insert(answer)
        context.insert(draft)

        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        completion.status = "failed"
        completion.lastError = storedRejection
        let childArtifact = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            dependsOn: completion,
            in: context
        )
        let childAnswer = try insert(
            SiteVisitSyncOperation.checklistAnswer(answer),
            dependsOn: childArtifact,
            in: context
        )
        let childDraft = try insert(
            SiteVisitSyncOperation.identityDraft(draft),
            dependsOn: childAnswer,
            in: context
        )
        let media = try insert(
            SiteVisitSyncOperation.media(artifact),
            dependsOn: childDraft,
            in: context
        )

        var records: [SiteVisitOrphanQuarantine] = []
        let result = try SiteVisitDeletedParentSettlement.sweep(
            in: context,
            activeUserId: userId,
            activeCompanyId: companyId,
            quarantine: { records.append($0) }
        )

        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.reason, .parentDeleted)
        XCTAssertEqual(record.siteVisitId, visitId)
        XCTAssertEqual(record.companyId, companyId)
        XCTAssertEqual(record.userId, userId)
        XCTAssertEqual(
            record.id,
            "site-visit-quarantine:parent_deleted:\(companyId):\(visitId)"
        )
        XCTAssertEqual(
            Set(record.childIds),
            [artifactId, answerId, draftId],
            "The packet must name every captured child so the vault archives them all"
        )

        for operation in [completion, childArtifact, childAnswer, childDraft, media] {
            XCTAssertEqual(operation.status, "quarantined")
        }
        XCTAssertFalse(visit.needsSync)
        XCTAssertFalse(artifact.needsSync)
        XCTAssertFalse(answer.needsSync)
        XCTAssertFalse(draft.needsSync)

        XCTAssertEqual(result.quarantinedVisitIds, [visitId])
        XCTAssertEqual(
            Set(result.settledOperationIds),
            Set([completion, childArtifact, childAnswer, childDraft, media].map(\.id))
        )
    }

    func test_sweepMatchesPendingAndParkedRoots() throws {
        // A root that parked under the new classifier — and one still "pending"
        // mid-backoff from an older build — both carry the stored rejection and
        // both must settle. Waiting for another doomed round trip helps no one.
        for rootStatus in ["parked", "pending"] {
            let context = try makeContainer().mainContext
            let visit = makeVisit()
            context.insert(visit)
            let completion = try insert(
                SiteVisitSyncOperation.completion(visit),
                in: context
            )
            completion.status = rootStatus
            completion.lastError = storedRejection

            let result = try SiteVisitDeletedParentSettlement.sweep(
                in: context,
                activeUserId: userId,
                activeCompanyId: companyId,
                quarantine: { _ in }
            )

            XCTAssertEqual(
                completion.status,
                "quarantined",
                "root with status \(rootStatus) must settle"
            )
            XCTAssertEqual(result.quarantinedVisitIds, [visitId])
        }
    }

    func test_sweepLeavesOtherVisitsForeignCompaniesAndUnrelatedErrorsAlone() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        context.insert(visit)

        // Root with an unrelated parked error — not our signal.
        let unrelated = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        unrelated.status = "parked"
        unrelated.lastError = "[55000] cannot_complete_cancelled_site_visit"

        // A different visit's healthy pending answer.
        let otherAnswer = SiteVisitChecklistAnswer(
            id: otherAnswerId,
            siteVisitId: otherVisitId,
            companyId: companyId,
            opportunityId: nil,
            siteVisitTypeId: nil,
            fieldId: "gate_code",
            label: "Gate code",
            kind: .shortText,
            required: false,
            sortOrder: 0,
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
        context.insert(otherAnswer)
        let otherOp = try insert(
            SiteVisitSyncOperation.checklistAnswer(otherAnswer),
            in: context
        )

        // A foreign-company chain carrying the signal — never ours to settle.
        let foreignVisit = SiteVisit(
            id: otherVisitId,
            companyId: foreignCompanyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
            assigneeIds: [userId],
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let foreignCompletion = try insert(
            SiteVisitSyncOperation.completion(foreignVisit),
            in: context
        )
        foreignCompletion.status = "failed"
        foreignCompletion.lastError = storedRejection

        var records: [SiteVisitOrphanQuarantine] = []
        let result = try SiteVisitDeletedParentSettlement.sweep(
            in: context,
            activeUserId: userId,
            activeCompanyId: companyId,
            quarantine: { records.append($0) }
        )

        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(result.quarantinedVisitIds.isEmpty)
        XCTAssertEqual(unrelated.status, "parked")
        XCTAssertEqual(otherOp.status, "pending")
        XCTAssertEqual(foreignCompletion.status, "failed")
    }

    func test_recorderFailureAbortsWithoutMutatingAnything() throws {
        // Mirrors the orphan-recovery discipline: custody is recorded BEFORE any
        // mutation. A full-disk/keychain failure must leave the chain exactly as
        // found so the next sweep can try again — never half-settled.
        struct VaultDown: Error {}
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        visit.needsSync = true
        let artifact = makeArtifact()
        context.insert(visit)
        context.insert(artifact)
        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        completion.status = "parked"
        completion.lastError = storedRejection
        let child = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            dependsOn: completion,
            in: context
        )

        XCTAssertThrowsError(
            try SiteVisitDeletedParentSettlement.sweep(
                in: context,
                activeUserId: userId,
                activeCompanyId: companyId,
                quarantine: { _ in throw VaultDown() }
            )
        )

        XCTAssertEqual(completion.status, "parked")
        XCTAssertEqual(child.status, "pending")
        XCTAssertTrue(visit.needsSync)
    }

    func test_inProgressOperationIsLeftForTheNextSweep() throws {
        // A write on the wire belongs to its engine until it lands. The sweep
        // settles around it; flipping it mid-flight would race the engine's own
        // completion/failure bookkeeping.
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact()
        context.insert(visit)
        context.insert(artifact)
        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        completion.status = "parked"
        completion.lastError = storedRejection
        let inFlight = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            in: context
        )
        inFlight.status = "inProgress"

        let result = try SiteVisitDeletedParentSettlement.sweep(
            in: context,
            activeUserId: userId,
            activeCompanyId: companyId,
            quarantine: { _ in }
        )

        XCTAssertEqual(completion.status, "quarantined")
        XCTAssertEqual(inFlight.status, "inProgress")
        XCTAssertFalse(result.settledOperationIds.contains(inFlight.id))
    }

    func test_secondSweepIsANoOp() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        context.insert(visit)
        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        completion.status = "failed"
        completion.lastError = storedRejection

        var recordCount = 0
        _ = try SiteVisitDeletedParentSettlement.sweep(
            in: context,
            activeUserId: userId,
            activeCompanyId: companyId,
            quarantine: { _ in recordCount += 1 }
        )
        let second = try SiteVisitDeletedParentSettlement.sweep(
            in: context,
            activeUserId: userId,
            activeCompanyId: companyId,
            quarantine: { _ in recordCount += 1 }
        )

        XCTAssertEqual(recordCount, 1)
        XCTAssertTrue(second.quarantinedVisitIds.isEmpty)
        XCTAssertEqual(completion.status, "quarantined")
    }

    // MARK: - Factories

    private func makeVisit() -> SiteVisit {
        SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .completed,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
            assigneeIds: [userId],
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeArtifact() -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: "local://project_images/markup.jpg",
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    private func makeAnswer() -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            id: answerId,
            siteVisitId: visitId,
            companyId: companyId,
            opportunityId: nil,
            siteVisitTypeId: nil,
            fieldId: "gate_code",
            label: "Gate code",
            kind: .shortText,
            required: false,
            sortOrder: 0,
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
    }

    private func makeDraft() -> SiteVisitIdentityDraft {
        SiteVisitIdentityDraft(
            id: draftId,
            siteVisitId: visitId,
            companyId: companyId,
            clientName: "Ridge Line Exteriors",
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
    }

    private func insert(
        _ specification: SiteVisitSyncOperation.Specification,
        dependsOn dependency: SyncOperation? = nil,
        in context: ModelContext
    ) throws -> SyncOperation {
        let operation = SyncOperation(
            entityType: specification.entityType.rawValue,
            entityId: specification.entityId,
            operationType: specification.operationType,
            payload: try JSONEncoder().encode(specification.payload),
            changedFields: specification.changedFields,
            priority: specification.priority,
            dependsOnId: dependency?.id.uuidString.lowercased()
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
