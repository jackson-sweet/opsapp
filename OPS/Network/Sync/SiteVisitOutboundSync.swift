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
    private let deliverWrite: SiteVisitVersionedSync.Deliver
    private let deliverDiscard: SiteVisitDiscardTransport.Deliver
    private let deliverStage: SiteVisitStageTransport.Deliver

    init(
        repositoryFactory: @escaping RepositoryFactory = { companyId in
            await MainActor.run { SiteVisitRepository(companyId: companyId) }
        },
        mediaManager: SiteVisitMediaSyncManager = SiteVisitMediaSyncManager(),
        sessionUserId: @escaping () -> String? = { SiteVisitAuthorHeal.sessionUserId() },
        deliverWrite: @escaping SiteVisitVersionedSync.Deliver = { try await SiteVisitVersionedSync.deliver(id: $0, command: $1, expectedActorId: $2) },
        deliverDiscard: @escaping SiteVisitDiscardTransport.Deliver = SiteVisitDiscardTransport.deliver,
        deliverStage: @escaping SiteVisitStageTransport.Deliver = SiteVisitStageTransport.deliver
    ) {
        self.repositoryFactory = repositoryFactory
        self.mediaManager = mediaManager
        self.sessionUserId = sessionUserId
        self.deliverWrite = deliverWrite
        self.deliverDiscard = deliverDiscard
        self.deliverStage = deliverStage
    }

    static func isSiteVisitOperation(_ operation: SyncOperation) -> Bool {
        guard let type = SyncEntityType(rawValue: operation.entityType) else {
            return false
        }
        switch type {
        case .siteVisit, .siteVisitArtifact, .siteVisitChecklistAnswer,
             .siteVisitIdentityDraft, .siteVisitType:
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
        if operation.operationType == SiteVisitSyncOperation.discardOperationType { return true }
        if let envelope = try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload),
           operations.contains(where: { candidate in
               candidate.operationType == SiteVisitSyncOperation.discardOperationType && unresolvedStatuses.contains(candidate.status) &&
                   (try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: candidate.payload))?.siteVisitId == envelope.siteVisitId
           }) { return false }
        // A deck_design artifact is a foreign key onto deck_designs. Its deck's
        // own create must land first or Postgres answers 23503 and the artifact
        // parks (bug 6271078d). The editor-open window, where no deck create is
        // queued yet, is `isHeldBehindUnsyncedDeck`'s to answer from the row.
        if let deckId = referencedDeckDesignId(of: operation),
           operations.contains(where: { candidate in
               candidate.entityType == SyncEntityType.deckDesign.rawValue
                   && candidate.operationType == "create"
                   && candidate.entityId.lowercased() == deckId
                   && unresolvedDeckCreateStatuses.contains(candidate.status)
           }) { return false }
        let referencedMedia = Set(SiteVisitVersionedSync.command(operation)?.rows.flatMap { row -> [String] in
            guard case .array(let ids) = row.values["answer_value"]?["artifactIds"] else { return [] }
            return ids.compactMap { $0.string?.lowercased() }
        } ?? [])
        // The URL-bearing metadata write is queued during upload. A static
        // answer->media edge alone cannot prove that remote custody has landed.
        if !referencedMedia.isEmpty && operations.contains(where: { candidate in
            candidate.id != operation.id && unresolvedStatuses.contains(candidate.status) &&
                candidate.entityType == SyncEntityType.siteVisitArtifact.rawValue &&
                referencedMedia.contains(candidate.entityId.lowercased())
        }) { return false }
        // Older persisted graphs put media behind the answer that needs it.
        // Bypass only that inverted edge, retaining parent/initial metadata
        // prerequisites. Neither command payload nor attempt/base is rewritten.
        let repairingMediaOrder = operation.operationType == SiteVisitSyncOperation.mediaOperationType &&
            operations.contains { candidate in
                candidate.entityType == SyncEntityType.siteVisitChecklistAnswer.rawValue &&
                    dependsTransitively(operation, on: candidate, in: operations)
            }
        if repairingMediaOrder {
            let envelope = try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload)
            if operations.contains(where: { candidate in
                guard candidate.id != operation.id, unresolvedStatuses.contains(candidate.status),
                      !dependsTransitively(candidate, on: operation, in: operations) else { return false }
                return (candidate.entityType == SyncEntityType.siteVisit.rawValue &&
                        candidate.entityId.lowercased() == envelope?.siteVisitId &&
                        ["create", "update", "delete"].contains(candidate.operationType)) ||
                    (candidate.entityType == SyncEntityType.siteVisitArtifact.rawValue &&
                        candidate.entityId.lowercased() == operation.entityId.lowercased() &&
                        candidate.operationType != SiteVisitSyncOperation.mediaOperationType)
            }) { return false }
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
           !repairingMediaOrder,
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
                  candidate.operationType != SiteVisitSyncOperation.stageOperationType,
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

    /// A dependency only means anything if it can eventually complete. Walking
    /// `dependsOnId` forward from `proposed` must never arrive back at
    /// `operation`: that pair (or ring) waits on itself forever and the drain
    /// never attempts any member. Returns nil when the edge would close such a
    /// loop, leaving the operation free to run on its own merits. Every writer
    /// of `dependsOnId` funnels through here so the rule has one home.
    static func dependencyWithoutCycle(
        _ proposed: String?,
        for operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> String? {
        guard let proposed, !proposed.isEmpty else { return nil }
        let ownId = operation.id.uuidString.lowercased()
        let operationsById = Dictionary(
            operations.map { ($0.id.uuidString.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var visited = Set<String>()
        var nextId: String? = proposed.lowercased()
        while let id = nextId, !id.isEmpty, visited.insert(id).inserted {
            if id == ownId { return nil }
            nextId = operationsById[id]?.dependsOnId?.lowercased()
        }
        return proposed
    }

    static func shouldContinueDrain(
        readyBeforePass: Set<UUID>,
        readyAfterPass: Set<UUID>
    ) -> Bool {
        !readyAfterPass.isEmpty && readyAfterPass != readyBeforePass
    }

    /// Every status that means "the server does not have this deck yet".
    /// Mirrors `SyncCrossEntityDependency`'s create statuses.
    private static let unresolvedDeckCreateStatuses: Set<String> = [
        "pending", "inProgress", "failed", "parked", "quarantined",
    ]

    /// The deck a metadata write for a `deck_design` artifact points at, or
    /// nil for photos, media uploads, and tombstones.
    private static func referencedDeckDesignId(of operation: SyncOperation) -> String? {
        guard operation.entityType == SyncEntityType.siteVisitArtifact.rawValue,
              operation.operationType != SiteVisitSyncOperation.mediaOperationType,
              operation.operationType != "delete",
              let envelope = try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload),
              let deckId = envelope.deckDesignId?.lowercased(), !deckId.isEmpty else { return nil }
        return deckId
    }

    /// True while a `deck_design` artifact's deck has never reached the server
    /// and nothing in the queue is about to deliver it — the window in which
    /// the deck editor is still open and holds the deck's own create back.
    /// Sending then is a guaranteed `23503`; holding costs one more pass.
    ///
    /// A completed create, a stamped `lastSyncedAt`, or a deck this phone never
    /// marked dirty (not its to deliver) all release the hold. Envelopes queued
    /// before the deck reference travelled in the payload fall back to the
    /// artifact row.
    static func isHeldBehindUnsyncedDeck(
        _ operation: SyncOperation,
        in operations: [SyncOperation],
        context: ModelContext
    ) throws -> Bool {
        guard operation.entityType == SyncEntityType.siteVisitArtifact.rawValue,
              operation.operationType != SiteVisitSyncOperation.mediaOperationType,
              operation.operationType != "delete" else { return false }
        var deckId = referencedDeckDesignId(of: operation)
        if deckId == nil {
            let artifactIds = [operation.entityId.lowercased(), operation.entityId.uppercased()]
            deckId = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(
                predicate: #Predicate { artifactIds.contains($0.id) }
            )).first?.deckDesignId?.lowercased()
        }
        guard let deckId, !deckId.isEmpty else { return false }
        if operations.contains(where: { candidate in
            candidate.entityType == SyncEntityType.deckDesign.rawValue
                && candidate.operationType == "create"
                && candidate.entityId.lowercased() == deckId
                && candidate.status == "completed"
        }) { return false }
        let deckIds = [deckId, deckId.uppercased()]
        guard let deck = try context.fetch(FetchDescriptor<DeckDesign>(
            predicate: #Predicate { deckIds.contains($0.id) }
        )).first else { return false }
        return deck.lastSyncedAt == nil && deck.needsSync
    }

    static func coalesceOperations(
        _ operations: [SyncOperation]
    ) -> [SyncOperation] {
        let ordered = operations.sorted(by: operationOrder)
        var result = ordered.filter {
            SiteVisitVersionedSync.handles($0)
                || $0.operationType == SiteVisitSyncOperation.completionOperationType
                || $0.operationType == SiteVisitSyncOperation.mediaOperationType
                || $0.operationType == SiteVisitSyncOperation.discardOperationType
                || $0.operationType == SiteVisitSyncOperation.stageOperationType
        }
        let crud = ordered.filter {
            !SiteVisitVersionedSync.handles($0)
                && $0.operationType != SiteVisitSyncOperation.completionOperationType
                && $0.operationType != SiteVisitSyncOperation.mediaOperationType
                && $0.operationType != SiteVisitSyncOperation.discardOperationType
                && $0.operationType != SiteVisitSyncOperation.stageOperationType
        }
        let groups = Dictionary(grouping: crud) {
            "\($0.entityType)::\($0.entityId.lowercased())::\($0.siteVisitWriteActorId ?? "unbound")"
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
        activeCompanyId: String,
        isCurrent: () -> Bool = { true },
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        guard Self.isSiteVisitOperation(operation) else { return false }
        if SiteVisitVersionedSync.handles(operation) {
            try await SiteVisitVersionedSync.execute(operation: operation, context: context,
                companyId: activeCompanyId, actorId: sessionUserId(), isCurrent: isCurrent, deliverWrite: deliverWrite, isolation: isolation)
            return true
        }
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

        if operation.operationType == SiteVisitSyncOperation.discardOperationType {
            guard let intent = envelope.discard, let actor = operation.siteVisitWriteActorId,
                  actor == sessionUserId()?.lowercased() else { throw SiteVisitWriteError.legacyPayload }
            if operation.siteVisitWriteAttemptedAt == nil { operation.siteVisitWriteAttemptedAt = Date(); try context.save() }
            let receipt = try await deliverDiscard(operation.id, intent, actor)
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            try SiteVisitDiscardTransport.accept(receipt, operation: operation, intent: intent, actor: actor, context: context)
            return true
        }

        if operation.operationType == SiteVisitSyncOperation.stageOperationType {
            guard let command = envelope.stageCommand,
                  command.companyId.lowercased() == activeCompany,
                  command.siteVisitId.lowercased() == envelope.siteVisitId.lowercased(),
                  command.siteVisitId.lowercased() == envelope.entityId.lowercased(),
                  command.actorId.lowercased() == sessionUserId()?.lowercased() else {
                throw SyncError.serverError(statusCode: 409, message: "ORIGINAL ACCOUNT REQUIRED FOR STAGE DELIVERY")
            }
            guard command.canDeliver else {
                throw SyncError.serverError(statusCode: 409, message: "STAGE REVIEW REQUIRED · OPEN LEAD")
            }
            let result = try await deliverStage(command)
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            try result.validate(for: command)
            // The durable receipt is authoritative for this command only.
            // Never apply a historical stage to a newer local opportunity.
            return true
        }

        if operation.operationType == SiteVisitSyncOperation.mediaOperationType {
            try await mediaManager.uploadPendingMedia(
                artifactId: envelope.entityId,
                mediaOperation: operation,
                context: context,
                isCurrent: isCurrent,
                isolation: isolation
            )
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            return true
        }

        let repository = await repositoryFactory(activeCompany)
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        switch SyncEntityType(rawValue: operation.entityType) {
        case .siteVisit:
            try await executeVisit(
                operation: operation,
                envelope: envelope,
                repository: repository,
                context: context,
                isCurrent: isCurrent,
                isolation: isolation
            )
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        case .siteVisitArtifact:
            try await executeArtifact(
                operation: operation,
                envelope: envelope,
                repository: repository,
                context: context,
                isCurrent: isCurrent,
                isolation: isolation
            )
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        case .siteVisitIdentityDraft:
            try await executeIdentityDraft(
                operation: operation,
                envelope: envelope,
                repository: repository,
                context: context,
                isCurrent: isCurrent,
                isolation: isolation
            )
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        default:
            return false
        }
        return true
    }

    private func executeVisit(
        operation: SyncOperation,
        envelope: SiteVisitSyncOperation.Payload,
        repository: SiteVisitRemoteWriting,
        context: ModelContext,
        isCurrent: () -> Bool,
        isolation: isolated (any Actor)?
    ) async throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        guard let expectedActor = operation.siteVisitWriteActorId, expectedActor == sessionUserId()?.lowercased() else {
            throw SiteVisitWriteError.legacyPayload
        }
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
                completion: completion, expectedActorId: expectedActor
            )
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
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
            guard let deletedAt = visit?.deletedAt else { throw SiteVisitWriteError.legacyPayload }
            try await repository.deleteVisit(envelope.entityId, at: deletedAt, expectedActorId: expectedActor)
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
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
            try CreateSiteVisitDTO(model: visit), expectedActorId: expectedActor
        )
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
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
        context: ModelContext,
        isCurrent: () -> Bool,
        isolation: isolated (any Actor)?
    ) async throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        let artifact = try fetchArtifact(id: envelope.entityId, context: context)
        if operation.operationType == "delete" || artifact?.deletedAt != nil {
            try await repository.softDelete(
                .artifacts,
                id: envelope.entityId,
                at: artifact?.deletedAt ?? Date()
            )
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
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
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
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

    private func executeIdentityDraft(
        operation: SyncOperation,
        envelope: SiteVisitSyncOperation.Payload,
        repository: SiteVisitRemoteWriting,
        context: ModelContext,
        isCurrent: () -> Bool,
        isolation: isolated (any Actor)?
    ) async throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        let draft = try fetchDraft(id: envelope.entityId, context: context)
        if operation.operationType == "delete" || draft?.deletedAt != nil {
            try await repository.softDelete(
                .identityDrafts,
                id: envelope.entityId,
                at: draft?.deletedAt ?? Date()
            )
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
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
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
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
                && $0.operationType != SiteVisitSyncOperation.stageOperationType
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
