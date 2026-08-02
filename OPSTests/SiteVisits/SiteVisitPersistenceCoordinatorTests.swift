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
