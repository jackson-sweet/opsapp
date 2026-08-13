//
//  SyncCrossEntityDependencyTests.swift
//  OPSTests
//
//  SYNC RECOVERY · cross-entity create barrier (bug 06f68200).
//
//  An outbound op can reference an entity whose OWN create has not reached the
//  server yet — the canonical repro: a deckDesign `update` carrying
//  {updated_at, project_id} while that project's create op is still queued. The
//  server evaluates RLS against a project it cannot see, returns 42501, and
//  `SyncErrorClassifier` (correctly, context-free) calls that permanent — so the
//  edit parks forever even though the create lands seconds later.
//
//  The fix is a barrier, not a reclassification: hold any op whose payload
//  carries a foreign key to an entity with a non-completed local `create`, and
//  self-heal ops already mis-parked by the race once that create completes.
//
//  Two groups here:
//    A — the pure module `SyncCrossEntityDependency` (blocking rule, ready sets,
//        drain continuation, releasable-parked detection). No fetches, no I/O:
//        every function takes a plain `[SyncOperation]`, because a #Predicate
//        fetch of SyncOperation traps against a never-populated table.
//    B — the wiring, driven through the REAL `OutboundProcessor`: a held op is
//        never attempted and never mutated; a mis-parked op is released to
//        pending at pass start. DataActor mirrors the same wiring (its copies are
//        private and unreachable from tests); the shared logic is proven here and
//        enforced identical by review — the established precedent from
//        DeckDesignLinkSyncTests.
//
//  Note on group B and connectivity: `processPendingOperations` short-circuits
//  when the host reports no usable network, and a freshly built
//  `ConnectivityManager` reports exactly that — its state starts `.offline` and
//  the first NWPathMonitor update only lands on a later MainActor hop. Passing a
//  real one would invert both tests: the hold would pass vacuously (the pass
//  never ran) and the release would fail forever (the release step lives inside
//  the pass). Both tests therefore drive the pass through
//  `AlwaysSyncableConnectivity`, which forces the guard open on any host,
//  offline included. That is environment control only — no barrier logic is
//  stubbed, and once the barrier exists neither test reaches the network: the
//  held op is filtered out, and the released op is skipped by its unmet
//  dependsOnId. Their assertions read the claim gate, which stamps
//  status/lastAttemptedAt BEFORE any network call, so a regression fails them
//  the moment an op is claimed.
//

import SwiftData
import XCTest
@testable import OPS

/// Environment control only — forces `processPendingOperations` past its
/// connectivity guard so the barrier is exercised deterministically on any host,
/// offline included. The real manager's state is NWPathMonitor-driven and
/// `private(set)`, so overriding the decision helper is the only way in. Nothing
/// network-touching runs in either group-B test once the barrier exists: the
/// held op is filtered out, the released op is skipped by its unmet dependsOnId.
@MainActor
private final class AlwaysSyncableConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { true }
}

@MainActor
final class SyncCrossEntityDependencyTests: XCTestCase {

    // Lowercase throughout — Postgres uuid columns are lowercase, and
    // `UUID().uuidString` is uppercase. Only the case-insensitivity test
    // deliberately mixes case.
    private let projectId = "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1"
    private let deckId = "bff17fb7-af08-457b-9062-822d25270e9a"
    private let clientId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"

    private let rlsError = "new row violates row-level security policy "
        + "\"assigned_lead_scope_update\" for table \"deck_designs\""
    private let foreignKeyError = "insert or update on table \"deck_designs\" "
        + "violates foreign key constraint \"deck_designs_project_id_fkey\""

    // MARK: - A. Pure module — blocking rule

    /// The canonical repro: an edit that references a project whose create is
    /// still queued must be held, not sent.
    func test_isBlockedByUnresolvedCreate_holdsUpdateWhileProjectCreateIsPending() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["updated_at": "2026-08-12T00:00:00Z", "project_id": projectId],
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId, "name": "Barrier project"],
            status: "pending",
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(update, in: [update, create]),
            "an edit referencing a project whose create has not synced must be held"
        )
    }

    /// Every non-completed status of the blocking create holds the dependent op —
    /// a create that is mid-flight, out of retries, or parked is just as absent
    /// from the server as one that is merely queued.
    func test_isBlockedByUnresolvedCreate_holdsForInProgressFailedAndParkedCreates() throws {
        for status in ["inProgress", "failed", "parked"] {
            let context = try makeContext()
            let update = makeOp(
                entityType: SyncEntityType.deckDesign.rawValue,
                entityId: deckId,
                operationType: "update",
                payload: ["project_id": projectId],
                in: context
            )
            let create = makeOp(
                entityType: SyncEntityType.project.rawValue,
                entityId: projectId,
                operationType: "create",
                payload: ["id": projectId],
                status: status,
                in: context
            )

            XCTAssertTrue(
                SyncCrossEntityDependency.isBlockedByUnresolvedCreate(update, in: [update, create]),
                "a \(status) create is still unresolved server-side — the dependent op stays held"
            )
        }
    }

    /// Once the create is confirmed the barrier lifts — the referenced row exists
    /// server-side, so the edit is safe to send.
    func test_isBlockedByUnresolvedCreate_liftsOnceCreateCompleted() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "completed",
            completedAt: Date(),
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(update, in: [update, create]),
            "a completed create means the referenced row exists — nothing to wait for"
        )
    }

    /// No local create at all means the project was never created on this device
    /// (it came down from the server) — the barrier must never invent a wait.
    func test_isBlockedByUnresolvedCreate_neverBlocksWhenNoLocalCreateExists() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(update, in: [update]),
            "with no local create for the referenced project there is nothing to hold behind"
        )
    }

    /// `UUID().uuidString` is uppercase while Postgres ids are lowercase — a
    /// case-sensitive comparison would silently miss the blocking create and ship
    /// the edit straight into the 42501.
    func test_isBlockedByUnresolvedCreate_matchesIdsCaseInsensitively() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId.uppercased()],
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(update, in: [update, create]),
            "id comparison is case-insensitive — an uppercase payload id still matches a lowercase create"
        )
    }

    /// Only the mapped foreign keys arm the barrier. `opportunity_id` is not one
    /// of them (leads are network-only and never carry a local create op), so it
    /// must never hold work.
    func test_isBlockedByUnresolvedCreate_ignoresUnmappedPayloadKeys() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["opportunity_id": projectId, "some_other_id": projectId],
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(update, in: [update, create]),
            "unmapped payload keys never arm the barrier, whatever value they carry"
        )
    }

    /// A JSON null or a number in an FK slot is not an id — decoding it as one
    /// would be a guess, and guessing here means holding work forever.
    func test_isBlockedByUnresolvedCreate_ignoresNonStringForeignKeyValues() throws {
        let context = try makeContext()
        let nullValued = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": NSNull()],
            in: context
        )
        let numberValued = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: "6cf2a6d1-1d8e-4a1e-9b8e-6f2d4a5c1e77",
            operationType: "update",
            payload: ["project_id": 42],
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            in: context
        )
        let all = [nullValued, numberValued, create]

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(nullValued, in: all),
            "a null foreign key references nothing — never blocks"
        )
        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(numberValued, in: all),
            "a non-string foreign key value is not an id — never blocks"
        )
    }

    /// Ids are unique per table, not globally — a create of a DIFFERENT entity
    /// type that happens to share the id must not hold the op.
    func test_isBlockedByUnresolvedCreate_ignoresCreateOfDifferentEntityType() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            in: context
        )
        let clientCreate = makeOp(
            entityType: SyncEntityType.client.rawValue,
            entityId: projectId,           // same id, wrong table
            operationType: "create",
            payload: ["id": projectId],
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(update, in: [update, clientCreate]),
            "only a create of the MAPPED entity type blocks — ids are unique per table, not globally"
        )
    }

    /// A create whose own payload echoes its id must not hold itself — that would
    /// deadlock the very op that resolves the dependency.
    func test_isBlockedByUnresolvedCreate_neverBlocksAnOperationOnItself() throws {
        let context = try makeContext()
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId, "project_id": projectId],
            in: context
        )

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedCreate(create, in: [create]),
            "an op never blocks on itself — that would deadlock the create that resolves the dependency"
        )
    }

    /// The mapped set is the contract between payload writers and the barrier.
    func test_payloadReferenceKeys_mapTheCrossEntityForeignKeys() {
        XCTAssertEqual(
            SyncCrossEntityDependency.payloadReferenceKeys,
            [
                "project_id": SyncEntityType.project.rawValue,
                "client_id": SyncEntityType.client.rawValue,
                "company_id": SyncEntityType.company.rawValue,
                "task_type_id": SyncEntityType.taskType.rawValue
            ],
            "the barrier arms on exactly these four foreign keys"
        )
    }

    // MARK: - A. Pure module — ready sets & drain continuation

    /// A held op is not ready work: counting it would spin the drain loop.
    func test_readyOperationIds_excludesPendingOperationHeldByTheBarrier() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            in: context
        )

        let ready = SyncCrossEntityDependency.readyOperationIds(in: [update, create])

        XCTAssertFalse(ready.contains(update.id), "a held op is not ready work")
        XCTAssertTrue(ready.contains(create.id), "the unblocked create is ready work")
    }

    /// A create completing mid-drain grows the ready set — that growth is the
    /// signal that another pass has real work to do.
    func test_readyOperationIds_includesHeldOperationOnceBlockingCreateCompletes() throws {
        let context = try makeContext()
        let update = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            in: context
        )

        let before = SyncCrossEntityDependency.readyOperationIds(in: [update, create])

        create.status = "completed"
        create.completedAt = Date()

        let after = SyncCrossEntityDependency.readyOperationIds(in: [update, create])

        XCTAssertFalse(before.contains(update.id))
        XCTAssertTrue(after.contains(update.id), "the create landing releases the held edit into the ready set")
        XCTAssertTrue(
            SyncCrossEntityDependency.shouldContinueDrain(readyBeforePass: before, readyAfterPass: after),
            "a grown, non-empty ready set means the drain continues in the same cycle"
        )
    }

    /// Releasable parked ops count as ready work — they rejoin the pass the
    /// release step puts them in.
    func test_readyOperationIds_includesReleasableParkedOperation() throws {
        let context = try makeContext()
        let t0 = Date(timeIntervalSince1970: 1_770_000_000)
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: t0,
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "completed",
            completedAt: t0.addingTimeInterval(120),
            in: context
        )

        let ready = SyncCrossEntityDependency.readyOperationIds(in: [parked, create])

        XCTAssertTrue(
            ready.contains(parked.id),
            "a provably mis-parked op is ready work — the release step will hand it to this pass"
        )
    }

    /// The drain continues only when the ready set is non-empty AND changed —
    /// an unchanged set means the pass made no progress and would loop forever.
    func test_shouldContinueDrain_onlyWhenReadySetIsNonEmptyAndChanged() {
        let a = UUID()
        let b = UUID()

        XCTAssertTrue(
            SyncCrossEntityDependency.shouldContinueDrain(readyBeforePass: [], readyAfterPass: [a]),
            "work appeared where there was none — continue"
        )
        XCTAssertTrue(
            SyncCrossEntityDependency.shouldContinueDrain(readyBeforePass: [a], readyAfterPass: [a, b]),
            "the ready set grew — continue"
        )
        XCTAssertFalse(
            SyncCrossEntityDependency.shouldContinueDrain(readyBeforePass: [a], readyAfterPass: [a]),
            "an unchanged ready set means the pass made no progress — stop, do not spin"
        )
        XCTAssertFalse(
            SyncCrossEntityDependency.shouldContinueDrain(readyBeforePass: [a], readyAfterPass: []),
            "no ready work left — stop"
        )
    }

    // MARK: - A. Pure module — releasing mis-parked operations

    /// The self-heal case: an RLS rejection stamped BEFORE the blocking create
    /// landed is provably a victim of the race, not a real permission failure.
    func test_parkedRelease_returnsRlsParkedOpWhoseBlockingCreateCompletedAfterTheAttempt() throws {
        let context = try makeContext()
        let t0 = Date(timeIntervalSince1970: 1_770_000_000)
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["updated_at": "2026-08-12T00:00:00Z", "project_id": projectId],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: t0,
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "completed",
            completedAt: t0.addingTimeInterval(120),
            in: context
        )

        let releasable = SyncCrossEntityDependency
            .parkedOperationsReleasableByCompletedCreates(in: [parked, create])

        XCTAssertEqual(releasable.map(\.id), [parked.id],
                       "an RLS park stamped before its blocking create landed is a mis-park — release it")
    }

    /// The same race also surfaces as a foreign-key violation when the referenced
    /// row is simply absent.
    func test_parkedRelease_returnsForeignKeyParkedOpWhoseBlockingCreateCompletedAfterTheAttempt() throws {
        let context = try makeContext()
        let t0 = Date(timeIntervalSince1970: 1_770_000_000)
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            status: "parked",
            lastError: foreignKeyError,
            lastAttemptedAt: t0,
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "completed",
            completedAt: t0.addingTimeInterval(120),
            in: context
        )

        let releasable = SyncCrossEntityDependency
            .parkedOperationsReleasableByCompletedCreates(in: [parked, create])

        XCTAssertEqual(releasable.map(\.id), [parked.id],
                       "a foreign-key park stamped before its blocking create landed is the same mis-park")
    }

    /// Parks for reasons the barrier cannot explain stay parked — releasing them
    /// would re-open the retry storm the parking discipline exists to prevent.
    func test_parkedRelease_leavesParksWithAnUnrelatedErrorAlone() throws {
        let context = try makeContext()
        let t0 = Date(timeIntervalSince1970: 1_770_000_000)
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            status: "parked",
            lastError: "new row for relation \"deck_designs\" violates check constraint \"deck_designs_title_check\"",
            lastAttemptedAt: t0,
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "completed",
            completedAt: t0.addingTimeInterval(120),
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create]).isEmpty,
            "only RLS/FK rejections are explainable by the missing create — everything else stays parked"
        )
    }

    /// The loop guard: an op attempted AFTER the create landed already had its
    /// chance, so its park is real. Without this, every re-park would re-release.
    func test_parkedRelease_leavesParksAttemptedAfterTheCreateCompleted() throws {
        let context = try makeContext()
        let completedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: completedAt,          // == completedAt: not strictly before
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "completed",
            completedAt: completedAt,
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create]).isEmpty,
            "an attempt at or after the create's completion is not explained by the race — release once, never in a loop"
        )

        parked.lastAttemptedAt = completedAt.addingTimeInterval(60)
        XCTAssertTrue(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create]).isEmpty,
            "a re-park stamped after the create landed must never be released again"
        )
    }

    /// A park with no attempt stamp cannot be proven to predate the create.
    func test_parkedRelease_leavesParksWithNoAttemptTimestamp() throws {
        let context = try makeContext()
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: nil,
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "completed",
            completedAt: Date(timeIntervalSince1970: 1_770_000_000),
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create]).isEmpty,
            "with no attempt stamp the race cannot be proven — leave the park alone"
        )
    }

    /// Nothing has changed until the create actually lands.
    func test_parkedRelease_leavesParksWhoseBlockingCreateIsStillUnresolved() throws {
        let context = try makeContext()
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: Date(timeIntervalSince1970: 1_770_000_000),
            in: context
        )
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId],
            status: "pending",
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create]).isEmpty,
            "the create has not landed — releasing now would just re-park the op"
        )
    }

    /// No local create means the park was never caused by this race.
    func test_parkedRelease_leavesParksWithNoBlockingCreateAtAll() throws {
        let context = try makeContext()
        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["project_id": projectId],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: Date(timeIntervalSince1970: 1_770_000_000),
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked]).isEmpty,
            "no local create for the referenced project — the park has some other cause"
        )
    }

    // MARK: - B. Wiring — the REAL OutboundProcessor

    /// HOLD. The blocking project create sits in backoff (so the pass never
    /// touches it, and no network is involved), while a deckDesign edit
    /// referencing that project is pending. The edit must come out of the pass
    /// bit-identical: still pending, never claimed, retry budget untouched.
    func test_processPendingOperations_holdsEditWhoseReferencedProjectCreateHasNotSynced() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId, "name": "Barrier project"],
            status: "pending",
            lastAttemptedAt: Date(),
            retryCount: 3,                     // → in backoff, the pass skips it
            in: context
        )
        let edit = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["updated_at": "2026-08-12T00:00:00Z", "project_id": projectId],
            in: context
        )
        try context.save()

        await OutboundProcessor().processPendingOperations(
            context: context,
            connectivity: AlwaysSyncableConnectivity()
        )

        XCTAssertEqual(
            edit.status, "pending",
            "an edit referencing an unsynced project must be held — never claimed, never sent"
        )
        XCTAssertNil(
            edit.lastAttemptedAt,
            "a held op is not an attempt: the claim gate must never stamp it"
        )
        XCTAssertEqual(
            edit.retryCount, 0,
            "holding must not burn the retry budget against a dependency of arbitrary latency"
        )
        XCTAssertEqual(
            create.status, "pending",
            "the blocking create stays queued — it is in backoff, not attempted"
        )
    }

    /// RELEASE. An edit already mis-parked by the race, whose blocking project
    /// create has since completed, is returned to `pending` at pass start with a
    /// fresh retry budget. Its `dependsOnId` points at an op that does not exist,
    /// so the eligibility filter skips it after release — the release is proven
    /// without any network attempt.
    func test_processPendingOperations_releasesMisparkedEditOnceBlockingCreateCompleted() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let attemptedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let completedAt = attemptedAt.addingTimeInterval(120)

        let parked = makeOp(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: deckId,
            operationType: "update",
            payload: ["updated_at": "2026-08-12T00:00:00Z", "project_id": projectId],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: attemptedAt,
            retryCount: 2,
            dependsOnId: "5e1c9f0a-8f4b-4a2c-9a3d-1b7e6c0d2f84",   // no such op
            in: context
        )
        _ = makeOp(
            entityType: SyncEntityType.project.rawValue,
            entityId: projectId,
            operationType: "create",
            payload: ["id": projectId, "name": "Barrier project"],
            status: "completed",
            completedAt: completedAt,
            in: context
        )
        try context.save()

        await OutboundProcessor().processPendingOperations(
            context: context,
            connectivity: AlwaysSyncableConnectivity()
        )

        XCTAssertEqual(
            parked.status, "pending",
            "the create landed after the park — the mis-parked edit self-heals back into the queue"
        )
        XCTAssertEqual(
            parked.retryCount, 0,
            "release matches user-Retry semantics: a clean retry budget"
        )
        XCTAssertEqual(
            parked.lastAttemptedAt, attemptedAt,
            "release is not an attempt — the unmet dependency filter still skips the op this pass"
        )
    }

    // MARK: - Helpers

    @discardableResult
    private func makeOp(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any],
        status: String = "pending",
        lastError: String? = nil,
        lastAttemptedAt: Date? = nil,
        completedAt: Date? = nil,
        retryCount: Int = 0,
        dependsOnId: String? = nil,
        in context: ModelContext
    ) -> SyncOperation {
        let op = SyncOperation(
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8),
            changedFields: Array(payload.keys),
            dependsOnId: dependsOnId
        )
        op.status = status
        op.lastError = lastError
        op.lastAttemptedAt = lastAttemptedAt
        op.completedAt = completedAt
        op.retryCount = retryCount
        context.insert(op)
        return op
    }

    private func makeContainer() throws -> ModelContainer {
        // PhotoAnnotation rides along because sync bookkeeping counts pending
        // dimensioned annotations alongside SyncOperation rows.
        let schema = Schema([DeckDesign.self, SyncOperation.self, PhotoAnnotation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        retainedContainers.append(container)
        return container.mainContext
    }
}
