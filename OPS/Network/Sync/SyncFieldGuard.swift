//
//  SyncFieldGuard.swift
//  OPS
//
//  Single source of truth for deciding which fields an inbound merge (full-sync
//  pull or realtime echo) must NOT overwrite because a local write to them is
//  still un-reconciled.
//
//  Background — the silent-revert race:
//  An outbound push flips its SyncOperation `pending -> inProgress` BEFORE the
//  network await, then `-> completed` once the server acknowledges. The inbound
//  field-guards historically protected only fields belonging to a `pending`
//  operation, which left two windows where a just-saved edit was unprotected:
//    1. In-flight: the realtime websocket is not gated by the sync engine, so a
//       stale echo of the pre-edit row can land while the op is `inProgress`.
//    2. Just-completed: the pull paths are actor-serialized, so the op is
//       already `completed` by the time the merge runs — `pending`-only checks
//       see nothing to protect and the echo reverts the edit.
//  Symptom: a task completed / rescheduled / reassigned from a review flow
//  reappears next session because the server row was overwritten back.
//
//  The insert-branch origin suppression in every sync processor already closed
//  the symmetric duplicate-insert race with a `hasRecentLocalWrite(within: 60s)`
//  time window. This type is the field-level analogue used by the existing-row
//  (update) merge branches, so both branches reason about op lifecycle the same
//  way.
//

import Foundation

enum SyncFieldGuard {
    /// Window, in seconds, during which a non-`pending` local write is still
    /// treated as "in flight" and its fields stay protected from an inbound
    /// echo. Matches the `hasRecentLocalWrite(withinSeconds:)` window used by the
    /// insert-branch origin suppression across RealtimeProcessor, InboundProcessor
    /// and DataActor — keep them in lockstep.
    static let recentLocalWriteWindow: TimeInterval = 60

    /// Returns the set of field names an inbound merge must keep local for one
    /// entity, given that entity's `ops` (already fetched for a single
    /// entityType + entityId).
    ///
    /// A field is protected when the operation that wrote it is either:
    ///   - `pending` — an un-pushed local write, protected regardless of age (an
    ///     offline-queued edit must survive until it actually reaches the
    ///     server, even if that is minutes or hours later); or
    ///   - recent — the op had any lifecycle event (created / last-attempted /
    ///     completed) within `window`, regardless of its current status. This
    ///     covers the `inProgress` (mid-push) and just-`completed` echoes, and a
    ///     recently-`failed` write whose local value should still win briefly.
    ///
    /// Field-level by design: only the fields a pending/recent op actually wrote
    /// are protected, so a concurrent remote edit to a *different* field of the
    /// same entity still merges. Protection self-heals once `window` elapses.
    ///
    /// - Parameters:
    ///   - ops: SyncOperations already scoped to one entity.
    ///   - now: reference time (injected so the window is deterministically
    ///     testable).
    ///   - window: recent-write window in seconds. Defaults to
    ///     ``recentLocalWriteWindow``.
    static func protectedFields(
        from ops: [SyncOperation],
        now: Date,
        window: TimeInterval = recentLocalWriteWindow
    ) -> Set<String> {
        let cutoff = now.addingTimeInterval(-window)
        var fields = Set<String>()
        for op in ops {
            let isPending = op.status == "pending"
            let isRecent = op.createdAt >= cutoff
                || (op.lastAttemptedAt.map { $0 >= cutoff } ?? false)
                || (op.completedAt.map { $0 >= cutoff } ?? false)
            guard isPending || isRecent else { continue }
            fields.formUnion(op.getChangedFields())
        }
        return fields
    }
}
