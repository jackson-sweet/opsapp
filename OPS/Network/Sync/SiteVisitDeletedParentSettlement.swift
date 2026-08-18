//
//  SiteVisitDeletedParentSettlement.swift
//  OPS
//
//  Deleted-parent settlement for the durable site-visit queue (SITE VISIT SYNC
//  WEDGE). When the server rejects a completion with
//  `cannot_complete_deleted_site_visit` (errcode 55000), the visit row carries
//  `deleted_at` server-side — someone deleted it in OPS. From that moment the
//  phone's whole queued chain for the visit is un-landable: the completion RPC
//  refuses, and every child insert/update is blocked by RLS
//  (`current_user_can_access_site_visit_child` requires `deleted_at is null`),
//  where the 42501 would misroute into the re-auth branch and wedge the queue.
//
//  Settlement moves the chain into the recovery vault's protected custody
//  (reason `parentDeleted`) — encrypted copies of every captured child AND its
//  local media — then marks the operations `quarantined` and clears the models'
//  dirty flags so no sweep re-enqueues doomed work. The operator sees one
//  honest packet in PENDING WORK ("Deleted in OPS — kept on this phone") with
//  EXPORT and an explicit, destructive-labelled DELETE. Nothing is discarded.
//
//  Runs on the MainActor sweep cadence (pre-drain + login recovery) because the
//  vault is MainActor-bound; the outbound engines only PARK the failing op (the
//  classifier routes 55000 to `.permanent`), and this sweep converts the parked
//  signal into settlement on the next pass. Known gap, accepted: a deleted-parent
//  chain that carries NO completion op has no typed signal to sweep on — its
//  child writes still fail through the pre-existing RLS/auth path.
//

import Foundation
import SwiftData

@MainActor
enum SiteVisitDeletedParentSettlement {
    typealias QuarantineRecorder = (SiteVisitOrphanQuarantine) throws -> Void

    struct Result: Equatable {
        let quarantinedVisitIds: [String]
        let settledOperationIds: [UUID]

        static let empty = Result(quarantinedVisitIds: [], settledOperationIds: [])
    }

    /// The exact raise name `complete_site_visit_guarded` emits when the visit
    /// row is soft-deleted. The NAME is the server contract; the errcode alone
    /// is not — 55000 carries many other deliberate raises (cancelled-visit,
    /// the lead-assignment family, …) whose chains must never settle this way.
    static let deletedParentRaise = "cannot_complete_deleted_site_visit"

    /// `inProgress` deliberately excluded: a write on the wire belongs to its
    /// engine until it lands. `quarantined`/`completed` are already settled.
    private static let settleableStatuses: Set<String> = [
        "pending", "failed", "parked",
    ]

    /// Typed detection at the moment the completion push fails. The repository
    /// wraps every PostgREST failure into `.server`, so this is the only shape
    /// the raise can arrive in.
    static func isDeletedParentRejection(_ error: Error) -> Bool {
        guard case let SiteVisitRepositoryError.server(code, message, _, _) = error else {
            return false
        }
        return code == "55000" && message.contains(deletedParentRaise)
    }

    /// Sweep-side detection from an operation's stored `lastError`. Both
    /// outbound engines persist `SiteVisitRepositoryError.errorDescription`
    /// ("[55000] cannot_complete_deleted_site_visit …"), so the raise name is
    /// preserved verbatim; older builds that classified the failure transient
    /// stored the same text, which lets the sweep settle a chain wedged before
    /// this code ever ran — without waiting for one more doomed round trip.
    static func indicatesDeletedParent(lastError: String?) -> Bool {
        lastError?.contains(deletedParentRaise) == true
    }

    /// Finds every settleable completion op carrying the deleted-parent
    /// rejection and moves its visit's whole chain into protected custody.
    ///
    /// Custody is recorded BEFORE any mutation (the orphan-recovery discipline):
    /// a vault failure aborts the sweep with every op and dirty flag exactly as
    /// found, so the next sweep simply tries again. Idempotent — settled chains
    /// are `quarantined` and no longer match.
    @discardableResult
    static func sweep(
        in modelContext: ModelContext,
        activeUserId: String,
        activeCompanyId: String,
        quarantine: QuarantineRecorder
    ) throws -> Result {
        let company = canonical(activeCompanyId)
        let user = canonical(activeUserId)
        guard !company.isEmpty, !user.isEmpty else { return .empty }

        // Predicate-free by necessity: a #Predicate fetch of SyncOperation
        // traps against a never-populated table (see ProjectCacheMerge).
        let operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())

        var rootVisitIds = Set<String>()
        for operation in operations where
            operation.operationType == SiteVisitSyncOperation.completionOperationType
                && settleableStatuses.contains(operation.status)
                && indicatesDeletedParent(lastError: operation.lastError)
        {
            guard let payload = decode(operation),
                  canonical(payload.companyId) == company else { continue }
            rootVisitIds.insert(canonical(payload.siteVisitId))
        }
        guard !rootVisitIds.isEmpty else { return .empty }

        var chains: [String: [SyncOperation]] = [:]
        for operation in operations where
            SiteVisitOutboundSync.isSiteVisitOperation(operation)
                && settleableStatuses.contains(operation.status)
        {
            guard let payload = decode(operation),
                  canonical(payload.companyId) == company else { continue }
            let visitId = canonical(payload.siteVisitId)
            guard rootVisitIds.contains(visitId) else { continue }
            chains[visitId, default: []].append(operation)
        }

        let visits = try modelContext.fetch(FetchDescriptor<SiteVisit>())
            .filter { canonical($0.companyId) == company }
        let artifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter { canonical($0.companyId) == company }
        let answers = try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter { canonical($0.companyId) == company }
        let drafts = try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter { canonical($0.companyId) == company }

        let orderedVisitIds = rootVisitIds.sorted()

        for visitId in orderedVisitIds {
            let chain = chains[visitId] ?? []
            var childIds = Set<String>()
            for artifact in artifacts where canonical(artifact.siteVisitId) == visitId {
                childIds.insert(canonical(artifact.id))
            }
            for answer in answers where canonical(answer.siteVisitId) == visitId {
                childIds.insert(canonical(answer.id))
            }
            for draft in drafts where canonical(draft.siteVisitId) == visitId {
                childIds.insert(canonical(draft.id))
            }
            // Queue-derived fallback: a child whose local row is already gone
            // still names itself through its operation, so the archive filter
            // can never silently narrow below what the queue knows about.
            for operation in chain where
                operation.entityType != SyncEntityType.siteVisit.rawValue
            {
                childIds.insert(canonical(operation.entityId))
            }

            let record = SiteVisitOrphanQuarantine(
                id: "site-visit-quarantine:"
                    + SiteVisitOrphanQuarantineReason.parentDeleted.rawValue
                    + ":\(company):\(visitId)",
                userId: user,
                companyId: company,
                siteVisitId: visitId,
                reason: .parentDeleted,
                childIds: childIds.sorted(),
                createdAt: chain.map(\.createdAt).min() ?? Date()
            )
            try quarantine(record)
        }

        var settledIds: [UUID] = []
        try modelContext.transaction {
            for visitId in orderedVisitIds {
                for operation in chains[visitId] ?? [] {
                    operation.status = "quarantined"
                    operation.lastError =
                        "Visit was deleted in OPS — work is held on this phone."
                    operation.lastAttemptedAt = nil
                    settledIds.append(operation.id)
                }
                // Settled means settled: leave the dirty flags clear or the
                // orphan-writes sweep re-enqueues a fresh doomed op for the
                // same deleted visit on the very next drain.
                for visit in visits where canonical(visit.id) == visitId {
                    visit.needsSync = false
                }
                for artifact in artifacts where canonical(artifact.siteVisitId) == visitId {
                    artifact.needsSync = false
                }
                for answer in answers where canonical(answer.siteVisitId) == visitId {
                    answer.needsSync = false
                }
                for draft in drafts where canonical(draft.siteVisitId) == visitId {
                    draft.needsSync = false
                }
            }
        }

        return Result(
            quarantinedVisitIds: orderedVisitIds,
            settledOperationIds: settledIds
        )
    }

    // MARK: - Internals

    private static func decode(
        _ operation: SyncOperation
    ) -> SiteVisitSyncOperation.Payload? {
        try? JSONDecoder().decode(
            SiteVisitSyncOperation.Payload.self,
            from: operation.payload
        )
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
