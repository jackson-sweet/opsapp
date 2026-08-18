//
//  AnalyticsFlushPolicy.swift
//  OPS
//
//  What the analytics flush does with a failed batch (bug 088d82dc).
//
//  The queue is a fixed 1,000-event ring in UserDefaults, and a failed batch is
//  re-queued at the FRONT. So any batch that can never succeed does not just
//  fail — it dams every event behind it until the cap starts dropping the
//  oldest. That is what happened: `analytics_events` grants the app INSERT and
//  nothing else, the client sent `.upsert(onConflict:)` returning a
//  representation, both of which need SELECT, and every batch 403'd on a
//  30-second loop forever.
//
//  The rules below make the dam impossible by construction:
//
//    * A duplicate key is not a failure. Each event carries a client-side UUID
//      primary key, so a duplicate means that event already landed and the
//      response was lost on the wire — at-least-once delivery, satisfied. The
//      batch is retried per event, because a Postgres INSERT is all-or-nothing
//      and the events that had NOT landed would otherwise be written off.
//    * A permanent rejection is dropped, not re-queued. Waiting cannot make it
//      deliverable, and analytics are the one payload in this app that is
//      cheaper to lose than to dam.
//    * Everything else retries with the existing backoff.
//
//  Disposition comes from `SyncErrorClassifier` — the same permanent/transient
//  split the outbound queue uses, so the two cannot drift on what "the server
//  will keep rejecting this" means.
//

import Foundation

enum AnalyticsFlushPolicy {

    /// What to do with a batch the server refused.
    enum Outcome: Equatable {
        /// Duplicate key — some or all of the batch is already on the server.
        /// Retry event by event so the ones that are not still get through.
        case splitBatch
        /// Transient — re-queue and try again on the next flush trigger.
        case retry
        /// Permanent — quarantine by dropping. Re-queueing would dam the queue.
        case drop
    }

    /// Postgres unique-violation SQLSTATE, and the phrase PostgREST surfaces
    /// when the Swift client flattens the error to a message. Matched on either
    /// because the typed code is not always preserved through the wrapping.
    static let duplicateKeySQLState = "23505"
    static let duplicateKeyPhrase = "duplicate key value violates unique constraint"

    static func outcome(for error: Error) -> Outcome {
        if isDuplicateKey(error) { return .splitBatch }
        switch SyncErrorClassifier.disposition(for: error) {
        case .permanent:
            return .drop
        case .transient, .auth:
            // Auth retries here rather than dropping: an expired token is the
            // most ordinary transient condition on a truck, and the outbound
            // queue's re-authentication escalation already owns fixing it.
            return .retry
        }
    }

    /// True when the server refused the write because the row is already there.
    ///
    /// Deliberately broader than `errorIndicatesPrimaryKeyViolation`, which
    /// requires a `_pkey` constraint name so a genuine unique-column collision
    /// still surfaces as a create failure. `analytics_events` has exactly one
    /// unique constraint — its primary key — so any duplicate here means the
    /// event already landed.
    static func isDuplicateKey(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains(duplicateKeySQLState)
            || text.contains(duplicateKeyPhrase)
    }
}
