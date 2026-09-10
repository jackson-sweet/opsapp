//
//  SyncOperationReconcilers.swift
//  OPS
//
//  Entity-aware terminal-failure reconciliation for outbound SyncOperations.
//  A "failure" that proves the server already holds the intended end state is
//  not a failure — it is a lost confirmation. These helpers detect the two
//  verified classes (bug ba75732a) so both outbound twins and the launch
//  auto-resolver treat them identically:
//
//  1. projectPhoto CREATE vs the site-visit dedupe indexes
//     (project_photos_active_site_visit_url_key / _uidx): the conversion RPC
//     private.execute_opportunity_conversion_core mirrors site-visit photos
//     server-side in the same transaction that creates the project, so the
//     queued client create is redundant whenever conversion ran online. The
//     server rows carry server-generated ids, `uploaded_by = sv.created_by`,
//     `taken_at = NULL` and no caption/thumbnail/rendered — so the phone can
//     neither insert nor link, and the op parks permanently.
//  2. projectTask UPDATE vs complete_project_task's task_not_found when the
//     server task is soft-deleted: the tombstone wins.
//
//  The local halves live here as plain store operations, deliberately: the
//  PostgREST lookups they hang off have no seam, so factoring the heal out is
//  the only way any of it is provable. The twins keep the network half and call
//  in for the rest, which also guarantees DataActor and OutboundProcessor heal
//  identically rather than by review alone.
//

import Foundation
import SwiftData

enum SyncOperationReconcilers {

    // MARK: - Detection

    /// True when a create failed only because an active-site-visit-photo dedupe
    /// arbiter already holds the row. Deliberately narrow: the constraint name
    /// must be one of the two known partial unique indexes, so an unrelated
    /// 23505 still parks for a human to look at.
    static func isSiteVisitPhotoDuplicate(_ errorDescription: String) -> Bool {
        errorDescription.contains("duplicate key value violates unique constraint")
            && errorDescription.contains("project_photos_active_site_visit_url")
    }

    /// True when a create failed only because the active-(project_id, url)
    /// arbiter already holds the row (project_photos_active_project_url_uidx,
    /// migration cluster_j_01). Same doctrine as the site-visit matcher: the
    /// constraint NAME is the contract; an unrelated 23505 still parks.
    static func isActiveProjectPhotoURLDuplicate(_ errorDescription: String) -> Bool {
        errorDescription.contains("duplicate key value violates unique constraint")
            && errorDescription.contains("project_photos_active_project_url")
    }

    /// True when a projectTask update was refused because the server task is
    /// gone (complete_project_task and its kin raise task_not_found).
    static func isTaskNotFound(_ errorDescription: String) -> Bool {
        errorDescription.contains("task_not_found")
    }

    /// The reconciliation an operation qualifies for, if any.
    enum Kind: Equatable {
        /// Adopt the server's photo row by natural key.
        case duplicatePhotoCreate
        /// Apply the server's task tombstone locally.
        case taskTombstone
        /// A project update the server matched to no row. Three truths hide
        /// behind that one shape — the row is live but this account may not
        /// edit it, the row is deleted, or the row is genuinely absent — and
        /// only a probe can say which. See `reconcileProjectUpdateRowVerdict`
        /// in either twin.
        case projectUpdateRowVerdict
    }

    /// Dispatch for a failure as it happens — the error just thrown.
    static func kind(
        operationType: String,
        entityType: String,
        errorDescription: String
    ) -> Kind? {
        if operationType == "create",
           entityType == SyncEntityType.projectPhoto.rawValue,
           isSiteVisitPhotoDuplicate(errorDescription)
            || isActiveProjectPhotoURLDuplicate(errorDescription) {
            return .duplicatePhotoCreate
        }
        if operationType == "update",
           entityType == SyncEntityType.projectTask.rawValue,
           (isTaskNotFound(errorDescription) || errorDescription.contains(SyncError.serverRowMissingMarker)) {
            return .taskTombstone
        }
        if operationType == "update",
           entityType == SyncEntityType.project.rawValue,
           errorDescription.contains(SyncError.serverRowMissingMarker) {
            return .projectUpdateRowVerdict
        }
        return nil
    }

    /// Dispatch for an operation that parked BEFORE the reconcilers existed.
    ///
    /// Same rules, plus the `_pkey` class for photo creates: the live path
    /// resolves those in the twins' PK-idempotency block, but ops parked on an
    /// older build never met it. Looking the row up by natural key resolves them
    /// too; if the payload lacks that key the reconciler simply declines and the
    /// op stays parked — never worse than today.
    static func parkedKind(for operation: SyncOperation) -> Kind? {
        let errorDescription = operation.lastError ?? ""
        if let kind = kind(
            operationType: operation.operationType,
            entityType: operation.entityType,
            errorDescription: errorDescription
        ) {
            return kind
        }
        if operation.operationType == "create",
           operation.entityType == SyncEntityType.projectPhoto.rawValue,
           errorDescription.contains("_pkey") {
            return .duplicatePhotoCreate
        }
        return nil
    }

    // MARK: - Project server state

    /// The server's verdict on a project row, company-scoped, independent of
    /// this operator's per-row visibility. Answered by the
    /// `public.project_server_state` RPC (migration cluster_j_03).
    enum ProjectServerState: String, Equatable {
        /// The row is live in this company. If the caller could not SELECT it,
        /// the caller's view scope no longer reaches it.
        case active
        /// The row is tombstoned. RLS hides it from everyone, so this is the
        /// only way a device can learn the deletion happened.
        case deleted
        /// No such row in this company — including another company's row, which
        /// reads `absent` rather than leaking across the tenant boundary.
        case absent
        /// The server could not resolve the CALLER to a company, so it has no
        /// opinion about the row. Bug bf2a75fb: this used to answer `absent`,
        /// and a caller that believed it dropped the queued mirror for good
        /// against a perfectly live job. Not evidence of anything — retry.
        case unknown
    }

    /// Reads the RPC's scalar answer off the wire.
    ///
    /// PostgREST renders a `text`-returning function as a JSON string
    /// (`"active"`); an unquoted body is tolerated too, so a transport detail
    /// can never cost us the verdict. Anything unrecognized returns nil and the
    /// caller invents nothing — a probe that did not answer is not evidence.
    static func projectServerState(from data: Data) -> ProjectServerState? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return ProjectServerState(rawValue: trimmed)
    }

    // MARK: - Photo create: adopt the server row

    /// The columns the reconciler reads back for a photo it lost the dedupe
    /// race to. Snake-cased to match PostgREST's response keys directly.
    struct ServerPhotoRow: Decodable, Equatable {
        let id: String
        let caption: String?
        let taken_at: String?
        let thumbnail_url: String?
        let rendered_url: String?

        init(
            id: String,
            caption: String? = nil,
            taken_at: String? = nil,
            thumbnail_url: String? = nil,
            rendered_url: String? = nil
        ) {
            self.id = id
            self.caption = caption
            self.taken_at = taken_at
            self.thumbnail_url = thumbnail_url
            self.rendered_url = rendered_url
        }
    }

    /// Binds the local photo row to the server's identity and reports the
    /// metadata the server is missing.
    ///
    /// Two shapes, because inbound sync may already have materialized the
    /// server row as a SECOND local row (it merges by id, and the ids differ):
    ///   * both rows present — merge the local-only metadata into the server-id
    ///     row and delete the orphan, so the gallery stops showing the photo
    ///     twice;
    ///   * only the local row — adopt the server id in place.
    /// Annotations bind by `photoURL`, never by photo id, so healing the id has
    /// no annotation ripple.
    ///
    /// Returns the back-fill patch for the columns the conversion RPC left
    /// empty and this device can supply — empty when there is nothing to send.
    /// Callers apply it AFTER the transaction commits: the op is already
    /// resolved, and the write guard may refuse it for a non-uploader.
    @discardableResult
    static func adoptServerPhotoRow(
        localId: String,
        server: ServerPhotoRow,
        in context: ModelContext
    ) throws -> [String: String] {
        let serverId = server.id.lowercased()
        let localRow = try fetchProjectPhoto(id: localId, in: context)
        let serverRow = try fetchProjectPhoto(id: serverId, in: context)

        let survivor: ProjectPhoto?
        if let serverRow {
            if let localRow, localRow !== serverRow {
                if serverRow.caption == nil { serverRow.caption = localRow.caption }
                if serverRow.thumbnailURL == nil { serverRow.thumbnailURL = localRow.thumbnailURL }
                if serverRow.renderedURL == nil { serverRow.renderedURL = localRow.renderedURL }
                if serverRow.takenAt == nil { serverRow.takenAt = localRow.takenAt }
                context.delete(localRow)
            }
            survivor = serverRow
        } else if let localRow {
            localRow.id = serverId
            survivor = localRow
        } else {
            survivor = nil
        }

        guard let survivor else { return [:] }
        survivor.needsSync = false
        survivor.lastSyncedAt = Date()

        var patch: [String: String] = [:]
        if server.caption == nil, let value = survivor.caption, !value.isEmpty {
            patch["caption"] = value
        }
        if server.taken_at == nil, let value = survivor.takenAt {
            patch["taken_at"] = SupabaseDate.format(value)
        }
        if server.thumbnail_url == nil, let value = survivor.thumbnailURL, value.hasPrefix("http") {
            patch["thumbnail_url"] = value
        }
        if server.rendered_url == nil, let value = survivor.renderedURL, value.hasPrefix("http") {
            patch["rendered_url"] = value
        }
        return patch
    }

    private static func fetchProjectPhoto(
        id: String,
        in context: ModelContext
    ) throws -> ProjectPhoto? {
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate<ProjectPhoto> { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    struct ServerTaskRow: Decodable {
        let id: String
        let company_id: String
        let deleted_at: String?
    }

    /// Called in either driver's model transaction after its scoped server read.
    /// Invisibility can mean permission loss, deletion, or an absent row. None
    /// proves delivery; the local copy and Pending Work must survive all three.
    static func reconcileTaskUpdate(_ operation: SyncOperation, server: ServerTaskRow?,
        companyId: String, in context: ModelContext) throws -> Bool {
        guard let server, server.id.lowercased() == operation.entityId.lowercased(),
              server.company_id.lowercased() == companyId.lowercased() else { return false }
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        guard !TaskLifecycleSync.hasUnresolvedCreationOrRestore(taskId: operation.entityId, in: operations),
              !TaskLifecycleSync.isLifecycle(operation),
              let raw = server.deleted_at, let deletedAt = SupabaseDate.parse(raw) else { return false }
        // Explicit evidence can hide stale live twins, but must not discard their edits.
        let ids = [operation.entityId.lowercased(), operation.entityId.uppercased()]
        let tasks = try context.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { ids.contains($0.id) }))
        for task in tasks where task.companyId.lowercased() == companyId.lowercased() {
            task.deletedAt = task.deletedAt ?? deletedAt
        }
        if TaskLifecycleSync.carriesSchedule(operation) { return false }
        markResolved(operation)
        return true
    }

    // MARK: - Task update: the tombstone wins

    /// Applies the server's tombstone to the local task.
    ///
    /// Returns whether a live local task was tombstoned. `false` is still a
    /// successful reconciliation — the device may simply hold no row for a task
    /// the server has already deleted.
    @discardableResult
    static func applyTaskTombstone(
        taskId: String,
        deletedAt: Date,
        in context: ModelContext
    ) throws -> Bool {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { $0.id == taskId }
        )
        guard let task = try context.fetch(descriptor).first, task.deletedAt == nil else {
            return false
        }
        task.deletedAt = deletedAt
        // The deletion is the newer truth; there is nothing left to push.
        task.needsSync = false
        return true
    }

    // MARK: - Project update: the tombstone wins

    /// Applies the server's project tombstone locally. The deletion is the newer
    /// truth; the project moves to trash on this phone and nothing is left to
    /// push.
    ///
    /// Returns whether a live local project was tombstoned. `false` is still a
    /// successful reconciliation — the device may hold no row, or already hold
    /// the tombstone. An existing tombstone is never restamped: the first
    /// deletion time this phone learned is the honest one.
    ///
    /// `#Predicate` on `Project` is safe. The documented SwiftData trap is
    /// specific to `SyncOperation` against a table that has never held a row.
    @discardableResult
    static func applyProjectTombstone(
        projectId: String,
        deletedAt: Date,
        in context: ModelContext
    ) throws -> Bool {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == projectId }
        )
        guard let project = try context.fetch(descriptor).first,
              project.deletedAt == nil else {
            return false
        }
        project.deletedAt = deletedAt
        // The deletion is the newer truth; there is nothing left to push.
        project.needsSync = false
        return true
    }

    /// Rewrites a zero-row project update as the edit-permission refusal it
    /// actually is. The op stays parked — nothing about it became sendable —
    /// but its stored reason now names the true cause, so PENDING WORK stops
    /// claiming a deletion that never happened.
    ///
    /// Rewriting `lastError` is also what makes the verdict self-terminating:
    /// the new description carries `serverEditRefusedMarker` and no longer
    /// carries `serverRowMissingMarker`, so `parkedKind` never re-matches this
    /// operation and the launch sweep cannot re-probe it forever.
    ///
    /// `completedAt` stays nil deliberately: the change never reached the
    /// server, and the operator's copy is still the only copy.
    static func applyEditRefusedVerdict(
        _ operation: SyncOperation,
        table: String
    ) {
        operation.status = "parked"
        operation.lastError = SyncError
            .serverEditRefused(table: table, id: operation.entityId)
            .localizedDescription
    }

    // MARK: - Operation completion

    /// Marks an operation resolved by reconciliation. The server already holds
    /// the intended end state, so this is a completion, not a retirement: it
    /// leaves `parked`, and PENDING WORK empties itself.
    static func markResolved(_ operation: SyncOperation, at date: Date = Date()) {
        operation.status = "completed"
        operation.completedAt = date
        operation.lastError = nil
    }
}
