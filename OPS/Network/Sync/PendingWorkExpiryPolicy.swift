//
//  PendingWorkExpiryPolicy.swift
//  OPS
//
//  Bug f71113a3 — pending work auto-deletes after 30 days. This file is the
//  complete, testable answer to WHAT may expire; SyncEngine.purgeExpiredPendingWork
//  is the only place that ACTS on it.
//
//  The line is drawn by criticality (bug a3f7cca8, Jackson's own words): after
//  30 days of failure, queue metadata leaves on its own; content that exists
//  nowhere else never silently dies — it stays, wearing CRITICAL.
//

import Foundation

enum PendingWorkExpiryScope: Equatable {
    /// Delete these SyncOperation rows outright. Safe for non-create loose ops:
    /// nothing re-derives a generic mutation (re-derivation exists only for
    /// site-visit lanes), and the local edit stays applied on this phone.
    case deleteOperations([UUID])
    /// Remove a durable lead-delivery request from the autocreate queue.
    case removeLeadRequest(clientId: String)
    /// Stop every queued send in an EMPTY site-visit work unit, using the exact
    /// decline semantics of a user swipe (PendingWorkDecline.queuedSends):
    /// operations move to the terminal "declined" status — never deleted, so
    /// orphan recovery cannot resurrect them — and the visit row stays local.
    case declineBundleSends(SiteVisitBundle)
}

enum PendingWorkExpiryDecision: Equatable {
    case expire(PendingWorkExpiryScope)
    case keep
}

/// What one expiry pass actually removed. Returned so the pass can decide
/// whether a save is even needed, and so tests can assert the outcome without
/// reading the log.
struct PendingWorkExpiryOutcome: Equatable {
    var expiredOperations = 0
    var expiredLeadRequests = 0
    var expiredEmptyBundles = 0

    static let none = PendingWorkExpiryOutcome()
    var total: Int { expiredOperations + expiredLeadRequests + expiredEmptyBundles }
}

enum PendingWorkExpiryPolicy {
    /// Same constant the STALE · 30D review tag uses. One number, one meaning.
    static let expiryInterval: TimeInterval = 30 * 24 * 60 * 60

    /// - Parameter clientCreateOpExists: whether ANY SyncOperation is a client
    ///   `create` for the given (lowercased) client id. A lead parked behind its
    ///   customer's refused create must live exactly as long as that create does
    ///   — expiring the lead alone would strand a retried customer with no lead.
    static func decision(
        for item: RecoveryItem,
        now: Date,
        clientCreateOpExists: (String) -> Bool
    ) -> PendingWorkExpiryDecision {
        // Only stalled work expires. Waiting/in-flight work is progressing —
        // a crew offline for five weeks reconnects and their queue SENDS.
        guard item.tone >= .attention else { return .keep }
        guard now.timeIntervalSince(item.sortDate) >= expiryInterval else { return .keep }

        switch item {
        case .op(let snapshot, _, _):
            // A create op is the only path for a whole record to reach the
            // server. Deleting it silently orphans the record forever.
            guard snapshot.operationType != "create", snapshot.operationType != ProjectReopenSync.operationType else { return .keep }
            return .expire(.deleteOperations([snapshot.id]))

        case .autocreate(let snapshot, _, _):
            // Parked behind its customer's own create: the pair lives and dies
            // together. While that create op exists (parked or retried), keep.
            if SyncStatusCopy.PendingWork.isClientRejected(snapshot.lastError),
               clientCreateOpExists(snapshot.clientId.lowercased()) {
                return .keep
            }
            return .expire(.removeLeadRequest(clientId: snapshot.clientId))

        case .bundle(let bundle):
            // Only EMPTY packets expire, and never while a send is on the wire.
            guard bundle.capturedItemCount == 0, !bundle.hasOperationInFlight else { return .keep }
            return .expire(.declineBundleSends(bundle))

        case .photos, .draft, .orphanDesign, .quarantinedVisit:
            // The only copy of real content, resumable captures, and custody
            // packets never silently expire. They wear CRITICAL instead.
            return .keep
        }
    }
}
