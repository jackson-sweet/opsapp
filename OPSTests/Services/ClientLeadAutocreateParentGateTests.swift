//
//  ClientLeadAutocreateParentGateTests.swift
//  OPSTests
//
//  The lead-delivery queue's ordering gate (client insert RLS defect,
//  2026-08-19).
//
//  THE BUG. `public.clients`' restrictive SELECT policy `role_scope_read`
//  resolved a row by re-reading `public.clients` by id. PostgREST asks for
//  `INSERT … RETURNING` whenever a client requests a representation, Postgres
//  applies SELECT policies to that RETURNING row as an INSERT check — before the
//  tuple exists — the self-lookup found nothing, and the customer create was
//  rejected 42501. The client's `SyncOperation` parked.
//
//  THE LOOP. `ClientLeadAutocreateQueue.performLiveAttempt` preconditions on
//  `ClientRepository.fetchOne`, which answers PGRST116 for the missing parent.
//  `SyncErrorClassifier` calls PGRST116 transient — correctly, and by design:
//  "no rows" means try again for every read that legitimately retries, and
//  teaching it otherwise re-opens the 2026-07-22 outage class. With no attempt
//  cap, the delivery retried against a customer that was never coming, and the
//  operator watched a raw PostgrestError dump in PENDING WORK.
//
//  THE FIX, and what this file locks: ordering is the QUEUE's job
//  (`SyncCrossEntityDependency`'s doctrine). The queue reads the parent's own
//  create op and decides — held, parked, or clear to send — without the
//  classifier learning anything about PGRST116.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class ClientLeadAutocreateParentGateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    /// Containers outlive the contexts they vend. A `ModelContext` does not keep
    /// its container alive, and inserting into a context whose container was
    /// released traps inside SwiftData (uncatchable EXC_BREAKPOINT) before the
    /// first assertion runs.
    private var retainedContainers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        suiteName = "ClientLeadAutocreateParentGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - A. The pure classifier

    /// Absence is not evidence. Completed ops are swept after 24h and clients
    /// arrive from paths that never record one — holding on "no op" would strand
    /// every such delivery forever with nothing able to release it.
    func testNoCreateOpReadsAsLanded() {
        XCTAssertEqual(
            ClientLeadAutocreateQueue.clientCreateState(forClientId: "client-1", in: []),
            .landed
        )
    }

    func testParkedClientCreateReadsAsRejected() throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", status: "parked", in: context)

        XCTAssertEqual(
            ClientLeadAutocreateQueue.clientCreateState(
                forClientId: "client-1",
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            .rejected
        )
    }

    /// A quarantined create is never sent at all, so it is just as absent from
    /// the server as a parked one.
    func testQuarantinedClientCreateReadsAsRejected() throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", status: "quarantined", in: context)

        XCTAssertEqual(
            ClientLeadAutocreateQueue.clientCreateState(
                forClientId: "client-1",
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            .rejected
        )
    }

    /// `failed` is in-flight, not rejected: the launch / reconnect sweep revives
    /// it. Parking a delivery behind work that is about to run on its own would
    /// make the operator retry something that needed no help.
    func testPendingInProgressAndFailedCreatesReadAsInFlight() throws {
        for status in ["pending", "inProgress", "failed"] {
            let context = try makeContext()
            _ = makeOp(entityId: "client-1", status: status, in: context)

            XCTAssertEqual(
                ClientLeadAutocreateQueue.clientCreateState(
                    forClientId: "client-1",
                    in: try context.fetch(FetchDescriptor<SyncOperation>())
                ),
                .inFlight,
                "a \(status) create is still working"
            )
        }
    }

    func testCompletedClientCreateReadsAsLanded() throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", status: "completed", in: context)

        XCTAssertEqual(
            ClientLeadAutocreateQueue.clientCreateState(
                forClientId: "client-1",
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            .landed
        )
    }

    /// THE TERMINATION GUARD. A create that was refused and later succeeded means
    /// the row IS on the server. If `parked` outranked `completed` here, a
    /// released delivery would be re-parked on the very next pass and the queue
    /// would oscillate forever.
    func testCompletedOutranksParkedForTheSameClient() throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", status: "parked", in: context)
        _ = makeOp(entityId: "client-1", status: "completed", in: context)

        XCTAssertEqual(
            ClientLeadAutocreateQueue.clientCreateState(
                forClientId: "client-1",
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            .landed
        )
    }

    /// `UUID().uuidString` is uppercase; Postgres uuid columns are not. A
    /// case-sensitive match would miss the create and attempt the very delivery
    /// this gate exists to hold.
    func testClientIdsMatchCaseInsensitively() throws {
        let context = try makeContext()
        let upper = "A1B2C3D4-0000-0000-0000-00000000000F"
        _ = makeOp(entityId: upper.lowercased(), status: "parked", in: context)

        XCTAssertEqual(
            ClientLeadAutocreateQueue.clientCreateState(
                forClientId: upper,
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            .rejected
        )
    }

    /// Ids are unique per table, not globally, and only a `create` says anything
    /// about whether the row exists.
    func testOtherEntitiesClientsAndOperationTypesAreIgnored() throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", operationType: "update", status: "parked", in: context)
        _ = makeOp(entityId: "client-2", status: "parked", in: context)
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: "client-1",
            status: "parked",
            in: context
        )

        XCTAssertEqual(
            ClientLeadAutocreateQueue.clientCreateState(
                forClientId: "client-1",
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            .landed
        )
    }

    // MARK: - B. The drain

    /// The founder's exact state: the customer create parked with the RLS
    /// rejection, and the lead delivery behind it. It must park WITHOUT ever
    /// reaching the network — attempting would only spend a round trip to be told
    /// what the queue already knows.
    func testRejectedClientCreateParksTheDeliveryWithoutAttemptingIt() async throws {
        let context = try makeContext()
        _ = makeOp(
            entityId: "client-1",
            status: "parked",
            lastError: #"new row violates row-level security policy "role_scope_read" for table "clients""#,
            in: context
        )

        var attemptCount = 0
        let queue = makeQueue { _ in
            attemptCount += 1
            throw TestError.transient
        }
        queue.configure(modelContext: context, activeCompanyId: { "company-1" })
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()

        XCTAssertEqual(attemptCount, 0, "the delivery must never be attempted")
        XCTAssertEqual(queue.parkedRequests.count, 1)
        XCTAssertEqual(
            queue.parkedRequests.first?.lastError,
            ClientLeadAutocreateError.clientCreateRejectedDetail
        )
        XCTAssertTrue(
            SyncStatusCopy.PendingWork.isClientRejected(queue.parkedRequests.first?.lastError),
            "the stamp must be the marker the copy layer and the release rule match on"
        )
    }

    /// Held means held. A create still working is not a rejection: the delivery
    /// waits, and the wait costs it nothing — no attempt, no park, no budget.
    func testInFlightClientCreateHoldsTheDeliveryWithoutBurningBudget() async throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", status: "pending", in: context)

        var attemptCount = 0
        let queue = makeQueue { _ in
            attemptCount += 1
            throw TestError.transient
        }
        queue.configure(modelContext: context, activeCompanyId: { "company-1" })
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()

        XCTAssertEqual(attemptCount, 0)
        XCTAssertEqual(queue.parkedRequests.count, 0)
        XCTAssertEqual(queue.activeRequests.count, 1)
        XCTAssertEqual(queue.activeRequests.first?.effectiveAttempts, 0)
        XCTAssertNil(queue.activeRequests.first?.lastAttemptAt)
        XCTAssertNil(queue.activeRequests.first?.lastError)
    }

    /// Once the customer reaches OPS the lead must follow on its own. Making the
    /// operator retry the same work twice — once for the customer, once for the
    /// lead they never asked for — is the failure this closes.
    func testParkedDeliveryIsReleasedOnceTheClientCreateCompletes() async throws {
        let context = try makeContext()
        let createOp = makeOp(entityId: "client-1", status: "parked", in: context)

        var attemptCount = 0
        let queue = makeQueue { _ in
            attemptCount += 1
            return ClientLeadAutocreateDelivery(
                opportunityId: "opp-1",
                opportunityDTO: nil,
                createdNow: true
            )
        }
        queue.configure(modelContext: context, activeCompanyId: { "company-1" })
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()
        XCTAssertEqual(queue.parkedRequests.count, 1)
        XCTAssertEqual(attemptCount, 0)

        // The operator retries the customer in PENDING WORK; it lands.
        createOp.status = "completed"
        createOp.completedAt = Date()

        await queue.drain()

        XCTAssertEqual(attemptCount, 1, "the released delivery is attempted exactly once")
        XCTAssertEqual(queue.pendingCount, 0, "and it delivers")
    }

    /// THE LOOP GUARD. The release is gated on the marker this queue writes. A
    /// delivery that parks for its own reason carries a different `lastError` and
    /// must never be handed back by the parent rule — otherwise a genuinely
    /// hopeless request would be retried forever the moment its client landed.
    func testAParkWithAnyOtherCauseIsNeverAutoReleased() async throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", status: "completed", completedAt: Date(), in: context)

        var attemptCount = 0
        let queue = makeQueue { _ in
            attemptCount += 1
            throw TestError.permanent
        }
        queue.configure(modelContext: context, activeCompanyId: { "company-1" })
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(queue.parkedRequests.count, 1)
        XCTAssertFalse(
            SyncStatusCopy.PendingWork.isClientRejected(queue.parkedRequests.first?.lastError)
        )

        await queue.drain()
        await queue.drain()

        XCTAssertEqual(attemptCount, 1, "a real park stays parked")
        XCTAssertEqual(queue.parkedRequests.count, 1)
    }

    /// The drain runs every 60s. Re-parking each pass would restamp the clock and
    /// fire an analytics event for a request already sitting in NEEDS ATTENTION.
    func testRepeatedDrainsDoNotRestampAnExistingPark() async throws {
        let context = try makeContext()
        _ = makeOp(entityId: "client-1", status: "parked", in: context)

        let queue = makeQueue { _ in throw TestError.transient }
        queue.configure(modelContext: context, activeCompanyId: { "company-1" })
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()
        let firstStamp = queue.parkedRequests.first?.parkedAt
        XCTAssertNotNil(firstStamp)

        await queue.drain()
        await queue.drain()

        XCTAssertEqual(queue.parkedRequests.count, 1)
        XCTAssertEqual(queue.parkedRequests.first?.parkedAt, firstStamp)
    }

    /// A queue with no model context (the pure state-machine harness the shipped
    /// policy tests use) must behave exactly as before — the gate can only hold
    /// work it has evidence about.
    func testQueueWithoutAModelContextIsUnaffected() async throws {
        var attemptCount = 0
        let queue = makeQueue { _ in
            attemptCount += 1
            return ClientLeadAutocreateDelivery(
                opportunityId: "opp-1",
                opportunityDTO: nil,
                createdNow: true
            )
        }
        queue.enqueue(makeClient(id: "client-1"), companyId: "company-1")

        await queue.drain()

        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    // MARK: - Fixtures

    private enum TestError: LocalizedError {
        case transient
        case permanent

        var errorDescription: String? {
            switch self {
            case .transient:
                return "The Internet connection appears to be offline."
            case .permanent:
                return "new row for relation \"opportunities\" violates check constraint \"opportunities_source_check\""
            }
        }
    }

    private func makeQueue(
        attempt: @escaping ClientLeadAutocreateQueue.Attempt
    ) -> ClientLeadAutocreateQueue {
        ClientLeadAutocreateQueue(
            defaults: defaults,
            defaultsKey: "pending",
            automaticRetry: false,
            attempt: attempt
        )
    }

    private func makeClient(id: String) -> Client {
        Client(
            id: id,
            name: "West Shore Decks",
            email: "office@example.com",
            phoneNumber: "250-555-0199",
            address: "12 Bay St",
            companyId: "company-1",
            notes: "Contact import"
        )
    }

    @discardableResult
    private func makeOp(
        entityType: String = SyncEntityType.client.rawValue,
        entityId: String,
        operationType: String = "create",
        status: String,
        lastError: String? = nil,
        completedAt: Date? = nil,
        in context: ModelContext
    ) -> SyncOperation {
        let op = SyncOperation(
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: Data("{}".utf8),
            changedFields: ["id"]
        )
        op.status = status
        op.lastError = lastError
        op.completedAt = completedAt
        context.insert(op)
        return op
    }

    private func makeContext() throws -> ModelContext {
        // A successful delivery runs `applyLocalDelivery` (Opportunity) and
        // `bindSiteVisitDrafts` (SiteVisitIdentityDraft, SiteVisit). Every model
        // those paths fetch must be in the schema — fetching an entity the
        // container does not know is not a caught error.
        let schema = Schema([
            SyncOperation.self,
            Opportunity.self,
            SiteVisit.self,
            SiteVisitIdentityDraft.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return container.mainContext
    }
}
