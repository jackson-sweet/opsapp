//
//  SyncEngine.swift
//  OPS
//
//  Central sync orchestrator for the offline-first sync engine.
//  Replaces SupabaseSyncManager as the single coordination point
//  for recording outbound operations, triggering push/pull cycles,
//  and managing sync lifecycle.
//

import Foundation
import SwiftData

// MARK: - SyncEngine

@MainActor
@Observable
final class SyncEngine {

    // MARK: - Public State

    var isSyncing: Bool = false
    var hasError: Bool = false
    var pendingOperationCount: Int = 0
    var statusText: String = ""
    var isPerformingInitialSync: Bool = false

    // MARK: - Private State

    private var modelContext: ModelContext?
    private var connectivity: ConnectivityManager?
    private var syncInProgress: Bool = false
    private var pushInProgress: Bool = false
    private var pushRequestedWhileInProgress: Bool = false
    nonisolated(unsafe) private var syncRetryTimer: Timer?

    /// The current authenticated user's ID, read from UserDefaults.
    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "currentUserId")
    }

    /// Retry interval in seconds for the periodic sync timer.
    private let retryInterval: TimeInterval = 180

    /// Delta pulls intentionally overlap the previous cursor. A row can update
    /// while a device is mid-sync; without overlap, setting the cursor to the
    /// sync completion time can skip that row forever.
    private let deltaOverlapWindow: TimeInterval = 300

    // MARK: - Processors

    private var outboundProcessor: OutboundProcessor?
    private var inboundProcessor: InboundProcessor?
    private var photoProcessor: PhotoProcessor?
    private var realtimeProcessor: RealtimeProcessor?
    private var backgroundScheduler: BackgroundSyncScheduler?
    private let dimensionedPendingSyncer: DimensionedPendingSyncing

    // MARK: - DataActor Path

    /// Background data actor — when present, sync ops route through this actor
    /// instead of the MainActor processors. Injected by DataController via configure.
    private weak var dataActor: DataActor?

    /// SyncEngine-owned spotlight tracker used to dispatch DataActor's accumulated
    /// spotlight diff. Distinct from InboundProcessor's tracker so actor-path and
    /// legacy-path instances don't share state. When the legacy path is retired,
    /// only this tracker remains.
    private let spotlightTracker = SpotlightSyncTracker()

    // MARK: - Lifecycle

    init(dimensionedPendingSyncer: DimensionedPendingSyncing? = nil) {
        self.dimensionedPendingSyncer = dimensionedPendingSyncer ?? DimensionedPhotoSyncManager.shared
    }

    deinit {
        syncRetryTimer?.invalidate()
    }

    // MARK: - Configuration

    /// Stores references to the model context and connectivity manager,
    /// initializes all processors, and starts the periodic retry timer.
    /// `dataActor` is optional so callers that haven't yet enabled the flag
    /// (e.g., tests, older integration points) keep compiling against the old
    /// signature without modification.
    func configure(
        modelContext: ModelContext,
        connectivity: ConnectivityManager,
        dataActor: DataActor? = nil
    ) {
        self.modelContext = modelContext
        self.connectivity = connectivity
        self.dataActor = dataActor

        // One-time recovery for the poisoned deck-design cursor (the crew
        // deck-blackout bug): an earlier build advanced sync.lastPull.deckDesign
        // past a swallowed decode failure, stranding already-existing decks on
        // every non-creator device (future deltas only pull rows updated after the
        // cursor). Clear that ONE cursor once so the next pull re-fetches all decks;
        // decode resilience then keeps a corrupt row from re-poisoning it. Gated by
        // a UserDefaults flag so it runs exactly once per device.
        let deckCursorRecoveryKey = "sync.deckCursorRecoveryV1"
        if !UserDefaults.standard.bool(forKey: deckCursorRecoveryKey) {
            UserDefaults.standard.removeObject(
                forKey: "sync.lastPull.\(SyncEntityType.deckDesign.rawValue)"
            )
            UserDefaults.standard.set(true, forKey: deckCursorRecoveryKey)
        }

        // One-time recovery for catalogStockUnitEvent: a pre-fix build registered
        // the entity but omitted it from DataActor.syncOrder (the default path),
        // so pullDelta advanced sync.lastPull.catalogStockUnitEvent to wall-clock
        // without ever fetching the ledger. Once the entity is wired in, that
        // poisoned cursor would strand every event created before the advance.
        // Clear it once so the first post-fix pull re-fetches the full ledger.
        let stockEventCursorRecoveryKey = "sync.stockUnitEventCursorRecoveryV1"
        if !UserDefaults.standard.bool(forKey: stockEventCursorRecoveryKey) {
            UserDefaults.standard.removeObject(
                forKey: "sync.lastPull.\(SyncEntityType.catalogStockUnitEvent.rawValue)"
            )
            UserDefaults.standard.set(true, forKey: stockEventCursorRecoveryKey)
        }

        // Initialize processors
        self.outboundProcessor = OutboundProcessor()
        self.inboundProcessor = InboundProcessor()
        self.photoProcessor = PhotoProcessor()
        self.realtimeProcessor = RealtimeProcessor()

        // Wire RealtimeProcessor to the actor when the flag is on — the channel
        // subscription must stay on main, but each event's SwiftData write can
        // dispatch to the actor.
        if let actor = dataActor {
            self.realtimeProcessor?.setDataActor(actor)
        }

        // Attach background-task handlers to the shared scheduler. Registration
        // already happened in AppDelegate.didFinishLaunching (BGTaskScheduler
        // requires it before launch returns). Here we just wire what should run
        // when those tasks fire.
        let scheduler = BackgroundSyncScheduler.shared
        scheduler.onRefreshTask = { [weak self] in
            await self?.pushPending()
        }
        scheduler.onProcessingTask = { [weak self] in
            await self?.triggerSync()
            await self?.photoProcessor?.processUploadQueue(
                context: modelContext,
                connectivity: connectivity
            )
            self?.cleanupCompletedOperations()
        }
        self.backgroundScheduler = scheduler

        // Listen for realtime catch-up notifications
        NotificationCenter.default.addObserver(
            forName: .realtimeNeedsCatchUp,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let disconnectedAt = notification.userInfo?["disconnectedAt"] as? Date else { return }
            Task { @MainActor [weak self] in
                await self?.deltaSyncSince(disconnectedAt)
            }
        }

        // Listen for connectivity changes to manage realtime disconnect/reconnect
        NotificationCenter.default.addObserver(
            forName: ConnectivityManager.connectivityChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.connectivity?.shouldAttemptSync == true {
                    // Connectivity restored — realtime will auto-reconnect via startListening
                } else {
                    // Connectivity lost — mark realtime as disconnected for catch-up tracking
                    self.realtimeProcessor?.handleDisconnect()
                }
            }
        }

        // Listen for permission changes detected by RealtimeProcessor
        NotificationCenter.default.addObserver(
            forName: .permissionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handlePermissionChange()
            }
        }

        // Refresh the pending count on configure
        refreshPendingCount()

        // Start the periodic retry timer
        startRetryTimer()

        print("[SYNC_ENGINE] Configured with modelContext and connectivity")
    }

    /// Reconfigure inbound processor repositories after companyId becomes available.
    /// Call after login completes and companyId is confirmed in UserDefaults.
    func reconfigureForCompany() {
        inboundProcessor?.reconfigure()
        print("[SYNC_ENGINE] Reconfigured InboundProcessor for current company")
    }

    /// Late-binds the background DataActor after configure() has already run.
    ///
    /// Required because DataController.fetchUserFromAPI (at auth check) can call
    /// initializeSyncManager — and therefore configure — BEFORE setModelContext's
    /// async Task block finishes creating the actor. Without this setter, subsequent
    /// initializeSyncManager calls early-return on the imageSyncManager guard and
    /// the actor never gets wired in. Also pushes the actor reference to the
    /// already-created RealtimeProcessor so its flag-gated dispatch engages.
    func setDataActor(_ actor: DataActor?) {
        self.dataActor = actor
        if let actor = actor {
            self.realtimeProcessor?.setDataActor(actor)
        }
        print("[SYNC_ENGINE] DataActor reference \(actor == nil ? "cleared" : "set — actor path now active")")
    }

    /// Starts Realtime subscriptions for the given company.
    func startRealtime(companyId: String, userId: String? = nil) async {
        guard let modelContext else { return }
        await realtimeProcessor?.startListening(companyId: companyId, userId: userId, context: modelContext)
    }

    /// Stops Realtime subscriptions.
    func stopRealtime() async {
        await realtimeProcessor?.stopListening()
    }

    /// Synchronously halts the parts of the sync engine that can fire
    /// autonomously — the retry timer and the notification observers.
    /// Must be called from `DataController.logout()` BEFORE the data wipe
    /// so the timer can't fire mid-wipe and access invalidated SwiftData
    /// models, and so a connectivity flip during logout can't re-arm the
    /// retry cycle. The realtime Supabase listener is stopped separately
    /// via `stopForLogoutAsync()` because it's an async call.
    ///
    /// Safe to call multiple times.
    func stopForLogoutSync() {
        print("[SYNC_ENGINE] stopForLogoutSync — halting timer + observers")

        syncRetryTimer?.invalidate()
        syncRetryTimer = nil

        NotificationCenter.default.removeObserver(self, name: .realtimeNeedsCatchUp, object: nil)
        NotificationCenter.default.removeObserver(self, name: ConnectivityManager.connectivityChangedNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .permissionsChanged, object: nil)

        // Clear the in-memory sync state so any view that re-reads the
        // pending count during view transition sees zero.
        isSyncing = false
        syncInProgress = false
        pendingOperationCount = 0
        statusText = ""
        isPerformingInitialSync = false
    }

    /// Tears down the realtime Supabase subscription. Called after
    /// `stopForLogoutSync()` as a fire-and-forget async step.
    func stopForLogoutAsync() async {
        await realtimeProcessor?.stopListening()
        print("[SYNC_ENGINE] stopForLogoutAsync complete — realtime stopped")
    }

    /// No-op kept for backwards compatibility. BGTaskScheduler registration now
    /// happens in AppDelegate.didFinishLaunching against the shared singleton —
    /// see BackgroundSyncScheduler.shared.registerTasks(). Calling this method
    /// after launch is a noop because attempting to re-register would crash.
    func registerBackgroundTasks() {
        // Intentional no-op. Do not call BGTaskScheduler.register here.
    }

    /// Schedules background sync tasks. Call when app enters background.
    func scheduleBackgroundSync() {
        backgroundScheduler?.scheduleRefresh()
        backgroundScheduler?.scheduleProcessing()
    }

    /// Processes the photo upload queue.
    func processPhotoUploads() async {
        guard let modelContext, let connectivity else { return }
        await photoProcessor?.processUploadQueue(context: modelContext, connectivity: connectivity)
    }

    // MARK: - Operation Log

    /// Records a new sync operation in SwiftData and attempts an immediate
    /// push if the device is online.
    ///
    /// - Parameters:
    ///   - entityType: The type of entity being synced.
    ///   - entityId: The unique identifier of the entity.
    ///   - operationType: One of "create", "update", or "delete".
    ///   - changedFields: Dictionary of field names to their new values.
    ///   - previousValues: Optional dictionary of field names to their previous values (for rollback).
    ///   - priority: Operation priority (0 = immediate, 1 = normal, 2 = low).
    ///   - dependsOnId: Optional ID of another operation this one depends on.
    /// - Returns: The created SyncOperation, or nil if recording failed.
    @discardableResult
    func recordOperation(
        entityType: SyncEntityType,
        entityId: String,
        operationType: String,
        changedFields: [String: Any],
        previousValues: [String: Any]? = nil,
        priority: Int = 1,
        dependsOnId: String? = nil,
        deferPush: Bool = false
    ) -> SyncOperation? {
        guard let modelContext else {
            print("[SYNC_ENGINE] Cannot record operation — modelContext not configured")
            return nil
        }

        // Encode changedFields to JSON Data for the payload
        let payloadData: Data
        do {
            payloadData = try JSONSerialization.data(
                withJSONObject: changedFields,
                options: []
            )
        } catch {
            print("[SYNC_ENGINE] Failed to encode changedFields: \(error)")
            return nil
        }

        // Encode previousValues to JSON Data if provided
        let previousData: Data?
        if let previousValues {
            do {
                previousData = try JSONSerialization.data(
                    withJSONObject: previousValues,
                    options: []
                )
            } catch {
                print("[SYNC_ENGINE] Failed to encode previousValues: \(error)")
                previousData = nil
            }
        } else {
            previousData = nil
        }

        // Extract field names from changedFields dictionary
        let fieldNames = Array(changedFields.keys)

        // Canonicalize the entityId to lowercase. Postgres stores uuid lowercase;
        // Swift's UUID().uuidString is UPPERCASE, so pre-canonicalized local
        // entities carried UPPERCASE ids that didn't match echoed lowercase ids
        // from Supabase. Normalizing here ensures origin-suppression comparisons
        // and outbound-route lookups use the same canonical form as DTOs.
        let canonicalEntityId = entityId.lowercased()

        // Create the SyncOperation
        let operation = SyncOperation(
            entityType: entityType.rawValue,
            entityId: canonicalEntityId,
            operationType: operationType,
            payload: payloadData,
            changedFields: fieldNames,
            previousValues: previousData,
            priority: priority,
            dependsOnId: dependsOnId
        )

        modelContext.insert(operation)

        do {
            try modelContext.save()
        } catch {
            print("[SYNC_ENGINE] Failed to save SyncOperation: \(error)")
            return nil
        }

        // Update pending count
        refreshPendingCount()

        print("[SYNC_ENGINE] Recorded \(operationType) for \(entityType.rawValue) [\(canonicalEntityId)]")
        if entityType == .projectTask {
            print("[DUPE_TRACE] SYNCOP.record id=\(canonicalEntityId) op=\(operationType) status=pending createdAt=\(operation.createdAt) ctx=\(ObjectIdentifier(modelContext))")
        }

        // Attempt immediate push if online. Bulk callers pass deferPush:true
        // and call pushPending() once for the whole batch — otherwise N task
        // writes each spawn a push, a request storm that drops the connection.
        if !deferPush, connectivity?.shouldAttemptSync == true {
            Task {
                await pushPending()
            }
        }

        return operation
    }

    /// One operation to enqueue via `recordOperations(_:)`.
    struct BulkOperationSpec {
        let entityType: SyncEntityType
        let entityId: String
        let operationType: String
        let changedFields: [String: Any]
    }

    /// Enqueue many operations with a SINGLE context save and NO per-op push.
    /// Built for bulk applies (priority-queue / auto-schedule run) so N task
    /// writes don't trigger N saves + N pushes — the cause of the main-thread
    /// hang and the `networkConnectionLost` request storm. The caller invokes
    /// `pushPending()` once afterward.
    @discardableResult
    func recordOperations(_ specs: [BulkOperationSpec]) -> Int {
        guard let modelContext else {
            print("[SYNC_ENGINE] Cannot record operations — modelContext not configured")
            return 0
        }
        guard !specs.isEmpty else { return 0 }
        var recorded = 0
        for spec in specs {
            let payloadData: Data
            do {
                payloadData = try JSONSerialization.data(withJSONObject: spec.changedFields, options: [])
            } catch {
                print("[SYNC_ENGINE] Skipping bulk op for \(spec.entityId) — encode failed: \(error)")
                continue
            }
            let operation = SyncOperation(
                entityType: spec.entityType.rawValue,
                entityId: spec.entityId.lowercased(),
                operationType: spec.operationType,
                payload: payloadData,
                changedFields: Array(spec.changedFields.keys),
                previousValues: nil,
                priority: 1,
                dependsOnId: nil
            )
            modelContext.insert(operation)
            recorded += 1
        }
        guard recorded > 0 else { return 0 }
        do {
            try modelContext.save()   // ONE save for the whole batch
        } catch {
            print("[SYNC_ENGINE] Failed to save \(recorded) bulk operation(s): \(error)")
            return 0
        }
        refreshPendingCount()
        print("[SYNC_ENGINE] Recorded \(recorded) operation(s) in one batch (push deferred to caller)")
        return recorded
    }

    // MARK: - Sync Triggers

    /// Fetches just the company row and merges it into SwiftData.
    ///
    /// Used during login to guarantee the company is in SwiftData before
    /// downstream features query it. Previously this was done via
    /// `triggerSync()` (delta) which does NOT include the company entity,
    /// so the company row only landed after a subsequent full sync and
    /// features hitting `getCurrentUserCompany()` briefly saw nil.
    ///
    /// Intentionally does NOT acquire the `syncInProgress` lock — it's a
    /// single-row fetch that is safe to run alongside other syncs.
    func syncCompanyNow() async {
        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] syncCompanyNow: network unavailable — skipping")
            return
        }

        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                try await actor.syncCompanyOnly(companyId: companyId)
            } else {
                guard let modelContext, let inboundProcessor else {
                    print("[SYNC_ENGINE] syncCompanyNow: not configured")
                    return
                }
                try await inboundProcessor.syncCompany(context: modelContext)
            }
        } catch {
            print("[SYNC_ENGINE] syncCompanyNow error: \(error)")
        }
    }

    /// Triggers a full push-then-pull cycle, guarding against concurrent syncs.
    func triggerSync() async {
        guard !syncInProgress else {
            print("[SYNC_ENGINE] Sync already in progress — skipping")
            return
        }

        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] Network not available — skipping sync")
            statusText = "Offline — changes queued"
            return
        }

        syncInProgress = true
        isSyncing = true
        hasError = false
        statusText = "Syncing…"

        defer {
            syncInProgress = false
            isSyncing = false
            refreshPendingCount()
        }

        // Push local changes first, then pull server changes
        await pushPending()
        await syncPendingLocalArtifacts()
        await pullDelta()

        if !hasError {
            statusText = "Synced"
            kickoffPhotoPrefetch()
        }
    }

    // MARK: - Photo Prefetch Hook

    /// Triggers PhotoPrefetchService after successful sync. Respects the
    /// service's own WiFi-only and enabled guards — SyncEngine just says
    /// "we just synced new data, consider downloading photos now."
    private func kickoffPhotoPrefetch() {
        guard let modelContext, let connectivity else { return }
        PhotoPrefetchService.shared.prefetchIfAppropriate(
            modelContext: modelContext,
            connectivity: connectivity
        )
    }

    // MARK: - Migration Cleanup

    /// One-time cleanup on first launch after sync overhaul.
    /// Purges stale SyncOperations that accumulated under the deleted SyncQueue
    /// (operations that were stuck with "Not yet connected to repositories" error
    /// or that exceeded max retries under the old system).
    private func migrateCleanup(context: ModelContext) {
        let failedPredicate = #Predicate<SyncOperation> { op in
            op.status == "failed"
        }
        let descriptor = FetchDescriptor<SyncOperation>(predicate: failedPredicate)
        guard let allFailed = try? context.fetch(descriptor) else { return }

        let stale = allFailed.filter { op in
            (op.lastError?.contains("Not yet connected to repositories") == true) ||
            (op.retryCount >= 20)
        }

        for op in stale {
            context.delete(op)
        }
        try? context.save()
        if !stale.isEmpty {
            print("[SYNC_ENGINE] Migration cleanup: purged \(stale.count) stale SyncOperations")
        }
    }

    /// Performs a full sync of all entities in dependency order.
    /// Used for initial sync or manual full-refresh.
    func fullSync() async {
        // One-time migration cleanup (gated by UserDefaults flag)
        let migrationKey = "sync.migrationCleanupV1"
        if !UserDefaults.standard.bool(forKey: migrationKey), let ctx = modelContext {
            migrateCleanup(context: ctx)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        // If another sync is in progress, wait briefly for it to finish
        // rather than silently skipping this full sync request
        if syncInProgress {
            print("[SYNC_ENGINE] Sync in progress — waiting for it to finish before full sync")
            for _ in 0..<30 { // Wait up to 3 seconds
                try? await Task.sleep(for: .milliseconds(100))
                if !syncInProgress { break }
            }
            guard !syncInProgress else {
                print("[SYNC_ENGINE] Sync still in progress after wait — skipping full sync")
                return
            }
        }

        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] Network not available — skipping full sync")
            statusText = "Offline — full sync deferred"
            return
        }

        syncInProgress = true
        isSyncing = true
        isPerformingInitialSync = true
        hasError = false
        statusText = "Performing full sync…"

        defer {
            isPerformingInitialSync = false
            syncInProgress = false
            isSyncing = false
            refreshPendingCount()
        }

        // Pull all entities via DataActor (flag-on) or InboundProcessor (legacy).
        guard let ctx = modelContext else { return }
        let syncStartedAt = Date()
        var failedEntities = Set<SyncEntityType>()
        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                failedEntities = try await actor.fullSync(
                    companyId: companyId,
                    onProgress: { [weak self] entityType, _ in
                        Task { @MainActor [weak self] in
                            self?.statusText = "Syncing \(entityType.rawValue)…"
                        }
                    }
                )
                await applySpotlightSnapshot(from: actor)
            } else {
                failedEntities = try await inboundProcessor?.fullSync(
                    context: ctx,
                    onProgress: { [weak self] entityType, _ in
                        self?.statusText = "Syncing \(entityType.rawValue)…"
                    }
                ) ?? []
            }
        } catch {
            print("[SYNC_ENGINE] Full sync pull error: \(error)")
            hasError = true

            let classified = classifySyncError(error)
            AnalyticsService.shared.track(
                eventType: .error,
                eventName: "sync_failed",
                properties: [
                    "error_type": classified.localizedDescription,
                    "retry_count": 0,
                    "sync_phase": "full_sync_pull"
                ]
            )

            if case .authExpired = classified {
                NotificationCenter.default.post(name: .syncAuthExpired, object: nil)
                return
            }
        }

        // Advance the last-sync cursor only for entities that did NOT fail this
        // pull. Advancing a failed entity's cursor strands its existing rows —
        // future deltas only re-pull rows updated after the cursor — which is how
        // a single transient deck-sync failure left crew devices unable to see any
        // deck designs. Failed entities keep their old cursor and are retried in
        // full on the next sync.
        if !hasError {
            advanceSyncCursors(InboundProcessor.syncOrder, excluding: failedEntities, to: syncStartedAt)
        }

        // Push any pending local operations
        await pushPending()
        await syncPendingLocalArtifacts()

        statusText = hasError ? "Sync error" : "Full sync complete"
        print("[SYNC_ENGINE] Full sync complete")

        // Bug G9 — rebuild mention-access index from latest ProjectNote rows.
        // Runs after every full sync so revoked mentions / new mentions resolve.
        if !hasError, let modelContext,
           let userId = UserDefaults.standard.string(forKey: "currentUserId"),
           !userId.isEmpty {
            MentionAccessIndex.shared.rebuild(context: modelContext, userId: userId)
        }

        if !hasError {
            kickoffPhotoPrefetch()
        }

        // Retry a queued onboarding-completion ACK if one is outstanding. This runs
        // on every full sync (periodic timer + foreground + post-login), so a user
        // who finished onboarding offline gets their server ACK re-sent and the
        // pending flag cleared as soon as connectivity returns.
        await retryPendingOnboardingCompletion()
    }

    /// Re-sends the onboarding-completion ACK (POST /api/onboarding/complete) when a
    /// prior attempt was queued offline, clearing `onboarding_completion_pending` on
    /// success. No-op when nothing is queued. Best-effort: failures are swallowed and
    /// retried on the next sweep.
    private func retryPendingOnboardingCompletion() async {
        guard UserDefaults.standard.bool(forKey: OnboardingStorageKeys.completionPending) else {
            return
        }
        guard let userId = currentUserId, !userId.isEmpty else { return }

        do {
            try await OnboardingService().markOnboardingComplete(userId: userId)
            UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.completionPending)
            print("[SYNC_ENGINE] Queued onboarding completion ACK delivered — flag cleared")
        } catch {
            print("[SYNC_ENGINE] Queued onboarding completion ACK still failing — will retry: \(error.localizedDescription)")
        }
    }

    /// Pushes all pending local operations to the server via OutboundProcessor.
    func pushPending() async {
        guard let modelContext, let connectivity else {
            print("[SYNC_ENGINE] Cannot push — not configured")
            return
        }

        guard !pushInProgress else {
            pushRequestedWhileInProgress = true
            print("[SYNC_ENGINE] Push already in progress — queueing one follow-up drain")
            return
        }
        pushInProgress = true
        defer {
            pushInProgress = false
            if pushRequestedWhileInProgress {
                pushRequestedWhileInProgress = false
                Task {
                    await pushPending()
                }
            }
        }

        // Safety net: recover any task whose local edit never produced an
        // outbound op (needsSync set without recordOperation) before reading the
        // pending queue, so a future bypass can't silently drop a write.
        enqueueOrphanedTaskWrites()

        let pending = getPendingOperations()
        guard !pending.isEmpty else {
            print("[SYNC_ENGINE] No pending operations to push")
            return
        }

        print("[SYNC_ENGINE] pushPending — \(pending.count) operation(s) to push")
        statusText = "Pushing \(pending.count) change(s)…"

        let pushStartedAt = Date()

        var completedProjectTaskIds = Set<String>()
        if FeatureFlags.useDataActor, let actor = dataActor {
            // Connectivity guard lives here (on main) per PM guidance — the actor
            // method has no connectivity parameter and trusts callers to gate.
            guard connectivity.shouldAttemptSync else {
                print("[SYNC_ENGINE] Skipping push — connectivity says do not sync")
                return
            }
            completedProjectTaskIds = await actor.processPendingOperations()
        } else {
            await outboundProcessor?.processPendingOperations(
                context: modelContext,
                connectivity: connectivity
            )
        }

        clearCompletedProjectTaskSyncFlags(
            since: pushStartedAt,
            completedProjectTaskIds: completedProjectTaskIds
        )
        refreshPendingCount()
    }

    /// Safety net for the persistence invariant. Task sync runs off the
    /// recordOperation queue; `needsSync` alone is a conflict-resolution flag
    /// with NO outbound sweep for tasks (only photos have one). If any code path
    /// ever mutates a task and sets needsSync WITHOUT recordOperation, the edit
    /// would silently never reach the server (the historical
    /// handleTaskScheduleUpdate bug). This finds such orphans — needsSync with no
    /// pending op — re-drives their schedule state, and logs each so a new bypass
    /// surfaces immediately instead of losing data silently.
    ///
    /// Bug 0d183476 — the sweep must NOT blindly trust the local row. A task can
    /// carry `needsSync == true` with a stale local date for reasons OTHER than a
    /// genuine un-synced edit (e.g. a row left dirty by the previously-broken task
    /// merge gate). Pushing such a row up would resurrect the stale local date over
    /// an authoritative server NULL — the wrong direction (server/web is the
    /// authoritative view per project convention). So we only re-enqueue when there
    /// is POSITIVE evidence the local schedule value is a genuine, not-yet-synced
    /// local edit: a recent SyncOperation lifecycle event for this task. A real
    /// handleTaskScheduleUpdate-class orphan is caught here within seconds-to-minutes
    /// of the edit (the sweep runs at every pushPending), while a stale-needsSync row
    /// has no such recent local-write signal. Orphans lacking that evidence get
    /// `needsSync` cleared so the next inbound/realtime merge applies the server
    /// value and the row converges to server truth.
    func enqueueOrphanedTaskWrites() {
        guard let modelContext else { return }
        let orphans: [ProjectTask]
        do {
            orphans = try modelContext.fetch(
                FetchDescriptor<ProjectTask>(
                    predicate: #Predicate { $0.needsSync == true && $0.deletedAt == nil }
                )
            )
        } catch {
            print("[SYNC_ENGINE] Orphan-task sweep fetch failed: \(error)")
            return
        }
        guard !orphans.isEmpty else { return }

        // A canonical write sets needsSync AND records an op in one synchronous
        // step, so a needsSync task WITH a pending op is normal. Skip those, and
        // skip ones created in the last 30s to avoid racing an in-flight create.
        let graceCutoff = Date().addingTimeInterval(-30)
        let writer = ISO8601DateFormatter()
        writer.formatOptions = [.withInternetDateTime]

        // Window for "recent local write" — generous enough to cover a genuine
        // orphan edit (the sweep runs frequently, so a real bypass is detected long
        // before this expires) yet short enough that a stale-needsSync row from a
        // prior session is never mistaken for a live edit.
        let recentLocalWriteWindow: TimeInterval = 15 * 60

        var didMutate = false
        for task in orphans {
            if let created = task.createdAt, created > graceCutoff { continue }
            if hasOpenOperation(entityId: task.id) { continue }

            guard hasRecentLocalWrite(entityId: task.id, withinSeconds: recentLocalWriteWindow) else {
                // No evidence of a genuine recent local edit. Do NOT push the local
                // schedule up — it may be a stale value sitting over an authoritative
                // server NULL. Clear the dirty flag and let the next inbound/realtime
                // merge apply the server value.
                print("[SYNC_ENGINE] Orphaned task \(task.id) has no recent local-write signal — clearing needsSync to defer to server truth (not re-pushing local schedule).")
                task.needsSync = false
                didMutate = true
                continue
            }

            print("[SYNC_ENGINE] WARNING: orphaned task write (needsSync, no pending op, recent local edit): \(task.id) — re-driving schedule. A code path mutated this task without recordOperation.")

            var fields: [String: Any] = ["duration": task.duration]
            fields["start_date"] = task.startDate.map { writer.string(from: $0) } ?? NSNull()
            fields["end_date"] = task.endDate.map { writer.string(from: $0) } ?? NSNull()

            _ = recordOperation(
                entityType: .projectTask,
                entityId: task.id,
                operationType: "update",
                changedFields: fields,
                deferPush: true
            )
        }

        if didMutate {
            do {
                try modelContext.save()
            } catch {
                print("[SYNC_ENGINE] Orphan-task sweep save failed after clearing needsSync: \(error)")
            }
        }
    }

    /// True if a pending or in-flight SyncOperation already exists for this entity id.
    private func hasOpenOperation(entityId: String) -> Bool {
        guard let modelContext else { return false }
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let entityType = SyncEntityType.projectTask.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate { op in
                op.entityType == entityType &&
                (op.entityId == idLower || op.entityId == idUpper || op.entityId == entityId) &&
                (op.status == "pending" || op.status == "inProgress")
            }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Clears task dirty flags after their outbound operation completed during
    /// this push. The orphan sweep runs on the main context, so relying on the
    /// background actor context to clear `needsSync` can leave a stale main-context
    /// flag that immediately re-enqueues the same task.
    private func clearCompletedProjectTaskSyncFlags(
        since pushStartedAt: Date,
        completedProjectTaskIds: Set<String>
    ) {
        guard let modelContext else { return }

        let dirtyTasks: [ProjectTask]
        do {
            dirtyTasks = try modelContext.fetch(
                FetchDescriptor<ProjectTask>(
                    predicate: #Predicate { $0.needsSync == true && $0.deletedAt == nil }
                )
            )
        } catch {
            print("[SYNC_ENGINE] Failed to fetch dirty project tasks after push: \(error)")
            return
        }
        guard !dirtyTasks.isEmpty else { return }

        var clearedCount = 0
        for task in dirtyTasks {
            if hasOpenOperation(entityId: task.id) { continue }
            guard completedProjectTaskIds.contains(task.id.lowercased()) ||
                    hasCompletedOperation(entityId: task.id, since: pushStartedAt) else { continue }
            task.needsSync = false
            task.lastSyncedAt = Date()
            clearedCount += 1
        }

        guard clearedCount > 0 else { return }
        do {
            try modelContext.save()
            print("[SYNC_ENGINE] Cleared needsSync on \(clearedCount) project task(s) after outbound completion")
        } catch {
            print("[SYNC_ENGINE] Failed to clear completed project task sync flags: \(error)")
        }
    }

    private func hasCompletedOperation(entityId: String, since date: Date) -> Bool {
        guard let modelContext else { return false }
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let entityType = SyncEntityType.projectTask.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { op in
                op.entityType == entityType &&
                op.status == "completed" &&
                (op.entityId == idLower || op.entityId == idUpper || op.entityId == entityId)
            }
        )
        guard let ops = try? modelContext.fetch(descriptor), !ops.isEmpty else {
            return false
        }
        return ops.contains { ($0.completedAt ?? .distantPast) >= date }
    }

    /// True if a SyncOperation for this entity had ANY lifecycle event
    /// (created / attempted / completed) within the given window, regardless of
    /// current status. Positive evidence that the local row reflects a genuine,
    /// recent local write rather than a stale dirty flag. Mirrors
    /// RealtimeProcessor.hasRecentLocalWrite; considers all three timestamps so the
    /// window covers freshly-recorded, push-in-flight, recently-completed, and
    /// offline-delayed-push cases.
    private func hasRecentLocalWrite(entityId: String, withinSeconds seconds: TimeInterval) -> Bool {
        guard let modelContext else { return false }
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { op in
                op.entityId == idLower || op.entityId == idUpper || op.entityId == entityId
            }
        )
        guard let ops = try? modelContext.fetch(descriptor), !ops.isEmpty else {
            return false
        }
        let cutoff = Date().addingTimeInterval(-seconds)
        for op in ops {
            if op.createdAt >= cutoff { return true }
            if let last = op.lastAttemptedAt, last >= cutoff { return true }
            if let completed = op.completedAt, completed >= cutoff { return true }
        }
        return false
    }

    /// Drains local artifact queues that do not use `SyncOperation` rows.
    /// Dimensioned captures queue as `PhotoAnnotation.needsSync` so their
    /// HEIC/depth/sidecar assets survive annotation dismissal and retry here
    /// during the same pending-sync sweep as standard offline operations.
    func syncPendingLocalArtifacts() async {
        guard let modelContext else {
            print("[SYNC_ENGINE] Cannot sync local artifacts — not configured")
            return
        }
        await dimensionedPendingSyncer.syncPendingDimensions(modelContext: modelContext)
        refreshPendingCount()
    }

    /// Pulls delta changes from the server since the last sync timestamp via InboundProcessor.
    func pullDelta() async {
        guard let modelContext else {
            print("[SYNC_ENGINE] Cannot pull — not configured")
            return
        }

        print("[SYNC_ENGINE] pullDelta — checking for server changes")
        statusText = "Checking for updates…"

        // Build timestamps dictionary from stored values. For entity types
        // that have never synced on this install (no stored timestamp), pass
        // epoch so the entity is pulled fully on first encounter — otherwise
        // newly-added entity types (e.g. the catalog_* set landed after the
        // user's first sync) silently skip pullDelta forever.
        let firstSyncSentinel = Date(timeIntervalSince1970: 0)
        let syncStartedAt = Date()
        var sinceTimestamps: [SyncEntityType: Date] = [:]
        for entityType in SyncEntityType.allCases {
            sinceTimestamps[entityType] = overlappedTimestamp(
                lastSyncTimestamp(for: entityType) ?? firstSyncSentinel
            )
        }

        do {
            var failedEntities = Set<SyncEntityType>()
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                failedEntities = try await actor.deltaSync(companyId: companyId, since: sinceTimestamps)
                await applySpotlightSnapshot(from: actor)
            } else {
                failedEntities = try await inboundProcessor?.deltaSync(
                    context: modelContext,
                    since: sinceTimestamps
                ) ?? []
            }

            // Advance the cursor only for entities that did NOT fail this pull.
            // A failed entity keeps its old cursor so the next delta re-pulls its
            // changes; advancing past a transient failure would strand existing
            // rows (the deck-design blackout bug).
            advanceSyncCursors(SyncEntityType.allCases, excluding: failedEntities, to: syncStartedAt)
        } catch {
            print("[SYNC_ENGINE] pullDelta error: \(error)")
            hasError = true
            statusText = "Sync error"

            let classified = classifySyncError(error)
            AnalyticsService.shared.track(
                eventType: .error,
                eventName: "sync_failed",
                properties: [
                    "error_type": classified.localizedDescription,
                    "retry_count": 0,
                    "sync_phase": "delta_pull"
                ]
            )

            if case .authExpired = classified {
                NotificationCenter.default.post(name: .syncAuthExpired, object: nil)
            }
        }
    }

    /// Pulls delta changes from a specific timestamp (used for Realtime catch-up).
    private func deltaSyncSince(_ date: Date) async {
        guard let modelContext else { return }

        print("[SYNC_ENGINE] Catch-up delta sync from \(date)")
        statusText = "Catching up…"

        // Build timestamps dictionary with the same date for all entity types
        let syncStartedAt = Date()
        let catchUpSince = overlappedTimestamp(date)
        var sinceTimestamps: [SyncEntityType: Date] = [:]
        for entityType in SyncEntityType.allCases {
            sinceTimestamps[entityType] = catchUpSince
        }

        do {
            var failedEntities = Set<SyncEntityType>()
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                failedEntities = try await actor.deltaSync(companyId: companyId, since: sinceTimestamps)
                await applySpotlightSnapshot(from: actor)
            } else {
                failedEntities = try await inboundProcessor?.deltaSync(
                    context: modelContext,
                    since: sinceTimestamps
                ) ?? []
            }

            // Advance the cursor only for entities that did NOT fail this catch-up
            // (a failed entity keeps its old cursor and is retried next sync).
            advanceSyncCursors(SyncEntityType.allCases, excluding: failedEntities, to: syncStartedAt)
            statusText = "Synced"
            kickoffPhotoPrefetch()
        } catch {
            print("[SYNC_ENGINE] Catch-up delta error: \(error)")
        }
    }

    // MARK: - Spotlight Snapshot Dispatch

    /// Extracts the DataActor's accumulated Spotlight diff and dispatches it via
    /// the main-side SpotlightSyncTracker. Called after each actor-path sync
    /// (fullSync/pullDelta/deltaSyncSince). Gated on `hasCompletedInitialBackfill`
    /// so we don't fire targeted updates before the full initial index exists.
    private func applySpotlightSnapshot(from actor: DataActor) async {
        let snapshot = await actor.extractAndResetSpotlight()
        guard SpotlightIndexManager.shared.hasCompletedInitialBackfill else { return }
        guard !snapshot.isEmpty else { return }

        for (domain, ids) in snapshot.dirty {
            for id in ids {
                spotlightTracker.markDirty(domain: domain, id: id)
            }
        }
        for (domain, ids) in snapshot.deleted {
            for id in ids {
                spotlightTracker.markDeleted(domain: domain, id: id)
            }
        }

        guard let ctx = modelContext else { return }
        await spotlightTracker.dispatch(context: ctx)
    }

    // MARK: - Timestamp Persistence

    /// Returns the last successful pull timestamp for a given entity type,
    /// or nil if the entity has never been synced.
    func lastSyncTimestamp(for entityType: SyncEntityType) -> Date? {
        let key = "sync.lastPull.\(entityType.rawValue)"
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    /// Stores the last successful pull timestamp for a given entity type.
    func setLastSyncTimestamp(_ date: Date, for entityType: SyncEntityType) {
        let key = "sync.lastPull.\(entityType.rawValue)"
        UserDefaults.standard.set(date, forKey: key)
    }

    /// Advance the last-pull cursor for each entity that did NOT fail this pull.
    /// A failed entity keeps its old cursor so the next sync re-pulls it in full —
    /// advancing past a transient failure strands the entity's existing rows (the
    /// deck-design blackout bug). Delegates to the pure `cursorsToAdvance` so the
    /// invariant is unit-testable.
    func advanceSyncCursors(
        _ entities: [SyncEntityType],
        excluding failed: Set<SyncEntityType>,
        to date: Date
    ) {
        for entityType in Self.cursorsToAdvance(entities, excluding: failed) {
            setLastSyncTimestamp(date, for: entityType)
        }
    }

    /// Pure selection: which entities should advance their cursor (the input
    /// entities minus the ones that failed this pull). Order-preserving.
    nonisolated static func cursorsToAdvance(
        _ entities: [SyncEntityType],
        excluding failed: Set<SyncEntityType>
    ) -> [SyncEntityType] {
        entities.filter { !failed.contains($0) }
    }

    private func overlappedTimestamp(_ date: Date) -> Date {
        date.addingTimeInterval(-deltaOverlapWindow)
    }

    /// Clears all stored sync timestamps. Used on logout or full reset.
    func clearAllTimestamps() {
        for entityType in SyncEntityType.allCases {
            let key = "sync.lastPull.\(entityType.rawValue)"
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Operation Queries

    /// Returns all pending sync operations sorted by priority (immediate first)
    /// then by creation date (oldest first).
    func getPendingOperations() -> [SyncOperation] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "pending" },
            sortBy: [
                SortDescriptor(\.priority, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("[SYNC_ENGINE] Failed to fetch pending operations: \(error)")
            return []
        }
    }

    /// Returns all failed sync operations.
    func getFailedOperations() -> [SyncOperation] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "failed" },
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("[SYNC_ENGINE] Failed to fetch failed operations: \(error)")
            return []
        }
    }

    // MARK: - Cancel

    /// Cancels (deletes) a single pending sync operation.
    /// Does nothing if the operation is currently in-progress.
    func cancelOperation(_ operation: SyncOperation) {
        guard let modelContext else { return }
        guard operation.status != "inProgress" else {
            print("[SYNC_ENGINE] Cannot cancel in-progress operation \(operation.id)")
            return
        }
        modelContext.delete(operation)
        try? modelContext.save()
        refreshPendingCount()
        print("[SYNC_ENGINE] Cancelled operation \(operation.id) (\(operation.operationType) \(operation.entityType))")
    }

    // MARK: - Cleanup

    /// Deletes completed sync operations that are older than 24 hours.
    func cleanupCompletedOperations() {
        guard let modelContext else { return }

        let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.status == "completed" && $0.completedAt != nil
            }
        )

        do {
            let completed = try modelContext.fetch(descriptor)
            var deletedCount = 0

            for op in completed {
                if let completedAt = op.completedAt, completedAt < cutoff {
                    modelContext.delete(op)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                try modelContext.save()
                print("[SYNC_ENGINE] Cleaned up \(deletedCount) completed operation(s)")
            }
        } catch {
            print("[SYNC_ENGINE] Failed to cleanup completed operations: \(error)")
        }
    }

    // MARK: - Permission Change Handling

    /// Handles a realtime permission change: re-fetches permissions, compares scopes,
    /// and either triggers a full sync (expanded) or posts a contraction notification (contracted).
    private func handlePermissionChange() async {
        guard let userId = currentUserId else {
            print("[SYNC_ENGINE] Permission change ignored — no currentUserId")
            return
        }

        // 1. Capture old scopes before refresh
        let oldProjectScope = PermissionStore.shared.scope(for: "projects.view") ?? "all"
        let oldTaskScope = PermissionStore.shared.scope(for: "tasks.view") ?? "all"
        let oldClientScope = PermissionStore.shared.scope(for: "clients.view") ?? "all"

        // 2. Re-fetch permissions from Supabase
        await PermissionStore.shared.fetchPermissions(userId: userId)

        // 3. Read new scopes
        let newProjectScope = PermissionStore.shared.scope(for: "projects.view") ?? "all"
        let newTaskScope = PermissionStore.shared.scope(for: "tasks.view") ?? "all"
        let newClientScope = PermissionStore.shared.scope(for: "clients.view") ?? "all"

        // 4. Compare — did any scope expand or contract?
        let expanded = scopeRank(newProjectScope) > scopeRank(oldProjectScope) ||
                       scopeRank(newTaskScope) > scopeRank(oldTaskScope) ||
                       scopeRank(newClientScope) > scopeRank(oldClientScope)
        let contracted = scopeRank(newProjectScope) < scopeRank(oldProjectScope) ||
                         scopeRank(newTaskScope) < scopeRank(oldTaskScope) ||
                         scopeRank(newClientScope) < scopeRank(oldClientScope)

        if contracted {
            print("[SYNC_ENGINE] Permission scope CONTRACTED — posting contraction notification")
            NotificationCenter.default.post(name: .permissionScopeContracted, object: nil)
        } else if expanded {
            print("[SYNC_ENGINE] Permission scope EXPANDED — triggering full sync")
            await fullSync()
        } else {
            print("[SYNC_ENGINE] Permission scopes unchanged")
        }
    }

    /// Returns a numeric rank for a scope string. Higher = broader access.
    private func scopeRank(_ scope: String) -> Int {
        switch scope {
        case "all":      return 3
        case "assigned": return 2
        case "own":      return 1
        default:         return 0
        }
    }

    // MARK: - Private Helpers

    /// Refreshes the pendingOperationCount from SwiftData.
    private func refreshPendingCount() {
        let pending = getPendingOperations()
        let dimensionedCount: Int
        if let modelContext {
            dimensionedCount = dimensionedPendingSyncer
                .pendingDimensionedAnnotationCount(modelContext: modelContext)
        } else {
            dimensionedCount = 0
        }
        pendingOperationCount = pending.count + dimensionedCount

        // Manage the retry timer based on pending operations
        if pendingOperationCount > 0 {
            ensureRetryTimerRunning()
        }
    }

    // MARK: - Retry Timer

    /// Starts the periodic retry timer.
    private func startRetryTimer() {
        syncRetryTimer?.invalidate()
        syncRetryTimer = Timer.scheduledTimer(
            withTimeInterval: retryInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.retryTimerFired()
            }
        }
    }

    /// Ensures the retry timer is running if there are pending operations.
    private func ensureRetryTimerRunning() {
        guard syncRetryTimer == nil || !syncRetryTimer!.isValid else { return }
        startRetryTimer()
    }

    /// Called by the retry timer. Triggers a sync if conditions are met.
    private func retryTimerFired() {
        guard connectivity?.shouldAttemptSync == true else { return }
        guard pendingOperationCount > 0 else { return }
        guard !syncInProgress else { return }

        print("[SYNC_ENGINE] Retry timer fired — \(pendingOperationCount) pending operation(s)")

        Task {
            await triggerSync()
        }
    }
}
