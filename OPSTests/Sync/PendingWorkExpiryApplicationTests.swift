//
//  PendingWorkExpiryApplicationTests.swift
//  OPSTests
//
//  Bug f71113a3 — the ACTING half of the 30-day expiry, against a real store.
//  `PendingWorkExpiryPolicyTests` pins what the policy decides; this file pins
//  what `SyncEngine.applyPendingWorkExpiry` actually does to the database when
//  it acts on those decisions.
//
//  The guarantees under test are the ones that cost real work if they break:
//    · stalled queue metadata is deleted, fresh work beside it is untouched;
//    · a create op — the only path a whole record has to the server — survives;
//    · an EMPTY visit packet's sends move to the terminal `declined` status and
//      are NEVER deleted (the decline-sticks contract, bug f7431c17), while the
//      visit row and every captured child stay exactly where they are;
//    · a content-bearing packet is not touched at all;
//    · a row retried between the inventory build and the purge keeps its fresh
//      attempt.
//
//  Inventory is assembled through the pure `RecoveryInventory.build` from live
//  rows — the same mapping `load` performs — so the test never reaches for the
//  recovery vault, UserDefaults scoping, or the shared autocreate queue.
//
//  SwiftData gotcha honoured here: a `#Predicate` fetch of `SyncOperation` TRAPS
//  (uncatchable EXC_BREAKPOINT) against a table that has never held a row, so
//  `makeContext` seeds an inert warm-up operation first.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PendingWorkExpiryApplicationTests: XCTestCase {

    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let userId = "310fbd03-4ffd-4432-b502-e20aff43d548"
    private let visitId = "2091c595-1d2c-4a3f-9a7b-6f4a0e8c1d20"

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var day: TimeInterval { 24 * 60 * 60 }

    private var retainedContainers: [ModelContainer] = []
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "pending-work-expiry-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Loose operations

    func testReopenAndDependentScheduleSurviveExpiryTogether() throws {
        let context = try makeContext()
        let reopen = makeOperation(entityType: .project, entityId: "archived-project",
            operationType: ProjectReopenSync.operationType, status: "parked", createdAt: now.addingTimeInterval(-400 * day))
        let schedule = makeOperation(entityType: .projectTask, entityId: "waiting-task",
            operationType: "update", status: "failed", createdAt: now.addingTimeInterval(-399 * day))
        schedule.dependsOnId = reopen.id.uuidString.lowercased()
        context.insert(reopen)
        context.insert(schedule)
        try context.save()
        XCTAssertEqual(apply(in: context), .none)
        let remaining = try liveOperations(in: context)
        XCTAssertTrue(remaining.contains { $0.id == reopen.id })
        XCTAssertTrue(remaining.contains { $0.id == schedule.id })
        XCTAssertEqual(schedule.dependsOnId, reopen.id.uuidString.lowercased())
    }

    func test_stalledUpdateIsDeletedAndFreshWorkBesideItSurvives() throws {
        let context = try makeContext()
        let stale = makeOperation(
            entityType: .project,
            entityId: "project-stale",
            operationType: "update",
            status: "failed",
            createdAt: now.addingTimeInterval(-31 * day)
        )
        let fresh = makeOperation(
            entityType: .project,
            entityId: "project-fresh",
            operationType: "update",
            status: "failed",
            createdAt: now.addingTimeInterval(-1 * day)
        )
        context.insert(stale)
        context.insert(fresh)
        try context.save()

        let outcome = apply(in: context)

        XCTAssertEqual(outcome.expiredOperations, 1)
        XCTAssertEqual(outcome.expiredLeadRequests, 0)
        XCTAssertEqual(outcome.expiredEmptyBundles, 0)

        let remaining = try liveOperations(in: context)
            .filter { $0.entityType == SyncEntityType.project.rawValue }
        XCTAssertEqual(remaining.map(\.entityId), ["project-fresh"])
    }

    /// Deleting a create op silently orphans a whole record on this phone.
    func test_stalledCreateIsNeverDeleted() throws {
        let context = try makeContext()
        let create = makeOperation(
            entityType: .project,
            entityId: "project-create",
            operationType: "create",
            status: "parked",
            createdAt: now.addingTimeInterval(-400 * day)
        )
        context.insert(create)
        try context.save()

        let outcome = apply(in: context)

        XCTAssertEqual(outcome, .none)
        XCTAssertEqual(
            try liveOperations(in: context).filter { $0.entityId == "project-create" }.count,
            1
        )
    }

    /// The live-status re-check: an op the policy marked, but whose row flipped
    /// back to `pending` before the purge ran, keeps its fresh attempt.
    func test_anOperationRetriedDuringThePassIsNotDeleted() throws {
        let context = try makeContext()
        let stale = makeOperation(
            entityType: .project,
            entityId: "project-retried",
            operationType: "update",
            status: "failed",
            createdAt: now.addingTimeInterval(-31 * day)
        )
        context.insert(stale)
        try context.save()

        let inventory = try liveInventory(in: context)
        XCTAssertEqual(inventory.attention.count, 1, "the stale op should be the only attention row")

        // The retry lands between the inventory build and the purge.
        stale.status = "pending"
        try context.save()

        let outcome = SyncEngine().applyPendingWorkExpiry(
            inventory: inventory,
            now: now,
            in: context,
            queue: makeQueue()
        )

        XCTAssertEqual(outcome, .none)
        XCTAssertEqual(
            try liveOperations(in: context).filter { $0.entityId == "project-retried" }.count,
            1
        )
    }

    // MARK: - Site-visit packets

    func test_emptyStalledPacketDeclinesItsSendsAndDeletesNothing() throws {
        let context = try makeContext()
        let visit = makeVisit(createdAt: now.addingTimeInterval(-31 * day))
        context.insert(visit)
        let draft = makeDraft(createdAt: now.addingTimeInterval(-31 * day))
        context.insert(draft)
        let packet = try makeVisitOperation(
            entityType: .siteVisit,
            entityId: visitId,
            operationType: "create",
            status: "failed",
            createdAt: now.addingTimeInterval(-31 * day)
        )
        context.insert(packet)
        try context.save()

        let outcome = apply(in: context)

        XCTAssertEqual(outcome.expiredEmptyBundles, 1)
        XCTAssertEqual(outcome.expiredOperations, 0)

        // Declined, never deleted — orphan recovery must not be able to
        // re-derive the send from a missing queue row.
        let operations = try liveOperations(in: context)
            .filter { $0.entityType == SyncEntityType.siteVisit.rawValue }
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.status, "declined")

        // The visit and its identity draft stay exactly where they are.
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisit>()).count, 1)
        XCTAssertNil(try context.fetch(FetchDescriptor<SiteVisit>()).first?.deletedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).count, 1)
    }

    /// Jackson's own line: an empty failed visit doesn't really matter, one
    /// carrying photos is probably pretty critical.
    func test_packetCarryingCapturedWorkIsLeftCompletelyAlone() throws {
        let context = try makeContext()
        let visit = makeVisit(createdAt: now.addingTimeInterval(-31 * day))
        context.insert(visit)
        let draft = makeDraft(createdAt: now.addingTimeInterval(-31 * day))
        context.insert(draft)
        let photo = SiteVisitCaptureArtifact(
            id: "artifact-1",
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: "file:///local/site-visit/1.jpg",
            capturedAt: now.addingTimeInterval(-31 * day),
            createdBy: userId,
            createdAt: now.addingTimeInterval(-31 * day)
        )
        context.insert(photo)
        let packet = try makeVisitOperation(
            entityType: .siteVisit,
            entityId: visitId,
            operationType: "create",
            status: "failed",
            createdAt: now.addingTimeInterval(-31 * day)
        )
        context.insert(packet)
        try context.save()

        let outcome = apply(in: context)

        XCTAssertEqual(outcome, .none)
        let operations = try liveOperations(in: context)
            .filter { $0.entityType == SyncEntityType.siteVisit.rawValue }
        XCTAssertEqual(operations.first?.status, "failed", "a content-bearing packet keeps sending")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).count, 1)
    }

    // MARK: - Lead delivery requests

    func test_stalledLeadRequestLeavesTheQueueAndItsClientStays() throws {
        let context = try makeContext()
        let queue = makeQueue()
        let client = Client(id: "CLIENT-1", name: "Charles", companyId: companyId)
        queue.enqueue(client, companyId: companyId)
        XCTAssertEqual(queue.pendingCount, 1)

        let request = AutocreateSnapshot(
            clientId: "client-1",
            name: "Charles",
            createdAt: now.addingTimeInterval(-31 * day),
            attempts: 8,
            lastAttemptAt: now.addingTimeInterval(-600),
            lastError: "400 source_thread_key",
            isParked: true
        )
        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [request],
            photos: [],
            drafts: [],
            artifacts: [],
            orphans: [],
            now: now
        )

        let outcome = SyncEngine().applyPendingWorkExpiry(
            inventory: inventory,
            now: now,
            in: context,
            queue: queue
        )

        XCTAssertEqual(outcome.expiredLeadRequests, 1)
        XCTAssertEqual(queue.pendingCount, 0, "the durable delivery receipt is gone")
        XCTAssertFalse(queue.contains(clientId: "client-1"))
    }

    // MARK: - Nothing to do

    func test_aQueueOfFreshWorkWritesNothingAtAll() throws {
        let context = try makeContext()
        let fresh = makeOperation(
            entityType: .project,
            entityId: "project-fresh",
            operationType: "update",
            status: "failed",
            createdAt: now.addingTimeInterval(-2 * day)
        )
        context.insert(fresh)
        try context.save()

        XCTAssertEqual(apply(in: context), .none)
        XCTAssertEqual(
            try liveOperations(in: context).filter { $0.entityId == "project-fresh" }.count,
            1
        )
    }

    // MARK: - Harness

    private func apply(in context: ModelContext) -> PendingWorkExpiryOutcome {
        guard let inventory = try? liveInventory(in: context) else {
            XCTFail("could not assemble the live inventory")
            return .none
        }
        return SyncEngine().applyPendingWorkExpiry(
            inventory: inventory,
            now: now,
            in: context,
            queue: makeQueue()
        )
    }

    /// Maps the live store into the pure builder exactly as
    /// `RecoveryInventory.load` does, without reaching for the recovery vault,
    /// the shared autocreate queue, or UserDefaults company scoping.
    private func liveInventory(in context: ModelContext) throws -> RecoveryInventory {
        let operations = try liveOperations(in: context)
            .filter { $0.entityType != "pendingWorkExpiryWarmup" }
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
            now: now
        )
    }

    private func liveOperations(in context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>())
    }

    /// An isolated queue on its own defaults suite — never the shared singleton,
    /// and never an automatic retry timer inside a test process.
    private func makeQueue() -> ClientLeadAutocreateQueue {
        ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: { _ in throw ExpiryTestError.notDelivered }
        )
    }

    private enum ExpiryTestError: Error {
        case notDelivered
    }

    // MARK: - Fixtures

    private func makeOperation(
        entityType: SyncEntityType,
        entityId: String,
        operationType: String,
        status: String,
        createdAt: Date
    ) -> SyncOperation {
        let operation = SyncOperation(
            entityType: entityType.rawValue,
            entityId: entityId,
            operationType: operationType,
            payload: Data("{}".utf8),
            changedFields: []
        )
        operation.status = status
        operation.createdAt = createdAt
        operation.retryCount = 20
        operation.lastAttemptedAt = createdAt
        operation.lastError = "server rejected"
        return operation
    }

    private func makeVisitOperation(
        entityType: SyncEntityType,
        entityId: String,
        operationType: String,
        status: String,
        createdAt: Date
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
            changedFields: [],
            priority: 1
        )
        operation.status = status
        operation.createdAt = createdAt
        operation.retryCount = 20
        operation.lastAttemptedAt = createdAt
        operation.lastError = "server rejected"
        return operation
    }

    private func makeVisit(createdAt: Date) -> SiteVisit {
        SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: createdAt,
            createdBy: userId,
            createdAt: createdAt
        )
    }

    private func makeDraft(createdAt: Date) -> SiteVisitIdentityDraft {
        SiteVisitIdentityDraft(
            siteVisitId: visitId,
            companyId: companyId,
            contactName: "Charles Krusekopf",
            address: "1420 Lyall St",
            createdBy: userId,
            createdAt: createdAt
        )
    }

    // MARK: - Container

    /// Retains the container for the case's lifetime — a `ModelContext` does not
    /// keep its container alive, and `makeContainer().mainContext` in one
    /// expression traps inside SwiftData on the next insert.
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
        retainedContainers.append(container)

        // A #Predicate fetch of SyncOperation TRAPS against a store whose
        // operation table has never held a row — materialize it with an inert
        // row scoped to no real entity.
        let warmup = ModelContext(container)
        warmup.insert(
            SyncOperation(
                entityType: "pendingWorkExpiryWarmup",
                entityId: "pendingWorkExpiryWarmup",
                operationType: "update",
                payload: Data("{}".utf8),
                changedFields: []
            )
        )
        try warmup.save()

        return ModelContext(container)
    }
}
