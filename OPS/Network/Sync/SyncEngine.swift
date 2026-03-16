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

    // MARK: - Lifecycle

    init() {}

    deinit {
        syncRetryTimer?.invalidate()
    }

    // MARK: - Configuration

    /// Stores references to the model context and connectivity manager,
    /// initializes all processors, and starts the periodic retry timer.
    func configure(modelContext: ModelContext, connectivity: ConnectivityManager) {
        self.modelContext = modelContext
        self.connectivity = connectivity

        // Initialize processors
        self.outboundProcessor = OutboundProcessor()
        self.inboundProcessor = InboundProcessor()
        self.photoProcessor = PhotoProcessor()
        self.realtimeProcessor = RealtimeProcessor()

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

    /// Starts Realtime subscriptions for the given company.
    func startRealtime(companyId: String, userId: String? = nil) async {
        guard let modelContext else { return }
        await realtimeProcessor?.startListening(companyId: companyId, userId: userId, context: modelContext)
    }

    /// Stops Realtime subscriptions.
    func stopRealtime() async {
        await realtimeProcessor?.stopListening()
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
        }
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

        // Pull all entities via InboundProcessor
        guard let ctx = modelContext else { return }
        do {
            try await inboundProcessor?.fullSync(
                context: ctx,
                onProgress: { [weak self] entityType, _ in
                    self?.statusText = "Syncing \(entityType.rawValue)…"
                }
            )
        } catch {
            print("[SYNC_ENGINE] Full sync pull error: \(error)")
            hasError = true
            if case .authExpired = classifySyncError(error) {
                NotificationCenter.default.post(name: .syncAuthExpired, object: nil)
                return
            }
        }

        // Update all timestamps on success
        if !hasError {
            let now = Date()
            for entityType in SyncEntityType.allCases {
                setLastSyncTimestamp(now, for: entityType)
            }
        }

        // Push any pending local operations
        await pushPending()

        statusText = hasError ? "Sync error" : "Full sync complete"
        print("[SYNC_ENGINE] Full sync complete")
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

        await outboundProcessor?.processPendingOperations(
            context: modelContext,
            connectivity: connectivity
        )

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
            try await inboundProcessor?.deltaSync(
                context: modelContext,
                since: sinceTimestamps
            )

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
            if case .authExpired = classifySyncError(error) {
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
            try await inboundProcessor?.deltaSync(
                context: modelContext,
                since: sinceTimestamps
            )

            // Update timestamps
            let now = Date()
            for entityType in SyncEntityType.allCases {
                setLastSyncTimestamp(now, for: entityType)
            }
            statusText = "Synced"
        } catch {
            print("[SYNC_ENGINE] Catch-up delta error: \(error)")
        }
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
