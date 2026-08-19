//
//  SiteVisitOutboundSync.swift
//  OPS
//
//  One typed outbound contract shared by the active DataActor and the legacy
//  OutboundProcessor. Operations resolve the current SwiftData snapshot while
//  completion preserves its originally committed idempotent payload.
//

import Foundation
import SwiftData

struct SiteVisitOutboundSync {
    typealias RepositoryFactory = (String) async -> SiteVisitRemoteWriting

    private static let unresolvedStatuses: Set<String> = [
        "pending", "inProgress", "failed", "parked",
    ]

    private let repositoryFactory: RepositoryFactory
    private let mediaManager: SiteVisitMediaSyncManager
    private let sessionUserId: () -> String?

    init(
        repositoryFactory: @escaping RepositoryFactory = { companyId in
            await MainActor.run { SiteVisitRepository(companyId: companyId) }
        },
        mediaManager: SiteVisitMediaSyncManager = SiteVisitMediaSyncManager(),
        sessionUserId: @escaping () -> String? = { SiteVisitAuthorHeal.sessionUserId() }
    ) {
        self.repositoryFactory = repositoryFactory
        self.mediaManager = mediaManager
        self.sessionUserId = sessionUserId
    }

    static func isSiteVisitOperation(_ operation: SyncOperation) -> Bool {
        guard let type = SyncEntityType(rawValue: operation.entityType) else {
            return false
        }
        switch type {
        case .siteVisit, .siteVisitArtifact, .siteVisitChecklistAnswer,
             .siteVisitIdentityDraft:
            return true
        default:
            return false
        }
    }

    static func bypassesGenericCoalescing(_ operation: SyncOperation) -> Bool {
        isSiteVisitOperation(operation)
    }

    static func readyPendingOperationIds(
        in operations: [SyncOperation],
        now: Date = Date()
    ) -> Set<UUID> {
        Set(
            operations.compactMap { operation in
                isReady(operation, in: operations, now: now)
                    ? operation.id
                    : nil
            }
        )
    }

    static func isReady(
        _ operation: SyncOperation,
        in operations: [SyncOperation],
        now: Date = Date()
    ) -> Bool {
        guard isSiteVisitOperation(operation), operation.status == "pending" else {
            return false
        }
        if operation.retryCount > 0,
           let lastAttempt = operation.lastAttemptedAt,
           now < lastAttempt.addingTimeInterval(operation.backoffDelay) {
            return false
        }
        // Sequencing that can never be satisfied must not gate the drain. The
        // 2026-08-19 device wedge held ten ops at zero attempts indefinitely:
        // an artifact update whose dependsOnId was its OWN id, an identity
        // draft likewise, and six checklist answers chained into a closed ring.
        // A dependency chain that walks back to this operation is exactly that
        // deadlock, so it is ignored rather than obeyed.
        if let dependency = operation.dependsOnId,
           !dependency.isEmpty,
           !dependencyIsCompleted(dependency, in: operations),
           !dependsTransitively(operation, on: operation, in: operations) {
            return false
        }

        guard operation.operationType == SiteVisitSyncOperation.completionOperationType,
              let envelope = try? JSONDecoder().decode(
                  SiteVisitSyncOperation.Payload.self,
                  from: operation.payload
              ) else {
            return true
        }

        // A completion is a live queue barrier, not merely a dependency snapshot
        // captured when Save was tapped. Any later child/media/parent write for
        // this visit must settle first. Other completion retries are ignored;
        // the guarded RPC is idempotent and each preserves its own payload.
        // EXCEPT: a candidate whose own dependsOnId chain reaches this
        // completion is sequenced AFTER it and can never settle first — counting
        // it deadlocks the queue (the candidate waits on the completion via its
        // dependency while the completion waits on the candidate via this
        // barrier; nothing ever attempts — the 2026-08-17 device wedge).
        return !operations.contains { candidate in
            guard candidate.id != operation.id,
                  isSiteVisitOperation(candidate),
                  candidate.operationType
                    != SiteVisitSyncOperation.completionOperationType,
                  unresolvedStatuses.contains(candidate.status),
                  !dependsTransitively(candidate, on: operation, in: operations),
                  let candidateEnvelope = try? JSONDecoder().decode(
                      SiteVisitSyncOperation.Payload.self,
                      from: candidate.payload
                  ) else {
                return false
            }
            return candidateEnvelope.siteVisitId.lowercased()
                == envelope.siteVisitId.lowercased()
        }
    }

    /// True when `candidate` is sequenced after `target` by its own dependsOnId
    /// chain. Visited-set guarded so a corrupt dependency cycle terminates
    /// instead of spinning.
    private static func dependsTransitively(
        _ candidate: SyncOperation,
        on target: SyncOperation,
        in operations: [SyncOperation]
    ) -> Bool {
        let operationsById = Dictionary(
            operations.map { ($0.id.uuidString.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let targetId = target.id.uuidString.lowercased()
        var visited = Set<String>()
        var nextId = candidate.dependsOnId?.lowercased()
        while let id = nextId, !id.isEmpty, visited.insert(id).inserted {
            if id == targetId { return true }
            nextId = operationsById[id]?.dependsOnId?.lowercased()
        }
        return false
    }

    static func shouldContinueDrain(
        readyBeforePass: Set<UUID>,
        readyAfterPass: Set<UUID>
    ) -> Bool {
        !readyAfterPass.isEmpty && readyAfterPass != readyBeforePass
    }

    static func coalesceOperations(
        _ operations: [SyncOperation]
    ) -> [SyncOperation] {
        let ordered = operations.sorted(by: operationOrder)
        var result = ordered.filter {
            $0.operationType == SiteVisitSyncOperation.completionOperationType
                || $0.operationType == SiteVisitSyncOperation.mediaOperationType
        }
        let crud = ordered.filter {
            $0.operationType != SiteVisitSyncOperation.completionOperationType
                && $0.operationType != SiteVisitSyncOperation.mediaOperationType
        }
        let groups = Dictionary(grouping: crud) {
            "\($0.entityType)::\($0.entityId.lowercased())"
        }

        for group in groups.values {
            if let deletion = group.last(where: { $0.operationType == "delete" }) {
                markSuperseded(group.filter { $0.id != deletion.id })
                result.append(deletion)
                continue
            }
            if let create = group.first(where: { $0.operationType == "create" }) {
                let superseded = group.filter { $0.id != create.id }
                mergeChangedFields(from: group, into: create)
                markSuperseded(superseded)
                result.append(create)
                continue
            }
            guard let survivor = group.last else { continue }
            mergeChangedFields(from: group, into: survivor)
            markSuperseded(group.filter { $0.id != survivor.id })
            result.append(survivor)
        }

        return result.sorted(by: executionOrder)
    }

    func executeIfHandled(
        operation: SyncOperation,
        context: ModelContext,
        activeCompanyId: String
    ) async throws -> Bool {
        guard Self.isSiteVisitOperation(operation) else { return false }
        let envelope: SiteVisitSyncOperation.Payload
        do {
            envelope = try JSONDecoder().decode(
                SiteVisitSyncOperation.Payload.self,
                from: operation.payload
            )
        } catch {
            throw SyncError.encodingFailed(
                detail: "Invalid site-visit operation envelope for \(operation.id)"
            )
        }

        let activeCompany = activeCompanyId.lowercased()
        guard !activeCompany.isEmpty else { throw SyncError.missingCompanyId }
        guard envelope.companyId.lowercased() == activeCompany else {
            throw SiteVisitRepositoryError.companyMismatch(
                expected: activeCompany,
                received: envelope.companyId.lowercased()
            )
        }
        guard envelope.entityId.lowercased() == operation.entityId.lowercased() else {
            throw SyncError.encodingFailed(
                detail: "Site-visit operation entity id does not match its envelope"
            )
        }

        if operation.operationType == SiteVisitSyncOperation.mediaOperationType {
            try await mediaManager.uploadPendingMedia(
                artifactId: envelope.entityId,
                mediaOperation: operation,
                context: context
            )
            return true
        }

        let repository = await repositoryFactory(activeCompany)
        switch SyncEntityType(rawValue: operation.entityType) {
        case .siteVisit:
            try await executeVisit(
                operation: operation,
                envelope: envelope,
                repository: repository,
                context: context
            )
        case .siteVisitArtifact:
            try await executeArtifact(
                operation: operation,
                envelope: envelope,
                repository: repository,
                context: context
            )
        case .siteVisitChecklistAnswer:
            try await executeChecklistAnswer(
                operation: operation,
                envelope: envelope,
                repository: repository,
                context: context
            )
        case .siteVisitIdentityDraft:
            try await executeIdentityDraft(
                operation: operation,
                envelope: envelope,
                repository: repository,
                context: context
            )
        default:
            return false
        }
        return true
    }

    private func executeVisit(
        operation: SyncOperation,
        envelope: SiteVisitSyncOperation.Payload,
        repository: SiteVisitRemoteWriting,
        context: ModelContext
    ) async throws {
        let visit = try fetchVisit(id: envelope.entityId, context: context)

        if operation.operationType == SiteVisitSyncOperation.completionOperationType {
            guard let completion = envelope.completion else {
                throw SyncError.encodingFailed(
                    detail: "Site-visit completion is missing its committed payload"
                )
            }
            guard let visit else { return }
            try requireCompany(visit.companyId, expected: envelope.companyId)
            let response = try await repository.completeSiteVisit(
                envelope.siteVisitId,
                completion: completion
            )
            try context.transaction {
                visit.loggedActivityId = response.activityId
                visit.lastSyncedAt = response.visit.updatedAt ?? Date()
                if !hasNewerCRUDOperation(
                    entityType: .siteVisit,
                    entityId: visit.id,
                    excluding: operation,
                    context: context
                ) {
                    visit.needsSync = false
                }
            }
            return
        }

        if operation.operationType == "delete" || visit?.deletedAt != nil {
            try await repository.softDelete(
                .visits,
                id: envelope.entityId,
                at: visit?.deletedAt ?? Date()
            )
            if let visit {
                try context.transaction {
                    visit.lastSyncedAt = Date()
                    visit.needsSync = false
                }
            }
            return
        }
        guard let visit else { return }
        try requireCompany(visit.companyId, expected: envelope.companyId)
        try healAuthorIfNeeded(visit, parentVisitId: nil, context: context)
        let response = try await repository.upsertVisit(
            try CreateSiteVisitDTO(model: visit)
        )
        try context.transaction {
            visit.loggedActivityId = response.activityId ?? visit.loggedActivityId
            visit.lastSyncedAt = response.updatedAt ?? Date()
            if !hasNewerCRUDOperation(
                entityType: .siteVisit,
                entityId: visit.id,
                excluding: operation,
                context: context
            ) {
                visit.needsSync = false
            }
        }
    }

    private func executeArtifact(
        operation: SyncOperation,
        envelope: SiteVisitSyncOperation.Payload,
        repository: SiteVisitRemoteWriting,
        context: ModelContext
    ) async throws {
        let artifact = try fetchArtifact(id: envelope.entityId, context: context)
        if operation.operationType == "delete" || artifact?.deletedAt != nil {
            try await repository.softDelete(
                .artifacts,
                id: envelope.entityId,
                at: artifact?.deletedAt ?? Date()
            )
            if let artifact {
                try markSynced(artifact, operation: operation, context: context)
            }
            return
        }
        guard let artifact else { return }
        try requireCompany(artifact.companyId, expected: envelope.companyId)
        try healAuthorIfNeeded(
            artifact,
            parentVisitId: envelope.siteVisitId,
            context: context
        )
        let response = try await repository.upsertArtifact(
            try UpsertSiteVisitArtifactDTO(model: artifact)
        )
        try context.transaction {
            artifact.lastSyncedAt = response.updatedAt
            if !hasNewerCRUDOperation(
                entityType: .siteVisitArtifact,
                entityId: artifact.id,
                excluding: operation,
                context: context
            ) {
                artifact.needsSync = false
            }
        }
    }

    private func executeChecklistAnswer(
        operation: SyncOperation,
        envelope: SiteVisitSyncOperation.Payload,
        repository: SiteVisitRemoteWriting,
        context: ModelContext
    ) async throws {
        let answer = try fetchAnswer(id: envelope.entityId, context: context)
        if operation.operationType == "delete" || answer?.deletedAt != nil {
            try await repository.softDelete(
                .checklistAnswers,
                id: envelope.entityId,
                at: answer?.deletedAt ?? Date()
            )
            if let answer {
                try markSynced(answer, operation: operation, context: context)
            }
            return
        }
        guard let answer else { return }
        try requireCompany(answer.companyId, expected: envelope.companyId)
        try healAuthorIfNeeded(
            answer,
            parentVisitId: envelope.siteVisitId,
            context: context
        )
        let response = try await repository.upsertChecklistAnswer(
            try UpsertSiteVisitChecklistAnswerDTO(model: answer)
        )
        try context.transaction {
            answer.lastSyncedAt = response.updatedAt
            if !hasNewerCRUDOperation(
                entityType: .siteVisitChecklistAnswer,
                entityId: answer.id,
                excluding: operation,
                context: context
            ) {
                answer.needsSync = false
            }
        }
    }

    private func executeIdentityDraft(
        operation: SyncOperation,
        envelope: SiteVisitSyncOperation.Payload,
        repository: SiteVisitRemoteWriting,
        context: ModelContext
    ) async throws {
        let draft = try fetchDraft(id: envelope.entityId, context: context)
        if operation.operationType == "delete" || draft?.deletedAt != nil {
            try await repository.softDelete(
                .identityDrafts,
                id: envelope.entityId,
                at: draft?.deletedAt ?? Date()
            )
            if let draft {
                try markSynced(draft, operation: operation, context: context)
            }
            return
        }
        guard let draft else { return }
        try requireCompany(draft.companyId, expected: envelope.companyId)
        try healAuthorIfNeeded(
            draft,
            parentVisitId: envelope.siteVisitId,
            context: context
        )
        let response = try await repository.upsertIdentityDraft(
            try UpsertSiteVisitIdentityDraftDTO(model: draft)
        )
        try context.transaction {
            draft.lastSyncedAt = response.updatedAt
            if !hasNewerCRUDOperation(
                entityType: .siteVisitIdentityDraft,
                entityId: draft.id,
                excluding: operation,
                context: context
            ) {
                draft.needsSync = false
            }
        }
    }

    // MARK: - Authorship heal
    //
    // `createdBy` arrived with the V19→V20 lightweight migration, which could only
    // default every existing row — parents included — to nil. The wire contract
    // requires it, so those rows threw at payload build BEFORE any network call,
    // classified transient, burned the retry budget, and were revived by the launch
    // sweep on every single launch. Worse, an unresolved child is a live barrier in
    // `isReady`, so its visit's completion notes never sent (bug 70db7ed6).
    //
    // Resolve the author from the parent visit — else the operator holding this
    // phone — and persist it, so the row is whole from here on instead of rebuilding
    // the same doomed payload forever.

    /// `parentVisitId` is nil for the visit itself — it has no parent to inherit
    /// from, so it resolves straight to the operator on this phone.
    ///
    /// Writes ONLY `createdBy`. Touching `needsSync`/`updatedAt` here would enqueue
    /// a fresh write for every legacy row on the device at once.
    private func healAuthorIfNeeded(
        _ row: SiteVisitAuthoredRow,
        parentVisitId: String?,
        context: ModelContext
    ) throws {
        guard SiteVisitAuthorHeal.needsAuthor(row.createdBy) else { return }
        let parentAuthor = try parentVisitId.flatMap {
            try fetchVisit(id: $0, context: context)
        }?.createdBy
        guard let resolved = SiteVisitAuthorHeal.resolvedAuthor(
            current: row.createdBy,
            parentVisitAuthor: parentAuthor,
            sessionUserId: sessionUserId()
        ) else { return }
        try context.transaction { row.createdBy = resolved }
    }

    private func markSynced(
        _ artifact: SiteVisitCaptureArtifact,
        operation: SyncOperation,
        context: ModelContext
    ) throws {
        try context.transaction {
            artifact.lastSyncedAt = Date()
            if !hasNewerCRUDOperation(
                entityType: .siteVisitArtifact,
                entityId: artifact.id,
                excluding: operation,
                context: context
            ) {
                artifact.needsSync = false
            }
        }
    }

    private func markSynced(
        _ answer: SiteVisitChecklistAnswer,
        operation: SyncOperation,
        context: ModelContext
    ) throws {
        try context.transaction {
            answer.lastSyncedAt = Date()
            if !hasNewerCRUDOperation(
                entityType: .siteVisitChecklistAnswer,
                entityId: answer.id,
                excluding: operation,
                context: context
            ) {
                answer.needsSync = false
            }
        }
    }

    private func markSynced(
        _ draft: SiteVisitIdentityDraft,
        operation: SyncOperation,
        context: ModelContext
    ) throws {
        try context.transaction {
            draft.lastSyncedAt = Date()
            if !hasNewerCRUDOperation(
                entityType: .siteVisitIdentityDraft,
                entityId: draft.id,
                excluding: operation,
                context: context
            ) {
                draft.needsSync = false
            }
        }
    }

    private func hasNewerCRUDOperation(
        entityType: SyncEntityType,
        entityId: String,
        excluding operation: SyncOperation,
        context: ModelContext
    ) -> Bool {
        let rawType = entityType.rawValue
        let exact = entityId
        let lower = entityId.lowercased()
        let upper = entityId.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate {
                $0.entityType == rawType
                    && ($0.entityId == exact
                        || $0.entityId == lower
                        || $0.entityId == upper)
            }
        )
        let operations = (try? context.fetch(descriptor)) ?? []
        return operations.contains {
            $0.id != operation.id
                && $0.operationType
                    != SiteVisitSyncOperation.completionOperationType
                && $0.operationType != SiteVisitSyncOperation.mediaOperationType
                && Self.unresolvedStatuses.contains($0.status)
        }
    }

    // MARK: - Single-row lookups
    //
    // Predicate-scoped and fetchLimit-1 on purpose. A whole-table fetch plus an
    // in-memory id filter registers every site-visit row in the actor's context
    // on every single operation; interleaved with this drain's unique-id
    // `context.transaction` saves, that desynced the context's registration map
    // and hit a fatal "Duplicate registration attempt" (bug 3eef6ad7).
    //
    // Ids here are only ever all-lowercase (model inits lowercase them, and
    // Postgres lowercases every uuid) or all-uppercase (`UUID().uuidString`), so
    // three candidates cover the space. There is deliberately NO table-scan
    // fallback — that would reintroduce the crash.

    private func fetchVisit(id: String, context: ModelContext) throws -> SiteVisit? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchArtifact(
        id: String,
        context: ModelContext
    ) throws -> SiteVisitCaptureArtifact? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchAnswer(
        id: String,
        context: ModelContext
    ) throws -> SiteVisitChecklistAnswer? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchDraft(
        id: String,
        context: ModelContext
    ) throws -> SiteVisitIdentityDraft? {
        let exact = id
        let lower = id.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate { $0.id == exact || $0.id == lower || $0.id == upper }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func requireCompany(_ actual: String, expected: String) throws {
        guard actual.lowercased() == expected.lowercased() else {
            throw SiteVisitRepositoryError.companyMismatch(
                expected: expected.lowercased(),
                received: actual.lowercased()
            )
        }
    }

    private static func dependencyIsCompleted(
        _ dependency: String,
        in operations: [SyncOperation]
    ) -> Bool {
        guard let dependencyId = UUID(uuidString: dependency) else { return false }
        return operations.contains {
            $0.id == dependencyId && $0.status == "completed"
        }
    }

    private static func mergeChangedFields(
        from operations: [SyncOperation],
        into survivor: SyncOperation
    ) {
        survivor.changedFields = Set(
            operations.flatMap { $0.getChangedFields() }
        ).sorted().joined(separator: ",")
    }

    private static func markSuperseded(_ operations: [SyncOperation]) {
        let now = Date()
        for operation in operations {
            operation.status = "completed"
            operation.completedAt = now
        }
    }

    private static func operationOrder(
        _ lhs: SyncOperation,
        _ rhs: SyncOperation
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func executionOrder(
        _ lhs: SyncOperation,
        _ rhs: SyncOperation
    ) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return operationOrder(lhs, rhs)
    }
}
