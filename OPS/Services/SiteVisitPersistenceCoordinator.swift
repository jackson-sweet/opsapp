//
//  SiteVisitPersistenceCoordinator.swift
//  OPS
//
//  Commits every site-visit model mutation with its durable SyncOperation in
//  one SwiftData transaction. No network call is authoritative for local save.
//

import Foundation
import SwiftData

@MainActor
final class SiteVisitPersistenceCoordinator {
    typealias OperationEncoder = (SiteVisitSyncOperation.Payload) throws -> Data
    typealias CommitValidator = () throws -> Void

    struct CommitResult: Equatable {
        let operationIds: [UUID]
        let completionOperationId: UUID?
    }

    enum Error: Swift.Error, LocalizedError {
        case transactionFailed(Swift.Error)
        case pendingChangesRequireIsolation

        var errorDescription: String? {
            switch self {
            case .transactionFailed(let error):
                return "Site visit save failed: \(error.localizedDescription)"
            case .pendingChangesRequireIsolation:
                return "Site visit save requires its own editing context"
            }
        }
    }

    /// Statuses that still OWN a record's outbound send, so the dirty-graph scan
    /// must not create a second one for the same work.
    ///
    /// `declined` is here deliberately (bug f7431c17). The operator stopping a
    /// send from PENDING WORK leaves the record itself dirty and untouched — if
    /// a declined operation read as resolved, `queueDirtyGraphs(onlyOrphans:)`
    /// would re-create the send before the next drain and the row would come
    /// straight back. Media makes this unavoidable: those sends are re-derived
    /// from a still-local asset URL, never from `needsSync`, so no flag on the
    /// model can stop them. Counting `declined` here also makes a genuine later
    /// edit revive that same operation through `enqueue` rather than duplicate it.
    private static let unresolvedStatuses: Set<String> = [
        "pending", "inProgress", "failed", "parked", "declined",
    ]

    /// Sends that wait on the operator: a permanent rejection held for review
    /// ("only user Retry / Discard moves it out") or a send the operator
    /// stopped in PENDING WORK. Saving the visit never restarts one on its own
    /// — only an edit made on the phone after the stop does
    /// (`markStoppedSendsEdited`, `saveShouldQueue`).
    private static let stoppedStatuses: Set<String> = ["parked", "declined"]

    /// Bounded work-count evidence; does not contain operator data.
    private(set) var lastChangedEntityCount = 0
    private(set) var lastLoadedOperationCount = 0
    private(set) var lastBoundarySnapshotCount = 0

    private var transactionOperationIds: Set<UUID> = []
    let modelContext: ModelContext
    private let ownsContext: Bool
    private let companyId: String
    private let encodeOperation: OperationEncoder
    private let validateCommit: CommitValidator

    init(
        modelContext: ModelContext,
        companyId: String,
        encodeOperation: @escaping OperationEncoder = {
            try JSONEncoder().encode($0)
        },
        validateCommit: @escaping CommitValidator = {},
        ownsContext: Bool = false
    ) {
        self.modelContext = modelContext
        self.companyId = companyId.lowercased()
        self.encodeOperation = encodeOperation
        self.validateCommit = validateCommit
        self.ownsContext = ownsContext
    }

    /// One capture/recovery operation owns this context. Caller WIP is never
    /// copied, saved, rolled back or inspected field-by-field by this session.
    func isolatedSession() -> SiteVisitPersistenceCoordinator {
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        return SiteVisitPersistenceCoordinator(modelContext: context, companyId: companyId,
            encodeOperation: encodeOperation, validateCommit: validateCommit, ownsContext: true)
    }

    /// Runs the model mutation, builds/coalesces all matching durable queue
    /// work, and lets SwiftData commit the transaction exactly once.
    @discardableResult
    /// Queues every dirty row of one visit — the moment the operator SAVES.
    ///
    /// Typing persists through `commit(queueing: false)`, which leaves the rows
    /// carrying `needsSync` and nothing in the upload queue; this is the only
    /// path that turns those rows into operations (Jackson, 2026-09-15: "It
    /// should only be uploading when the user saves the site visit"). Unattempted
    /// commands for the same rows are refreshed in place, attempted ones gain a
    /// sequenced successor, and a pending completion is re-anchored behind the
    /// new tail.
    func queueDirtyWork(siteVisitId: String) throws -> CommitResult {
        var queuedIds: [UUID] = []
        let ids: Set<String> = [siteVisitId.lowercased()]
        do {
            try modelContext.transaction {
                let result = try queueDirtyGraphs(onlyOrphans: false, siteVisitIds: ids)
                queuedIds = result.operationIds
                try repairCompletionDependencies(chainTips: result.chainTips, siteVisitIds: ids)
                try validateCommit()
            }
        } catch {
            modelContext.rollback()
            throw Error.transactionFailed(error)
        }
        return CommitResult(operationIds: queuedIds, completionOperationId: nil)
    }

    func commit(
        completing visit: SiteVisit? = nil,
        discarding discardedVisit: SiteVisit? = nil,
        stageCommand: SiteVisitStageCommand? = nil,
        revisedMediaArtifactIds: Set<String> = [],
        queueing: Bool = true,
        mutation: () throws -> Void
    ) throws -> CommitResult {
        // The compatible closure API cannot identify which pre-existing WIP
        // belongs to its caller. Reject before invoking it; shared-context
        // clients resolve their models through isolatedSession().modelContext.
        guard ownsContext || !modelContext.hasChanges else {
            throw Error.pendingChangesRequireIsolation
        }
        let discardIntent: SiteVisitDiscardIntent?
        if let discardedVisit {
            guard discardedVisit.bookedAt == nil, discardedVisit.deletedAt == nil,
                  ![SiteVisitStatus.completed, .cancelled].contains(discardedVisit.status),
                  let actor = SiteVisitAuthorHeal.sessionUserId()?.lowercased() else { throw SiteVisitWriteError.legacyPayload }
            let all = try modelContext.fetch(FetchDescriptor<SyncOperation>())
            let originalIds = all.filter {
                $0.status != "completed" && ($0.siteVisitWriteActorId == nil || $0.siteVisitWriteActorId == actor) &&
                (try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: $0.payload))?.siteVisitId == discardedVisit.id.lowercased()
            }.map(\.id)
            discardIntent = SiteVisitDiscardIntent(capture: try SiteVisitWriteJSON.encode(CreateSiteVisitDTO(model: discardedVisit)),
                discardedAt: SupabaseDate.format(Date()), supersededOperationIds: originalIds)
        } else { discardIntent = nil }
        var queuedIds: [UUID] = []
        var completionId: UUID?
        let boundary = SiteVisitMutationBoundary(context: modelContext)
        var changed: [any PersistentModel] = []
        var changedRows: [SiteVisitMutationBoundary.Row] = []
        transactionOperationIds = []

        do {
            try modelContext.transaction {
                defer { changedRows = changed.map(SiteVisitMutationBoundary.Row.init) }
                do {
                    try mutation()
                } catch {
                    // Preserve identities before transaction unwinding clears
                    // the context's change list, so held rows can be refreshed.
                    changed = boundary.changedEntities(in: modelContext)
                    throw error
                }
                changed = boundary.changedEntities(in: modelContext)
                lastChangedEntityCount = changed.count
                lastBoundarySnapshotCount = boundary.pendingSnapshotCount + changed.count
                lastLoadedOperationCount = 0
                let result: QueueResult
                if let discardedVisit, let discardIntent {
                    let discardedAt = SupabaseDate.parse(discardIntent.discardedAt)
                    discardedVisit.deletedAt = discardedAt
                    for row in changed {
                        if let artifact = row as? SiteVisitCaptureArtifact, artifact.deletedAt != nil { artifact.deletedAt = discardedAt }
                        if let answer = row as? SiteVisitChecklistAnswer, answer.deletedAt != nil { answer.deletedAt = discardedAt }
                        if let draft = row as? SiteVisitIdentityDraft, draft.deletedAt != nil { draft.deletedAt = discardedAt }
                    }
                    let payload = SiteVisitSyncOperation.Payload(companyId: companyId, siteVisitId: discardedVisit.id,
                        entityId: discardedVisit.id, discard: discardIntent)
                    let operation = SyncOperation(entityType: SyncEntityType.siteVisit.rawValue, entityId: discardedVisit.id,
                        operationType: SiteVisitSyncOperation.discardOperationType, payload: try encodeOperation(payload), changedFields: ["deleted_at"])
                    operation.siteVisitWriteActorId = SiteVisitAuthorHeal.sessionUserId()?.lowercased()
                    modelContext.insert(operation)
                    transactionOperationIds.insert(operation.id)
                    result = QueueResult(operationIds: [operation.id], chainTips: [discardedVisit.id.lowercased(): operation.id.uuidString.lowercased()])
                } else if queueing || visit != nil || stageCommand != nil {
                    result = try queueChangedEntities(changed, completing: visit, revisedMediaArtifactIds: revisedMediaArtifactIds)
                } else {
                    // Local-only save: the rows keep `needsSync`, and
                    // `queueDirtyWork` turns them into operations when the
                    // operator saves the visit. An edit to a record whose
                    // send has stopped is recorded on that send, so the save
                    // restarts it.
                    try markStoppedSendsEdited(changed)
                    result = QueueResult(operationIds: [], chainTips: [:])
                }
                queuedIds = result.operationIds

                if let visit {
                    let dependencyId = result.chainTips[visit.id.lowercased()]
                    let completion = try insertCompletion(
                        for: visit,
                        dependsOnId: dependencyId
                    )
                    queuedIds.append(completion.id)
                    completionId = completion.id
                    if let stageCommand {
                        guard stageCommand.siteVisitId.lowercased() == visit.id.lowercased(),
                              stageCommand.companyId.lowercased() == companyId,
                              stageCommand.opportunityId.lowercased() == visit.opportunityId?.lowercased() else {
                            throw SyncError.encodingFailed(detail: "Stage command does not belong to this visit")
                        }
                        let payload = SiteVisitSyncOperation.Payload(companyId: companyId,
                            siteVisitId: visit.id, entityId: visit.id, stageCommand: stageCommand)
                        let stage = SyncOperation(entityType: SyncEntityType.siteVisit.rawValue,
                            entityId: visit.id.lowercased(), operationType: SiteVisitSyncOperation.stageOperationType,
                            payload: try encodeOperation(payload), changedFields: ["stage"], priority: 1,
                            dependsOnId: completion.id.uuidString.lowercased())
                        if !stageCommand.canDeliver {
                            stage.status = "parked"
                            stage.lastError = "STAGE REVIEW REQUIRED · OPEN LEAD"
                        }
                        modelContext.insert(stage)
                        queuedIds.append(stage.id)
                    }
                } else if stageCommand != nil {
                    throw SyncError.encodingFailed(detail: "Stage command requires visit completion")
                }

                // Test seam for a transaction/store failure after every model
                // and queue mutation has been staged but before commit.
                try validateCommit()
            }
        } catch {
            modelContext.rollback()
            for row in changedRows { row.rematerialize(in: modelContext) }
            if (try? modelContext.fetchCount(FetchDescriptor<SyncOperation>())) ?? 0 > 0 {
                for id in transactionOperationIds {
                    _ = try? modelContext.fetch(FetchDescriptor<SyncOperation>(
                        predicate: #Predicate { $0.id == id }
                    ))
                }
            }
            throw Error.transactionFailed(error)
        }

        return CommitResult(
            operationIds: queuedIds,
            completionOperationId: completionId
        )
    }

    /// Removes a never-synced visit and every local queue row that can reference
    /// it. This is the only hard-delete path; synced capture packets use
    /// tombstones so their server copies are removed too.
    func hardDeleteNeverSyncedVisit(
        _ visit: SiteVisit,
        artifacts: [SiteVisitCaptureArtifact],
        answers: [SiteVisitChecklistAnswer],
        drafts: [SiteVisitIdentityDraft]
    ) throws {
        guard ownsContext || !modelContext.hasChanges else {
            throw Error.pendingChangesRequireIsolation
        }
        // This entry point is used only by the explicit pending-work deletion
        // action. Capture entry never calls it to infer that a visit is empty.
        guard visit.lastSyncedAt == nil,
              artifacts.allSatisfy({ $0.lastSyncedAt == nil }),
              answers.allSatisfy({ $0.lastSyncedAt == nil }), drafts.allSatisfy({ $0.lastSyncedAt == nil }) else {
            throw SyncError.encodingFailed(detail: "Visit still owns synced work")
        }
        let entityIds = Set(
            ([visit.id] + artifacts.map(\.id) + answers.map(\.id) + drafts.map(\.id))
                .map { $0.lowercased() }
        )
        do {
            try modelContext.transaction {
                let operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
                for operation in operations where
                    Self.unresolvedStatuses.contains(operation.status)
                        && entityIds.contains(operation.entityId.lowercased())
                {
                    modelContext.delete(operation)
                }
                for artifact in artifacts { modelContext.delete(artifact) }
                for answer in answers { modelContext.delete(answer) }
                for draft in drafts { modelContext.delete(draft) }
                modelContext.delete(visit)
            }
        } catch {
            modelContext.rollback()
            throw Error.transactionFailed(error)
        }
    }

    /// Repairs legacy/bypassed dirty rows without disturbing work already in
    /// flight, exhausted, or parked. This is intentionally company-scoped and
    /// never auto-revives a permanent rejection.
    @discardableResult
    func recoverOrphanedWrites(siteVisitIds: Set<String>? = nil) throws -> CommitResult {
        var queuedIds: [UUID] = []
        let normalizedIds = siteVisitIds.map { Set($0.map { $0.lowercased() }) }
        do {
            try modelContext.transaction {
                let result = try queueDirtyGraphs(onlyOrphans: true, siteVisitIds: normalizedIds)
                queuedIds = result.operationIds
                try repairCompletionDependencies(
                    chainTips: result.chainTips,
                    siteVisitIds: normalizedIds
                )
                try validateCommit()
            }
        } catch {
            modelContext.rollback()
            throw Error.transactionFailed(error)
        }
        return CommitResult(
            operationIds: queuedIds,
            completionOperationId: nil
        )
    }

    /// A legacy completion command may predate the reconstructed parent and
    /// therefore carry no dependency. Re-anchor it to the last parent/child/media
    /// operation for the same visit so priority sorting can never complete the
    /// visit before its packet exists on the server.
    private func repairCompletionDependencies(
        chainTips: [String: String],
        siteVisitIds: Set<String>? = nil
    ) throws {
        let operations = try siteVisitIds.map { try fetchOperations(entityIds: $0) }
            ?? modelContext.fetch(FetchDescriptor<SyncOperation>())
        for completion in operations where
            completion.operationType == SiteVisitSyncOperation.completionOperationType
                && Self.unresolvedStatuses.contains(completion.status)
        {
            guard let payload = try? JSONDecoder().decode(
                SiteVisitSyncOperation.Payload.self,
                from: completion.payload
            ), belongsToCompany(payload.companyId) else { continue }
            let visitId = payload.siteVisitId.lowercased()
            guard siteVisitIds == nil || siteVisitIds!.contains(visitId) else { continue }
            if let chainTip = chainTips[visitId] {
                completion.dependsOnId = chainTip
                continue
            }
            if siteVisitIds != nil { continue }
            completion.dependsOnId = operations
                .filter { operation in
                    guard operation.id != completion.id,
                          operation.operationType
                            != SiteVisitSyncOperation.completionOperationType,
                          operation.operationType != SiteVisitSyncOperation.stageOperationType,
                          Self.unresolvedStatuses.contains(operation.status),
                          let otherPayload = try? JSONDecoder().decode(
                            SiteVisitSyncOperation.Payload.self,
                            from: operation.payload
                          ) else { return false }
                    return otherPayload.siteVisitId.lowercased() == visitId
                        && belongsToCompany(otherPayload.companyId)
                }
                .sorted(by: operationOrder)
                .last?
                .id.uuidString.lowercased()
        }
    }

    private struct QueueResult {
        let operationIds: [UUID]
        let chainTips: [String: String]
    }

    private func queueDirtyGraphs(
        onlyOrphans: Bool = false,
        siteVisitIds: Set<String>? = nil
    ) throws -> QueueResult {
        var queuedIds: [UUID] = []
        var chainTips: [String: String] = [:]
        let companies = [companyId, companyId.uppercased()]
        let requestedIds = siteVisitIds.map { Array(Set($0.flatMap { [$0.lowercased(), $0.uppercased()] })) }
        let visits: [SiteVisit]
        if let requestedIds {
            visits = try modelContext.fetch(FetchDescriptor<SiteVisit>(predicate: #Predicate {
                companies.contains($0.companyId) && requestedIds.contains($0.id)
            }, sortBy: [SortDescriptor(\.createdAt)]))
        } else {
            visits = try modelContext.fetch(FetchDescriptor<SiteVisit>(predicate: #Predicate {
                companies.contains($0.companyId)
            }, sortBy: [SortDescriptor(\.createdAt)]))
        }
        let ids = Array(Set(visits.flatMap { [$0.id.lowercased(), $0.id.uppercased()] }))
        var visitIds = Set(ids.map { $0.lowercased() })
        guard !ids.isEmpty else { return QueueResult(operationIds: [], chainTips: [:]) }
        let artifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(predicate: #Predicate {
            companies.contains($0.companyId) && ids.contains($0.siteVisitId)
        }, sortBy: [SortDescriptor(\.createdAt)]))
        let answers = try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate {
            companies.contains($0.companyId) && ids.contains($0.siteVisitId) && $0.needsSync
        }, sortBy: [SortDescriptor(\.createdAt)]))
        let drafts = try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>(predicate: #Predicate {
            companies.contains($0.companyId) && ids.contains($0.siteVisitId) && $0.needsSync
        }, sortBy: [SortDescriptor(\.createdAt)]))
        var operations = try fetchOperations(entityIds: Set(ids + artifacts.map(\.id) + answers.map(\.id) + drafts.map(\.id)))

        let discardedPackets = Set(operations.filter { $0.operationType == SiteVisitSyncOperation.discardOperationType }.compactMap {
            (try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: $0.payload))?.siteVisitId
        })
        visitIds.subtract(discardedPackets)
        for visit in visits where visit.needsSync && visitIds.contains(visit.id.lowercased()) {
            let specification = SiteVisitSyncOperation.parent(visit)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
                continue
            }
            if !onlyOrphans,
               !saveShouldQueue(specification, operations: operations) {
                continue
            }
            let operation = try enqueue(
                specification,
                dependsOnId: nil,
                operations: &operations
            )
            queuedIds.append(operation.id)
            chainTips[visit.id.lowercased()] = operation.id.uuidString.lowercased()
        }

        for artifact in artifacts where artifact.needsSync {
            let visitId = artifact.siteVisitId.lowercased()
            guard visitIds.contains(visitId) else { continue }
            let specification = SiteVisitSyncOperation.artifact(artifact)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
                continue
            }
            if !onlyOrphans,
               !saveShouldQueue(specification, operations: operations) {
                continue
            }
            let operation = try enqueue(
                specification,
                dependsOnId: dependencyRoot(
                    for: visitId,
                    chainTips: chainTips,
                    operations: operations
                ),
                operations: &operations
            )
            queuedIds.append(operation.id)
            chainTips[visitId] = operation.id.uuidString.lowercased()
        }

        // Upload before linked answers; readiness also waits for the remote-URL
        // metadata acknowledgment queued by the media sender.
        for artifact in artifacts where
            artifact.deletedAt == nil && needsMediaUpload(artifact)
        {
            let visitId = artifact.siteVisitId.lowercased()
            guard visitIds.contains(visitId) else { continue }
            let specification = SiteVisitSyncOperation.media(artifact)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
                continue
            }
            if !onlyOrphans,
               !saveShouldQueue(specification, operations: operations) {
                continue
            }
            let operation = try enqueue(
                specification,
                dependsOnId: dependencyRoot(
                    for: visitId,
                    chainTips: chainTips,
                    operations: operations
                ),
                operations: &operations
            )
            queuedIds.append(operation.id)
            chainTips[visitId] = operation.id.uuidString.lowercased()
        }


        for answer in answers {
            let visitId = answer.siteVisitId.lowercased()
            guard visitIds.contains(visitId) else { continue }
            let specification = try checklistSpecification(answer)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
                continue
            }
            if !onlyOrphans,
               !saveShouldQueue(specification, operations: operations) {
                continue
            }
            let operation = try enqueue(
                specification,
                dependsOnId: dependencyRoot(
                    for: visitId,
                    chainTips: chainTips,
                    operations: operations
                ),
                operations: &operations
            )
            queuedIds.append(operation.id)
            chainTips[visitId] = operation.id.uuidString.lowercased()
        }

        for draft in drafts {
            let visitId = draft.siteVisitId.lowercased()
            guard visitIds.contains(visitId) else { continue }
            let specification = SiteVisitSyncOperation.identityDraft(draft)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
                continue
            }
            if !onlyOrphans,
               !saveShouldQueue(specification, operations: operations) {
                continue
            }
            let operation = try enqueue(
                specification,
                dependsOnId: dependencyRoot(
                    for: visitId,
                    chainTips: chainTips,
                    operations: operations
                ),
                operations: &operations
            )
            queuedIds.append(operation.id)
            chainTips[visitId] = operation.id.uuidString.lowercased()
        }


        var seenOperationIds: Set<UUID> = []
        let distinctOperationIds = queuedIds.filter { seenOperationIds.insert($0).inserted }
        return QueueResult(operationIds: distinctOperationIds, chainTips: chainTips)
    }

    /// Transaction-local work only. The snapshot boundary excludes pre-existing
    /// unsaved edits, including another console's inserted objects.
    private func queueChangedEntities(_ changed: [any PersistentModel], completing visitToComplete: SiteVisit?,
                                      revisedMediaArtifactIds: Set<String>) throws -> QueueResult {
        let changedVisits = changed.compactMap { $0 as? SiteVisit }
            .filter { belongsToCompany($0.companyId) }
        let artifacts = changed.compactMap { $0 as? SiteVisitCaptureArtifact }
            .filter { belongsToCompany($0.companyId) }
        let answers = changed.compactMap { $0 as? SiteVisitChecklistAnswer }
            .filter { belongsToCompany($0.companyId) }
        let drafts = changed.compactMap { $0 as? SiteVisitIdentityDraft }
            .filter { belongsToCompany($0.companyId) }
        let specifications = try artifacts.map(SiteVisitSyncOperation.artifact)
            + answers.map(checklistSpecification)
            + drafts.map(SiteVisitSyncOperation.identityDraft)
        let visitIds = Set(changedVisits.map { $0.id.lowercased() }
            + specifications.map { $0.payload.siteVisitId })
        guard !visitIds.isEmpty else { return QueueResult(operationIds: [], chainTips: [:]) }
        var visits = changedVisits
        for id in visitIds where !visits.contains(where: { $0.id.lowercased() == id }) {
            let upper = id.uppercased()
            var descriptor = FetchDescriptor<SiteVisit>(predicate: #Predicate {
                $0.id == id || $0.id == upper
            })
            descriptor.fetchLimit = 1
            if let parent = try modelContext.fetch(descriptor).first,
               belongsToCompany(parent.companyId) { visits.append(parent) }
        }
        let validVisitIds = Set(visits.map { $0.id.lowercased() })
        var entityIds = visitIds.union(specifications.map { $0.entityId })
        if let visitToComplete {
            let id = visitToComplete.id
            entityIds.formUnion(try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(
                predicate: #Predicate { $0.siteVisitId == id })).map(\.id))
            entityIds.formUnion(try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(
                predicate: #Predicate { $0.siteVisitId == id })).map(\.id))
            entityIds.formUnion(try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>(
                predicate: #Predicate { $0.siteVisitId == id })).map(\.id))
        }
        let operations = try fetchOperations(entityIds: entityIds)
        lastLoadedOperationCount = operations.count
        var index = OperationIndex(operations)
        var queued: [UUID] = []
        var tips: [String: String] = [:]
        let revisedVisitIds = Set(changedVisits.map { $0.id.lowercased() })
        for visit in visits.sorted(by: { $0.createdAt < $1.createdAt }) {
            let specification = SiteVisitSyncOperation.parent(visit)
            if let owner = index.owner(specification), !revisedVisitIds.contains(visit.id.lowercased()) {
                tips[visit.id.lowercased()] = owner.id.uuidString.lowercased()
                continue
            }
            guard revisedVisitIds.contains(visit.id.lowercased()) || visit.lastSyncedAt == nil else { continue }
            let operation = try enqueueScoped(specification, dependency: nil, index: &index)
            queued.append(operation.id)
            tips[visit.id.lowercased()] = operation.id.uuidString.lowercased()
        }
        for specification in artifacts.map(SiteVisitSyncOperation.artifact) where validVisitIds.contains(specification.payload.siteVisitId) {
            let operation = try enqueueScoped(specification,
                dependency: tips[specification.payload.siteVisitId], index: &index)
            queued.append(operation.id)
            tips[specification.payload.siteVisitId] = operation.id.uuidString.lowercased()
        }
        for artifact in artifacts where artifact.isActive && needsMediaUpload(artifact)
            && validVisitIds.contains(artifact.siteVisitId.lowercased()) {
            let specification = SiteVisitSyncOperation.media(artifact)
            // Metadata edits never revive an existing stopped media upload.
            // The media sender resolves current local variants on explicit retry.
            if let owner = index.owner(specification), !revisedMediaArtifactIds.contains(artifact.id.lowercased()) {
                tips[artifact.siteVisitId.lowercased()] = owner.id.uuidString.lowercased()
                continue
            }
            let operation = try enqueueScoped(specification,
                dependency: tips[artifact.siteVisitId.lowercased()], index: &index)
            queued.append(operation.id)
            tips[artifact.siteVisitId.lowercased()] = operation.id.uuidString.lowercased()
        }
        for specification in try answers.map(checklistSpecification) + drafts.map(SiteVisitSyncOperation.identityDraft) where validVisitIds.contains(specification.payload.siteVisitId) {
            let operation = try enqueueScoped(specification,
                dependency: tips[specification.payload.siteVisitId], index: &index)
            queued.append(operation.id)
            tips[specification.payload.siteVisitId] = operation.id.uuidString.lowercased()
        }
        if let visitToComplete {
            let tail = index.byId.values.filter {
                $0.operationType != SiteVisitSyncOperation.completionOperationType
                    && $0.operationType != SiteVisitSyncOperation.stageOperationType
            }.sorted(by: operationOrder).last
            tips[visitToComplete.id.lowercased()] = tail?.id.uuidString.lowercased()
        }
        return QueueResult(operationIds: Array(Set(queued)).sorted { $0.uuidString < $1.uuidString }, chainTips: tips)
    }

    private func fetchOperations(entityIds: Set<String>) throws -> [SyncOperation] {
        // An untouched empty SyncOperation table traps with a predicate on iOS
        // 26.5. Count without a predicate first; never materialize history.
        let ids = Array(entityIds.union(entityIds.map { $0.uppercased() }))
        let statuses = Array(Self.unresolvedStatuses)
        var count = FetchDescriptor<SyncOperation>()
        count.includePendingChanges = false
        guard try modelContext.fetchCount(count) > 0 else {
            return modelContext.insertedModelsArray.compactMap { $0 as? SyncOperation }.filter {
                ids.contains($0.entityId) && Self.unresolvedStatuses.contains($0.status)
            }
        }
        return try modelContext.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate {
            ids.contains($0.entityId) && statuses.contains($0.status)
        }))
    }

    private struct OperationIndex {
        var byKey: [String: [SyncOperation]] = [:]
        var byId: [String: SyncOperation] = [:]

        init(_ operations: [SyncOperation]) {
            for operation in operations.sorted(by: {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }) { append(operation) }
        }
        static func key(type: String, id: String, media: Bool) -> String {
            "\(type)::\(id.lowercased())::\(media)"
        }
        mutating func append(_ operation: SyncOperation) {
            byId[operation.id.uuidString.lowercased()] = operation
            guard operation.operationType != SiteVisitSyncOperation.completionOperationType,
                  operation.operationType != SiteVisitSyncOperation.stageOperationType else { return }
            let key = Self.key(type: operation.entityType, id: operation.entityId,
                media: operation.operationType == SiteVisitSyncOperation.mediaOperationType)
            byKey[key, default: []].append(operation)
        }
        func candidates(_ specification: SiteVisitSyncOperation.Specification) -> [SyncOperation] {
            byKey[Self.key(type: specification.entityType.rawValue, id: specification.entityId,
                media: specification.operationType == SiteVisitSyncOperation.mediaOperationType)] ?? []
        }
        func owner(_ specification: SiteVisitSyncOperation.Specification) -> SyncOperation? {
            candidates(specification).last
        }
        func safeDependency(_ proposed: String?, for operation: SyncOperation) -> String? {
            var seen = Set<String>()
            var cursor = proposed?.lowercased()
            while let id = cursor, seen.insert(id).inserted {
                if id == operation.id.uuidString.lowercased() { return operation.dependsOnId }
                cursor = byId[id]?.dependsOnId?.lowercased()
            }
            return proposed
        }
    }

    private func checklistSpecification(_ answer: SiteVisitChecklistAnswer) throws -> SiteVisitSyncOperation.Specification {
        try SiteVisitSyncOperation.checklistAnswer(answer,
            forceChoiceProtocol: SiteVisitWriteModels.currentTemplateHasChoice(for: answer, context: modelContext))
    }

    private func enqueueScoped(_ specification: SiteVisitSyncOperation.Specification,
                               dependency: String?, index: inout OperationIndex) throws -> SyncOperation {
        let candidates = index.candidates(specification)
        let payload = try encodeOperation(specification.payload)
        if let existing = candidates.last(where: { SiteVisitVersionedSync.command($0)?.protocol == specification.payload.writeCommand?.protocol && $0.siteVisitWriteActorId == SiteVisitAuthorHeal.sessionUserId()?.lowercased() && $0.status != "inProgress" &&
            (!SiteVisitVersionedSync.handles($0) || ($0.status == "pending" && $0.siteVisitWriteAttemptedAt == nil && $0.lastAttemptedAt == nil)) }) {
            transactionOperationIds.insert(existing.id)
            if existing.operationType != "create" || specification.operationType == "delete" {
                existing.operationType = specification.operationType
            }
            existing.payload = payload
            existing.changedFields = specification.changedFields.joined(separator: ",")
            existing.priority = min(existing.priority, specification.priority)
            existing.dependsOnId = index.safeDependency(dependency, for: existing)
            existing.status = "pending"
            existing.retryCount = 0
            existing.lastAttemptedAt = nil
            existing.completedAt = nil
            existing.lastError = nil
            return existing
        }
        let operation = SyncOperation(entityType: specification.entityType.rawValue,
            entityId: specification.entityId, operationType: specification.operationType,
            payload: payload, changedFields: specification.changedFields,
            priority: specification.priority,
            dependsOnId: candidates.last?.id.uuidString.lowercased() ?? dependency)
        transactionOperationIds.insert(operation.id)
        operation.siteVisitWriteActorId = SiteVisitAuthorHeal.sessionUserId()?.lowercased()
        modelContext.insert(operation)
        index.append(operation)
        return operation
    }

    private func dependencyRoot(
        for siteVisitId: String,
        chainTips: [String: String],
        operations: [SyncOperation]
    ) -> String? {
        if let chainTip = chainTips[siteVisitId] { return chainTip }
        return operations
            .filter { operation in
                // A declined send never completes (the operator stopped it),
                // and a dependency is satisfied only by `completed` — so
                // nothing new may be sequenced behind one, or it waits forever.
                guard operation.operationType
                        != SiteVisitSyncOperation.completionOperationType,
                      operation.operationType != SiteVisitSyncOperation.stageOperationType,
                      Self.unresolvedStatuses.contains(operation.status),
                      operation.status != "declined",
                      SiteVisitOutboundSync.isSiteVisitOperation(operation),
                      let payload = try? JSONDecoder().decode(
                          SiteVisitSyncOperation.Payload.self,
                          from: operation.payload
                      ) else {
                    return false
                }
                return payload.siteVisitId.lowercased() == siteVisitId
                    && belongsToCompany(payload.companyId)
            }
            .sorted(by: operationOrder)
            .last?
            .id.uuidString.lowercased()
    }

    private func enqueue(
        _ specification: SiteVisitSyncOperation.Specification,
        dependsOnId: String?,
        operations: inout [SyncOperation]
    ) throws -> SyncOperation {
        let canonicalEntityId = specification.entityId.lowercased()
        let candidates = unresolvedCandidates(specification, in: operations)

        let payload = try encodeOperation(specification.payload)
        if let existing = candidates.last(where: { SiteVisitVersionedSync.command($0)?.protocol == specification.payload.writeCommand?.protocol && $0.siteVisitWriteActorId == SiteVisitAuthorHeal.sessionUserId()?.lowercased() && $0.status != "inProgress" &&
            (!SiteVisitVersionedSync.handles($0) || ($0.status == "pending" && $0.siteVisitWriteAttemptedAt == nil && $0.lastAttemptedAt == nil)) }) {
            if existing.operationType != "create" || specification.operationType == "delete" {
                existing.operationType = specification.operationType
            }
            existing.payload = payload
            existing.changedFields = specification.changedFields.joined(separator: ",")
            existing.priority = min(existing.priority, specification.priority)
            // `dependencyRoot` answers "the newest unresolved op for this
            // visit", which is `existing` itself once this entity is already
            // queued — re-queueing would then make the op wait on itself, or
            // close a ring with its siblings. Either way nothing is ever
            // attempted again (the 2026-08-19 device wedge).
            existing.dependsOnId = SiteVisitOutboundSync.dependencyWithoutCycle(
                dependsOnId,
                for: existing,
                in: operations
            )
            existing.status = "pending"
            existing.retryCount = 0
            existing.lastAttemptedAt = nil
            existing.completedAt = nil
            existing.lastError = nil
            return existing
        }

        let inProgressDependency = candidates.last(where: { $0.status == "inProgress" || SiteVisitVersionedSync.handles($0) })
            .map { $0.id.uuidString.lowercased() }
        let operation = SyncOperation(
            entityType: specification.entityType.rawValue,
            entityId: canonicalEntityId,
            operationType: specification.operationType,
            payload: payload,
            changedFields: specification.changedFields,
            priority: specification.priority,
            dependsOnId: inProgressDependency ?? dependsOnId
        )
        operation.siteVisitWriteActorId = SiteVisitAuthorHeal.sessionUserId()?.lowercased()
        modelContext.insert(operation)
        operations.append(operation)
        return operation
    }

    private func insertCompletion(
        for visit: SiteVisit,
        dependsOnId: String?
    ) throws -> SyncOperation {
        let specification = SiteVisitSyncOperation.completion(visit)
        let operation = SyncOperation(
            entityType: specification.entityType.rawValue,
            entityId: specification.entityId,
            operationType: specification.operationType,
            payload: try encodeOperation(specification.payload),
            changedFields: specification.changedFields,
            priority: specification.priority,
            dependsOnId: dependsOnId
        )
        operation.siteVisitWriteActorId = SiteVisitAuthorHeal.sessionUserId()?.lowercased()
        modelContext.insert(operation)
        return operation
    }

    private func belongsToCompany(_ candidate: String) -> Bool {
        candidate.lowercased() == companyId
    }

    /// The unresolved sends `enqueue` matches for `specification`, oldest
    /// first: same record, same kind (a photo upload or not), never a
    /// completion or stage command.
    private func unresolvedCandidates(
        _ specification: SiteVisitSyncOperation.Specification,
        in operations: [SyncOperation]
    ) -> [SyncOperation] {
        let canonicalEntityId = specification.entityId.lowercased()
        let isMedia = specification.operationType
            == SiteVisitSyncOperation.mediaOperationType
        return operations
            .filter {
                $0.entityType == specification.entityType.rawValue
                    && $0.entityId.lowercased() == canonicalEntityId
                    && $0.operationType != SiteVisitSyncOperation.completionOperationType
                    && $0.operationType != SiteVisitSyncOperation.stageOperationType
                    && (($0.operationType
                            == SiteVisitSyncOperation.mediaOperationType) == isMedia)
                    && Self.unresolvedStatuses.contains($0.status)
            }
            .sorted(by: operationOrder)
    }

    /// Whether saving the visit (`queueDirtyWork`) should (re)queue this dirty
    /// record's send. The save re-sends what changed on the phone and nothing
    /// else — the outcome per-edit queueing had before typing went local-only
    /// (2026-09-15). Until this rule every save re-derived a send for every
    /// dirty row, so DONE revived held rejections and declined sends and
    /// queued duplicates behind work already in flight.
    ///
    /// - A photo upload belongs to capture and markup: the save only derives
    ///   one for a photo with no unresolved upload at all.
    /// - An answer's queued command carries its values. When this operator's
    ///   newest attempted, stopped or failed command already asks for exactly
    ///   these, there is nothing new to send; an unattempted one is still
    ///   refreshed in place.
    /// - A parked or declined send restarts only for a record edited on the
    ///   phone after the stop, while that stop still stands (`RestartMark`).
    private func saveShouldQueue(
        _ specification: SiteVisitSyncOperation.Specification,
        operations: [SyncOperation]
    ) -> Bool {
        guard let newest = unresolvedCandidates(specification, in: operations).last else {
            return true
        }
        if specification.operationType == SiteVisitSyncOperation.mediaOperationType {
            return false
        }
        if let command = specification.payload.writeCommand {
            if newest.status == "pending",
               newest.siteVisitWriteAttemptedAt == nil,
               newest.lastAttemptedAt == nil {
                return true
            }
            guard newest.siteVisitWriteActorId == SiteVisitAuthorHeal.sessionUserId()?.lowercased(),
                  let queued = SiteVisitVersionedSync.command(newest) else {
                return true
            }
            return !Self.carriesSameValues(queued, command)
        }
        guard Self.stoppedStatuses.contains(newest.status) else { return true }
        guard let mark = Self.envelope(of: newest)?.restartMark else { return false }
        return mark.stillStands(for: newest)
    }

    /// Whether a queued answer command already asks for what `current` asks:
    /// the same protocol and, row by row, the same values and explicit clear.
    /// Base revisions and `before` rows are bookkeeping the sender rebases,
    /// not intent.
    private static func carriesSameValues(
        _ queued: SiteVisitWriteCommand,
        _ current: SiteVisitWriteCommand
    ) -> Bool {
        queued.protocol == current.protocol
            && queued.entity == current.entity
            && queued.rows.count == current.rows.count
            && zip(queued.rows, current.rows).allSatisfy {
                $0.id == $1.id && $0.values == $1.values && $0.clearAnswer == $1.clearAnswer
            }
    }

    private static func envelope(of operation: SyncOperation) -> SiteVisitSyncOperation.Payload? {
        try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload)
    }

    /// A local-only commit that edits a visit, artifact or identity draft
    /// whose newest send has stopped (parked or declined) records the edit on
    /// that send, in the same transaction as the row, so the next save
    /// restarts it (`saveShouldQueue`). Answers need no mark — their queued
    /// command carries its values, so the save compares content — and a save
    /// never restarts a photo upload.
    private func markStoppedSendsEdited(_ changed: [any PersistentModel]) throws {
        let specifications: [SiteVisitSyncOperation.Specification] = changed.compactMap { model in
            switch model {
            case let visit as SiteVisit where belongsToCompany(visit.companyId):
                return SiteVisitSyncOperation.parent(visit)
            case let artifact as SiteVisitCaptureArtifact where belongsToCompany(artifact.companyId):
                return SiteVisitSyncOperation.artifact(artifact)
            case let draft as SiteVisitIdentityDraft where belongsToCompany(draft.companyId):
                return SiteVisitSyncOperation.identityDraft(draft)
            default:
                return nil
            }
        }
        guard !specifications.isEmpty else { return }
        let operations = try fetchOperations(entityIds: Set(specifications.map(\.entityId)))
        for specification in specifications {
            guard let stopped = unresolvedCandidates(specification, in: operations).last,
                  Self.stoppedStatuses.contains(stopped.status),
                  let envelope = Self.envelope(of: stopped) else { continue }
            let mark = SiteVisitSyncOperation.Payload.RestartMark(stoppedSend: stopped)
            guard envelope.restartMark != mark else { continue }
            stopped.payload = try encodeOperation(envelope.withRestartMark(mark))
        }
    }

    private func hasUnresolvedOperation(
        _ specification: SiteVisitSyncOperation.Specification,
        operations: [SyncOperation]
    ) -> Bool {
        let isMedia = specification.operationType
            == SiteVisitSyncOperation.mediaOperationType
        return operations.contains {
            $0.entityType == specification.entityType.rawValue
                && $0.entityId.lowercased() == specification.entityId.lowercased()
                && $0.operationType != SiteVisitSyncOperation.completionOperationType
                    && $0.operationType != SiteVisitSyncOperation.stageOperationType
                && (($0.operationType
                        == SiteVisitSyncOperation.mediaOperationType) == isMedia)
                && Self.unresolvedStatuses.contains($0.status)
        }
    }

    private func needsMediaUpload(
        _ artifact: SiteVisitCaptureArtifact
    ) -> Bool {
        [
            artifact.localAssetURL,
            artifact.renderedAssetURL,
            artifact.thumbnailURL,
        ].compactMap { $0 }.contains {
            !SiteVisitMediaSyncManager.isRemoteURL($0)
        }
    }

    private func operationOrder(_ lhs: SyncOperation, _ rhs: SyncOperation) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
