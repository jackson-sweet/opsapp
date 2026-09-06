//
//  OutboundProcessor.swift
//  OPS
//
//  Processes pending SyncOperations, coalesces redundant ops,
//  and pushes changes to Supabase via the repository layer.
//  Standalone worker — does not depend on SyncEngine or other processors.
//

import Foundation
import SwiftData
import Supabase

// MARK: - OutboundProcessor

@MainActor
final class OutboundProcessor {

    private let projectTaskSyncingFactory: (String) -> ProjectTaskSyncing

    init(projectTaskSyncingFactory: @escaping (String) -> ProjectTaskSyncing = { TaskRepository(companyId: $0) }) {
        self.projectTaskSyncingFactory = projectTaskSyncingFactory
    }

    // MARK: - Main Entry Point

    /// Fetches all pending SyncOperations, coalesces them, and pushes each to Supabase.
    /// Operations that are in backoff or have unmet dependencies are skipped.
    func processPendingOperations(
        context: ModelContext,
        connectivity: ConnectivityManager
    ) async {
        var shouldContinueDrain: Bool
        repeat {
            let mentionReadyBeforePass = readyPendingMentionOperationIds(
                context: context
            )
            let taskTypeReadyBeforePass =
                readyPendingTaskTypePipelineOperationIds(
                    context: context
                )
            let siteVisitReadyBeforePass =
                readyPendingSiteVisitOperationIds(context: context)
            let crossEntityReadyBeforePass =
                readyCrossEntityOperationIds(context: context)
            await processPendingOperationsPass(
                context: context,
                connectivity: connectivity
            )
            let mentionReadyAfterPass = readyPendingMentionOperationIds(
                context: context
            )
            let taskTypeReadyAfterPass =
                readyPendingTaskTypePipelineOperationIds(
                    context: context
                )
            let siteVisitReadyAfterPass =
                readyPendingSiteVisitOperationIds(context: context)
            let crossEntityReadyAfterPass =
                readyCrossEntityOperationIds(context: context)
            let shouldContinueMentionDrain = ProjectNoteMentionEditSync
                .shouldContinueDrain(
                    readyBeforePass: mentionReadyBeforePass,
                    readyAfterPass: mentionReadyAfterPass
                )
            let shouldContinueTaskTypeDrain =
                !taskTypeReadyAfterPass.isEmpty
                    && taskTypeReadyAfterPass
                        != taskTypeReadyBeforePass
            let shouldContinueSiteVisitDrain = SiteVisitOutboundSync
                .shouldContinueDrain(
                    readyBeforePass: siteVisitReadyBeforePass,
                    readyAfterPass: siteVisitReadyAfterPass
                )
            let shouldContinueCrossEntityDrain = SyncCrossEntityDependency
                .shouldContinueDrain(
                    readyBeforePass: crossEntityReadyBeforePass,
                    readyAfterPass: crossEntityReadyAfterPass
                )
            shouldContinueDrain =
                shouldContinueMentionDrain
                    || shouldContinueTaskTypeDrain
                    || shouldContinueSiteVisitDrain
                    || shouldContinueCrossEntityDrain
            if shouldContinueCrossEntityDrain {
                print(
                    "[OutboundProcessor] A referenced create landed — "
                        + "continuing drain to push the work waiting on it"
                )
            } else if shouldContinueTaskTypeDrain {
                print(
                    "[OutboundProcessor] Task-type ordering released "
                        + "more local work — continuing drain"
                )
            } else if shouldContinueSiteVisitDrain {
                print("[OutboundProcessor] Site-visit dependency released — continuing drain")
            } else if shouldContinueMentionDrain {
                print("[OutboundProcessor] Mention dependency released — continuing local-context drain")
            } else if !mentionReadyAfterPass.isEmpty,
                      mentionReadyAfterPass == mentionReadyBeforePass {
                print("[OutboundProcessor] Mention drain made no progress — stopping until the next sync trigger")
            }
        } while shouldContinueDrain
    }

    private func processPendingOperationsPass(
        context: ModelContext,
        connectivity: ConnectivityManager
    ) async {
        guard await connectivity.shouldAttemptSync else {
            print("[OutboundProcessor] Skipping — connectivity says do not sync")
            return
        }

        // 0. Hand back work parked before the row it references existed. Runs
        //    ahead of the fetch so a released op joins THIS pass.
        releaseCrossEntityMisparkedOperations(context: context)

        // 1. Fetch pending operations sorted by priority ASC, createdAt ASC
        let pending: [SyncOperation]
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> { $0.status == "pending" },
                sortBy: [
                    SortDescriptor(\.priority, order: .forward),
                    SortDescriptor(\.createdAt, order: .forward)
                ]
            )
            pending = try context.fetch(descriptor)
        } catch {
            print("[OutboundProcessor] Failed to fetch pending operations: \(error)")
            return
        }

        guard !pending.isEmpty else {
            print("[OutboundProcessor] No pending operations")
            return
        }

        print("[OutboundProcessor] Found \(pending.count) pending operation(s)")

        // 2. Filter out operations in backoff or with unmet dependencies
        let now = Date()
        let allOperations = (
            try? context.fetch(FetchDescriptor<SyncOperation>())
        ) ?? pending
        let eligible = pending.filter { op in
            guard !DeckEditingSessionRegistry.shared.isHeld(
                entityType: op.entityType, entityId: op.entityId
            ) else { return false }
            // Backoff check: if retried before, ensure enough time has elapsed since last attempt
            if op.retryCount > 0, let lastAttempt = op.lastAttemptedAt {
                let earliestRetry = lastAttempt.addingTimeInterval(op.backoffDelay)
                if now < earliestRetry {
                    print("[OutboundProcessor] Skipping \(op.entityType) \(op.entityId) — in backoff (retry \(op.retryCount), delay \(op.backoffDelay)s)")
                    return false
                }
            }

            // Dependency check
            if let depId = op.dependsOnId, !depId.isEmpty {
                let depCompleted = pending.contains { $0.id.uuidString == depId && $0.status == "completed" }
                if !depCompleted {
                    // Also check if the dependency was already completed (not in pending list)
                    let isDepCompleted = isDependencyCompleted(depId, context: context)
                    if !isDepCompleted {
                        print("[OutboundProcessor] Skipping \(op.entityType) \(op.entityId) — dependency \(depId) not completed")
                        return false
                    }
                }
            }

            if TaskTypeMutationSync.isBlockedByUnresolvedMutation(
                op,
                in: allOperations
            ) {
                print(
                    "[OutboundProcessor] Holding later write "
                        + "\(op.entityType) \(op.entityId) "
                        + "behind an unresolved task-type mutation"
                )
                return false
            }

            if SiteVisitOutboundSync.isSiteVisitOperation(op),
               !SiteVisitOutboundSync.isReady(op, in: allOperations, now: now) {
                print(
                    "[OutboundProcessor] Holding site-visit work behind its live graph barrier: "
                        + "\(op.operationType) \(op.entityId)"
                )
                return false
            }

            // Create ordering. Two failures, one gate:
            //   * an op referencing a row whose create has not reached the
            //     server cannot pass that server's RLS check, and the rejection
            //     classifies permanent — it would park forever (bug 06f68200);
            //   * an op against a row whose OWN create has not reached the
            //     server matches nothing, and PostgREST answers a zero-row
            //     PATCH with 200 — the edit retires as delivered and is gone
            //     (bug 2e58c85b).
            // Hold either; the create releases it.
            if SyncCrossEntityDependency.isHeld(op, in: allOperations) {
                print(
                    "[OutboundProcessor] Holding \(op.entityType) \(op.entityId) "
                        + "behind an unsynced create"
                )
                return false
            }

            return true
        }

        // 3. Coalesce
        let coalesced = coalesceOperations(eligible)
        print("[OutboundProcessor] Coalesced \(eligible.count) → \(coalesced.count) operation(s)")

        // 4. Execute each independently
        for op in coalesced {
            do {
                try await executeOperation(op, context: context)
            } catch {
                let classified = classifySyncError(error)
                print("[OutboundProcessor] Operation failed for \(op.entityType) \(op.entityId): \(classified.localizedDescription)")
                // Error handling already done inside executeOperation
            }
        }

        // 5. Save context
        do {
            try context.save()
            print("[OutboundProcessor] Context saved")
        } catch {
            print("[OutboundProcessor] Failed to save context: \(error)")
        }
    }

    private func readyPendingMentionOperationIds(
        context: ModelContext,
        now: Date = Date()
    ) -> Set<UUID> {
        let operations = (
            try? context.fetch(FetchDescriptor<SyncOperation>())
        ) ?? []
        return ProjectNoteMentionEditSync.readyPendingOperationIds(
            in: operations,
            now: now
        )
    }

    private func readyPendingTaskTypePipelineOperationIds(
        context: ModelContext,
        now: Date = Date()
    ) -> Set<UUID> {
        let operations = (
            try? context.fetch(FetchDescriptor<SyncOperation>())
        ) ?? []
        return TaskTypeMutationSync.readyPendingPipelineOperationIds(
            in: operations,
            now: now
        )
    }

    /// Cross-entity readiness snapshot. Predicate-free by necessity: a
    /// `#Predicate` fetch of `SyncOperation` traps against a table that has
    /// never held a row, and this runs on every pass.
    private func readyCrossEntityOperationIds(
        context: ModelContext
    ) -> Set<UUID> {
        let operations = (
            try? context.fetch(FetchDescriptor<SyncOperation>())
        ) ?? []
        return SyncCrossEntityDependency.readyOperationIds(in: operations)
    }

    /// Returns ops parked by the cross-entity race whose blocking create has
    /// since landed to `pending`. Single-shot per op by construction — see
    /// `SyncCrossEntityDependency` for why this cannot loop.
    private func releaseCrossEntityMisparkedOperations(context: ModelContext) {
        let operations = (
            try? context.fetch(FetchDescriptor<SyncOperation>())
        ) ?? []
        guard !operations.isEmpty else { return }
        do {
            var released: [SyncOperation] = []
            try context.transaction {
                released = SyncCrossEntityDependency.releaseParkedOperations(
                    in: operations
                )
            }
            if !released.isEmpty {
                print(
                    "[OutboundProcessor] Released \(released.count) operation(s) "
                        + "parked before the create they reference landed"
                )
            }
        } catch {
            print(
                "[OutboundProcessor] Failed to release cross-entity parked work: \(error)"
            )
        }
    }

    private func readyPendingSiteVisitOperationIds(
        context: ModelContext,
        now: Date = Date()
    ) -> Set<UUID> {
        let operations = (
            try? context.fetch(FetchDescriptor<SyncOperation>())
        ) ?? []
        return SiteVisitOutboundSync.readyPendingOperationIds(
            in: operations,
            now: now
        )
    }

    // MARK: - Dependency Check

    /// Checks whether a dependency operation (by UUID string) has status "completed" in the store.
    private func isDependencyCompleted(_ dependsOnId: String, context: ModelContext) -> Bool {
        guard let depUUID = UUID(uuidString: dependsOnId) else { return false }
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> { op in
                    op.id == depUUID && op.status == "completed"
                }
            )
            let results = try context.fetch(descriptor)
            return !results.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Coalescing

    /// Groups operations by (entityType, entityId) and merges redundant ops.
    ///
    /// Rules:
    /// - "create" + subsequent "update"s → merge changedFields into the create, keep latest payload
    /// - "delete" discards all preceding creates/updates for the same entity
    /// - Multiple "update"s → merge changedFields, keep latest payload, produce one operation
    /// - "linkOpportunity" (deckDesign) merges INTO a create in the same group (the
    ///   create legally carries opportunity_id for a linked INSERT); with no create
    ///   present it is peeled out to execute standalone, never merged into the
    ///   all-updates survivor (which would lose the link or the edit).
    func coalesceOperations(_ operations: [SyncOperation]) -> [SyncOperation] {
        // Group by (entityType, entityId)
        var groups: [String: [SyncOperation]] = [:]
        for op in operations
        where !ProjectNoteMentionEditSync.bypassesGenericCoalescing(op)
            && !TaskTypeMutationSync.bypassesGenericCoalescing(op)
            && !SiteVisitOutboundSync.bypassesGenericCoalescing(op) {
            let key = "\(op.entityType)::\(op.entityId)"
            groups[key, default: []].append(op)
        }

        // Mention edits and their persisted-event dispatches form an explicit
        // dependency chain. Coalescing them would discard immutable event IDs
        // or mark a dependency completed without executing its RPC.
        var result = operations.filter {
            ProjectNoteMentionEditSync.bypassesGenericCoalescing($0)
                || TaskTypeMutationSync.bypassesGenericCoalescing($0)
        }
        result.removeAll(where: SiteVisitOutboundSync.isSiteVisitOperation)
        result.append(
            contentsOf: SiteVisitOutboundSync.coalesceOperations(
                operations.filter(SiteVisitOutboundSync.isSiteVisitOperation)
            )
        )

        for (_, groupOps) in groups {
            guard !groupOps.isEmpty else { continue }
            var ops = groupOps

            // Single operation — no coalescing needed
            if ops.count == 1 {
                result.append(ops[0])
                continue
            }

            // Check if there's a delete — it wins over everything
            if let deleteOp = ops.last(where: { $0.operationType == "delete" }) {
                // Mark all preceding ops as completed (they're superseded)
                for op in ops where op.id != deleteOp.id {
                    op.status = "completed"
                    op.completedAt = Date()
                }
                result.append(deleteOp)
                continue
            }

            // linkOpportunity (deckDesign) is only safe to merge INTO a create,
            // whose payload legally carries opportunity_id for a linked INSERT. In
            // an all-updates group a merged link would either lose opportunity_id to
            // the update path's strip (lost link) or drop the survivor's edit fields
            // when the link handler runs (lost edit). With no create in the group,
            // peel every link op out to execute standalone — the RPC is idempotent.
            if !ops.contains(where: { $0.operationType == "create" }) {
                let linkOps = ops.filter { $0.operationType == "linkOpportunity" }
                if !linkOps.isEmpty {
                    result.append(contentsOf: linkOps)
                    ops.removeAll { $0.operationType == "linkOpportunity" }
                    if ops.isEmpty { continue }
                }
            }

            // Check if there's a create
            if let createOp = ops.first(where: { $0.operationType == "create" }) {
                // Merge all subsequent updates into the create
                var allChangedFields = Set(createOp.getChangedFields())
                var mergedPayload = createOp.payload

                for op in ops where op.id != createOp.id {
                    let fields = op.getChangedFields()
                    allChangedFields.formUnion(fields)
                    if let encoded = mergePayloads(base: mergedPayload, overlay: op.payload) {
                        mergedPayload = encoded
                    }
                    // Mark the update as completed (superseded)
                    op.status = "completed"
                    op.completedAt = Date()
                }

                createOp.payload = mergedPayload
                createOp.changedFields = Array(allChangedFields).joined(separator: ",")
                result.append(createOp)
                continue
            }

            // All updates — merge into one
            var allChangedFields = Set<String>()
            for op in ops {
                allChangedFields.formUnion(op.getChangedFields())
            }
            // Keep the last update (most recent payload)
            let survivor = ops.last!
            survivor.changedFields = Array(allChangedFields).joined(separator: ",")

            // Merge all payloads into the survivor
            var mergedPayloadDict: [String: Any] = [:]
            for op in ops {
                if let dict = decodePayload(op.payload) {
                    for (key, value) in dict {
                        mergedPayloadDict[key] = value
                    }
                }
                if op.id != survivor.id {
                    op.status = "completed"
                    op.completedAt = Date()
                }
            }
            if let encoded = encodePayload(mergedPayloadDict) {
                survivor.payload = encoded
            }

            result.append(survivor)
        }

        // Sort result by priority ASC, createdAt ASC to maintain ordering
        return result.sorted { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.createdAt < b.createdAt
        }
    }

    // MARK: - Per-Operation Execution

    /// Executes a single SyncOperation against Supabase.
    /// Sets status to "inProgress" before attempting, and updates status/retryCount on completion or failure.
    func executeOperation(_ operation: SyncOperation, context: ModelContext) async throws {
        guard !DeckEditingSessionRegistry.shared.isHeld(
            entityType: operation.entityType, entityId: operation.entityId
        ) else { return }
        guard try claimForExecution(
            operation,
            context: context
        ) else { return }
        defer {
            ProjectNoteMentionQueueCoordinator.shared.release(
                operationId: operation.id
            )
        }
        print("[OutboundProcessor] Pushing \(operation.entityType) \(operation.entityId)...")

        do {
            let activeCompanyId = UserDefaults.standard.string(
                forKey: "currentUserCompanyId"
            ) ?? ""
            let handledSiteVisit = try await SiteVisitOutboundSync()
                .executeIfHandled(
                    operation: operation,
                    context: context,
                    activeCompanyId: activeCompanyId
                )
            if !handledSiteVisit {
                guard let payloadDict = decodePayload(operation.payload) else {
                    throw SyncError.decodingFailed(detail: "Could not decode payload for \(operation.entityType) \(operation.entityId)")
                }
                try await routeToRepository(
                    entityType: operation.entityType,
                    entityId: operation.entityId,
                    operationType: operation.operationType,
                    payload: payloadDict
                )
            }

        } catch {
            let classified = classifySyncError(error)

            // Idempotency: if this is a `create` retry and the server says the row
            // already exists (PK unique-constraint violation), the first push
            // succeeded server-side but the response was lost — network blip,
            // app killed mid-flight, etc. Mark the op completed instead of
            // retrying forever against a server that already has the row.
            // See `errorIndicatesPrimaryKeyViolation` for the detection contract.
            // MUST run before disposition routing — a 23505 classifies permanent.
            if operation.operationType == "create",
               errorIndicatesPrimaryKeyViolation(error) {
                operation.status = "completed"
                operation.completedAt = Date()
                operation.lastError = nil
                print("[OutboundProcessor] create \(operation.entityType) \(operation.entityId) — server already has row (PK conflict on retry); marking completed")
                return
            }

            // Idempotency, natural-key form (bug ba75732a). Two failures prove
            // the server already holds the intended end state, and parking them
            // strands real work forever:
            //   * a site-visit photo create that hits the
            //     (company_id, project_id, site_visit_id, url) dedupe index —
            //     the opportunity-conversion RPC inserted that photo
            //     transactionally under a server-generated id;
            //   * a task update refused with task_not_found against a task the
            //     server has soft-deleted — the tombstone is the newer truth.
            // MUST run before disposition routing: both classify permanent.
            // Both descriptions are searched: `classified` is what gets stored in
            // `lastError` (and therefore what the parked sweep re-reads), while
            // the raw error is what the live path holds.
            if let reconciliation = SyncOperationReconcilers.kind(
                operationType: operation.operationType,
                entityType: operation.entityType,
                errorDescription: "\(error.localizedDescription) \(classified.localizedDescription)"
            ), await reconcile(operation, as: reconciliation, context: context) {
                return
            }

            // Classify + apply the SHARED failure policy (single source of truth
            // for the state transition — mirrored byte-for-byte with DataActor).
            // Permanent rejections park immediately (no retry consumed); transient
            // failures keep the existing retry budget; auth routes to re-auth.
            let disposition = SyncErrorClassifier.disposition(for: error)
            let outcome = SyncOperationFailurePolicy.apply(
                disposition,
                to: operation,
                errorDescription: classified.localizedDescription
            )

            switch outcome {
            case .authExpired:
                print("[OutboundProcessor] Auth expired — stopping sync for \(operation.entityType) \(operation.entityId)")
                AnalyticsService.shared.track(
                    eventType: .error,
                    eventName: "sync_failed",
                    properties: [
                        "error_type": "auth_expired",
                        "retry_count": operation.retryCount,
                        "entity_type": operation.entityType,
                        "operation_type": operation.operationType
                    ]
                )
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .syncAuthExpired,
                        object: nil
                    )
                }

            case .parked:
                var wasSuperseded = false
                var retiredCreateDelete = false
                var restoredTaskTypeDelete = false
                var taskTypeMutationRollback =
                    TaskTypeMutationSync.RejectionRollbackResult.none
                do {
                    try context.transaction {
                        let operations = try context.fetch(
                            FetchDescriptor<SyncOperation>()
                        )
                        wasSuperseded = ProjectNoteMentionEditSync
                            .supersedeParkedUpdatesReplacedByLaterEdits(
                                in: operations
                            )
                        retiredCreateDelete = ProjectNoteMentionEditSync
                            .retireParkedCreateWithQueuedDelete(
                                operation,
                                in: operations
                            )
                        if retiredCreateDelete {
                            let noteId = operation.entityId.lowercased()
                            if let note = try ProjectNoteMentionEditSync
                                .fetchProjectNote(
                                    matching: noteId,
                                    in: context
                                ) {
                                note.needsSync = false
                            }
                        }
                        restoredTaskTypeDelete = try TaskTypeMutationSync
                            .restoreRejectedDirectDelete(
                                operation,
                                in: context
                            )
                        taskTypeMutationRollback = try TaskTypeMutationSync
                            .rollbackRejectedMutation(
                                operation,
                                in: context
                            )
                    }
                } catch {
                    print(
                        "[OutboundProcessor] Failed parked-chain reconciliation: \(error)"
                    )
                }
                if taskTypeMutationRollback.didRollback {
                    print(
                        "[OutboundProcessor] Rolled back rejected task type "
                            + "mutation chain: "
                            + taskTypeMutationRollback.restoredCommandIds
                                .joined(separator: ",")
                    )
                    if taskTypeMutationRollback.reminderStateChanged {
                        NotificationCenter.default.post(
                            name: .taskTypeMutationRolledBack,
                            object: nil
                        )
                    }
                } else if restoredTaskTypeDelete {
                    print(
                        "[OutboundProcessor] Restored task type "
                            + operation.entityId
                            + " after the server rejected its delete"
                    )
                } else if retiredCreateDelete {
                    print(
                        "[OutboundProcessor] Retired local-only "
                            + "project-note create/delete chain "
                            + operation.entityId
                    )
                } else if wasSuperseded {
                    print("[OutboundProcessor] Retired rejected project-note edit \(operation.entityId) — later authoritative replacement released")
                } else {
                    print("[OutboundProcessor] Parked \(operation.entityType) \(operation.entityId) — server rejected it (permanent); will not auto-retry: \(classified.localizedDescription)")
                }
                AnalyticsService.shared.track(
                    eventType: .error,
                    eventName: "sync_parked",
                    properties: [
                        "error_type": classified.localizedDescription,
                        "retry_count": operation.retryCount,
                        "entity_type": operation.entityType,
                        "operation_type": operation.operationType
                    ]
                )

            case .exhausted:
                print("[OutboundProcessor] Permanently failed \(operation.entityType) \(operation.entityId) after \(operation.retryCount) retries")
                AnalyticsService.shared.track(
                    eventType: .error,
                    eventName: "sync_failed",
                    properties: [
                        "error_type": classified.localizedDescription,
                        "retry_count": operation.retryCount,
                        "entity_type": operation.entityType,
                        "operation_type": operation.operationType
                    ]
                )

            case .retryScheduled:
                print("[OutboundProcessor] Retry \(operation.retryCount)/\(SyncOperationFailurePolicy.maxRetries) for \(operation.entityType) \(operation.entityId): \(classified.localizedDescription)")
            }

            throw error
        }

        // Push confirmed. Persisting the confirmation is a LOCAL concern: it
        // sits outside the push's `do` so a store throw can never be classified
        // as a server rejection, consume retry budget, or park an operation the
        // server already accepted (bug ba75732a class). If it throws the op stays
        // `inProgress` and SyncEngine.reenqueueRecoverableOperations revives it —
        // the idempotency and reconciler paths absorb the re-push.
        do {
            // Success. Complete the dependent field guards in the same local
            // transaction so the authoritative pull can reconcile immediately.
            let completedAt = Date()
            try context.transaction {
                operation.status = "completed"
                operation.completedAt = completedAt
                try TaskTypeMutationSync.completeProtectionOperations(
                    for: operation,
                    in: context,
                    completedAt: completedAt
                )
                // Confirmed server success is the ONLY thing that clears a
                // calendar row's dirty flag — and it commits with the
                // completion, because that flag is what keeps the inbound merge
                // off a locally-edited row (bug ef5a69e6).
                try CalendarUserEventOutboundSync.clearNeedsSyncOnCompletion(
                    for: operation,
                    in: context
                )
                // Confirmed server success is also the only thing that may move
                // a deck design's merge base — the baseline the inbound merge
                // compares against to decide whether a snapshot is a genuine
                // remote edit or an echo of this push (bug 9f4aeaf8).
                try DeckDesignServerMerge.recordConfirmedPush(
                    for: operation,
                    in: context
                )
            }
            print("[OutboundProcessor] Completed \(operation.entityType) \(operation.entityId)")
        } catch {
            DebugLogger.shared.log(
                "outbound \(operation.entityType) \(operation.entityId) pushed but completion could not be persisted — left inProgress for the stale sweep: \(error)",
                level: .error,
                category: "OutboundProcessor"
            )
        }
    }

    // MARK: - Terminal-failure reconciliation (bug ba75732a)

    /// Routes a reconcilable failure to its handler. `false` falls through to
    /// normal disposition — a genuinely unexplained refusal still parks.
    /// Mirrors DataActor.reconcile with this twin's explicit context.
    private func reconcile(
        _ operation: SyncOperation,
        as kind: SyncOperationReconcilers.Kind,
        context: ModelContext
    ) async -> Bool {
        switch kind {
        case .duplicatePhotoCreate:
            return await reconcileDuplicateProjectPhotoCreate(operation, context: context)
        case .taskTombstone:
            return await reconcileTaskUpdateAgainstTombstone(operation, context: context)
        case .projectUpdateRowVerdict:
            return await reconcileProjectUpdateRowVerdict(operation, context: context)
        }
    }

    /// Resolves a projectPhoto create that lost the dedupe race: finds the
    /// server row by its natural key, heals the local store onto the server id,
    /// back-fills the metadata the conversion RPC does not carry, and completes
    /// the operation. Returns false when no server row matches the natural key
    /// (then the failure is real and disposition should run).
    private func reconcileDuplicateProjectPhotoCreate(
        _ operation: SyncOperation,
        context: ModelContext
    ) async -> Bool {
        guard let payload = decodePayload(operation.payload),
              let projectId = payload["project_id"] as? String,
              let url = payload["url"] as? String else { return false }
        let siteVisitId = payload["site_visit_id"] as? String

        do {
            var query = SupabaseService.shared.client
                .from("project_photos")
                .select("id, caption, taken_at, thumbnail_url, rendered_url")
                .eq("project_id", value: projectId)
                .eq("url", value: url)
                .is("deleted_at", value: nil)
            if let siteVisitId {
                query = query.eq("site_visit_id", value: siteVisitId)
            }
            let rows: [SyncOperationReconcilers.ServerPhotoRow] = try await query
                .limit(1)
                .execute()
                .value
            guard let server = rows.first else { return false }

            let serverId = server.id.lowercased()
            var patch: [String: String] = [:]
            try context.transaction {
                patch = try SyncOperationReconcilers.adoptServerPhotoRow(
                    localId: operation.entityId,
                    server: server,
                    in: context
                )
                SyncOperationReconcilers.markResolved(operation)
            }

            // Best-effort metadata back-fill. The columns are client-granted by
            // project_photos_client_update_grant, but the write guard can refuse
            // for a non-uploader — acceptable, the operation is already resolved
            // and the photo is already safe.
            if !patch.isEmpty {
                try? await SupabaseService.shared.client
                    .from("project_photos")
                    .update(patch)
                    .eq("id", value: serverId)
                    .execute()
            }
            print("[OutboundProcessor] projectPhoto create \(operation.entityId) reconciled to server row \(serverId) (dedupe-index conflict)")
            return true
        } catch {
            print("[OutboundProcessor] projectPhoto duplicate reconciliation failed for \(operation.entityId): \(error)")
            return false
        }
    }

    /// Returns true when the server task exists but is soft-deleted: the local
    /// task is tombstoned to match and the op completes. A live or absent server
    /// task returns false — parking is correct for a refusal we cannot explain.
    private func reconcileTaskUpdateAgainstTombstone(
        _ operation: SyncOperation,
        context: ModelContext
    ) async -> Bool {
        struct ServerTaskRow: Decodable {
            let id: String
            let deleted_at: String?
        }
        do {
            let rows: [ServerTaskRow] = try await SupabaseService.shared.client
                .from("project_tasks")
                .select("id, deleted_at")
                .eq("id", value: operation.entityId.lowercased())
                .execute()
                .value
            if rows.isEmpty {
                // The task read policy hides soft-deleted rows entirely, so the
                // tombstone this op parked on can never become visible here. The
                // RPC raised task_not_found under the caller's own RLS — the task
                // is gone from this caller's world and a retry can never succeed.
                // Retire the operation; leave local task data untouched so a
                // permission eclipse (not a deletion) self-corrects on later pulls.
                try context.transaction {
                    SyncOperationReconcilers.markResolved(operation)
                }
                print("[OutboundProcessor] projectTask update \(operation.entityId) retired: server row invisible after task_not_found")
                return true
            }
            guard let server = rows.first,
                  let deletedAtRaw = server.deleted_at,
                  let deletedAt = SupabaseDate.parse(deletedAtRaw) else { return false }

            try context.transaction {
                _ = try SyncOperationReconcilers.applyTaskTombstone(
                    taskId: operation.entityId,
                    deletedAt: deletedAt,
                    in: context
                )
                SyncOperationReconcilers.markResolved(operation)
            }
            print("[OutboundProcessor] projectTask update \(operation.entityId) resolved against server tombstone")
            return true
        } catch {
            print("[OutboundProcessor] task tombstone reconciliation failed for \(operation.entityId): \(error)")
            return false
        }
    }

    /// Asks which of three truths is behind a project update the server matched
    /// to no row, instead of inferring the worst one. Byte-mirrored in
    /// DataActor — the twins keep the network half by house doctrine.
    ///
    /// Probe 1 (RLS SELECT) — a row comes back: the projects read policy exposes
    /// only live rows, so the project IS there and IS readable by this account.
    /// The zero-row UPDATE was an edit-permission refusal, not an absence. Park
    /// it honestly; the operator's copy is safe and an admin can make the change.
    ///
    /// Probe 2 (project_server_state RPC) — the row is invisible to this
    /// account, and only the server can say why:
    ///   * `deleted`  — the tombstone is the newer truth: apply it locally and
    ///     retire the op. The server does not expose the deletion timestamp to a
    ///     non-viewer, so `Date()` is the honest local apply time; any later
    ///     authoritative merge converges local trash on the real one.
    ///   * `active`   — the row lives but this account's view scope no longer
    ///     reaches it. The existing missing-row copy already says exactly that
    ///     ("…or it is no longer shared with you"), so fall through and park
    ///     with it.
    ///   * `absent`   — genuinely not there. The missing-row verdict is now the
    ///     TRUE one, so fall through and park with it.
    ///
    /// Any probe failure falls through as well: a probe that did not answer is
    /// not evidence, and inventing a verdict from one is the bug being fixed.
    private func reconcileProjectUpdateRowVerdict(
        _ operation: SyncOperation,
        context: ModelContext
    ) async -> Bool {
        struct ServerProjectRow: Decodable {
            let id: String
            let deleted_at: String?
        }
        let projectId = operation.entityId.lowercased()
        do {
            let rows: [ServerProjectRow] = try await SupabaseService.shared.client
                .from("projects")
                .select("id, deleted_at")
                .eq("id", value: projectId)
                .execute()
                .value
            if !rows.isEmpty {
                try context.transaction {
                    SyncOperationReconcilers.applyEditRefusedVerdict(
                        operation,
                        table: SyncEntityType.project.supabaseTable
                    )
                }
                print("[OutboundProcessor] project update \(operation.entityId) parked as edit-refused — the row is live and visible to this account")
                return true
            }

            let response = try await SupabaseService.shared.client
                .rpc("project_server_state", params: ["p_project_id": projectId])
                .execute()
            guard let state = SyncOperationReconcilers
                .projectServerState(from: response.data) else {
                print("[OutboundProcessor] project_server_state returned an unrecognized verdict for \(operation.entityId)")
                return false
            }
            guard state == .deleted else {
                print("[OutboundProcessor] project update \(operation.entityId) parks with the missing-row verdict — server state \(state.rawValue)")
                return false
            }

            try context.transaction {
                _ = try SyncOperationReconcilers.applyProjectTombstone(
                    projectId: operation.entityId,
                    deletedAt: Date(),
                    in: context
                )
                SyncOperationReconcilers.markResolved(operation)
            }
            print("[OutboundProcessor] project update \(operation.entityId) resolved against server tombstone")
            return true
        } catch {
            print("[OutboundProcessor] project row-verdict probe failed for \(operation.entityId): \(error)")
            return false
        }
    }

    /// Resolves operations that parked BEFORE the reconcilers existed: site-visit
    /// photo creates parked on the dedupe index, and task updates parked on
    /// task_not_found. Parked ops are excluded from execution by the claim gate,
    /// so without this sweep a device in the field keeps them forever.
    ///
    /// Runs at launch / reconnect, is idempotent, and touches nothing else —
    /// parked stays a terminal state for every other class. Resolved ops leave
    /// `parked`, so the PENDING WORK screen empties itself with no user action.
    ///
    /// Fetches predicate-free and filters in Swift: a `#Predicate` fetch of
    /// SyncOperation traps against a table that has never held a row.
    func resolveReconcilableParkedOperations(context: ModelContext) async {
        let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
        let parked = all.filter { $0.status == "parked" }
        guard !parked.isEmpty else { return }
        var resolved = 0
        for operation in parked {
            guard let kind = SyncOperationReconcilers.parkedKind(for: operation) else { continue }
            if await reconcile(operation, as: kind, context: context) { resolved += 1 }
        }
        if resolved > 0 {
            print("[OutboundProcessor] Parked-op sweep: \(resolved) reconciled against server state")
        }
    }

    /// Readiness validation and the `pending → inProgress` transition share one
    /// owning-context transaction, giving concurrent edits a single
    /// linearization point. A retarget committed first prevents this claim; a
    /// claim committed first means the request legitimately precedes that edit.
    private func claimForExecution(
        _ operation: SyncOperation,
        context: ModelContext
    ) throws -> Bool {
        if SiteVisitOutboundSync.isSiteVisitOperation(operation) {
            let operations = try context.fetch(FetchDescriptor<SyncOperation>())
            guard SiteVisitOutboundSync.isReady(
                operation,
                in: operations
            ) else {
                return false
            }
        }
        if try TaskTypeMutationSync.isBlockedByUnresolvedMutation(
            operation,
            in: context
        ) {
            print(
                "[OutboundProcessor] Holding stale later-write snapshot "
                    + "\(operation.entityType) \(operation.entityId)"
            )
            return false
        }
        if let didClaim = try TaskTypeMutationSync
            .claimForExecutionIfHandled(
                operation,
                context: context,
                refreshFromStore: false
            ) {
            if !didClaim {
                print(
                    "[OutboundProcessor] Waiting to run task-type mutation "
                        + operation.entityId
                        + " until earlier affected writes finish"
                )
            }
            return didClaim
        }
        let didClaim = try ProjectNoteMentionEditSync.claimForExecution(
            operation,
            context: context,
            refreshFromStore: false
        )
        if !didClaim,
           ProjectNoteMentionEditSync.isDependencyDrainOperation(
               operation
           ) {
            print(
                "[OutboundProcessor] Skipping stale dependency snapshot "
                    + "\(operation.operationType) \(operation.entityId)"
            )
        }
        return didClaim
    }

    // MARK: - Repository Routing

    /// Routes an operation to the correct Supabase repository based on entityType and operationType.
    private func routeToRepository(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any]
    ) async throws {
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""

        if try await ProjectNoteMentionEditSync.executeIfHandled(
            entityType: entityType,
            operationType: operationType,
            payload: payload,
            companyId: companyId
        ) {
            return
        }
        if try await TaskTypeMutationSync.executeIfHandled(
            entityType: entityType,
            operationType: operationType,
            payload: payload
        ) {
            return
        }
        // Time off and personal events. Owned here rather than by a switch case
        // below because the create also carries the notification that must not
        // fire until the server has the row (bug ef5a69e6).
        if try await CalendarUserEventOutboundSync.executeIfHandled(
            entityType: entityType,
            operationType: operationType,
            entityId: entityId,
            payload: payload,
            companyId: companyId
        ) {
            return
        }

        guard let syncEntityType = SyncEntityType(rawValue: entityType) else {
            print("[OutboundProcessor] Unknown entity type: \(entityType) — using generic table push")
            try await genericTablePush(entityType: entityType, entityId: entityId, operationType: operationType, payload: payload)
            return
        }

        switch syncEntityType {
        case .project:
            try await handleProject(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .projectTask:
            try await handleProjectTask(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .user:
            try await handleUser(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .client:
            try await handleClient(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .company:
            try await handleCompany(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .taskType:
            try await handleTaskType(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .siteVisitType:
            try await handleSiteVisitType(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .deckDesign:
            try await handleDeckDesign(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .wizardState:
            try await handleWizardState(entityId: entityId, operationType: operationType, payload: payload)
        default:
            // TODO(catalog-outbound): catalog/product entity types fall through
            // to genericTablePush. The catalog sheets currently write directly
            // via their repositories (immediate, online-only path), so the
            // queue is exercised only for offline-buffered ops where generic
            // upsert is sufficient. Promote to dedicated handlers when we add
            // field-level merge protection or column sanitization for catalog.
            try await genericTablePush(
                entityType: entityType,
                entityId: entityId,
                operationType: operationType,
                payload: payload,
                tableName: syncEntityType.supabaseTable
            )
        }
    }

    // MARK: - Entity Handlers

    private func handleProject(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = ProjectRepository(companyId: companyId)
        let sanitizedPayload = Self.sanitizedProjectPayloadForSync(payload)

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseProjectDTO.self, from: jsonData)
            try await repo.create(dto)

        case "update":
            // Restore is staged as an `update` carrying `deleted_at: null`
            // (DataController.restoreTrash), so the "delete" branch never sees
            // it — and `deleted_at` cannot ride a PATCH on projects in either
            // direction. Split it off for the definer RPC, in the order the read
            // policy allows (SoftDeleteRPC.swift).
            for step in TombstoneFieldSplit.steps(for: payloadToAnyJSON(sanitizedPayload)) {
                switch step {
                case .patch(let patch):
                    try await repo.updateFields(entityId, fields: patch)
                case .softDelete:
                    try await repo.softDelete(entityId)
                case .restore:
                    try await repo.restore(entityId)
                }
            }

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for project")
        }
    }

    /// Valid Supabase column names for each table.
    /// Used to filter out local-only SwiftData properties (e.g. task_index, needs_sync)
    /// that would cause "could not find column" errors if sent to PostgREST.
    private static let validProjectColumns: Set<String> = [
        "id", "bubble_id", "company_id", "client_id", "opportunity_id",
        "title", "title_is_auto", "status", "address", "latitude", "longitude",
        "start_date", "end_date", "duration", "notes", "description",
        "all_day", "project_images", "completed_at",
        // Deck Builder vinyl-order marker columns - see DataActor.validProjectColumns
        // for the full rationale. MUST stay in sync across both outbound paths or
        // "MARK ORDERED" is stripped before push and reverts on the next sync.
        "vinyl_order_status", "vinyl_ordered_at", "vinyl_ordered_by",
        "vinyl_color", "vinyl_po", "vinyl_source",
        "deleted_at", "created_at", "updated_at", "priority_rank"
    ]

    private static let validProjectTaskColumns: Set<String> = [
        "id", "bubble_id", "company_id", "project_id", "task_type_id",
        "custom_title", "task_notes", "status", "task_color", "display_order",
        "team_member_ids", "source_line_item_id", "source_estimate_id",
        "start_date", "end_date", "duration", "schedule_locked", "dependency_overrides",
        "start_time", "end_time", "deleted_at", "created_at", "updated_at"
    ]

    private static let validUserColumns: Set<String> = [
        "id", "bubble_id", "company_id", "first_name", "last_name",
        "email", "phone_number", "role", "profile_image_url",
        "deleted_at", "created_at", "updated_at"
    ]

    private static let validClientColumns: Set<String> = [
        "id", "bubble_id", "company_id", "name", "email",
        "phone_number", "address", "latitude", "longitude",
        "notes", "profile_image_url",
        "deleted_at", "created_at", "updated_at"
    ]

    private static let validTaskTypeColumns: Set<String> = [
        "id", "bubble_id", "company_id", "display", "color",
        "icon", "is_default", "display_order", "dependencies",
        "default_team_member_ids",
        "deleted_at", "created_at", "updated_at"
    ]

    private static let validSiteVisitTypeColumns: Set<String> = [
        "id", "company_id", "slug", "name", "description_text",
        "is_system_template", "is_default", "sort_order", "fields",
        "created_at", "updated_at", "deleted_at"
    ]

    private static let validDeckDesignColumns: Set<String> = [
        "id", "company_id", "project_id", "opportunity_id", "title", "drawing_data",
        "thumbnail_url", "version", "created_by",
        "deleted_at", "created_at", "updated_at"
    ]

    private static let validWizardStateColumns: Set<String> = [
        "id", "wizard_id", "user_id", "status", "current_step_index",
        "do_not_show", "completed_at", "total_duration_ms", "steps_skipped",
        "last_active_at", "current_session_id",
        "created_at", "updated_at"
    ]

    private static let validCompanyColumns: Set<String> = [
        "id", "bubble_id", "name", "external_id", "description", "website",
        "phone", "email", "address", "latitude", "longitude",
        "open_hour", "close_hour", "logo_url", "default_project_color",
        "industries", "company_size", "company_age", "referral_method",
        "account_holder_id", "admin_ids", "seated_employee_ids", "max_seats",
        "subscription_status", "subscription_plan", "subscription_end",
        "subscription_period", "trial_start_date", "trial_end_date",
        "seat_grace_start_date", "has_priority_support",
        "data_setup_purchased", "data_setup_completed", "data_setup_scheduled",
        "stripe_customer_id", "subscription_ids_json", "company_code",
        "precise_scheduling_enabled", "skip_weekends_in_auto_schedule",
        "weather_dependent", "industry", "client_comms_settings",
        "timezone", "locale",
        "deleted_at", "created_at", "updated_at"
    ]

    private func handleProjectTask(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = projectTaskSyncingFactory(companyId)

        // Filter payload to only include valid Supabase columns, stripping
        // local-only SwiftData properties like task_index or needs_sync
        let sanitizedPayload = Self.sanitizedProjectTaskPayloadForSync(payload)
        let shouldComplete = TaskCompletionSync.isCompletionPayload(payload)

        switch operationType {
        case "create":
            var createPayload = sanitizedPayload
            if shouldComplete {
                createPayload["status"] = TaskStatus.active.rawValue
            }
            let jsonData = try JSONSerialization.data(withJSONObject: createPayload)
            let dto = try JSONDecoder().decode(SupabaseProjectTaskDTO.self, from: jsonData)
            _ = try await repo.create(dto)
            if shouldComplete {
                _ = try await repo.completeProjectTask(
                    taskId: entityId,
                    idempotencyKey: TaskCompletionSync.idempotencyKey(from: payload, taskId: entityId),
                    materialAdjustments: TaskCompletionSync.materialAdjustments(from: payload)
                )
            }

        case "update":
            if shouldComplete {
                var updatePayload = sanitizedPayload
                updatePayload.removeValue(forKey: "status")
                let fields = payloadToAnyJSON(updatePayload)
                if !fields.isEmpty {
                    try await repo.updateFields(entityId, fields: fields)
                }
                _ = try await repo.completeProjectTask(
                    taskId: entityId,
                    idempotencyKey: TaskCompletionSync.idempotencyKey(from: payload, taskId: entityId),
                    materialAdjustments: TaskCompletionSync.materialAdjustments(from: payload)
                )
            } else {
                // A completion payload never carries `deleted_at`, so only this
                // arm needs the split. Restore arrives here as an `update`
                // carrying `deleted_at: null`, and the tombstone column cannot
                // travel by PATCH in either direction (SoftDeleteRPC.swift).
                for step in TombstoneFieldSplit.steps(for: payloadToAnyJSON(sanitizedPayload)) {
                    switch step {
                    case .patch(let patch):
                        try await repo.updateFields(entityId, fields: patch)
                    case .softDelete:
                        try await repo.softDelete(entityId)
                    case .restore:
                        try await repo.restore(entityId)
                    }
                }
            }

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for projectTask")
        }
    }

    static func sanitizedProjectPayloadForSync(_ payload: [String: Any]) -> [String: Any] {
        // `vinyl_ordered_by` is a Postgres uuid column; a non-UUID attribution
        // (historic Firebase-UID writes, bug 0f86b9b0) would 22P02 the whole
        // PATCH and wedge the queued op. Null it instead of poisoning the write.
        SupabaseUUID.nullingNonUuidValue(
            forKey: "vinyl_ordered_by",
            in: payload.filter { Self.validProjectColumns.contains($0.key) }
        )
    }

    static func sanitizedProjectTaskPayloadForSync(_ payload: [String: Any]) -> [String: Any] {
        // Every outbound task create/update on the OutboundProcessor path passes
        // through here. Re-anchor all-day start_date/end_date to LOCAL midnight so
        // no write persists an off-day instant (renders a day off on web). Shared
        // with the DataActor path via SupabaseDate.anchoringScheduleDates so the
        // two outbound paths cannot drift. Idempotent. Tasks are all-day today;
        // gate on all_day when timed tasks ship.
        SupabaseDate.anchoringScheduleDates(
            payload.filter { Self.validProjectTaskColumns.contains($0.key) }
        )
    }

    private func handleUser(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = UserRepository(companyId: companyId)
        let sanitizedPayload = payload.filter { Self.validUserColumns.contains($0.key) }

        switch operationType {
        case "create":
            // UserRepository doesn't have a generic create — use upsert approach
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseUserDTO.self, from: jsonData)
            try await repo.upsert(dto)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(userId: entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for user")
        }
    }

    private func handleClient(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = ClientRepository(companyId: companyId)
        let sanitizedPayload = payload.filter { Self.validClientColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseClientDTO.self, from: jsonData)
            try await repo.create(dto)

        case "update":
            // ClientRepository doesn't have updateFields — use generic table push.
            // The tombstone half cannot go through PostgREST at all: setting
            // `deleted_at` is refused 42501 and clearing it matches zero rows in
            // silence, so it splits off to the definer RPC (SoftDeleteRPC.swift).
            for step in TombstoneFieldSplit.steps(for: payloadToAnyJSON(sanitizedPayload)) {
                switch step {
                case .patch(let patch):
                    try await genericUpdateFields(table: "clients", entityId: entityId, fields: patch)
                case .softDelete:
                    try await repo.softDelete(entityId)
                case .restore:
                    try await repo.restore(entityId)
                }
            }

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for client")
        }
    }

    private func handleCompany(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = CompanyRepository()
        let sanitizedPayload = payload.filter { Self.validCompanyColumns.contains($0.key) }

        switch operationType {
        case "create":
            // Company creation uses NewCompanyPayload — decode and insert
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let companyPayload = try JSONDecoder().decode(NewCompanyPayload.self, from: jsonData)
            _ = try await repo.insert(companyPayload)

        case "update":
            // Use the generic AnyJSON path so array columns (e.g. admin_ids,
            // seated_employee_ids, industries) serialize as Postgres arrays
            // instead of being force-stringified into a malformed array literal.
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(companyId: entityId, fields: fields)

        case "delete":
            // CompanyRepository has no softDelete — use generic approach
            let fields: [String: AnyJSON] = [
                "deleted_at": .string(ISO8601DateFormatter().string(from: Date())),
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            try await genericUpdateFields(table: "companies", entityId: entityId, fields: fields)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for company")
        }
    }

    private func handleTaskType(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = TaskTypeRepository(companyId: companyId)
        let sanitizedPayload = payload.filter { Self.validTaskTypeColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseTaskTypeDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await genericUpdateFields(table: "task_types", entityId: entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for taskType")
        }
    }

    private func handleSiteVisitType(
        entityId: String,
        operationType: String,
        payload: [String: Any],
        companyId: String
    ) async throws {
        let repo = SiteVisitTypeRepository(companyId: companyId)
        let sanitized = payload.filter {
            Self.validSiteVisitTypeColumns.contains($0.key)
        }

        switch operationType {
        case "create":
            let data = try JSONSerialization.data(withJSONObject: sanitized)
            try await repo.upsert(try JSONDecoder().decode(SiteVisitTypeDTO.self, from: data))
        case "update":
            try await repo.updateFields(
                entityId,
                fields: payloadToAnyJSON(sanitized)
            )
        case "delete":
            try await repo.softDelete(entityId)
        default:
            throw SyncError.encodingFailed(
                detail: "Unsupported siteVisitType operation: \(operationType)"
            )
        }
    }

    private func handleDeckDesign(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = DeckDesignRepository(companyId: companyId)
        let sanitizedPayload = payload.filter { Self.validDeckDesignColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseDeckDesignDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            // The reparent guard trigger (trg_deck_designs_guard_opportunity_reparent)
            // rejects any PATCH that carries opportunity_id (42501). The lead link
            // travels ONLY via the dedicated "linkOpportunity" op below — never an
            // update payload — so strip it here as a defense against any legacy or
            // stray update op that still carries it.
            var updatePayload = sanitizedPayload
            updatePayload.removeValue(forKey: "opportunity_id")
            let fields = payloadToAnyJSON(updatePayload)
            try await repo.updateFields(entityId, fields: fields)

        case "linkOpportunity":
            // Server-guarded orphan→lead link (link_deck_design_to_opportunity_guarded).
            // already_linked:true is an idempotent success; a different lead raises
            // 23514 and a missing row P0002 — both classify permanent → the op parks.
            // A missing/garbage payload can't be fixed by retry, so throw encodingFailed
            // (also permanent → parks) rather than burning the retry budget.
            guard let rawOpportunityId = payload["opportunity_id"] as? String,
                  !rawOpportunityId.isEmpty else {
                throw SyncError.encodingFailed(
                    detail: "linkOpportunity for deckDesign \(entityId) missing opportunity_id"
                )
            }
            _ = try await repo.linkToOpportunity(
                designId: entityId,
                opportunityId: rawOpportunityId.lowercased()
            )

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for deckDesign")
        }
    }

    /// Pushes wizard_states rows. No companyId — user-scoped per RLS.
    /// Hard delete path (wizard_states has no deleted_at column).
    private func handleWizardState(entityId: String, operationType: String, payload: [String: Any]) async throws {
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        let repo = WizardStateRepository(userId: userId)
        let sanitizedPayload = payload.filter { Self.validWizardStateColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(CreateWizardStateDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(entityId, fields: fields)

        case "delete":
            try await repo.delete(id: entityId)

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for wizardState")
        }
    }

    // MARK: - Generic Table Operations

    /// Generic update for tables without a dedicated updateFields method.
    private func genericUpdateFields(table: String, entityId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        let response = try await SupabaseService.shared.client
            .from(table)
            .update(payload)
            .eq("id", value: entityId)
            .select("id")
            .execute()
        try SupabaseWriteGuard.requireAffectedRow(
            response: response.data,
            table: table,
            id: entityId,
            fields: payload
        )
    }

    /// Generic fallback for entity types without a dedicated handler.
    private func genericTablePush(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any],
        tableName: String? = nil
    ) async throws {
        let table = tableName ?? entityType
        let client = SupabaseService.shared.client
        let fields = payloadToAnyJSON(payload)

        switch operationType {
        case "create":
            var insertPayload = fields
            insertPayload["id"] = .string(entityId)
            try await client
                .from(table)
                .insert(insertPayload)
                .execute()

        case "update":
            try await genericUpdateFields(table: table, entityId: entityId, fields: fields)

        case "delete":
            let deletePayload: [String: AnyJSON] = [
                "deleted_at": .string(ISO8601DateFormatter().string(from: Date())),
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            try await client
                .from(table)
                .update(deletePayload)
                .eq("id", value: entityId)
                .execute()

        default:
            print("[OutboundProcessor] Unknown operation type '\(operationType)' for generic table \(table)")
        }
    }

    // MARK: - Payload Helpers

    /// Decodes a JSON Data payload into a dictionary.
    private func decodePayload(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Encodes a dictionary back into JSON Data.
    private func encodePayload(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }

    /// Merges two JSON payloads. Overlay values overwrite base values for matching keys.
    private func mergePayloads(base: Data, overlay: Data) -> Data? {
        guard var baseDict = decodePayload(base) else { return overlay }
        guard let overlayDict = decodePayload(overlay) else { return base }
        for (key, value) in overlayDict {
            baseDict[key] = value
        }
        return encodePayload(baseDict)
    }

    /// Converts a [String: Any] dictionary to [String: AnyJSON] for Supabase update calls.
    /// Delegates to the one shared converter. This used to be a local copy that
    /// matched `Int` before `Bool`, which flattened every JSON boolean to 0/1 —
    /// see `AnyJSONBridge`.
    private func payloadToAnyJSON(_ payload: [String: Any]) -> [String: AnyJSON] {
        AnyJSONBridge.payload(payload)
    }
}
