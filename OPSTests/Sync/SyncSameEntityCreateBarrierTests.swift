//
//  SyncSameEntityCreateBarrierTests.swift
//  OPSTests
//
//  Same-entity create ordering (bug 2e58c85b) — the silent-loss half of the
//  create barrier.
//
//  Coalescing merges a create with its later updates only when both land in the
//  SAME eligible batch. A create that is ineligible — in retry backoff, out of
//  budget, parked, quarantined — leaves its updates behind as an "all updates"
//  group that ships alone against a row the server has never seen. PostgREST
//  answers that PATCH with 200 and an empty body, the queue retires the op as
//  delivered, and the operator's edit is gone with no trace anywhere.
//
//  The fix is the same shape as the cross-entity barrier it extends: HOLD the
//  later write until the create it belongs to is confirmed. Held is not failed —
//  never attempted, never parked, no retry budget consumed.
//
//  Two groups, mirroring SyncCrossEntityDependencyTests:
//    A — the pure module (blocking rule, subsystem exemptions, ready sets,
//        releasable-parked detection). No fetches: a #Predicate fetch of
//        SyncOperation traps against a never-populated table.
//    B — the wiring, driven through the REAL OutboundProcessor. DataActor
//        mirrors the same wiring (its copy is private and unreachable from
//        tests); the shared logic is proven here and enforced identical by
//        review — the established precedent from DeckDesignLinkSyncTests.
//

import SwiftData
import XCTest
@testable import OPS

/// Environment control only — forces `processPendingOperations` past its
/// connectivity guard so the barrier is exercised deterministically on any host,
/// offline included. A freshly built ConnectivityManager reports `.offline`
/// until an NWPathMonitor update lands on a later MainActor hop, which would
/// make the group-B test pass vacuously.
@MainActor
private final class AlwaysSyncableConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { true }
}

@MainActor
final class SyncSameEntityCreateBarrierTests: XCTestCase {

    // Lowercase throughout — Postgres uuid columns are lowercase and
    // `UUID().uuidString` is uppercase. Only the casing test mixes them.
    private let deckId = "bff17fb7-af08-457b-9062-822d25270e9a"
    private let otherId = "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"

    private let rlsError = "new row violates row-level security policy "
        + "\"assigned_lead_scope_update\" for table \"deck_designs\""

    // MARK: - A. Pure module — the blocking rule

    /// The canonical repro: the create is stuck, the edit would ship alone into
    /// a zero-row PATCH. Hold it.
    func test_sameEntityBarrier_holdsUpdateWhileItsOwnCreateIsPending() throws {
        let context = try makeContext()
        let create = makeOp(operationType: "create", payload: ["id": deckId], in: context)
        let update = makeOp(
            operationType: "update",
            payload: ["title": "Renamed by the operator"],
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                update, in: [create, update]
            ),
            "an edit whose own create has not synced must be held, not shipped into a zero-row PATCH"
        )
    }

    /// Every non-completed status of the create means the same thing to the
    /// server: the row is not there.
    func test_sameEntityBarrier_holdsForEveryUnresolvedCreateStatus() throws {
        for status in ["pending", "inProgress", "failed", "parked", "quarantined"] {
            let context = try makeContext()
            let create = makeOp(
                operationType: "create",
                payload: ["id": deckId],
                status: status,
                in: context
            )
            let update = makeOp(
                operationType: "update",
                payload: ["title": "Renamed"],
                in: context
            )

            XCTAssertTrue(
                SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                    update, in: [create, update]
                ),
                "a create in status \(status) is absent from the server — hold the edit"
            )
        }
    }

    /// A delete is held for the same reason and one more: pushing it against a
    /// row that does not exist "succeeds" against nothing, and the day the
    /// parked create is retried the row appears with no delete left to remove
    /// it — a resurrection the operator can neither see nor undo.
    func test_sameEntityBarrier_holdsDeleteWhileItsOwnCreateIsUnresolved() throws {
        let context = try makeContext()
        let create = makeOp(
            operationType: "create",
            payload: ["id": deckId],
            status: "parked",
            in: context
        )
        let delete = makeOp(operationType: "delete", payload: [:], in: context)

        XCTAssertTrue(
            SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                delete, in: [create, delete]
            ),
            "a delete ahead of its create would leave the row resurrectable — hold it"
        )
    }

    /// The gate lifts the moment the row exists server-side.
    func test_sameEntityBarrier_liftsOnceTheCreateCompletes() throws {
        let context = try makeContext()
        let create = makeOp(
            operationType: "create",
            payload: ["id": deckId],
            status: "completed",
            completedAt: Date(),
            in: context
        )
        let update = makeOp(operationType: "update", payload: ["title": "Renamed"], in: context)

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                update, in: [create, update]
            ),
            "the row is on the server — the edit is free to go"
        )
    }

    /// A create is never held: it is the thing everything else waits for.
    func test_sameEntityBarrier_neverHoldsACreate() throws {
        let context = try makeContext()
        let first = makeOp(operationType: "create", payload: ["id": deckId], in: context)
        let second = makeOp(operationType: "create", payload: ["id": deckId], in: context)

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                second, in: [first, second]
            ),
            "holding a create behind another create for the same row would deadlock the row forever"
        )
    }

    /// Ids compare lowercased. `UUID().uuidString` is uppercase while Postgres
    /// uuid columns are not, so a case-sensitive match would miss the create and
    /// ship the edit into the void.
    func test_sameEntityBarrier_matchesIdsCaseInsensitively() throws {
        let context = try makeContext()
        let create = makeOp(
            entityId: deckId.uppercased(),
            operationType: "create",
            payload: ["id": deckId],
            in: context
        )
        let update = makeOp(
            entityId: deckId,
            operationType: "update",
            payload: ["title": "Renamed"],
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                update, in: [create, update]
            ),
            "casing is a storage detail — the uppercase create is the same row"
        )
    }

    /// Ids are unique per table, not globally. A create for a different row must
    /// not hold this one.
    func test_sameEntityBarrier_ignoresCreateOfADifferentRow() throws {
        let context = try makeContext()
        let create = makeOp(
            entityId: otherId,
            operationType: "create",
            payload: ["id": otherId],
            in: context
        )
        let update = makeOp(operationType: "update", payload: ["title": "Renamed"], in: context)

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                update, in: [create, update]
            ),
            "a different row's create says nothing about this one"
        )
    }

    /// Same id, different table — ids collide across tables and must not gate
    /// each other.
    func test_sameEntityBarrier_ignoresCreateOfADifferentEntityType() throws {
        let context = try makeContext()
        let create = makeOp(
            entityType: SyncEntityType.project.rawValue,
            operationType: "create",
            payload: ["id": deckId],
            in: context
        )
        let update = makeOp(operationType: "update", payload: ["title": "Renamed"], in: context)

        XCTAssertFalse(
            SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                update, in: [create, update]
            ),
            "ids are unique per table — a project create must not gate a deck edit"
        )
    }

    /// Subsystems with their own ordering graph are exempt. Double-gating them
    /// can only deadlock work their own barrier is holding for another reason.
    func test_sameEntityBarrier_exemptsSubsystemsThatOrderTheirOwnWrites() throws {
        let exemptCases: [(entityType: String, operationType: String, label: String)] = [
            (SyncEntityType.siteVisit.rawValue, "update", "site visit"),
            (SyncEntityType.siteVisitArtifact.rawValue, "update", "site-visit capture"),
            (SyncEntityType.siteVisitIdentityDraft.rawValue, "update", "site-visit identity"),
            (SyncEntityType.taskType.rawValue, "update", "task type"),
            (SyncEntityType.projectNote.rawValue,
             ProjectNoteMentionEditSync.updateOperationType,
             "mention edit")
        ]

        for exempt in exemptCases {
            let context = try makeContext()
            let create = makeOp(
                entityType: exempt.entityType,
                operationType: "create",
                payload: ["id": deckId],
                in: context
            )
            let later = makeOp(
                entityType: exempt.entityType,
                operationType: exempt.operationType,
                payload: ["title": "Renamed"],
                in: context
            )

            XCTAssertFalse(
                SyncCrossEntityDependency.isBlockedByUnresolvedSameEntityCreate(
                    later, in: [create, later]
                ),
                "\(exempt.label) work is ordered by its own graph — this barrier must not touch it"
            )
        }
    }

    // MARK: - A. Pure module — ready sets

    /// A held op is not ready work: counting it would spin the drain loop.
    func test_readyOperationIds_excludesOperationHeldByItsOwnCreate() throws {
        let context = try makeContext()
        let create = makeOp(
            operationType: "create",
            payload: ["id": deckId],
            status: "pending",
            in: context
        )
        let update = makeOp(operationType: "update", payload: ["title": "Renamed"], in: context)

        let ready = SyncCrossEntityDependency.readyOperationIds(in: [create, update])

        XCTAssertFalse(ready.contains(update.id), "a held edit is not ready work")
        XCTAssertTrue(ready.contains(create.id), "the create it waits on is")
    }

    /// The create landing grows the ready set — that growth is the signal the
    /// drain has real work left in this same cycle.
    func test_readyOperationIds_releasesTheHeldEditOnceTheCreateCompletes() throws {
        let context = try makeContext()
        let create = makeOp(operationType: "create", payload: ["id": deckId], in: context)
        let update = makeOp(operationType: "update", payload: ["title": "Renamed"], in: context)

        let before = SyncCrossEntityDependency.readyOperationIds(in: [create, update])
        create.status = "completed"
        create.completedAt = Date()
        let after = SyncCrossEntityDependency.readyOperationIds(in: [create, update])

        XCTAssertFalse(before.contains(update.id))
        XCTAssertTrue(after.contains(update.id))
        XCTAssertTrue(
            SyncCrossEntityDependency.shouldContinueDrain(
                readyBeforePass: before, readyAfterPass: after
            ),
            "a grown, non-empty ready set continues the drain in the same cycle"
        )
    }

    // MARK: - A. Pure module — releasing mis-parked work

    /// Self-heal: an edit parked for a reason the missing row explains, stamped
    /// BEFORE its own create landed, was a victim of the ordering gap — hand it
    /// back to the queue.
    func test_parkedRelease_returnsEditParkedBeforeItsOwnCreateCompleted() throws {
        let context = try makeContext()
        let attemptedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let parked = makeOp(
            operationType: "update",
            payload: ["title": "Renamed"],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: attemptedAt,
            in: context
        )
        let create = makeOp(
            operationType: "create",
            payload: ["id": deckId],
            status: "completed",
            completedAt: attemptedAt.addingTimeInterval(120),
            in: context
        )

        XCTAssertEqual(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create])
                .map(\.id),
            [parked.id],
            "the row exists now — the park was ordering, not permission"
        )
    }

    /// The loop guard: an attempt at or after the create's completion had its
    /// fair chance, so its park is real. Without this every re-park re-releases.
    func test_parkedRelease_leavesEditAttemptedAfterItsOwnCreateLanded() throws {
        let context = try makeContext()
        let completedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let parked = makeOp(
            operationType: "update",
            payload: ["title": "Renamed"],
            status: "parked",
            lastError: rlsError,
            lastAttemptedAt: completedAt,
            in: context
        )
        let create = makeOp(
            operationType: "create",
            payload: ["id": deckId],
            status: "completed",
            completedAt: completedAt,
            in: context
        )

        XCTAssertTrue(
            SyncCrossEntityDependency
                .parkedOperationsReleasableByCompletedCreates(in: [parked, create]).isEmpty,
            "release once, never in a loop"
        )
    }

    // MARK: - B. Wiring — the REAL OutboundProcessor

    /// HOLD. The create sits in backoff (so the pass skips it, and no network is
    /// involved) while an edit for the same row is pending. Before the barrier
    /// this edit was the whole bug: coalescing could not merge it into an
    /// ineligible create, so it shipped alone and retired as delivered. It must
    /// now come out of the pass bit-identical.
    func test_processPendingOperations_holdsEditWhoseOwnCreateHasNotSynced() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let create = makeOp(
            operationType: "create",
            payload: ["id": deckId, "title": "Back deck"],
            status: "pending",
            lastAttemptedAt: Date(),
            retryCount: 3,                     // → in backoff, the pass skips it
            in: context
        )
        let edit = makeOp(
            operationType: "update",
            payload: ["title": "Back deck — revised"],
            in: context
        )
        try context.save()

        await OutboundProcessor().processPendingOperations(
            context: context,
            connectivity: AlwaysSyncableConnectivity()
        )

        XCTAssertEqual(
            edit.status, "pending",
            "an edit whose own create has not synced must be held — never claimed, never sent"
        )
        XCTAssertNil(
            edit.lastAttemptedAt,
            "a held op is not an attempt: the claim gate must never stamp it"
        )
        XCTAssertEqual(
            edit.retryCount, 0,
            "holding must not burn the retry budget against a dependency of arbitrary latency"
        )
        XCTAssertNil(
            edit.completedAt,
            "and above all it must never be retired as delivered — that was the data loss"
        )
        XCTAssertEqual(
            create.status, "pending",
            "the blocking create stays queued — it is in backoff, not attempted"
        )
    }

    // MARK: - Helpers

    @discardableResult
    private func makeOp(
        entityType: String = SyncEntityType.deckDesign.rawValue,
        entityId: String? = nil,
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
            entityId: entityId ?? deckId,
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
