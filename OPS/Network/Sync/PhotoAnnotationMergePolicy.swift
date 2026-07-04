//
//  PhotoAnnotationMergePolicy.swift
//  OPS
//
//  Shared inbound-merge rule for photo annotations. Annotations do not use
//  SyncOperation rows (PhotoAnnotationSyncManager tracks its own needsSync
//  flag), so acceptableFields / SyncFieldGuard cannot protect them — without
//  this rule an inbound "live row" echo clobbers a locally-pending tombstone:
//  deletedAt reverts to nil, needsSync resets to false, the user's delete is
//  silently dropped, and the markup resurrects on their own screen. Exactly
//  that happened in prod on 2026-06-24 (bugs 452bab04 / 0415504f — the
//  soft-delete push was RLS-rejected, then the next delta pull erased the
//  pending tombstone so the device never retried).
//
//  ONE predicate, used by all three inbound paths (InboundProcessor,
//  DataActor, RealtimeProcessor) so the rule cannot drift between them.
//

import Foundation

enum PhotoAnnotationMergePolicy {
    /// True when the local row carries a not-yet-synced tombstone and the
    /// server echo is still live: keep the local `deletedAt` AND keep
    /// `needsSync` so the pending sweep still pushes the delete. A
    /// server-side tombstone (`incomingDeletedAt != nil`) always merges
    /// normally — that is convergence, not a clobber.
    static func shouldPreserveLocalTombstone(
        localNeedsSync: Bool,
        localDeletedAt: Date?,
        incomingDeletedAt: Date?
    ) -> Bool {
        localNeedsSync && localDeletedAt != nil && incomingDeletedAt == nil
    }
}
