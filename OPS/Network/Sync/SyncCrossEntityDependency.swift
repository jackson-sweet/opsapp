//
//  SyncCrossEntityDependency.swift
//  OPS
//
//  Cross-entity ordering for the outbound queue (bug 06f68200).
//
//  The queue already orders work WITHIN an entity group: coalescing merges a
//  create with its later updates, and the site-visit / task-type / mention
//  barriers hold dependent writes behind their own graph. Nothing ordered work
//  ACROSS entities. So an op could reference a row the server has never seen:
//
//      deckDesign update {updated_at, project_id: P}   ← pushed first
//      project     create {id: P, …}                   ← still queued
//
//  The server evaluates the deck_designs RLS policy against project P, cannot
//  resolve it, and returns 42501. `SyncErrorClassifier` — correctly, and by
//  design — has no queue context, so it reads "42501" as a permanent rejection
//  and the op parks forever. Observed 2026-08-12 on the founder's device: two
//  deckDesign updates parked while the very projects they referenced were
//  created server-side minutes later in the same drain.
//
//  WHY A BARRIER, NOT A CLASSIFIER CHANGE. Making the classifier retry an RLS
//  rejection when a create is pending would re-open exactly the failure mode
//  the classifier exists to prevent (see its header: born from the 2026-07-22
//  outage, where a permanent rejection burned the same 20-retry budget as a
//  transient 504). It would also spend a network attempt to discover something
//  the local queue already knows, and burn that budget against a dependency of
//  unbounded latency — a create can sit unsent for days on a truck with no
//  signal. Holding the op costs nothing and cannot fail. The classifier stays
//  context-free; ordering stays the queue's job.
//
//  THE SAME-ENTITY CASE (bug 2e58c85b). The barrier above orders work ACROSS
//  entities; nothing ordered a row against ITS OWN create. Coalescing merges a
//  create with its later updates only when both land in the SAME eligible
//  batch, so a create that is ineligible — in retry backoff, out of budget,
//  parked, quarantined — leaves its updates behind as an "all updates" group
//  that ships alone:
//
//      project create {id: P, …}                 ← parked / backing off
//      project update {title: "Fixed"}           ← pushed alone
//
//  PostgREST answers a PATCH that matches no row with 200 and an empty body.
//  The queue read that as delivered and retired the op: the edit was gone, and
//  the operator was never told. Same rule, same reasoning as above — an op
//  whose own row is not on the server yet is HELD, not sent. It costs nothing
//  and cannot fail, where sending costs the edit itself.
//
//  Deletes are held too, deliberately. A delete pushed while its create is
//  parked "succeeds" against nothing, and the day that create is retried the
//  row appears on the server with no delete left to remove it — a resurrection
//  the operator can neither see nor undo. Holding trades one extra round trip
//  (the create lands, then the delete tombstones it) for a state that always
//  converges. Subsystems that run their own ordering graph (site visit, task
//  type, mention edits) are exempt: they are already ordered, and double-gating
//  them would deadlock work their own barrier is holding for another reason.
//
//  SELF-HEALING THE OPS ALREADY PARKED. Shipping the barrier does not un-park
//  what the race already broke. `parkedOperationsReleasableByCompletedCreates`
//  identifies parks that are PROVABLY this race — an RLS/FK rejection whose
//  last attempt predates the completion of the very create it was waiting on —
//  and hands them back to the queue. The proof is what makes it loop-safe:
//  releasing stamps a fresh `lastAttemptedAt` on the next claim, which is by
//  construction later than the create's `completedAt`, so a second park can
//  never satisfy the rule again. A park with any other cause, or one attempted
//  after its create landed, is left exactly where it is.
//
//  Pure by necessity: every function takes a plain `[SyncOperation]` and does
//  no fetching. A `#Predicate` fetch of `SyncOperation` traps (uncatchable
//  EXC_BREAKPOINT) against a table that has never held a row, and these run on
//  every outbound pass.
//

import Foundation
import SwiftData

enum SyncCrossEntityDependency {

    // MARK: - The mapped foreign keys

    /// Payload column → the entity type whose local `create` must reach the
    /// server before an op carrying that column can be sent.
    ///
    /// Deliberately narrow. A key earns a place here only when the client can
    /// create the referenced row locally AND the server evaluates it during a
    /// write. `opportunity_id` is absent on purpose: leads are network-only
    /// (never in SwiftData, no local create op can exist), and the deck→lead
    /// link travels via its own guarded `linkOpportunity` RPC.
    static let payloadReferenceKeys: [String: String] = [
        "project_id": SyncEntityType.project.rawValue,
        "client_id": SyncEntityType.client.rawValue,
        "primary_sub_client_id": SyncEntityType.subClient.rawValue,
        "company_id": SyncEntityType.company.rawValue,
        "task_type_id": SyncEntityType.taskType.rawValue
    ]

    /// Every status that means "the server does not have this row yet".
    /// Mirrors `SiteVisitOutboundSync.unresolvedStatuses` — a create that is
    /// queued, in flight, out of retries, or parked is equally absent.
    private static let unresolvedCreateStatuses: Set<String> = [
        "pending", "inProgress", "failed", "parked", "quarantined"
    ]

    // MARK: - The barrier

    /// THE ordering gate both outbound paths ask before sending anything: true
    /// when this op cannot legally reach the server yet, because a row it needs
    /// — one it references, or its own — has no confirmed create.
    ///
    /// Held means held: never attempted, never parked, no retry budget consumed.
    static func isHeld(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> Bool {
        isBlockedByUnresolvedCreate(operation, in: operations)
            || isBlockedByUnresolvedSameEntityCreate(operation, in: operations)
    }

    /// True when `operation` references an entity whose own create has not yet
    /// been confirmed by the server. Such an op must be HELD — never attempted,
    /// never parked, no retry budget consumed.
    static func isBlockedByUnresolvedCreate(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> Bool {
        !unresolvedCreates(blocking: operation, in: operations).isEmpty
    }

    /// True when `operation` is a later write against a row whose OWN create is
    /// still unresolved — the 0-row PATCH that used to retire silently.
    ///
    /// A create never blocks on itself, and subsystems with their own ordering
    /// graph are exempt (see the header). Ids compare lowercased:
    /// `UUID().uuidString` is uppercase while Postgres uuid columns are not, so
    /// a case-sensitive match would miss the create and ship the write into the
    /// void it was meant to be held back from.
    static func isBlockedByUnresolvedSameEntityCreate(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> Bool {
        !unresolvedSameEntityCreates(blocking: operation, in: operations).isEmpty
    }

    // MARK: - The same question, asked from outside the queue

    /// True when the server has no confirmed row for `entityId` yet, because a
    /// local `create` for it is still unresolved.
    ///
    /// The barrier above orders QUEUED work. Two photo rails write by REST,
    /// entirely outside the `SyncOperation` queue, and so were never ordered by
    /// anything: `ImageSyncManager` (in-app gallery + note attachments, which
    /// inserts `project_photos` and PATCHes `projects.project_images` directly)
    /// and `ShareUploadCoordinator` (the share extension's App Group queue,
    /// which POSTs to `/api/uploads/share-photo`). Both address a project the
    /// operator picked on THIS phone, which may exist only on this phone.
    ///
    /// Rather than teach each rail its own notion of "is this project real",
    /// they ask this — the same rule, over the same data, that governs every
    /// queued write. Held means held: the photo waits on the device and goes
    /// out on a later pass, once the create lands. Same reasoning as the
    /// header's: holding costs one more drain pass, sending costs the photo.
    ///
    /// Pure like everything else here — a `#Predicate` fetch of `SyncOperation`
    /// traps (uncatchable EXC_BREAKPOINT) against a table that has never held a
    /// row, so callers fetch predicate-free and hand the array in.
    ///
    /// Ids compare lowercased: `UUID().uuidString` is uppercase while Postgres
    /// uuid columns are not, and a case-sensitive match would miss the blocking
    /// create and ship the photo into the rejection it was meant to be held
    /// back from.
    static func hasUnresolvedCreate(
        entityType: SyncEntityType,
        entityId: String,
        in operations: [SyncOperation]
    ) -> Bool {
        let canonicalId = entityId.lowercased()
        guard !canonicalId.isEmpty else { return false }
        return operations.contains { candidate in
            candidate.operationType == "create"
                && candidate.entityType == entityType.rawValue
                && candidate.entityId.lowercased() == canonicalId
                && unresolvedCreateStatuses.contains(candidate.status)
        }
    }

    /// The same-entity create ops (unresolved, or completed when
    /// `includingCompleted`) that govern `operation`.
    private static func unresolvedSameEntityCreates(
        blocking operation: SyncOperation,
        in operations: [SyncOperation],
        includingCompleted: Bool = false
    ) -> [SyncOperation] {
        guard operation.operationType != "create",
              !runsItsOwnOrderingGraph(operation) else { return [] }

        let entityType = operation.entityType
        let entityId = operation.entityId.lowercased()

        return operations.filter { candidate in
            guard candidate.id != operation.id,
                  candidate.operationType == "create",
                  candidate.entityType == entityType,
                  candidate.entityId.lowercased() == entityId
            else { return false }
            return includingCompleted
                ? candidate.status == "completed"
                : unresolvedCreateStatuses.contains(candidate.status)
        }
    }

    /// Subsystems that order their own writes. Their barriers already know when
    /// a row exists server-side — and know things this one cannot, like a
    /// packet's media stage — so a second gate here can only deadlock them.
    private static func runsItsOwnOrderingGraph(
        _ operation: SyncOperation
    ) -> Bool {
        SiteVisitOutboundSync.isSiteVisitOperation(operation)
            || TaskTypeMutationSync.bypassesGenericCoalescing(operation)
            || ProjectNoteMentionEditSync.bypassesGenericCoalescing(operation)
    }

    /// The unresolved (or completed, when `includingCompleted`) create ops that
    /// `operation`'s payload references. One payload decode per call.
    private static func unresolvedCreates(
        blocking operation: SyncOperation,
        in operations: [SyncOperation],
        includingCompleted: Bool = false
    ) -> [SyncOperation] {
        let references = payloadReferences(of: operation)
        guard !references.isEmpty else { return [] }

        return operations.filter { candidate in
            // An op never blocks on itself: a create whose payload echoes its
            // own id would otherwise deadlock the very write that resolves it.
            guard candidate.id != operation.id,
                  candidate.operationType == "create" else { return false }
            guard includingCompleted
                    ? candidate.status == "completed"
                    : unresolvedCreateStatuses.contains(candidate.status)
            else { return false }
            // Ids are unique per table, not globally — the entity type must
            // match the column the id came from.
            return references.contains(
                Reference(
                    entityType: candidate.entityType,
                    entityId: candidate.entityId.lowercased()
                )
            )
        }
    }

    /// A (table, id) pair a payload points at.
    private struct Reference: Hashable {
        let entityType: String
        let entityId: String
    }

    /// The mapped foreign keys carried by an op's payload, lowercased.
    ///
    /// String values only. A JSON null or a number in an id slot is not an id,
    /// and coercing one would be a guess — guessing here means holding real
    /// work behind a dependency that does not exist.
    private static func payloadReferences(
        of operation: SyncOperation
    ) -> Set<Reference> {
        guard let payload = try? JSONSerialization.jsonObject(
            with: operation.payload
        ) as? [String: Any] else {
            return []
        }
        var references: Set<Reference> = []
        for (key, entityType) in payloadReferenceKeys {
            guard let value = payload[key] as? String, !value.isEmpty else {
                continue
            }
            // `UUID().uuidString` is uppercase; Postgres uuid columns are
            // lowercase. A case-sensitive match would miss the blocking create
            // and ship the op straight into the rejection.
            references.insert(
                Reference(entityType: entityType, entityId: value.lowercased())
            )
        }
        return references
    }

    // MARK: - Drain continuation

    /// Ids of the work this barrier considers ready right now: pending ops it
    /// is not holding, plus parked ops the release step will hand back to the
    /// queue. Backoff is deliberately NOT consulted — a blocking create sitting
    /// in backoff is still ready work as far as ordering is concerned, and
    /// folding backoff in here would make the set flap with the clock and spin
    /// the drain loop.
    static func readyOperationIds(
        in operations: [SyncOperation]
    ) -> Set<UUID> {
        var ready = Set(
            operations.compactMap { operation -> UUID? in
                guard operation.status == "pending",
                      !isHeld(operation, in: operations)
                else { return nil }
                return operation.id
            }
        )
        ready.formUnion(
            parkedOperationsReleasableByCompletedCreates(in: operations)
                .map(\.id)
        )
        return ready
    }

    /// Another pass is worth running only when this barrier has ready work AND
    /// that work changed — an unchanged set means the last pass released
    /// nothing, and repeating it would spin.
    static func shouldContinueDrain(
        readyBeforePass: Set<UUID>,
        readyAfterPass: Set<UUID>
    ) -> Bool {
        !readyAfterPass.isEmpty && readyAfterPass != readyBeforePass
    }

    // MARK: - Releasing mis-parked work

    /// Rejection phrases that the missing row explains: an RLS policy that
    /// cannot resolve the row, a foreign key with nothing to point at, or our
    /// own zero-row PATCH verdict — the three ways "that row is not there"
    /// reaches the queue. Conservative on purpose; anything else (a check
    /// constraint, a bad value, a deliberate raise) has a different cause and
    /// keeps its park.
    private static let releasableRejectionPhrases = [
        "row-level security",
        "violates foreign key constraint",
        SyncError.serverRowMissingMarker
    ]

    /// Parked ops whose park is provably this race: rejected for a reason the
    /// missing row explains, and last attempted STRICTLY before the create they
    /// were waiting on completed — whether that create belongs to a row they
    /// reference or to the row itself. Strictness is the loop guard — an op
    /// attempted at or after that moment had its fair chance, so its park is
    /// real.
    static func parkedOperationsReleasableByCompletedCreates(
        in operations: [SyncOperation]
    ) -> [SyncOperation] {
        operations.filter { operation in
            guard operation.status == "parked",
                  let lastAttemptedAt = operation.lastAttemptedAt,
                  let lastError = operation.lastError,
                  rejectionIsExplainedByMissingRow(lastError)
            else { return false }

            let blockingCreates = unresolvedCreates(
                blocking: operation,
                in: operations,
                includingCompleted: true
            ) + unresolvedSameEntityCreates(
                blocking: operation,
                in: operations,
                includingCompleted: true
            )

            return blockingCreates.contains { create in
                guard let completedAt = create.completedAt else { return false }
                return lastAttemptedAt < completedAt
            }
        }
    }

    private static func rejectionIsExplainedByMissingRow(
        _ message: String
    ) -> Bool {
        let lowered = message.lowercased()
        return releasableRejectionPhrases.contains { lowered.contains($0) }
    }

    /// Hands a mis-parked op back to the queue. Matches user-Retry semantics: a
    /// clean retry budget. `lastAttemptedAt` and `lastError` are deliberately
    /// left in place — the stamp is what keeps the release single-shot, and the
    /// error stays visible in Pending Work until the op actually resolves.
    ///
    /// Callers own the transaction (both outbound paths persist differently).
    @discardableResult
    static func releaseParkedOperations(
        in operations: [SyncOperation]
    ) -> [SyncOperation] {
        let releasable = parkedOperationsReleasableByCompletedCreates(
            in: operations
        )
        for operation in releasable {
            operation.status = "pending"
            operation.retryCount = 0
        }
        return releasable
    }
}
