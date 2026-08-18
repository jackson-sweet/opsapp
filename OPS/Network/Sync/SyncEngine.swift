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

/// Serializes outbound drains while coalescing any request that arrives during
/// an active pass into one additional pass. Every caller waits until the whole
/// coalesced drain is idle, which makes push-before-pull ordering deterministic.
@MainActor
final class SyncPushDrainCoordinator {
    private var isRunning = false
    private var rerunRequested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(_ operation: @MainActor () async -> Void) async {
        if isRunning {
            rerunRequested = true
            await waitUntilIdle()
            return
        }

        isRunning = true
        repeat {
            rerunRequested = false
            await operation()
        } while rerunRequested
        isRunning = false

        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    private func waitUntilIdle() async {
        guard isRunning else { return }

        await withCheckedContinuation { continuation in
            if isRunning {
                waiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
    }
}

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
    private var syncRequestedWhileInProgress: Bool = false
    private let pushDrainCoordinator = SyncPushDrainCoordinator()
    nonisolated(unsafe) private var syncRetryTimer: Timer?

    #if DEBUG
    /// Deterministic test seam invoked after every discard mutation and delete
    /// registration, immediately before SwiftData commits the transaction.
    var projectNoteDiscardFailureInjector: (() throws -> Void)?
    #endif

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

    /// An `inProgress` op older than this (or with a nil lastAttemptedAt) was
    /// stranded by an app kill mid-push; the launch / connectivity-restore
    /// re-enqueue sweep resets it to `pending`. PK-violation idempotency makes a
    /// replayed create safe.
    private let inProgressStalenessWindow: TimeInterval = 300

    /// The recoverable re-enqueue sweep runs at most ONCE per launch (plus on
    /// connectivity-restore). This gate keeps the 180s retry timer — which drains
    /// via pushPending — from ever resurrecting failed ops on a loop.
    private var hasSweptRecoverableThisLaunch = false

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
        // decode resilience then keeps a corrupt row from re-poisoning it.
        SyncEngine.runCursorRecovery(
            key: "sync.deckCursorRecoveryV1",
            entities: [.deckDesign]
        )

        // One-time recovery for poisoned project / project_task delta cursors
        // carried over from the 3.0.3 sync engine. That build used gte + a
        // whole-batch decode and advanced the cursor to a post-pull wall-clock
        // `now` with no overlap window and no per-entity error isolation, so a
        // row written during an in-flight pull (or a single undecodable row)
        // could strand schedule changes that delta pulls then never re-fetched —
        // crew saw stale schedules until a reinstall wiped UserDefaults. Resilient
        // decode + the overlap window fix FUTURE poisoning, but the cursor value
        // already on disk only self-corrects if a launch full-sync happens to
        // succeed. Clear the two schedule cursors once so the next pull re-fetches
        // from the epoch sentinel and heals the device in place — no reinstall.
        SyncEngine.runCursorRecovery(
            key: "sync.scheduleCursorRecoveryV1",
            entities: [.project, .projectTask]
        )

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
                    // Connectivity restored — actually re-establish Realtime. The
                    // old code only commented that it "will auto-reconnect" but
                    // never called startListening, so a device that lost and
                    // regained network kept a dead channel until the next
                    // foreground. ensureRealtime resubscribes + catch-up syncs.
                    let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                    if !companyId.isEmpty {
                        let userId = UserDefaults.standard.string(forKey: "currentUserId")
                        await self.ensureRealtime(companyId: companyId, userId: userId)
                    }
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

        // SYNC RECOVERY: resurrect work stranded by an app kill (inProgress) or a
        // spent retry budget (failed) once per launch so it ships this session
        // instead of sitting invisible. Runs regardless of pending count — a device
        // with ONLY failed/inProgress ops (no pending) never triggers a startup
        // push, so this is the correct home for the once-per-launch sweep (NOT
        // pushPending, which the 180s timer also drives). parked ops stay parked.
        if !hasSweptRecoverableThisLaunch {
            hasSweptRecoverableThisLaunch = true
            reenqueueRecoverableOperations()
            // Calendar rows left dirty by the old fire-and-forget writes have
            // nothing queued to push them — no operation exists to revive. Give
            // them one, so they drain or become visible (bug ef5a69e6).
            CalendarUserEventOutboundSync.backfillStrandedEvents(
                in: modelContext,
                syncEngine: self
            )
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

    /// Starts Realtime subscriptions for the given company (forced resubscribe).
    func startRealtime(companyId: String, userId: String? = nil) async {
        guard let modelContext else { return }
        await realtimeProcessor?.startListening(companyId: companyId, userId: userId, context: modelContext)
    }

    /// Ensures Realtime is live for the given company, subscribing only if it
    /// isn't already. Idempotent — safe to call on cold launch, login, every
    /// foreground, and connectivity-restore without churning the channel.
    func ensureRealtime(companyId: String, userId: String? = nil) async {
        guard let modelContext else { return }
        await realtimeProcessor?.ensureListening(companyId: companyId, userId: userId, context: modelContext)
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

    /// Atomically applies one local note edit and appends its two durable queue
    /// records. The RPC payload uses server column names, while
    /// `changedFields` deliberately uses the SwiftData property names consumed
    /// by inbound merge protection.
    @discardableResult
    func recordProjectNoteMentionEdit(
        note: ProjectNote,
        content: String,
        mentionedUserIds: [String],
        mentionEventId: String
    ) -> Bool {
        guard let modelContext else {
            print("[SYNC_ENGINE] Cannot record project-note mention edit — modelContext not configured")
            return false
        }

        let noteId = note.id.lowercased()
        let canonicalEventId = mentionEventId.lowercased()
        let updatePayload: Data
        let dispatchPayload: Data
        let previousUpdatedAtPayload: Any
        if let updatedAt = note.updatedAt {
            previousUpdatedAtPayload =
                updatedAt.timeIntervalSince1970
        } else {
            previousUpdatedAtPayload = NSNull()
        }
        do {
            updatePayload = try JSONSerialization.data(
                withJSONObject: [
                    ProjectNoteMentionEditSync.noteIdPayloadKey: noteId,
                    ProjectNoteMentionEditSync.contentPayloadKey: content,
                    ProjectNoteMentionEditSync.mentionedUserIdsPayloadKey: mentionedUserIds,
                    ProjectNoteMentionEditSync.eventIdPayloadKey: canonicalEventId,
                    ProjectNoteMentionEditSync.previousContentPayloadKey:
                        note.content,
                    ProjectNoteMentionEditSync
                        .previousMentionedUserIdsPayloadKey:
                        note.mentionedUserIds,
                    ProjectNoteMentionEditSync.previousNeedsSyncPayloadKey:
                        note.needsSync,
                    ProjectNoteMentionEditSync.previousUpdatedAtPayloadKey:
                        previousUpdatedAtPayload,
                ]
            )
            dispatchPayload = try JSONSerialization.data(
                withJSONObject: [
                    ProjectNoteMentionEditSync.eventIdPayloadKey: canonicalEventId
                ]
            )
        } catch {
            print("[SYNC_ENGINE] Failed to encode project-note mention edit: \(error)")
            return false
        }

        do {
            try ProjectNoteMentionQueueCoordinator.shared.withMutation {
                activeClaimIds in
                // The main context can retain objects changed by DataActor.
                // Persist any existing main-context work, then refresh while
                // holding the shared gate so the transaction below starts from
                // the same store snapshot the actor must claim against.
                if modelContext.hasChanges {
                    try modelContext.save()
                }
                modelContext.rollback()
                try modelContext.transaction {
                    let allOperations = try modelContext.fetch(
                        FetchDescriptor<SyncOperation>()
                    )
                    let activeStatuses = Set([
                        "pending",
                        "inProgress",
                        "failed",
                        "parked",
                    ])
                    let unresolvedCreate = allOperations
                        .filter {
                            $0.entityType
                                == SyncEntityType.projectNote.rawValue
                                && $0.entityId.lowercased() == noteId
                                && $0.operationType == "create"
                                && activeStatuses.contains($0.status)
                        }
                        .max {
                            if $0.createdAt != $1.createdAt {
                                return $0.createdAt < $1.createdAt
                            }
                            return $0.id.uuidString < $1.id.uuidString
                        }
                    let previousUpdate = allOperations
                        .filter {
                            ProjectNoteMentionEditSync
                                .isUpdateOperation($0)
                                && $0.entityId.lowercased() == noteId
                                && activeStatuses.contains($0.status)
                        }
                        .max {
                            if $0.createdAt != $1.createdAt {
                                return $0.createdAt < $1.createdAt
                            }
                            return $0.id.uuidString < $1.id.uuidString
                        }
                    let sameNoteUpdateIds = Set(
                        allOperations.compactMap {
                            operation -> String? in
                            guard ProjectNoteMentionEditSync
                                .isUpdateOperation(operation),
                                operation.entityId.lowercased()
                                    == noteId else {
                                return nil
                            }
                            return operation.id.uuidString
                        }
                    )
                    let updateOperation = SyncOperation(
                        entityType:
                            SyncEntityType.projectNote.rawValue,
                        entityId: noteId,
                        operationType:
                            ProjectNoteMentionEditSync
                            .updateOperationType,
                        payload: updatePayload,
                        changedFields: [
                            "content",
                            "mentionedUserIdsString",
                        ],
                        priority: 1,
                        dependsOnId:
                            previousUpdate?.id.uuidString
                                ?? unresolvedCreate?.id.uuidString
                    )
                    let dispatchOperation = SyncOperation(
                        entityType:
                            SyncEntityType.projectNote.rawValue,
                        entityId: canonicalEventId,
                        operationType:
                            ProjectNoteMentionEditSync
                            .dispatchOperationType,
                        payload: dispatchPayload,
                        changedFields: [],
                        priority: 1,
                        dependsOnId:
                            updateOperation.id.uuidString
                    )

                    for operation in allOperations where
                        operation.entityType
                            == SyncEntityType.projectNote.rawValue
                            && operation.entityId.lowercased()
                                == noteId
                            && (
                                ProjectNoteMentionEditSync
                                    .isUpdateOperation(operation)
                                    || operation.operationType
                                        == "create"
                            )
                            && operation.status == "failed"
                    {
                        operation.status = "pending"
                        operation.retryCount = 0
                        operation.lastAttemptedAt = nil
                        operation.completedAt = nil
                    }

                    note.content = content
                    note.mentionedUserIds = mentionedUserIds
                    note.updatedAt = Date()
                    note.needsSync = true

                    // A dispatch whose request is currently executing has
                    // crossed the mutation boundary. Only work without an
                    // active execution lease may move behind this replacement.
                    for operation in allOperations where
                        ProjectNoteMentionEditSync
                            .isDispatchOperation(operation)
                            && operation.status != "completed"
                            && operation.status != "inProgress"
                            && !activeClaimIds
                                .contains(operation.id)
                            && operation.dependsOnId.map(
                                sameNoteUpdateIds.contains
                            ) == true
                    {
                        if operation.status == "failed" {
                            operation.status = "pending"
                            operation.retryCount = 0
                            operation.lastAttemptedAt = nil
                            operation.completedAt = nil
                        }
                        operation.dependsOnId =
                            updateOperation.id.uuidString
                    }

                    modelContext.insert(updateOperation)
                    modelContext.insert(dispatchOperation)
                    ProjectNoteMentionEditSync
                        .supersedeParkedUpdatesReplacedByLaterEdits(
                            in:
                                allOperations
                                + [
                                    updateOperation,
                                    dispatchOperation,
                                ]
                        )
                }
            }
        } catch {
            print("[SYNC_ENGINE] Failed to save project-note mention edit: \(error)")
            return false
        }

        refreshPendingCount()
        if connectivity?.shouldAttemptSync == true {
            Task { @MainActor [weak self] in
                await self?.pushPending()
            }
        }
        return true
    }

    /// Atomically tombstones one note, retires every mention delivery that has
    /// not started, and queues the generic delete behind any same-note write
    /// already in flight (or the unresolved create for an offline-new note).
    @discardableResult
    func recordProjectNoteDelete(
        note: ProjectNote,
        deletedAt: Date = Date()
    ) -> Bool {
        guard let modelContext else { return false }
        let noteId = note.id.lowercased()
        let payload: Data
        let deletedAtString = ISO8601DateFormatter().string(from: deletedAt)
        do {
            payload = try JSONSerialization.data(
                withJSONObject: ["deleted_at": deletedAtString]
            )
        } catch {
            print("[SYNC_ENGINE] Failed to encode project-note delete: \(error)")
            return false
        }

        do {
            try ProjectNoteMentionQueueCoordinator.shared.withMutation {
                activeClaimIds in
                if modelContext.hasChanges {
                    try modelContext.save()
                }
                modelContext.rollback()
                try modelContext.transaction {
                    let operations = try modelContext.fetch(
                        FetchDescriptor<SyncOperation>()
                    )
                    let sameNoteUpdates = operations.filter {
                        ProjectNoteMentionEditSync
                            .isUpdateOperation($0)
                            && $0.entityId.lowercased() == noteId
                    }
                    let eventIds = Set(
                        sameNoteUpdates.compactMap {
                            update -> String? in
                            guard let payload = try?
                                JSONSerialization.jsonObject(
                                    with: update.payload
                                ) as? [String: Any] else {
                                return nil
                            }
                            return (
                                payload[
                                    ProjectNoteMentionEditSync
                                        .eventIdPayloadKey
                                ] as? String
                            )?.lowercased()
                        }
                    )
                    let sameNoteDispatches = operations.filter {
                        ProjectNoteMentionEditSync
                            .isDispatchOperation($0)
                            && eventIds.contains(
                                $0.entityId.lowercased()
                            )
                    }
                    let inFlightMentionOperation = (
                        sameNoteUpdates + sameNoteDispatches
                    )
                    .filter {
                        $0.status == "inProgress"
                            || activeClaimIds
                                .contains($0.id)
                    }
                    .max {
                        if $0.createdAt != $1.createdAt {
                            return $0.createdAt < $1.createdAt
                        }
                        return $0.id.uuidString
                            < $1.id.uuidString
                    }
                    let unresolvedCreate = operations
                        .filter {
                            ProjectNoteMentionEditSync
                                .isProjectNoteCreateOperation($0)
                                && $0.entityId.lowercased()
                                    == noteId
                                && $0.status != "completed"
                        }
                        .max {
                            if $0.createdAt != $1.createdAt {
                                return $0.createdAt < $1.createdAt
                            }
                            return $0.id.uuidString
                                < $1.id.uuidString
                        }
                    let dependencyId =
                        inFlightMentionOperation?.id.uuidString
                            ?? unresolvedCreate?.id.uuidString
                    let deleteOperation = SyncOperation(
                        entityType:
                            SyncEntityType.projectNote.rawValue,
                        entityId: noteId,
                        operationType: "delete",
                        payload: payload,
                        changedFields: ["deletedAt"],
                        priority: 1,
                        dependsOnId: dependencyId
                    )
                    let retiredIds = Set(
                        (
                            sameNoteUpdates
                                + sameNoteDispatches
                        ).compactMap {
                            $0.status == "completed"
                                || $0.status == "inProgress"
                                || activeClaimIds
                                    .contains($0.id)
                                ? nil
                                : $0.id
                        }
                    )

                    if let unresolvedCreate,
                       unresolvedCreate.status == "failed" {
                        unresolvedCreate.status = "pending"
                        unresolvedCreate.retryCount = 0
                        unresolvedCreate.lastAttemptedAt = nil
                        unresolvedCreate.completedAt = nil
                    }
                    note.deletedAt = deletedAt
                    note.needsSync = true
                    if unresolvedCreate?.status != "parked" {
                        for operation in operations where
                            retiredIds.contains(operation.id)
                        {
                            modelContext.delete(operation)
                        }
                    }
                    modelContext.insert(deleteOperation)
                    if let unresolvedCreate,
                       ProjectNoteMentionEditSync
                        .retireParkedCreateWithQueuedDelete(
                            unresolvedCreate,
                            in: operations + [deleteOperation]
                        ) {
                        note.needsSync = false
                    }
                }
            }
        } catch {
            print("[SYNC_ENGINE] Failed to queue project-note delete: \(error)")
            return false
        }

        refreshPendingCount()
        ProjectNoteChangeSignal.post(projectId: note.projectId)
        if connectivity?.shouldAttemptSync == true {
            Task { @MainActor [weak self] in
                await self?.pushPending()
            }
        }
        return true
    }

    /// One operation to enqueue via `recordOperations(_:)`.
    struct BulkOperationSpec {
        let entityType: SyncEntityType
        let entityId: String
        let operationType: String
        let changedFields: [String: Any]
    }

    enum TransactionalOperationStagingError: Error {
        case contextUnavailable
        case contextMismatch
        case payloadEncodingFailed
    }

    /// Inserts a complete ordered batch into an already-open ModelContext
    /// transaction without saving it. Payloads are encoded before the first
    /// insert, so the production stager itself is all-or-nothing; the caller's
    /// transaction owns the final atomic commit with the associated model edits.
    func stageOperationsForTransaction(
        _ specs: [BulkOperationSpec],
        in transactionContext: ModelContext
    ) throws -> [SyncOperation] {
        guard let modelContext else {
            throw TransactionalOperationStagingError.contextUnavailable
        }
        guard modelContext === transactionContext else {
            throw TransactionalOperationStagingError.contextMismatch
        }
        guard !specs.isEmpty else { return [] }

        let prepared: [(spec: BulkOperationSpec, payload: Data)]
        do {
            prepared = try specs.map { spec in
                (
                    spec,
                    try JSONSerialization.data(
                        withJSONObject: spec.changedFields,
                        options: []
                    )
                )
            }
        } catch {
            throw TransactionalOperationStagingError.payloadEncodingFailed
        }

        var nextCreatedAt = Date()
        return prepared.map { preparedOperation in
            let spec = preparedOperation.spec
            let operation = SyncOperation(
                entityType: spec.entityType.rawValue,
                entityId: spec.entityId.lowercased(),
                operationType: spec.operationType,
                payload: preparedOperation.payload,
                changedFields: Array(spec.changedFields.keys),
                previousValues: nil,
                priority: 1,
                dependsOnId: nil
            )
            operation.createdAt = nextCreatedAt
            nextCreatedAt = Date(
                timeIntervalSinceReferenceDate:
                    nextCreatedAt.timeIntervalSinceReferenceDate.nextUp
            )
            transactionContext.insert(operation)
            return operation
        }
    }

    /// Refreshes observable outbox state only after the caller's shared model +
    /// ledger transaction has committed successfully.
    func didPersistStagedOperations(_ operations: [SyncOperation]) {
        guard !operations.isEmpty else { return }
        refreshPendingCount()
        print("[SYNC_ENGINE] Persisted \(operations.count) staged operation(s) atomically")
    }

    /// True when this engine writes through `context` — i.e. when the one
    /// save inside `recordOperations` also commits pending edits made on
    /// `context`. Callers that let the batch commit their own model changes
    /// must confirm this, mirroring the `===` guard in
    /// `stageOperationsForTransaction`.
    func sharesModelContext(with context: ModelContext) -> Bool {
        modelContext === context
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

    /// Refreshes queue state after a feature appends a custom SyncOperation
    /// inside the same SwiftData transaction as its local model changes.
    /// Custom commands use this path because calling `recordOperation` would
    /// require a second save and create a crash window between state and queue.
    func notifyDurableOperationQueued(pullAfterPush: Bool = false) {
        refreshPendingCount()
        guard connectivity?.shouldAttemptSync == true else { return }
        Task { @MainActor [weak self] in
            if pullAfterPush {
                await self?.triggerSync()
            } else {
                await self?.pushPending()
            }
        }
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

    /// Fetches ONE client row by id and merges it into SwiftData.
    ///
    /// Opening a project's details needs that client row current and nothing
    /// else. It used to call `triggerSync()` — a whole-app push + pull over
    /// every SyncEntityType, plus orphan sweeps and a photo-prefetch kickoff —
    /// on EVERY open, which is what made the sheet stutter.
    ///
    /// Offline parity with the path it replaces: gated on `shouldAttemptSync`,
    /// so a degraded or airplane-mode open fails fast here instead of riding a
    /// URLSession timeout, and the screen renders from local data exactly as
    /// before.
    ///
    /// Intentionally does NOT acquire the `syncInProgress` lock and never
    /// touches `statusText` / `isSyncing` — it is a single-row read, not a sync
    /// pass, and must not present itself to the operator as one.
    func syncClientNow(clientId: String) async {
        guard !clientId.isEmpty else { return }

        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] syncClientNow: network unavailable — skipping")
            return
        }

        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                try await actor.syncClientOnly(clientId: clientId, companyId: companyId)
            } else {
                guard let modelContext, let inboundProcessor else {
                    print("[SYNC_ENGINE] syncClientNow: not configured")
                    return
                }
                try await inboundProcessor.syncClient(clientId: clientId, context: modelContext)
            }
        } catch {
            print("[SYNC_ENGINE] syncClientNow error: \(error)")
        }
    }

    /// Triggers a full push-then-pull cycle, guarding against concurrent syncs.
    func triggerSync() async {
        guard !syncInProgress else {
            syncRequestedWhileInProgress = true
            print(
                "[SYNC_ENGINE] Sync already in progress — queued one follow-up"
            )
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
            drainQueuedSyncRequest()
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

    private func drainQueuedSyncRequest() {
        guard syncRequestedWhileInProgress else { return }
        syncRequestedWhileInProgress = false
        Task { @MainActor [weak self] in
            await self?.triggerSync()
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
            drainQueuedSyncRequest()
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

    /// Schedule-only refresh backing pull-to-refresh — projects, tasks, task
    /// types, and calendar events. A lean "check for schedule updates" for when
    /// realtime hasn't delivered an edit, instead of a full all-entity sync that
    /// drags the whole catalog/estimates/invoices/photos down on every pull.
    /// Still pushes pending local ops so an offline edit isn't stranded.
    @discardableResult
    func refreshScheduleData(companyId requestedCompanyId: String? = nil) async -> Bool {
        // Briefly defer to an in-flight sync rather than racing it.
        if syncInProgress {
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                if !syncInProgress { break }
            }
            guard !syncInProgress else {
                print("[SYNC_ENGINE] Sync in progress — skipping schedule refresh")
                return false
            }
        }

        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] Network not available — skipping schedule refresh")
            statusText = "Offline — schedule refresh deferred"
            return false
        }

        let companyId = requestedCompanyId
            ?? UserDefaults.standard.string(forKey: "currentUserCompanyId")
            ?? ""
        guard !companyId.isEmpty else {
            print("[SYNC_ENGINE] Cannot refresh schedule — no company ID")
            statusText = "Sync error"
            return false
        }

        syncInProgress = true
        isSyncing = true
        hasError = false
        statusText = "Checking for schedule updates…"

        defer {
            syncInProgress = false
            isSyncing = false
            refreshPendingCount()
            drainQueuedSyncRequest()
        }

        guard let ctx = modelContext else { return false }
        var taskTypesRefreshed = false
        do {
            let failedEntities: Set<SyncEntityType>
            if FeatureFlags.useDataActor, let actor = dataActor {
                failedEntities = try await actor.syncScheduleEntities(companyId: companyId)
            } else {
                // Legacy path has no scoped pull — fall back to a full inbound
                // sync (rare: the actor path is the default).
                failedEntities = try await inboundProcessor?.fullSync(
                    context: ctx,
                    onProgress: { _, _ in }
                ) ?? [.taskType]
            }
            taskTypesRefreshed = !failedEntities.contains(.taskType)
            hasError = !failedEntities.isEmpty
        } catch {
            print("[SYNC_ENGINE] Schedule refresh error: \(error)")
            hasError = true
            let classified = classifySyncError(error)
            if case .authExpired = classified {
                NotificationCenter.default.post(name: .syncAuthExpired, object: nil)
                return false
            }
        }

        // Push any pending local schedule edits so a manual refresh reconciles
        // both directions, not just inbound.
        await pushPending()

        statusText = hasError ? "Sync error" : "Schedule up to date"
        return taskTypesRefreshed
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

        await pushDrainCoordinator.run {
            // Safety net: recover any task whose local edit never produced an
            // outbound op (needsSync set without recordOperation) before reading the
            // pending queue, so a future bypass can't silently drop a write.
            self.enqueueOrphanedTaskWrites()

            // Repair historical site-visit rows whose local dirty flag exists
            // without a durable queue record. The coordinator is company-scoped
            // and skips all open/failed/parked work, so this never revives a
            // permanent rejection or crosses tenants.
            self.enqueueOrphanedSiteVisitWrites()

            // Settle chains whose site visit was deleted in OPS: a completion
            // carrying `cannot_complete_deleted_site_visit` can never land, and
            // its children are RLS-blocked behind the deleted parent. The whole
            // chain moves to protected vault custody (visible in PENDING WORK)
            // instead of retrying forever. Runs after the orphan sweep so a
            // reconstructed parent's dirty flags are already accounted for.
            self.settleDeletedParentSiteVisitChains()

            // A media upload that parked because its local bytes were gone
            // can never be revived by the normal path (parked work never
            // auto-retries, and the orphan sweep treats parked as unresolved).
            // Re-read the filesystem: retire pointers that are truly dead, and
            // hand back any whose file is actually present.
            SiteVisitParkedMediaReconciler.reconcile(in: modelContext)

            // Same class of safety net for deck→project links: a stranded link
            // (needsSync set, no op recorded) re-records its update here and
            // drains in this very pass.
            self.enqueueStrandedDeckDesignLinks()

            // One-time server-orphan heal for deck→lead links (RC3): records a
            // guarded linkOpportunity op for every locally-linked design whose
            // server row may still be an orphan (older builds stripped the link).
            // Idempotent + gated by a UserDefaults flag, so it drains in this pass
            // exactly once per device.
            self.enqueueDeckDesignLinkBackfillOnce()

            // Legacy site-visit rows carry no author: `created_by` arrived with
            // the V19→V20 migration, which could only default existing rows to
            // nil. Such a row can never build a valid payload, so it failed
            // before every send and — being a child — dammed its visit's
            // completion behind it (bug 70db7ed6). Heal the whole backlog here,
            // ahead of the drain, so no row spends its turn failing.
            self.healSiteVisitAuthorshipOnce()

            // Recover a chain persisted between the instant a predecessor parked
            // and the normal post-failure reconciliation. A later full replacement
            // proves the parked payload and its event are safe to supersede.
            self.reconcileSupersededParkedProjectNoteMentionUpdates()
            self.reconcileParkedProjectNoteCreateDeleteChains()

            let pending = self.getPendingOperations()
            guard !pending.isEmpty else {
                print("[SYNC_ENGINE] No pending operations to push")
                return
            }

            print("[SYNC_ENGINE] pushPending — \(pending.count) operation(s) to push")
            self.statusText = "Pushing \(pending.count) change(s)…"

            let pushStartedAt = Date()

            var completedProjectTaskIds = Set<String>()
            if FeatureFlags.useDataActor, let actor = self.dataActor {
                // Connectivity guard lives here (on main) per PM guidance — the actor
                // method has no connectivity parameter and trusts callers to gate.
                guard connectivity.shouldAttemptSync else {
                    print("[SYNC_ENGINE] Skipping push — connectivity says do not sync")
                    return
                }
                completedProjectTaskIds.formUnion(
                    await actor.processPendingOperations()
                )
            } else {
                await self.outboundProcessor?.processPendingOperations(
                    context: modelContext,
                    connectivity: connectivity
                )
            }

            self.clearCompletedProjectTaskSyncFlags(
                since: pushStartedAt,
                completedProjectTaskIds: completedProjectTaskIds
            )
            self.refreshPendingCount()
        }
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
            if hasOpenOperation(entityType: .projectTask, entityId: task.id) { continue }

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

    /// Recovery sweep for deck→project links stranded by the pre-fix
    /// site-visit conversion handoff: needsSync == true with a projectId but
    /// no SyncOperation ever recorded — the link exists only on the capturing
    /// phone, so the deck shows project_id NULL to every other device. This
    /// re-records a durable {project_id, updated_at} update (deferPush — the
    /// surrounding pushPending drains it in the same pass). Decks with an open
    /// op are already in flight; decks with any recent op lifecycle are
    /// converging through the normal pipeline (needsSync clears on the next
    /// inbound merge) and must not be spammed with link updates.
    func enqueueStrandedDeckDesignLinks() {
        guard let modelContext else { return }
        let stranded: [DeckDesign]
        do {
            stranded = try modelContext.fetch(
                FetchDescriptor<DeckDesign>(
                    predicate: #Predicate { $0.needsSync == true && $0.deletedAt == nil }
                )
            )
        } catch {
            print("[SYNC_ENGINE] Stranded-deck sweep fetch failed: \(error)")
            return
        }
        guard !stranded.isEmpty else { return }

        let writer = ISO8601DateFormatter()
        for design in stranded {
            guard let projectId = design.projectId, !projectId.isEmpty else { continue }
            guard !hasOpenOperation(entityType: .deckDesign, entityId: design.id) else { continue }
            guard !hasRecentLocalWrite(entityId: design.id, withinSeconds: 15 * 60) else { continue }

            print("[SYNC_ENGINE] Stranded deck link (needsSync, no op): \(design.id) — re-recording project link \(projectId)")
            _ = recordOperation(
                entityType: .deckDesign,
                entityId: design.id,
                operationType: "update",
                changedFields: [
                    "project_id": projectId,
                    "updated_at": writer.string(from: Date())
                ],
                deferPush: true
            )
        }
    }

    /// One-time server-orphan heal for deck→lead links (RC3). Before the
    /// linked-INSERT fix, every deck create/update stripped opportunity_id, so a
    /// deck drawn on a lead reached the server with opportunity_id NULL — an orphan
    /// the reparent guard trigger then blocked from ever being PATCHed. This sweep,
    /// gated once by UserDefaults `deckDesignLinkBackfill.v1`, records a guarded
    /// `linkOpportunity` op for every local design that carries a lead link
    /// (`opportunityId != nil`, not deleted) and has no open link op already. The
    /// RPC is idempotent (`already_linked` → success) and a different-lead conflict
    /// parks visibly, so it is safe on any device state; the flag flips true only
    /// after a clean pass so a mid-sweep interruption retries instead of skipping.
    func enqueueDeckDesignLinkBackfillOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "deckDesignLinkBackfill.v1") else { return }
        guard let modelContext else { return }

        let linked: [DeckDesign]
        do {
            linked = try modelContext.fetch(
                FetchDescriptor<DeckDesign>(
                    predicate: #Predicate { $0.opportunityId != nil && $0.deletedAt == nil }
                )
            )
        } catch {
            print("[SYNC_ENGINE] Deck link backfill fetch failed: \(error)")
            return
        }

        for design in linked {
            guard let opportunityId = design.opportunityId, !opportunityId.isEmpty else { continue }
            guard !hasOpenLinkOperation(entityId: design.id) else { continue }

            print("[SYNC_ENGINE] Deck link backfill: recording linkOpportunity for \(design.id) → \(opportunityId)")
            _ = recordOperation(
                entityType: .deckDesign,
                entityId: design.id,
                operationType: "linkOpportunity",
                changedFields: ["opportunity_id": opportunityId.lowercased()],
                deferPush: true
            )
        }

        // Flip the one-time flag only after a clean pass (no fetch failure) — a
        // mid-sweep crash must retry rather than silently skip designs.
        defaults.set(true, forKey: "deckDesignLinkBackfill.v1")
    }

    /// One-time authorship heal for site-visit rows the V19→V20 lightweight
    /// migration left holding a nil `createdBy` (bug 70db7ed6). Resolves each
    /// row's author from its parent visit, else the operator signed in on this
    /// phone, and persists it — `created_by` only, so nothing is re-dirtied.
    ///
    /// The flag flips only after a pass that left NOTHING unresolved: a launch
    /// that runs before sign-in completes resolves nobody, and must run again
    /// next launch rather than retire having healed no one.
    func healSiteVisitAuthorshipOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "siteVisitAuthorBackfill.v1") else { return }
        guard let modelContext else { return }

        do {
            let result = try SiteVisitAuthorHeal.backfillAuthors(
                in: modelContext,
                sessionUserId: SiteVisitAuthorHeal.sessionUserId()
            )
            if !result.healedIds.isEmpty {
                print("[SYNC_ENGINE] Site-visit author backfill healed \(result.healedIds.count) row(s)")
            }
            if result.isClean {
                defaults.set(true, forKey: "siteVisitAuthorBackfill.v1")
            } else {
                print("[SYNC_ENGINE] Site-visit author backfill left \(result.unresolvedIds.count) row(s) unresolved — retrying next launch")
            }
        } catch {
            print("[SYNC_ENGINE] Site-visit author backfill failed: \(error)")
        }
    }

    /// True if a pending/inProgress `linkOpportunity` op already exists for this
    /// deck design — stops the backfill stacking a duplicate link op on a design
    /// the recorder (or a prior backfill attempt) already enqueued.
    private func hasOpenLinkOperation(entityId: String) -> Bool {
        guard let modelContext else { return false }
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let deckType = SyncEntityType.deckDesign.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate { op in
                op.entityType == deckType &&
                op.operationType == "linkOpportunity" &&
                (op.entityId == idLower || op.entityId == idUpper || op.entityId == entityId) &&
                (op.status == "pending" || op.status == "inProgress")
            }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// True if a pending or in-flight SyncOperation already exists for this entity.
    private func hasOpenOperation(entityType type: SyncEntityType, entityId: String) -> Bool {
        guard let modelContext else { return false }
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let entityType = type.rawValue
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
            if hasOpenOperation(entityType: .projectTask, entityId: task.id) { continue }
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
        // Pending PencilKit annotation writes (offline edits + soft-delete
        // tombstones) track `PhotoAnnotation.needsSync` the same way but
        // previously only retried when a photo viewer happened to open —
        // drain them on this same sweep so a stuck tombstone converges on
        // the next sync cycle instead of waiting for a viewer visit.
        await PhotoAnnotationSyncManager.shared.syncPendingAnnotations(modelContext: modelContext)
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

    /// One-time, per-device cursor recovery. If `key` has not yet been recorded
    /// in `defaults`, clears the last-pull delta cursor for each entity in
    /// `entities` (so the next pull re-fetches from the epoch sentinel) and
    /// records `key` so the recovery never runs again. Returns whether it ran.
    /// Pure and defaults-injectable so the gating is unit-testable.
    @discardableResult
    nonisolated static func runCursorRecovery(
        key: String,
        entities: [SyncEntityType],
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !defaults.bool(forKey: key) else { return false }
        for entity in entities {
            defaults.removeObject(forKey: "sync.lastPull.\(entity.rawValue)")
        }
        defaults.set(true, forKey: key)
        return true
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

    /// Retires permanently rejected mention updates only when a later
    /// full-authoritative replacement is already queued directly behind them.
    /// Used by both live failure handling and the push-start recovery sweep.
    @discardableResult
    func reconcileSupersededParkedProjectNoteMentionUpdates() -> Bool {
        guard let modelContext else { return false }
        do {
            let operations = try modelContext.fetch(
                FetchDescriptor<SyncOperation>()
            )
            var didChange = false
            try modelContext.transaction {
                didChange = ProjectNoteMentionEditSync
                    .supersedeParkedUpdatesReplacedByLaterEdits(
                        in: operations
                    )
            }
            if didChange {
                refreshPendingCount()
            }
            return didChange
        } catch {
            print(
                "[SYNC_ENGINE] Failed to reconcile parked project-note mention chain: \(error)"
            )
            return false
        }
    }

    func enqueueOrphanedSiteVisitWrites() {
        guard let modelContext else { return }
        let companyId = UserDefaults.standard.string(
            forKey: "currentUserCompanyId"
        )?.lowercased() ?? ""
        let userId = UserDefaults.standard.string(
            forKey: "currentUserId"
        )?.lowercased() ?? ""
        guard !companyId.isEmpty, !userId.isEmpty else { return }

        do {
            let result = try SiteVisitOrphanRecovery.recover(
                in: modelContext,
                activeUserId: userId,
                activeCompanyId: companyId,
                quarantine: { record in
                    try SiteVisitRecoveryVault.shared.recordQuarantine(
                        record,
                        from: modelContext
                    )
                }
            )
            let marker = "site_visit_orphan_recovery_v1:\(userId):\(companyId)"
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: marker)
            if !result.operationIds.isEmpty {
                print(
                    "[SYNC_ENGINE] Recovered \(result.operationIds.count) orphaned site-visit operation(s)"
                )
                refreshPendingCount()
            }
        } catch {
            print("[SYNC_ENGINE] Site-visit orphan sweep failed: \(error)")
        }
    }

    /// Converts parked/failed deleted-parent completions into protected vault
    /// custody and settles their whole chain (SITE VISIT SYNC WEDGE). The
    /// outbound engines only park the failing op — the vault is MainActor-bound,
    /// so settlement happens here on the sweep cadence. Idempotent; a vault
    /// failure aborts cleanly and the next sweep retries.
    func settleDeletedParentSiteVisitChains() {
        guard let modelContext else { return }
        let companyId = UserDefaults.standard.string(
            forKey: "currentUserCompanyId"
        )?.lowercased() ?? ""
        let userId = UserDefaults.standard.string(
            forKey: "currentUserId"
        )?.lowercased() ?? ""
        guard !companyId.isEmpty, !userId.isEmpty else { return }

        do {
            let result = try SiteVisitDeletedParentSettlement.sweep(
                in: modelContext,
                activeUserId: userId,
                activeCompanyId: companyId,
                quarantine: { record in
                    try SiteVisitRecoveryVault.shared.recordQuarantine(
                        record,
                        from: modelContext
                    )
                }
            )
            if !result.settledOperationIds.isEmpty {
                print(
                    "[SYNC_ENGINE] Settled \(result.settledOperationIds.count) "
                        + "operation(s) for \(result.quarantinedVisitIds.count) "
                        + "visit(s) deleted in OPS — moved to protected custody"
                )
                AnalyticsService.shared.track(
                    eventType: .error,
                    eventName: "sync_deleted_parent_settled",
                    properties: [
                        "visit_count": result.quarantinedVisitIds.count,
                        "operation_count": result.settledOperationIds.count
                    ]
                )
                refreshPendingCount()
            }
        } catch {
            print("[SYNC_ENGINE] Deleted-parent settlement failed: \(error)")
        }
    }

    /// Idempotent restart recovery for the crash window between persisting a
    /// permanently rejected local-only create and retiring its already-queued
    /// delete. The whole chain and tombstoned note dirty flag converge in one
    /// transaction before every push, so the delete can never depend forever
    /// on a parked create.
    @discardableResult
    func reconcileParkedProjectNoteCreateDeleteChains() -> Bool {
        guard let modelContext else { return false }
        do {
            var didChange = false
            try ProjectNoteMentionQueueCoordinator.shared.withMutation { _ in
                if modelContext.hasChanges {
                    try modelContext.save()
                }
                modelContext.rollback()
                try modelContext.transaction {
                    let operations = try modelContext.fetch(
                        FetchDescriptor<SyncOperation>()
                    )
                    let notes = try modelContext.fetch(
                        FetchDescriptor<ProjectNote>()
                    )
                    for create in operations where
                        ProjectNoteMentionEditSync
                            .isProjectNoteCreateOperation(create)
                            && create.status == "parked"
                    {
                        guard ProjectNoteMentionEditSync
                            .retireParkedCreateWithQueuedDelete(
                                create,
                                in: operations
                            ) else {
                            continue
                        }
                        didChange = true
                        let noteId = create.entityId.lowercased()
                        if let note = notes.first(where: {
                            $0.id.lowercased() == noteId
                        }), note.deletedAt != nil {
                            note.needsSync = false
                        }
                    }
                }
            }
            if didChange {
                refreshPendingCount()
            }
            return didChange
        } catch {
            print(
                "[SYNC_ENGINE] Failed parked project-note create/delete recovery: \(error)"
            )
            return false
        }
    }

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

    /// Re-enqueues recoverable sync operations at launch and on connectivity-restore
    /// (SYNC RECOVERY spec §3). NOT called by the 180s retry timer.
    ///
    /// - `inProgress` ops stranded by an app kill (lastAttemptedAt nil or older than
    ///   `inProgressStalenessWindow`) → `pending`, retryCount left intact. The
    ///   PK-violation idempotency guard makes a replayed create safe.
    /// - `failed` ops (they exhausted their retry budget) → `pending`, retryCount
    ///   reset to 0, `lastError` PRESERVED — a fresh retry budget per session
    ///   ("restart retries by default").
    /// - `parked` ops are LEFT UNTOUCHED. A permanent server rejection never
    ///   auto-retries; only an explicit user Retry or Discard moves it.
    func reenqueueRecoverableOperations() {
        guard let modelContext else { return }

        let staleCutoff = Date().addingTimeInterval(-inProgressStalenessWindow)
        let inProgressDescriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "inProgress" }
        )
        let failedDescriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "failed" }
        )

        var revivedInProgress = 0
        var revivedFailed = 0
        do {
            let inProgressOps = try modelContext.fetch(inProgressDescriptor)
            let failedOps = try modelContext.fetch(failedDescriptor)

            try modelContext.transaction {
                for op in inProgressOps {
                    // A fresh in-flight op (recent lastAttemptedAt) is left alone;
                    // only nil or stale ones are crash-stranded.
                    if let last = op.lastAttemptedAt, last >= staleCutoff { continue }
                    op.status = "pending"
                    revivedInProgress += 1
                }
                for op in failedOps {
                    op.status = "pending"
                    op.retryCount = 0
                    // lastError PRESERVED so the recovery screen still shows why it
                    // failed last session.
                    revivedFailed += 1
                }
            }
        } catch {
            print("[SYNC_ENGINE] reenqueueRecoverableOperations failed: \(error)")
            return
        }

        if revivedInProgress + revivedFailed > 0 {
            print("[SYNC_ENGINE] Re-enqueue sweep: \(revivedInProgress) stranded in-flight + \(revivedFailed) failed → pending (parked untouched)")
            refreshPendingCount()
        }
    }

    /// Reconciles queued offline project-status writes after a separate
    /// authoritative RPC commits a newer status.
    ///
    /// Rewrites only the status field in every nonterminal stored operation so
    /// mixed payloads keep their unrelated edits. A trailing operation repairs
    /// any request that was already decoded and in flight when this runs.
    @discardableResult
    func supersedeProjectStatus(entityID: String, with status: String) -> Bool {
        guard let modelContext else { return false }
        let canonicalID = entityID.lowercased()
        let descriptor = FetchDescriptor<SyncOperation>()

        do {
            let operations = try modelContext.fetch(descriptor)
            for operation in operations where
                operation.entityType == SyncEntityType.project.rawValue
                    && operation.entityId.lowercased() == canonicalID
                    && ["pending", "inProgress", "failed"].contains(operation.status)
            {
                guard let payload = Self.payload(
                    operation.payload,
                    settingStatus: status
                ) else { continue }
                operation.payload = payload
                var fields = Set(operation.getChangedFields())
                fields.insert("status")
                operation.changedFields = fields.sorted().joined(separator: ",")
            }
            try modelContext.save()
        } catch {
            print("[SYNC_ENGINE] Failed to supersede project status: \(error)")
            return false
        }

        return recordOperation(
            entityType: .project,
            entityId: canonicalID,
            operationType: "update",
            changedFields: ["status": status],
            priority: 0
        ) != nil
    }

    /// Reconciles queued offline task writes after an authoritative review RPC
    /// commits newer server fields. Existing mixed payloads retain unrelated
    /// local edits; the priority-zero tail repairs a request that was already
    /// decoded and in flight when the RPC completed.
    @discardableResult
    func supersedeProjectTaskFields(
        entityID: String,
        with authoritativeFields: [String: Any]
    ) -> Bool {
        guard let modelContext,
              !authoritativeFields.isEmpty,
              JSONSerialization.isValidJSONObject(authoritativeFields) else {
            return false
        }
        let canonicalID = entityID.lowercased()
        let descriptor = FetchDescriptor<SyncOperation>()

        do {
            let operations = try modelContext.fetch(descriptor)
            for operation in operations where
                operation.entityType == SyncEntityType.projectTask.rawValue
                    && operation.entityId.lowercased() == canonicalID
                    && ["pending", "inProgress", "failed"].contains(operation.status)
            {
                guard let payload = Self.payload(
                    operation.payload,
                    overlaying: authoritativeFields
                ) else { continue }
                operation.payload = payload
                var fields = Set(operation.getChangedFields())
                fields.formUnion(authoritativeFields.keys)
                operation.changedFields = fields.sorted().joined(separator: ",")
            }
            try modelContext.save()
        } catch {
            print("[SYNC_ENGINE] Failed to supersede project task fields: \(error)")
            return false
        }

        return recordOperation(
            entityType: .projectTask,
            entityId: canonicalID,
            operationType: "update",
            changedFields: authoritativeFields,
            priority: 0
        ) != nil
    }

    nonisolated static func payload(
        _ data: Data,
        settingStatus status: String
    ) -> Data? {
        payload(data, overlaying: ["status": status])
    }

    nonisolated static func payload(
        _ data: Data,
        overlaying fields: [String: Any]
    ) -> Data? {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        fields.forEach { object[$0.key] = $0.value }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Explicit Retry

    /// Rearms recoverable operations transactionally. Task-type mutations also
    /// rearm their field guards; when a permanent rejection already rolled the
    /// optimistic projection back, the guard snapshots are refreshed from the
    /// current local state before retrying.
    func retryOperations(_ operations: [SyncOperation]) {
        guard let modelContext, !operations.isEmpty else { return }
        let requestedIds = Set(operations.map(\.id))

        do {
            try modelContext.transaction {
                let persisted = try modelContext.fetch(
                    FetchDescriptor<SyncOperation>()
                )
                for operation in persisted
                where requestedIds.contains(operation.id)
                    && (
                        operation.status == "failed"
                            || operation.status == "parked"
                    ) {
                    if try TaskTypeMutationSync
                        .prepareForRetryIfHandled(
                            operation,
                            in: modelContext
                        ) {
                        continue
                    }
                    operation.status = "pending"
                    operation.retryCount = 0
                    operation.lastAttemptedAt = nil
                    operation.completedAt = nil
                    operation.lastError = nil
                }
            }
        } catch {
            print(
                "[SYNC_ENGINE] Failed to rearm recoverable operations: "
                    + "\(error)"
            )
            return
        }
        refreshPendingCount()
    }

    // MARK: - Cancel

    /// Cancels one operation. Mention edits are dependency-aware: the rejected
    /// update's impossible dispatch is removed with it and surviving full
    /// replacements inherit the discarded node's upstream dependency.
    /// Does nothing if the operation is currently in-progress.
    func cancelOperation(_ operation: SyncOperation) {
        guard let modelContext else { return }
        let operationId = operation.id
        let operationType = operation.operationType
        let entityType = operation.entityType
        var cancelled = false
        var projectIdToSignal: String?
        var rejectionReason: String?
        var taskTypeReminderStateChanged = false
        var discardStateSnapshot:
            ProjectNoteMentionEditSync.DiscardRecoverySnapshot?

        do {
            try ProjectNoteMentionQueueCoordinator.shared.withMutation(
                recoveringWith: { _ in
                    do {
                        if let discardStateSnapshot {
                            try ProjectNoteMentionEditSync
                                .restoreDiscardState(
                                    discardStateSnapshot,
                                    in: modelContext
                                )
                        } else {
                            modelContext.rollback()
                        }
                    } catch {
                        print(
                            "[SYNC_ENGINE] Failed to restore discard state "
                                + "after cancellation error: \(error)"
                        )
                    }
                }
            ) { activeClaimIds in
                guard !activeClaimIds.contains(operationId) else {
                    rejectionReason = "operation is actively executing"
                    return
                }
                if modelContext.hasChanges {
                    try modelContext.save()
                }
                modelContext.rollback()
                try modelContext.transaction {
                    let descriptor = FetchDescriptor<SyncOperation>(
                        predicate: #Predicate {
                            $0.id == operationId
                        }
                    )
                    guard let persistedOperation =
                        try modelContext.fetch(descriptor).first else {
                        rejectionReason = "operation no longer exists"
                        return
                    }
                    guard persistedOperation.status != "inProgress" else {
                        rejectionReason = "operation is in progress"
                        return
                    }

                    let operations = try modelContext.fetch(
                        FetchDescriptor<SyncOperation>()
                    )
                    if let taskTypePlan =
                        TaskTypeMutationSync.discardPlanIfHandled(
                            persistedOperation,
                            in: operations
                        ) {
                        let hasExecutingTaskTypeOperation =
                            operations.contains {
                                taskTypePlan.commandIds.contains($0.id)
                                    && (
                                        $0.status == "inProgress"
                                            || activeClaimIds
                                                .contains($0.id)
                                    )
                            }
                        guard !hasExecutingTaskTypeOperation else {
                            rejectionReason =
                                "a related task type change is actively executing"
                            return
                        }

                        if taskTypePlan.restoresDirectDelete {
                            guard try TaskTypeMutationSync
                                .restoreRejectedDirectDelete(
                                    persistedOperation,
                                    in: modelContext
                                ) else {
                                rejectionReason =
                                    "the deleted task type could not be restored"
                                return
                            }
                        } else {
                            let rollback = try TaskTypeMutationSync
                                .rollbackRejectedMutation(
                                    persistedOperation,
                                    in: modelContext
                                )
                            guard rollback.didRollback else {
                                rejectionReason =
                                    "task type rollback snapshots are unavailable"
                                return
                            }
                            taskTypeReminderStateChanged =
                                rollback.reminderStateChanged
                        }

                        for candidate in operations
                        where taskTypePlan.operationIds.contains(
                            candidate.id
                        ) {
                            modelContext.delete(candidate)
                        }
                        cancelled = true
                        return
                    }

                    let discardedIds =
                        ProjectNoteMentionEditSync.prepareForDiscard(
                            persistedOperation,
                            in: operations
                        )
                    let dependencyRewires = ProjectNoteMentionEditSync
                        .dependencyRewiresForDiscard(
                            discardedIds: discardedIds,
                            in: operations
                        )
                    let touchedIds = discardedIds.union(
                        dependencyRewires.map {
                            $0.operation.id
                        }
                    )
                    let hasExecutingDiscard = operations.contains {
                        touchedIds.contains($0.id)
                            && (
                                $0.status == "inProgress"
                                    || activeClaimIds.contains($0.id)
                            )
                    }
                    guard !hasExecutingDiscard else {
                        rejectionReason =
                            "a dependent operation is actively executing"
                        return
                    }

                    let reconciledState = ProjectNoteMentionEditSync
                        .reconciledNoteStateAfterDiscard(
                            persistedOperation,
                            discardedIds: discardedIds,
                            in: operations
                        )
                    let discardsUncreatedNote =
                        ProjectNoteMentionEditSync
                        .isProjectNoteCreateOperation(
                            persistedOperation
                        )
                    let discardsProjectNoteDelete =
                        persistedOperation.entityType
                            == SyncEntityType.projectNote.rawValue
                            && persistedOperation.operationType == "delete"
                    let noteId =
                        persistedOperation.entityId.lowercased()
                    let reconciledNote: ProjectNote?
                    if reconciledState != nil
                        || discardsUncreatedNote
                        || discardsProjectNoteDelete {
                        reconciledNote =
                            try ProjectNoteMentionEditSync
                            .fetchProjectNote(
                                matching: noteId,
                                in: modelContext
                            )
                    } else {
                        reconciledNote = nil
                    }
                    let noteMutation:
                        ProjectNoteMentionEditSync.DiscardNoteMutation?
                    if discardsUncreatedNote {
                        noteMutation = .offlineCreateDeletion
                    } else if reconciledState != nil {
                        noteMutation = .mentionUpdate
                    } else if discardsProjectNoteDelete {
                        noteMutation = .delete
                    } else {
                        noteMutation = nil
                    }

                    discardStateSnapshot = ProjectNoteMentionEditSync
                        .discardRecoverySnapshot(
                            note: reconciledNote,
                            noteMutation: noteMutation,
                            operations: operations,
                            discardedIds: discardedIds,
                            dependencyRewires: dependencyRewires
                        )
                    ProjectNoteMentionEditSync.applyDiscardRewires(
                        dependencyRewires
                    )
                    if let reconciledState, let reconciledNote {
                        reconciledNote.content = reconciledState.content
                        reconciledNote.mentionedUserIds =
                            reconciledState.mentionedUserIds
                        reconciledNote.needsSync =
                            reconciledState.needsSync
                        reconciledNote.updatedAt =
                            reconciledState.updatedAt
                    }
                    if discardsProjectNoteDelete,
                       let reconciledNote {
                        let unresolvedStatuses = Set([
                            "pending",
                            "inProgress",
                            "failed",
                            "parked",
                        ])
                        let hasSurvivingSameNoteWrite =
                            operations.contains {
                                !discardedIds.contains($0.id)
                                    && $0.entityType
                                        == SyncEntityType.projectNote
                                        .rawValue
                                    && $0.entityId.lowercased()
                                        == noteId
                                    && unresolvedStatuses
                                        .contains($0.status)
                                    && (
                                        ProjectNoteMentionEditSync
                                            .isUpdateOperation($0)
                                            || [
                                                "create",
                                                "update",
                                                "delete",
                                            ].contains(
                                                $0.operationType
                                            )
                                    )
                            }
                        reconciledNote.deletedAt = nil
                        reconciledNote.needsSync =
                            hasSurvivingSameNoteWrite
                    }
                    if discardsUncreatedNote, let reconciledNote {
                        modelContext.delete(reconciledNote)
                    } else {
                        projectIdToSignal = reconciledNote?.projectId
                    }
                    for candidate in operations where
                        discardedIds.contains(candidate.id) {
                        modelContext.delete(candidate)
                    }
                    #if DEBUG
                    try projectNoteDiscardFailureInjector?()
                    #endif
                    cancelled = true
                }
            }
        } catch let cancellationError {
            print(
                "[SYNC_ENGINE] Failed to cancel operation \(operationId): "
                    + "\(cancellationError)"
            )
            return
        }
        guard cancelled else {
            print(
                "[SYNC_ENGINE] Cannot cancel operation \(operationId): "
                    + (rejectionReason ?? "operation was not cancellable")
            )
            return
        }
        if let projectIdToSignal {
            ProjectNoteChangeSignal.post(projectId: projectIdToSignal)
        }
        if taskTypeReminderStateChanged {
            NotificationCenter.default.post(
                name: .taskTypeMutationRolledBack,
                object: nil
            )
        }
        refreshPendingCount()
        print(
            "[SYNC_ENGINE] Cancelled operation \(operationId) "
                + "(\(operationType) \(entityType))"
        )
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
            let allOperations = try modelContext.fetch(FetchDescriptor<SyncOperation>())
            let liveDependencyIds = Set(
                allOperations.compactMap { operation -> String? in
                    guard operation.status != "completed" else { return nil }
                    return operation.dependsOnId
                }
            )
            var deletedCount = 0

            for op in completed {
                if let completedAt = op.completedAt,
                   completedAt < cutoff,
                   !liveDependencyIds.contains(op.id.uuidString) {
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
    func refreshPendingCount() {
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
