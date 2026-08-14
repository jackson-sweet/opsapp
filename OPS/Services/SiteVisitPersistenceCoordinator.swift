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

        var errorDescription: String? {
            switch self {
            case .transactionFailed(let error):
                return "Site visit save failed: \(error.localizedDescription)"
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

    private let modelContext: ModelContext
    private let companyId: String
    private let encodeOperation: OperationEncoder
    private let validateCommit: CommitValidator

    init(
        modelContext: ModelContext,
        companyId: String,
        encodeOperation: @escaping OperationEncoder = {
            try JSONEncoder().encode($0)
        },
        validateCommit: @escaping CommitValidator = {}
    ) {
        self.modelContext = modelContext
        self.companyId = companyId.lowercased()
        self.encodeOperation = encodeOperation
        self.validateCommit = validateCommit
    }

    /// Runs the model mutation, builds/coalesces all matching durable queue
    /// work, and lets SwiftData commit the transaction exactly once.
    @discardableResult
    func commit(
        completing visit: SiteVisit? = nil,
        mutation: () throws -> Void
    ) throws -> CommitResult {
        var queuedIds: [UUID] = []
        var completionId: UUID?

        do {
            try modelContext.transaction {
                try mutation()
                let result = try queueDirtyGraphs()
                queuedIds = result.operationIds

                if let visit {
                    let dependencyId = result.chainTips[visit.id.lowercased()]
                    let completion = try insertCompletion(
                        for: visit,
                        dependsOnId: dependencyId
                    )
                    queuedIds.append(completion.id)
                    completionId = completion.id
                }

                // Test seam for a transaction/store failure after every model
                // and queue mutation has been staged but before commit.
                try validateCommit()
            }
        } catch {
            modelContext.rollback()
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
    func recoverOrphanedWrites() throws -> CommitResult {
        var queuedIds: [UUID] = []
        do {
            try modelContext.transaction {
                let result = try queueDirtyGraphs(onlyOrphans: true)
                queuedIds = result.operationIds
                try repairCompletionDependencies(
                    chainTips: result.chainTips
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
        chainTips: [String: String]
    ) throws {
        let operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
        for completion in operations where
            completion.operationType == SiteVisitSyncOperation.completionOperationType
                && Self.unresolvedStatuses.contains(completion.status)
        {
            guard let payload = try? JSONDecoder().decode(
                SiteVisitSyncOperation.Payload.self,
                from: completion.payload
            ), belongsToCompany(payload.companyId) else { continue }
            let visitId = payload.siteVisitId.lowercased()
            if let chainTip = chainTips[visitId] {
                completion.dependsOnId = chainTip
                continue
            }
            completion.dependsOnId = operations
                .filter { operation in
                    guard operation.id != completion.id,
                          operation.operationType
                            != SiteVisitSyncOperation.completionOperationType,
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
        onlyOrphans: Bool = false
    ) throws -> QueueResult {
        var operations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
        var queuedIds: [UUID] = []
        var chainTips: [String: String] = [:]

        let visits = try modelContext.fetch(FetchDescriptor<SiteVisit>())
            .filter { belongsToCompany($0.companyId) }
            .sorted { $0.createdAt < $1.createdAt }
        let visitIds = Set(visits.map { $0.id.lowercased() })

        for visit in visits where visit.needsSync {
            let specification = SiteVisitSyncOperation.parent(visit)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
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

        let artifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter { belongsToCompany($0.companyId) }
            .sorted { $0.createdAt < $1.createdAt }
        for artifact in artifacts where artifact.needsSync {
            let visitId = artifact.siteVisitId.lowercased()
            guard visitIds.contains(visitId) else { continue }
            let specification = SiteVisitSyncOperation.artifact(artifact)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
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

        let answers = try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter { belongsToCompany($0.companyId) && $0.needsSync }
            .sorted { $0.createdAt < $1.createdAt }
        for answer in answers {
            let visitId = answer.siteVisitId.lowercased()
            guard visitIds.contains(visitId) else { continue }
            let specification = SiteVisitSyncOperation.checklistAnswer(answer)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
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

        let drafts = try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter { belongsToCompany($0.companyId) && $0.needsSync }
            .sorted { $0.createdAt < $1.createdAt }
        for draft in drafts {
            let visitId = draft.siteVisitId.lowercased()
            guard visitIds.contains(visitId) else { continue }
            let specification = SiteVisitSyncOperation.identityDraft(draft)
            if onlyOrphans,
               hasUnresolvedOperation(specification, operations: operations) {
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

        // Media follows every model row. Each operation uploads all still-local
        // variants for one artifact; it persists progress per variant and queues
        // the remote-URL artifact upsert behind itself.
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

    private func dependencyRoot(
        for siteVisitId: String,
        chainTips: [String: String],
        operations: [SyncOperation]
    ) -> String? {
        if let chainTip = chainTips[siteVisitId] { return chainTip }
        return operations
            .filter { operation in
                guard operation.operationType
                        != SiteVisitSyncOperation.completionOperationType,
                      Self.unresolvedStatuses.contains(operation.status),
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
        let isMedia = specification.operationType
            == SiteVisitSyncOperation.mediaOperationType
        let candidates = operations
            .filter {
                $0.entityType == specification.entityType.rawValue
                    && $0.entityId.lowercased() == canonicalEntityId
                    && $0.operationType != SiteVisitSyncOperation.completionOperationType
                    && (($0.operationType
                            == SiteVisitSyncOperation.mediaOperationType) == isMedia)
                    && Self.unresolvedStatuses.contains($0.status)
            }
            .sorted(by: operationOrder)

        let payload = try encodeOperation(specification.payload)
        if let existing = candidates.last(where: { $0.status != "inProgress" }) {
            if existing.operationType != "create" || specification.operationType == "delete" {
                existing.operationType = specification.operationType
            }
            existing.payload = payload
            existing.changedFields = specification.changedFields.joined(separator: ",")
            existing.priority = min(existing.priority, specification.priority)
            existing.dependsOnId = dependsOnId
            existing.status = "pending"
            existing.retryCount = 0
            existing.lastAttemptedAt = nil
            existing.completedAt = nil
            existing.lastError = nil
            return existing
        }

        let inProgressDependency = candidates.last(where: { $0.status == "inProgress" })
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
        modelContext.insert(operation)
        return operation
    }

    private func belongsToCompany(_ candidate: String) -> Bool {
        candidate.lowercased() == companyId
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
