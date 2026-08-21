//
//  HistoricalSiteVisitSettlementCoordinatorTests.swift
//  OPSTests
//
//  End-to-end synthetic proof for the non-automatic executor: active history
//  gets one narrow link and exact re-arm; completed history performs no remote
//  mutation and records local accounting with no false server confirmation.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class HistoricalSiteVisitSettlementCoordinatorTests: XCTestCase {
    private let companyID = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let userID = "11111111-1111-4111-8111-111111111111"
    private let opportunityID = "22222222-2222-4222-8222-222222222222"
    private let visitID = "33333333-3333-4333-8333-333333333333"
    private let serverUpdatedAt = Date(timeIntervalSince1970: 1_780_000_000)
    private var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func test_activeLinkUsesOneCASThenIdempotentReplayDoesNotMutateAgain() async throws {
        let context = try makeContext()
        let visit = makeVisit(status: .inProgress)
        let operation = try insertGraph(visit: visit, context: context)
        operation.status = "parked"
        operation.lastError = "historical relationship rejected"
        try context.save()

        let remote = FakeHistoricalRemote(
            unlinked: try makeBundle(status: .inProgress, opportunityId: nil),
            linked: try makeBundle(status: .inProgress, opportunityId: opportunityID)
        )
        let receipts = MemoryHistoricalReceiptStore()
        let coordinator = HistoricalSiteVisitSettlementCoordinator(
            context: context,
            remote: remote,
            receipts: receipts,
            manifest: makeManifest(status: .inProgress, outcome: .recoverActiveLink)
        )
        let policy = makeAccessPolicy()
        let plan = try await coordinator.prepare(
            visitId: visitID,
            actorUserId: userID,
            accessPolicy: policy
        )
        let approval = makeApproval(plan)

        let first = try await coordinator.execute(
            plan: plan,
            approval: approval,
            accessPolicy: policy,
            now: Date(timeIntervalSince1970: 1_780_000_100)
        )
        let second = try await coordinator.execute(
            plan: plan,
            approval: approval,
            accessPolicy: policy,
            now: Date(timeIntervalSince1970: 1_780_000_200)
        )

        XCTAssertEqual(remote.mutationCount, 1)
        XCTAssertEqual(first.phase, .applied)
        XCTAssertEqual(second, first)
        XCTAssertTrue(first.serverMutationPerformed)
        XCTAssertEqual(operation.status, "pending")
        XCTAssertEqual(operation.retryCount, 0)
        XCTAssertNil(operation.lastError)
        XCTAssertEqual(visit.opportunityId, opportunityID)
    }

    func test_completedSettlementNeverMutatesServerAndClearsOnlyRejectedLocalIntent() async throws {
        let context = try makeContext()
        let visit = makeVisit(status: .completed)
        visit.completedAt = Date(timeIntervalSince1970: 1_779_999_900)
        let operation = try insertGraph(visit: visit, context: context)
        operation.status = "parked"
        operation.lastError = "completed history is immutable"
        try context.save()

        let bundle = try makeBundle(
            status: .completed,
            opportunityId: nil,
            completedAt: visit.completedAt
        )
        let remote = FakeHistoricalRemote(unlinked: bundle, linked: bundle)
        let receipts = MemoryHistoricalReceiptStore()
        let coordinator = HistoricalSiteVisitSettlementCoordinator(
            context: context,
            remote: remote,
            receipts: receipts,
            manifest: makeManifest(status: .completed, outcome: .settleCompletedHistory)
        )
        let policy = makeAccessPolicy()
        let plan = try await coordinator.prepare(
            visitId: visitID,
            actorUserId: userID,
            accessPolicy: policy
        )
        let receipt = try await coordinator.execute(
            plan: plan,
            approval: makeApproval(plan),
            accessPolicy: policy,
            now: Date(timeIntervalSince1970: 1_780_000_100)
        )

        XCTAssertEqual(remote.mutationCount, 0)
        XCTAssertEqual(receipt.phase, .applied)
        XCTAssertFalse(receipt.serverMutationPerformed)
        XCTAssertNil(visit.opportunityId)
        XCTAssertFalse(visit.needsSync)
        XCTAssertEqual(operation.status, "completed")
        XCTAssertNil(operation.serverConfirmedAt)
        XCTAssertEqual(operation.completedAt, Date(timeIntervalSince1970: 1_780_000_100))
    }

    func test_fileReceiptStoreRejectsDigestCollisionAndPersistsAppliedState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoricalSiteVisitSettlementReceiptStore(directoryURL: directory)
        let plan = makePlanForReceipt()
        let approval = makeApproval(plan)

        _ = try store.prepare(plan: plan, approval: approval, at: serverUpdatedAt)
        let applied = try store.markApplied(
            approvalDigest: plan.approvalDigest,
            serverMutationPerformed: false,
            at: serverUpdatedAt.addingTimeInterval(1)
        )

        XCTAssertEqual(try store.receipt(approvalDigest: plan.approvalDigest), applied)
        XCTAssertThrowsError(
            try store.prepare(
                plan: plan,
                approval: approval.replacing(
                    targetOpportunityId: "44444444-4444-4444-8444-444444444444"
                ),
                at: serverUpdatedAt
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .auditConflict) }
    }

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            Opportunity.self,
            SyncOperation.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return container.mainContext
    }

    private func makeVisit(status: SiteVisitStatus) -> SiteVisit {
        let visit = SiteVisit(
            id: visitID,
            opportunityId: opportunityID,
            companyId: companyID,
            status: status,
            scheduledAt: Date(timeIntervalSince1970: 1_779_999_000),
            assigneeIds: [userID],
            createdBy: userID,
            createdAt: Date(timeIntervalSince1970: 1_779_999_000)
        )
        visit.needsSync = true
        return visit
    }

    private func insertGraph(visit: SiteVisit, context: ModelContext) throws -> SyncOperation {
        let opportunity = Opportunity(
            id: opportunityID,
            companyId: companyID,
            contactName: "Synthetic Lead"
        )
        opportunity.assignedTo = userID
        context.insert(opportunity)
        context.insert(visit)

        let specification = SiteVisitSyncOperation.parent(visit)
        let operation = SyncOperation(
            entityType: specification.entityType.rawValue,
            entityId: specification.entityId,
            operationType: "update",
            payload: try JSONEncoder().encode(specification.payload),
            changedFields: specification.changedFields
        )
        context.insert(operation)
        return operation
    }

    private func makeManifest(
        status: SiteVisitStatus,
        outcome: HistoricalSiteVisitSettlementOutcome
    ) -> HistoricalSiteVisitSettlementManifest {
        HistoricalSiteVisitSettlementManifest(
            entries: [
                .init(
                    visitId: visitID,
                    companyId: companyID,
                    expectedServerStatus: status,
                    expectedServerUpdatedAt: serverUpdatedAt,
                    outcome: outcome
                ),
            ]
        )
    }

    private func makeBundle(
        status: SiteVisitStatus,
        opportunityId: String?,
        completedAt: Date? = nil
    ) throws -> SiteVisitBundleDTO {
        var visit: [String: Any] = [
            "id": visitID,
            "company_id": companyID,
            "scheduled_at": SupabaseDate.format(Date(timeIntervalSince1970: 1_779_999_000)),
            "duration_minutes": 60,
            "assignee_ids": [userID],
            "status": status.rawValue,
            "photos": [],
            "created_by": userID,
            "created_at": SupabaseDate.format(Date(timeIntervalSince1970: 1_779_999_000)),
            "updated_at": SupabaseDate.format(serverUpdatedAt),
        ]
        if let opportunityId { visit["opportunity_id"] = opportunityId }
        if let completedAt { visit["completed_at"] = SupabaseDate.format(completedAt) }
        let data = try JSONSerialization.data(withJSONObject: [
            "visit": visit,
            "artifacts": [],
            "checklist_answers": [],
            "identity_drafts": [],
        ])
        return try JSONDecoder().decode(SiteVisitBundleDTO.self, from: data)
    }

    private func makeAccessPolicy() -> LeadAccessPolicy {
        LeadAccessPolicy(
            currentUserId: userID,
            permissions: [
                "pipeline.view": "all",
                "pipeline.edit": "all",
            ],
            explicitPermissionKeys: ["pipeline.view", "pipeline.edit"]
        )
    }

    private func makeApproval(
        _ plan: HistoricalSiteVisitSettlementPlan
    ) -> HistoricalSiteVisitSettlementApproval {
        HistoricalSiteVisitSettlementApproval(
            approvalDigest: plan.approvalDigest,
            actorUserId: userID,
            companyId: companyID,
            visitId: visitID,
            targetOpportunityId: opportunityID,
            outcome: plan.outcome,
            approvedAt: serverUpdatedAt
        )
    }

    private func makePlanForReceipt() -> HistoricalSiteVisitSettlementPlan {
        HistoricalSiteVisitSettlementPlan(
            visitId: visitID,
            companyId: companyID,
            actorUserId: userID,
            targetOpportunityId: opportunityID,
            targetOpportunityAssignedTo: userID,
            expectedServerStatus: .completed,
            expectedServerUpdatedAt: serverUpdatedAt,
            outcome: .settleCompletedHistory,
            operationIds: ["55555555-5555-4555-8555-555555555555"],
            contentFingerprint: "content",
            approvalDigest: String(repeating: "a", count: 64)
        )
    }
}
@MainActor
private final class FakeHistoricalRemote: HistoricalSiteVisitSettlementRemote {
    private var current: SiteVisitBundleDTO
    private let linked: SiteVisitBundleDTO
    private(set) var mutationCount = 0

    init(unlinked: SiteVisitBundleDTO, linked: SiteVisitBundleDTO) {
        current = unlinked
        self.linked = linked
    }

    func fetchBundle(siteVisitId: String) async throws -> SiteVisitBundleDTO {
        current
    }

    func compareAndSetUnlinkedActiveVisit(
        visitId: String,
        companyId: String,
        targetOpportunityId: String,
        expectedStatus: SiteVisitStatus,
        expectedUpdatedAt: Date
    ) async throws -> SiteVisitBundleDTO {
        mutationCount += 1
        current = linked
        return linked
    }
}

@MainActor
private final class MemoryHistoricalReceiptStore: HistoricalSiteVisitSettlementReceiptStoring {
    private var receipts: [String: HistoricalSiteVisitSettlementReceipt] = [:]

    func receipt(approvalDigest: String) throws -> HistoricalSiteVisitSettlementReceipt? {
        receipts[approvalDigest]
    }

    func prepare(
        plan: HistoricalSiteVisitSettlementPlan,
        approval: HistoricalSiteVisitSettlementApproval,
        at date: Date
    ) throws -> HistoricalSiteVisitSettlementReceipt {
        if let existing = receipts[plan.approvalDigest] { return existing }
        let receipt = HistoricalSiteVisitSettlementReceipt(
            plan: plan,
            approval: approval,
            phase: .prepared,
            preparedAt: date,
            appliedAt: nil,
            serverMutationPerformed: false
        )
        receipts[plan.approvalDigest] = receipt
        return receipt
    }

    func markApplied(
        approvalDigest: String,
        serverMutationPerformed: Bool,
        at date: Date
    ) throws -> HistoricalSiteVisitSettlementReceipt {
        guard let existing = receipts[approvalDigest] else {
            throw HistoricalSiteVisitSettlementError.auditConflict
        }
        let receipt = HistoricalSiteVisitSettlementReceipt(
            plan: existing.plan,
            approval: existing.approval,
            phase: .applied,
            preparedAt: existing.preparedAt,
            appliedAt: date,
            serverMutationPerformed: serverMutationPerformed
        )
        receipts[approvalDigest] = receipt
        return receipt
    }
}
