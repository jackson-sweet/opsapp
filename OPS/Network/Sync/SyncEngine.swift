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
    nonisolated(unsafe) private var syncRetryTimer: Timer?

    /// The current authenticated user's ID, read from UserDefaults.
    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "currentUserId")
    }

    /// Retry interval in seconds for the periodic sync timer.
    private let retryInterval: TimeInterval = 180

    // MARK: - Processors

    private var outboundProcessor: OutboundProcessor?
    private var inboundProcessor: InboundProcessor?
    private var photoProcessor: PhotoProcessor?
    private var realtimeProcessor: RealtimeProcessor?
    private var backgroundScheduler: BackgroundSyncScheduler?

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

    init() {}

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

        // Initialize background scheduler
        let scheduler = BackgroundSyncScheduler()
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

    /// Registers BGTaskScheduler tasks. Call from AppDelegate.
    func registerBackgroundTasks() {
        backgroundScheduler?.registerTasks()
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
        dependsOnId: String? = nil
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

        // Create the SyncOperation
        let operation = SyncOperation(
            entityType: entityType.rawValue,
            entityId: entityId,
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

        print("[SYNC_ENGINE] Recorded \(operationType) for \(entityType.rawValue) [\(entityId)]")

        // Attempt immediate push if online
        if connectivity?.shouldAttemptSync == true {
            Task {
                await pushPending()
            }
        }

        return operation
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
        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                try await actor.fullSync(
                    companyId: companyId,
                    onProgress: { [weak self] entityType, _ in
                        Task { @MainActor [weak self] in
                            self?.statusText = "Syncing \(entityType.rawValue)…"
                        }
                    }
                )
                await applySpotlightSnapshot(from: actor)
            } else {
                try await inboundProcessor?.fullSync(
                    context: ctx,
                    onProgress: { [weak self] entityType, _ in
                        self?.statusText = "Syncing \(entityType.rawValue)…"
                    }
                )
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

        // Update timestamps only for entity types that were actually synced
        if !hasError {
            let now = Date()
            for entityType in InboundProcessor.syncOrder {
                setLastSyncTimestamp(now, for: entityType)
            }
        }

        // Push any pending local operations
        await pushPending()

        statusText = hasError ? "Sync error" : "Full sync complete"
        print("[SYNC_ENGINE] Full sync complete")

        if !hasError {
            kickoffPhotoPrefetch()
        }
    }

    /// Pushes all pending local operations to the server via OutboundProcessor.
    func pushPending() async {
        guard let modelContext, let connectivity else {
            print("[SYNC_ENGINE] Cannot push — not configured")
            return
        }

        let pending = getPendingOperations()
        guard !pending.isEmpty else {
            print("[SYNC_ENGINE] No pending operations to push")
            return
        }

        print("[SYNC_ENGINE] pushPending — \(pending.count) operation(s) to push")
        statusText = "Pushing \(pending.count) change(s)…"

        if FeatureFlags.useDataActor, let actor = dataActor {
            // Connectivity guard lives here (on main) per PM guidance — the actor
            // method has no connectivity parameter and trusts callers to gate.
            guard connectivity.shouldAttemptSync else {
                print("[SYNC_ENGINE] Skipping push — connectivity says do not sync")
                return
            }
            await actor.processPendingOperations()
        } else {
            await outboundProcessor?.processPendingOperations(
                context: modelContext,
                connectivity: connectivity
            )
        }

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

        // Build timestamps dictionary from stored values
        var sinceTimestamps: [SyncEntityType: Date] = [:]
        for entityType in SyncEntityType.allCases {
            if let ts = lastSyncTimestamp(for: entityType) {
                sinceTimestamps[entityType] = ts
            }
        }

        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                try await actor.deltaSync(companyId: companyId, since: sinceTimestamps)
                await applySpotlightSnapshot(from: actor)
            } else {
                try await inboundProcessor?.deltaSync(
                    context: modelContext,
                    since: sinceTimestamps
                )
            }

            // Update all timestamps on success
            let now = Date()
            for entityType in SyncEntityType.allCases {
                if sinceTimestamps[entityType] != nil {
                    setLastSyncTimestamp(now, for: entityType)
                }
            }
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
        var sinceTimestamps: [SyncEntityType: Date] = [:]
        for entityType in SyncEntityType.allCases {
            sinceTimestamps[entityType] = date
        }

        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                try await actor.deltaSync(companyId: companyId, since: sinceTimestamps)
                await applySpotlightSnapshot(from: actor)
            } else {
                try await inboundProcessor?.deltaSync(
                    context: modelContext,
                    since: sinceTimestamps
                )
            }

            // Update timestamps
            let now = Date()
            for entityType in SyncEntityType.allCases {
                setLastSyncTimestamp(now, for: entityType)
            }
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
        pendingOperationCount = pending.count

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
