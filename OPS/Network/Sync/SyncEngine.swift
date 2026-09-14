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
    private var pending: [Bool: @MainActor () async -> Void] = [:]
    private var order: [Bool] = []
    private var activeKind: Bool?
    private var activeOperation: (@MainActor () async -> Void)?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Upload requests coalesce together; recovery has a distinct slot so an
    /// edit arriving during discovery cannot replace or accidentally rerun it.
    func run(recovery: Bool = false, _ operation: @escaping @MainActor () async -> Void) async {
        if pending[recovery] == nil { order.append(recovery) }
        pending[recovery] = activeKind == recovery ? activeOperation : (pending[recovery] ?? operation)
        if isRunning {
            await waitUntilIdle()
            return
        }
        isRunning = true
        while !order.isEmpty {
            let kind = order.removeFirst()
            let next = pending.removeValue(forKey: kind)
            activeKind = kind
            activeOperation = next
            await next?()
            activeKind = nil
            activeOperation = nil
        }
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
    private var syncCycleID: UUID?
    private var syncInProgress: Bool = false
    private let syncFollowUp = SyncFollowUpRequest()
    private let execution: SyncExecutionCoordinator
    private let pushDrainCoordinator = SyncPushDrainCoordinator()
    private var recoveryTask: Task<Void, Never>?
    private var recoveryTaskID: UUID?
    private var uploadWakeupTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var recoveryRequested = false

    /// Coalesces post-editor uploads without pulling the whole app. Outbox
    /// writes are already durable; cancelling a wakeup never cancels custody.
    func scheduleUploadWakeup() {
        uploadWakeupTask?.cancel()
        uploadWakeupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.uploadWakeupTask = nil
            await self.pushPending()
        }
    }

    /// Explicit launch/reconnect/manual recovery boundary. Ordinary online
    /// edits only wake pushPending() and never rediscover historical graphs.
    func requestRecovery() {
        recoveryRequested = true
        guard SyncExecutionContext.isCurrent, recoveryTask == nil, execution.acceptsOrdinaryWork || SyncExecutionContext.scope != nil else { return }
        let taskID = UUID()
        recoveryTaskID = taskID
        let generation = lifecycleGeneration
        let userID = currentUserId?.lowercased()
        let companyID = UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased()
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                // Only this task may clear its slot. An obsolete first turn
                // must not permanently block later account/company recovery.
                if self.recoveryTaskID == taskID {
                    self.recoveryTask = nil
                    self.recoveryTaskID = nil
                    if self.recoveryRequested && SyncExecutionContext.isCurrent { self.requestRecovery() }
                }
            }
            @MainActor func scopeIsCurrent() -> Bool {
                SyncExecutionContext.isCurrent && generation == self.lifecycleGeneration
                    && self.currentUserId?.lowercased() == userID
                    && UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() == companyID
            }
            guard scopeIsCurrent() else { return }
            repeat {
                self.recoveryRequested = false
                await self.runRecoveryPass()
            } while self.recoveryRequested && scopeIsCurrent()
            guard scopeIsCurrent(), self.recoveryTaskID == taskID else { return }
            self.recoveryTask = nil
            self.recoveryTaskID = nil
            await self.pushPending()
        }
    }

    private func runRecoveryPass() async {
        await performExecution(name: "sync-recovery", showsStatus: false) { await self.runRecoveryPassAdmitted() }
    }

    private func runRecoveryPassAdmitted() async {
        guard await awaitDataActorReadiness() else { return }
        guard let context = modelContext else { return }
        let generation = lifecycleGeneration
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() ?? ""
        let userId = currentUserId?.lowercased()
        guard !companyId.isEmpty else { return }
        func scopeIsCurrent() -> Bool {
            SyncExecutionContext.isCurrent && generation == lifecycleGeneration
                && currentUserId?.lowercased() == userId
                && UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() == companyId
        }
        let container = context.container
        do {
            let candidates = try await Task.detached(priority: .utility) {
                try SyncRecoveryReader.discover(container: container, companyId: companyId)
            }.value
            guard scopeIsCurrent() else { return }
            // Serialize repair mutations with outbound claims. Discovery can
            // overlap interaction; these exact graph transactions cannot overlap
            // an engine drain or cross an auth/container lifetime.
            await pushDrainCoordinator.run(recovery: true) {
                guard scopeIsCurrent() else { return }
                if candidates.hasParkedTaskUpdates { self.settleDeletedProjectTaskUpdates() }
                if candidates.hasQuarantines { self.releaseRestoredParentSiteVisitChains() }
                let tasks = candidates.taskIds.sorted()
                for start in stride(from: 0, to: tasks.count, by: 8) {
                    guard scopeIsCurrent() else { return }
                    self.enqueueOrphanedTaskWrites(candidateIds: Set(tasks[start..<min(start + 8, tasks.count)]))
                    await Task.yield()
                }
                let visits = candidates.visitIds.sorted()
                for start in stride(from: 0, to: visits.count, by: 8) {
                    guard scopeIsCurrent() else { return }
                    self.enqueueOrphanedSiteVisitWrites(siteVisitIds: Set(visits[start..<min(start + 8, visits.count)]))
                    await Task.yield()
                }
                guard scopeIsCurrent() else { return }
                if candidates.hasDeletedVisitParents { self.settleDeletedParentSiteVisitChains() }
                if candidates.hasParkedMedia { SiteVisitParkedMediaReconciler.reconcile(in: context) }
                let decks = candidates.deckIds.sorted()
                for start in stride(from: 0, to: decks.count, by: 8) {
                    guard scopeIsCurrent() else { return }
                    self.enqueueStrandedDeckDesigns(candidateIds: Set(decks[start..<min(start + 8, decks.count)]))
                    await Task.yield()
                }
                guard scopeIsCurrent() else { return }
                self.enqueueDeckDesignLinkBackfillOnce()
                self.healSiteVisitAuthorshipOnce()
                if candidates.hasParkedNotes {
                    self.reconcileSupersededParkedProjectNoteMentionUpdates()
                    self.reconcileParkedProjectNoteCreateDeleteChains()
                }
                self.refreshPendingCount()
            }
        } catch {
            // Failure leaves the durable queue untouched and the next explicit
            // boundary retries discovery. Never interpret failure as no work.
            print("[SYNC_ENGINE] Recovery discovery failed: \(error)")
        }
    }

    nonisolated(unsafe) private var syncRetryTimer: Timer?

    #if DEBUG
    var hasRecoveryTaskForTesting: Bool { recoveryTask != nil }
    var hasPendingRecoveryForTesting: Bool { recoveryRequested }
    func awaitScheduledRecoveryForTesting() async { await recoveryTask?.value }
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
    private var dataActorStartup: DataActorStartup?

    /// SyncEngine-owned spotlight tracker used to dispatch DataActor's accumulated
    /// spotlight diff. Distinct from InboundProcessor's tracker so actor-path and
    /// legacy-path instances don't share state. When the legacy path is retired,
    /// only this tracker remains.
    private let spotlightTracker = SpotlightSyncTracker()

    /// Interruption retains one foreground retry and cannot publish successful
    /// completion or advance cursors from an expired continuation.
    @discardableResult
    private func performExecution(
        name: String,
        showsStatus: Bool = true,
        operation: @escaping @MainActor () async -> Void
    ) async -> Bool {
        let generation = lifecycleGeneration
        do {
            try await execution.run(name: name) { await operation() }
            return true
        } catch {
            guard generation == lifecycleGeneration else { return false }
            syncFollowUp.request()
            if showsStatus && !syncInProgress { statusText = "Sync paused" }
            return false
        }
    }

    // MARK: - Lifecycle

    init(dimensionedPendingSyncer: DimensionedPendingSyncing? = nil, execution: SyncExecutionCoordinator? = nil) {
        self.execution = execution ?? .shared
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
        if let startup = self.dataActorStartup, !startup.matches(modelContext.container) {
            startup.invalidate()
            self.dataActorStartup = nil
        }
        outboundProcessor?.invalidate()
        photoProcessor?.invalidate()
        self.dataActor?.retireAndDrainModelWork()
        lifecycleGeneration += 1
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryRequested = false
        self.modelContext = modelContext
        self.connectivity = connectivity
        self.dataActor = dataActor
        syncCycleID = nil
        syncInProgress = false
        syncFollowUp.cancel(preservingRequest: false)
        isSyncing = false
        isPerformingInitialSync = false
        dataActor?.resumeOutboundWork()

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

        retireRealtimeProcessor()

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
            guard let self, self.modelContext === modelContext,
                  connectivity.shouldAttemptSync else { return false }
            let generation = self.lifecycleGeneration
            guard await self.awaitDataActorReadiness(),
                  self.lifecycleGeneration == generation, self.modelContext === modelContext,
                  let session = self.sessionScope() else { return false }
            let pushed = await self.performPushPending()
            return pushed && self.sessionIsCurrent(session) && !self.hasError
        }
        scheduler.onProcessingTask = { [weak self] in
            guard let self, self.modelContext === modelContext else { return false }
            let generation = self.lifecycleGeneration
            guard await self.awaitDataActorReadiness(),
                  self.lifecycleGeneration == generation, self.modelContext === modelContext,
                  let session = self.sessionScope() else { return false }
            guard await self.performTriggerSync(), self.sessionIsCurrent(session) else { return false }
            await self.photoProcessor?.processUploadQueue(
                context: modelContext,
                connectivity: connectivity
            )
            guard self.sessionIsCurrent(session) else { return false }
            self.cleanupCompletedOperations()
            self.purgeExpiredPendingWork()
            return self.sessionIsCurrent(session) && !self.hasError
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
                    self.requestRecovery()
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
            // BEFORE the re-enqueue, never after: re-enqueue flips failed →
            // pending, which drops the tone to waiting and would shield
            // 30-day-dead work from expiry for another whole session.
            purgeExpiredPendingWork()
            reenqueueRecoverableOperations()
            // Calendar rows left dirty by the old fire-and-forget writes have
            // nothing queued to push them — no operation exists to revive. Give
            // them one, so they drain or become visible (bug ef5a69e6).
            CalendarUserEventOutboundSync.backfillStrandedEvents(
                in: modelContext,
                syncEngine: self
            )
        }

        if NSClassFromString("XCTestCase") == nil { requestRecovery() }

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
        if NSClassFromString("XCTestCase") == nil { requestRecovery() }
        print("[SYNC_ENGINE] Reconfigured InboundProcessor for current company")
    }

    /// Late-binds the background DataActor after configure() has already run.
    /// Pending startup is registered before auth/reconnect can request sync.
    /// Configuration can then finish asynchronously without exposing legacy.
    func setDataActorStartup(_ startup: DataActorStartup) {
        guard self.dataActorStartup !== startup else { return }
        let needsRealtimeProcessor = realtimeProcessor != nil
        retireRealtimeProcessor()
        if needsRealtimeProcessor { realtimeProcessor = RealtimeProcessor() }
        outboundProcessor?.invalidate()
        self.dataActorStartup?.invalidate()
        self.dataActor?.retireAndDrainModelWork()
        self.dataActor = nil
        self.dataActorStartup = startup
        syncCycleID = nil
        // The old pass no longer owns these flags, so its guarded defer will
        // intentionally leave replacement state alone.
        syncInProgress = false
        syncFollowUp.cancel(preservingRequest: false)
        isSyncing = false
        isPerformingInitialSync = false
        lifecycleGeneration += 1
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryRequested = false
    }

    /// Existing callers can provide an already-ready actor. Multiple readiness
    /// waiters binding the same instance must not invalidate each other's work.
    func setDataActor(_ actor: DataActor?) {
        guard self.dataActor !== actor else { return }
        self.dataActor?.retireAndDrainModelWork()
        self.dataActor = actor
        actor?.resumeOutboundWork()
        if let actor { self.realtimeProcessor?.setDataActor(actor) }
    }

    private struct SessionScope: Sendable {
        let generation: Int
        let contextID: ObjectIdentifier
        let container: ModelContainer
        let startupID: ObjectIdentifier?
        let actorID: ObjectIdentifier?
        let userID: String?
        let companyID: String?
        let usesActor: Bool
    }

    private func sessionScope() -> SessionScope? {
        guard SyncExecutionContext.isCurrent, let context = modelContext else { return nil }
        return SessionScope(generation: lifecycleGeneration,
            contextID: ObjectIdentifier(context), container: context.container,
            startupID: dataActorStartup.map(ObjectIdentifier.init),
            actorID: dataActor.map(ObjectIdentifier.init),
            userID: currentUserId?.lowercased(),
            companyID: UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased(),
            usesActor: FeatureFlags.useDataActor)
    }

    private func sessionIsCurrent(_ scope: SessionScope) -> Bool {
        guard SyncExecutionContext.isCurrent, let context = modelContext else { return false }
        return lifecycleGeneration == scope.generation
            && ObjectIdentifier(context) == scope.contextID
            && dataActorStartup.map(ObjectIdentifier.init) == scope.startupID
            && dataActor.map(ObjectIdentifier.init) == scope.actorID
            && currentUserId?.lowercased() == scope.userID
            && UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() == scope.companyID
            && FeatureFlags.useDataActor == scope.usesActor
    }

    private func awaitDataActorReadiness() async -> Bool {
        guard SyncExecutionContext.isCurrent else { return false }
        guard FeatureFlags.useDataActor, let startup = dataActorStartup else {
            return true // Explicit legacy/standalone integrations keep their existing path.
        }
        guard let context = modelContext, startup.matches(context.container) else { return false }
        let generation = lifecycleGeneration
        let userID = currentUserId?.lowercased()
        let companyID = UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased()
        guard let actor = await startup.value(), SyncExecutionContext.isCurrent,
              generation == lifecycleGeneration, dataActorStartup === startup,
              modelContext === context,
              currentUserId?.lowercased() == userID,
              UserDefaults.standard.string(forKey: "currentUserCompanyId")?.lowercased() == companyID else {
            return false
        }
        setDataActor(actor)
        return true
    }

    /// Starts Realtime subscriptions for the given company (forced resubscribe).
    func startRealtime(companyId: String, userId: String? = nil) async {
        guard await awaitDataActorReadiness() else { return }
        guard let modelContext else { return }
        await realtimeProcessor?.startListening(companyId: companyId, userId: userId, context: modelContext)
    }

    /// Ensures Realtime is live for the given company, subscribing only if it
    /// isn't already. Idempotent — safe to call on cold launch, login, every
    /// foreground, and connectivity-restore without churning the channel.
    func ensureRealtime(companyId: String, userId: String? = nil) async {
        guard await awaitDataActorReadiness() else { return }
        guard let modelContext else { return }
        await realtimeProcessor?.ensureListening(companyId: companyId, userId: userId, context: modelContext)
    }

    private func retireRealtimeProcessor() {
        guard let retired = realtimeProcessor else { return }
        retired.retireModelBinding()
        realtimeProcessor = nil
        // Capture the retired instance, never a replacement installed later.
        Task { await retired.stopListening() }
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
        syncFollowUp.cancel(preservingRequest: false)
        syncCycleID = nil
        retireRealtimeProcessor()
        dataActorStartup?.invalidate()
        outboundProcessor?.invalidate()
        photoProcessor?.invalidate()
        self.dataActor?.retireAndDrainModelWork()
        lifecycleGeneration += 1
        recoveryRequested = false
        recoveryTask?.cancel()
        recoveryTask = nil
        uploadWakeupTask?.cancel()
        uploadWakeupTask = nil
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
        await performExecution(name: "sync-photos") { await self.processPhotoUploadsAdmitted() }
    }

    private func processPhotoUploadsAdmitted() async {
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
    ///
    /// Bug f5f57917 — `attachments` is the media half of the edit. `nil` means
    /// the edit left the note's photos alone, and it is encoded by OMITTING the
    /// `attachments` key: a text-only edit therefore queues an operation whose
    /// RPC payload is exactly the one every previous build queued. The
    /// `previous_attachments` key is recorded either way, so discarding the
    /// operation can always put the photos back.
    @discardableResult
    func recordProjectNoteMentionEdit(
        note: ProjectNote,
        content: String,
        mentionedUserIds: [String],
        mentionEventId: String,
        attachments: [String]? = nil
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
        let previousAttachments = note.attachments
        do {
            var updateObject: [String: Any] = [
                ProjectNoteMentionEditSync.noteIdPayloadKey: noteId,
                ProjectNoteMentionEditSync.contentPayloadKey: content,
                ProjectNoteMentionEditSync.mentionedUserIdsPayloadKey: mentionedUserIds,
                ProjectNoteMentionEditSync.eventIdPayloadKey: canonicalEventId,
                ProjectNoteMentionEditSync.previousContentPayloadKey:
                    note.content,
                ProjectNoteMentionEditSync
                    .previousMentionedUserIdsPayloadKey:
                    note.mentionedUserIds,
                ProjectNoteMentionEditSync
                    .previousAttachmentsPayloadKey:
                    previousAttachments,
                ProjectNoteMentionEditSync.previousNeedsSyncPayloadKey:
                    note.needsSync,
                ProjectNoteMentionEditSync.previousUpdatedAtPayloadKey:
                    previousUpdatedAtPayload,
            ]
            if let attachments {
                updateObject[
                    ProjectNoteMentionEditSync.attachmentsPayloadKey
                ] = attachments
            }
            updatePayload = try JSONSerialization.data(
                withJSONObject: updateObject
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
                        // Inbound merge protection reads these. A media edit
                        // must claim `attachmentsJSON` too, or a server pull
                        // landing before the operation does would paint the
                        // detached photo straight back onto the card. A
                        // text-only edit claims exactly what it always did.
                        changedFields: attachments == nil
                            ? [
                                "content",
                                "mentionedUserIdsString",
                            ]
                            : [
                                "content",
                                "mentionedUserIdsString",
                                "attachmentsJSON",
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
                    if let attachments {
                        note.attachments = attachments
                    }
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
        var dependsOnId: String? = nil
        var operationId: UUID? = nil
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
                dependsOnId: spec.dependsOnId
            )
            if let operationId = spec.operationId { operation.id = operationId }
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
        await performExecution(name: "sync-company", showsStatus: false) { await self.syncCompanyNowAdmitted() }
    }

    private func syncCompanyNowAdmitted() async {
        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] syncCompanyNow: network unavailable — skipping")
            return
        }

        guard await awaitDataActorReadiness() else { return }
        guard let session = sessionScope() else { return }
        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                try await actor.syncCompanyOnly(companyId: companyId)
                guard sessionIsCurrent(session) else { return }
            } else {
                guard let modelContext, let inboundProcessor else {
                    print("[SYNC_ENGINE] syncCompanyNow: not configured")
                    return
                }
                try await inboundProcessor.syncCompany(context: modelContext)
                guard sessionIsCurrent(session) else { return }
            }
        } catch {
            guard sessionIsCurrent(session) else { return }
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
        await performExecution(name: "sync-client", showsStatus: false) { await self.syncClientNowAdmitted(clientId: clientId) }
    }

    private func syncClientNowAdmitted(clientId: String) async {
        guard !clientId.isEmpty else { return }

        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] syncClientNow: network unavailable — skipping")
            return
        }

        guard await awaitDataActorReadiness() else { return }
        guard let session = sessionScope() else { return }
        do {
            if FeatureFlags.useDataActor, let actor = dataActor {
                let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
                try await actor.syncClientOnly(clientId: clientId, companyId: companyId)
                guard sessionIsCurrent(session) else { return }
            } else {
                guard let modelContext, let inboundProcessor else {
                    print("[SYNC_ENGINE] syncClientNow: not configured")
                    return
                }
                try await inboundProcessor.syncClient(clientId: clientId, context: modelContext)
                guard sessionIsCurrent(session) else { return }
            }
        } catch {
            guard sessionIsCurrent(session) else { return }
            print("[SYNC_ENGINE] syncClientNow error: \(error)")
        }
    }

    /// Triggers a full push-then-pull cycle, guarding against concurrent syncs.
    func triggerSync() async {
        _ = await performTriggerSync()
    }

    private func performTriggerSync() async -> Bool {
        var synced = false
        let completed = await performExecution(name: "sync-cycle") {
            synced = await self.triggerSyncAdmitted()
        }
        return completed && synced
    }

    private func triggerSyncAdmitted() async -> Bool {
        guard await awaitDataActorReadiness() else { return false }
        guard let session = sessionScope() else { return false }
        guard !syncInProgress else {
            syncFollowUp.request()
            print(
                "[SYNC_ENGINE] Sync already in progress — queued one follow-up"
            )
            return false
        }

        guard connectivity?.shouldAttemptSync == true else {
            print("[SYNC_ENGINE] Network not available — skipping sync")
            statusText = "Offline — changes queued"
            return false
        }

        syncFollowUp.consumePending()
        let cycleID = UUID()
        syncCycleID = cycleID
        syncInProgress = true
        isSyncing = true
        hasError = false
        statusText = "Syncing…"

        defer {
            // Cleanup is governed by ownership, even when this task expired.
            if syncCycleID == cycleID {
                syncCycleID = nil
                syncInProgress = false
                isSyncing = false
                refreshPendingCount()
                drainQueuedSyncRequest()
            }
        }

        // Push local changes first, then pull server changes
        await pushPending()
        guard sessionIsCurrent(session) else { return false }
        await syncPendingLocalArtifacts()
        guard sessionIsCurrent(session) else { return false }
        await pullDelta()
        guard sessionIsCurrent(session) else { return false }

        // This cycle pushes before it pulls. If the pull restored a parent that
        // had been in deleted-parent custody, release and drain that exact packet
        // now instead of waiting for the next periodic trigger.
        if releaseRestoredParentSiteVisitChains() {
            await pushPending()
            guard sessionIsCurrent(session) else { return false }
        }

        if !hasError {
            statusText = "Synced"
            kickoffPhotoPrefetch()
        }
        return !hasError
    }

    private func drainQueuedSyncRequest() {
        syncFollowUp.scheduleIfAdmitted(canStart: { [weak self] in
            guard let self else { return false }
            return self.execution.acceptsOrdinaryWork && !self.syncInProgress
        }) { [weak self] in
            guard let self else { return false }
            return await self.performTriggerSync()
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
            // A durable stage command retains its original authority and receipt.
            // Generic legacy cleanup cannot erase its recovery custody.
            guard op.operationType != SiteVisitSyncOperation.stageOperationType,
                  !ProjectReopenSync.preservesOrdering(op) else { return false }
            return (op.lastError?.contains("Not yet connected to repositories") == true) ||
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
        await performExecution(name: "sync-full") { await self.fullSyncAdmitted() }
    }

    private func fullSyncAdmitted() async {
        guard await awaitDataActorReadiness() else { return }
        guard let session = sessionScope() else { return }
        requestRecovery()
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
                guard sessionIsCurrent(session) else { return }
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

        syncFollowUp.consumePending()
        let cycleID = UUID()
        syncCycleID = cycleID
        syncInProgress = true
        isSyncing = true
        isPerformingInitialSync = true
        hasError = false
        statusText = "Performing full sync…"

        defer {
            // Cleanup is governed by ownership, even when this task expired.
            if syncCycleID == cycleID {
                syncCycleID = nil
                isPerformingInitialSync = false
                syncInProgress = false
                isSyncing = false
                refreshPendingCount()
                drainQueuedSyncRequest()
            }
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
                            guard let self, self.sessionIsCurrent(session) else { return }
                            self.statusText = "Syncing \(entityType.rawValue)…"
                        }
                    }
                )
                guard sessionIsCurrent(session) else { return }
                await applySpotlightSnapshot(from: actor)
                guard sessionIsCurrent(session) else { return }
            } else {
                failedEntities = try await inboundProcessor?.fullSync(
                    context: ctx,
                    onProgress: { [weak self] entityType, _ in
                        guard let self, self.sessionIsCurrent(session) else { return }
                        self.statusText = "Syncing \(entityType.rawValue)…"
                    }
                ) ?? []
                guard sessionIsCurrent(session) else { return }
            }
        } catch {
            guard sessionIsCurrent(session) else { return }
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
        guard sessionIsCurrent(session) else { return }
        await syncPendingLocalArtifacts()
        guard sessionIsCurrent(session) else { return }

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
        guard sessionIsCurrent(session) else { return }

    }

    /// Schedule-only refresh backing pull-to-refresh — projects, tasks, task
    /// types, and calendar events. A lean "check for schedule updates" for when
    /// realtime hasn't delivered an edit, instead of a full all-entity sync that
    /// drags the whole catalog/estimates/invoices/photos down on every pull.
    /// Still pushes pending local ops so an offline edit isn't stranded.
    @discardableResult
    func refreshScheduleData(companyId requestedCompanyId: String? = nil) async -> Bool {
        var refreshed = false
        let completed = await performExecution(name: "sync-schedule") {
            refreshed = await self.refreshScheduleDataAdmitted(companyId: requestedCompanyId)
        }
        return completed && refreshed
    }

    private func refreshScheduleDataAdmitted(companyId requestedCompanyId: String?) async -> Bool {
        guard await awaitDataActorReadiness() else { return false }
        guard let session = sessionScope() else { return false }
        // Briefly defer to an in-flight sync rather than racing it.
        if syncInProgress {
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                guard sessionIsCurrent(session) else { return false }
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

        syncFollowUp.consumePending()
        let cycleID = UUID()
        syncCycleID = cycleID
        syncInProgress = true
        isSyncing = true
        hasError = false
        statusText = "Checking for schedule updates…"

        defer {
            // Cleanup is governed by ownership, even when this task expired.
            if syncCycleID == cycleID {
                syncCycleID = nil
                syncInProgress = false
                isSyncing = false
                refreshPendingCount()
                drainQueuedSyncRequest()
            }
        }

        guard let ctx = modelContext else { return false }
        var taskTypesRefreshed = false
        do {
            let failedEntities: Set<SyncEntityType>
            if FeatureFlags.useDataActor, let actor = dataActor {
                failedEntities = try await actor.syncScheduleEntities(companyId: companyId)
                guard sessionIsCurrent(session) else { return false }
            } else {
                // Legacy path has no scoped pull — fall back to a full inbound
                // sync (rare: the actor path is the default).
                failedEntities = try await inboundProcessor?.fullSync(
                    context: ctx,
                    onProgress: { _, _ in }
                ) ?? [.taskType]
                guard sessionIsCurrent(session) else { return false }
            }
            taskTypesRefreshed = !failedEntities.contains(.taskType)
            hasError = !failedEntities.isEmpty
        } catch {
            guard sessionIsCurrent(session) else { return false }
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
        guard sessionIsCurrent(session) else { return false }

        statusText = hasError ? "Sync error" : "Schedule up to date"
        return taskTypesRefreshed
    }

    /// Re-sends the onboarding-completion ACK (POST /api/onboarding/complete) when a
    /// prior attempt was queued offline, clearing `onboarding_completion_pending` on
    /// success. No-op when nothing is queued. Best-effort: failures are swallowed and
    /// retried on the next sweep.
    private func retryPendingOnboardingCompletion() async {
        guard let session = sessionScope() else { return }
        guard UserDefaults.standard.bool(forKey: OnboardingStorageKeys.completionPending) else {
            return
        }
        guard let userId = currentUserId, !userId.isEmpty else { return }

        do {
            try await OnboardingService().markOnboardingComplete(userId: userId)
            guard sessionIsCurrent(session) else { return }
            UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.completionPending)
            print("[SYNC_ENGINE] Queued onboarding completion ACK delivered — flag cleared")
        } catch {
            guard sessionIsCurrent(session) else { return }
            print("[SYNC_ENGINE] Queued onboarding completion ACK still failing — will retry: \(error.localizedDescription)")
        }
    }

    /// Pushes all pending local operations to the server via OutboundProcessor.
    func pushPending() async {
        _ = await performPushPending()
    }

    private func performPushPending() async -> Bool {
        var pushed = false
        let completed = await performExecution(name: "sync-push") {
            pushed = await self.pushPendingAdmitted()
        }
        return completed && pushed
    }

    private func pushPendingAdmitted() async -> Bool {
        guard let modelContext, let connectivity else { return false }
        guard connectivity.shouldAttemptSync else { return false }
        guard await awaitDataActorReadiness() else { return false }
        guard let session = sessionScope() else { return false }
        let generation = lifecycleGeneration
        // Legacy children need their recovered parent before the first send.
        // The recovery task clears this slot before its own final upload wakeup.
        if let recoveryTask { await recoveryTask.value }
        guard sessionIsCurrent(session) else { return false }
        guard generation == lifecycleGeneration, !Task.isCancelled else { return false }
        var didFinish = false
        await pushDrainCoordinator.run {
            guard self.sessionIsCurrent(session), generation == self.lifecycleGeneration,
                  connectivity.shouldAttemptSync else { return }
            let pending = self.getPendingOperations()
            guard !pending.isEmpty else {
                didFinish = true
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

            guard self.sessionIsCurrent(session) else { return }
            self.clearCompletedProjectTaskSyncFlags(
                since: pushStartedAt,
                completedProjectTaskIds: completedProjectTaskIds
            )
            self.refreshPendingCount()
            didFinish = true
        }
        return sessionIsCurrent(session) && didFinish

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
    func enqueueOrphanedTaskWrites(candidateIds: Set<String>? = nil) {
        guard let modelContext else { return }
        if let candidateIds, candidateIds.isEmpty { return }
        let ids = RecoveryStoreQueries.caseVariants(candidateIds ?? [])
        let scoped = candidateIds != nil
        let orphans: [ProjectTask]
        do {
            orphans = try modelContext.fetch(
                FetchDescriptor<ProjectTask>(
                    predicate: #Predicate { $0.needsSync == true && $0.deletedAt == nil && (!scoped || ids.contains($0.id)) }
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
            if hasRecoveryOwnerOperation(entityType: .projectTask, entityId: task.id) { continue }

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

    /// Recovery sweep for deck designs stranded with work the server never got:
    /// unpushed content with no SyncOperation ever recorded, so the drawing
    /// exists only on the capturing phone. Re-records a durable full revision
    /// (deferPush — the surrounding pushPending drains it in the same pass).
    /// Decks with an open op are already in flight; decks with any recent op
    /// lifecycle are converging through the normal pipeline and must not be
    /// spammed.
    ///
    /// Bug 9f4aeaf8 rebuilt this. It used to require a `projectId`, which
    /// skipped every lead deck and standalone sketch — the two kinds most
    /// likely to be stranded, because a site-visit deck is created before it
    /// has a project. And it pushed `project_id` + `updated_at` ONLY, so a deck
    /// it did sweep had its server `updated_at` bumped by the table's trigger
    /// without a single vertex being delivered: the recovery path was arming
    /// the inbound clobber instead of curing it. It now carries the drawing.
    func enqueueStrandedDeckDesigns(candidateIds: Set<String>? = nil) {
        guard let modelContext else { return }
        if let candidateIds, candidateIds.isEmpty { return }
        let ids = RecoveryStoreQueries.caseVariants(candidateIds ?? [])
        let scoped = candidateIds != nil
        let candidates: [DeckDesign]
        do {
            candidates = try modelContext.fetch(
                FetchDescriptor<DeckDesign>(
                    predicate: #Predicate { $0.deletedAt == nil && (!scoped || ids.contains($0.id)) }
                )
            )
        } catch {
            print("[SYNC_ENGINE] Stranded-deck sweep fetch failed: \(error)")
            return
        }
        // Filtered in Swift: `hasUnsyncedDrawing` is a content comparison
        // against the recorded merge base and cannot be expressed in a
        // #Predicate.
        let stranded = candidates.filter { $0.needsSync || $0.hasUnsyncedDrawing }
        guard !stranded.isEmpty else { return }

        let writer = ISO8601DateFormatter()
        for design in stranded {
            guard !DeckEditingSessionRegistry.shared.isHeld(entityType: "deckDesign", entityId: design.id),
                  !hasRecoveryOwnerOperation(entityType: .deckDesign, entityId: design.id) else { continue }
            guard !hasRecentLocalWrite(entityId: design.id, withinSeconds: 15 * 60) else { continue }

            // The Supabase `drawing_data` column is jsonb, so the payload has to
            // carry a parsed object rather than the JSON string.
            let drawingObject: Any = (try? JSONSerialization.jsonObject(
                with: Data(design.drawingDataJSON.utf8),
                options: []
            )) ?? [String: Any]()

            design.version += 1

            var changedFields: [String: Any] = [
                "title": design.title,
                "drawing_data": drawingObject,
                "version": design.version,
                "updated_at": writer.string(from: Date())
            ]
            // Included only when non-nil: an explicit null from a device whose
            // local row is stale-nil would UNLINK a deck another device just
            // attached (Carol Dancer case).
            if let projectId = design.projectId, !projectId.isEmpty {
                changedFields["project_id"] = projectId
            }
            if let thumbnail = design.thumbnailURL, !thumbnail.isEmpty {
                changedFields["thumbnail_url"] = thumbnail
            }

            print("[SYNC_ENGINE] Stranded deck (unpushed content, no op): \(design.id) — re-recording full revision")
            _ = recordOperation(
                entityType: .deckDesign,
                entityId: design.id,
                operationType: "update",
                changedFields: changedFields,
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

    private func hasRecoveryOwnerOperation(entityType: SyncEntityType, entityId: String) -> Bool {
        guard let modelContext else { return true }
        let ids = RecoveryStoreQueries.caseVariants([entityId])
        let type = entityType.rawValue
        do {
            guard try modelContext.fetchCount(FetchDescriptor<SyncOperation>()) > 0 else { return false }
            let rows = try modelContext.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate {
                $0.entityType == type && ids.contains($0.entityId) && $0.status != "completed"
            }))
            return !rows.isEmpty
        } catch { return true } // Unreadable custody never permits a new send.
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
        guard let session = sessionScope() else { return }
        guard let modelContext else {
            print("[SYNC_ENGINE] Cannot sync local artifacts — not configured")
            return
        }
        await dimensionedPendingSyncer.syncPendingDimensions(modelContext: modelContext)
        guard sessionIsCurrent(session) else { return }
        // Pending PencilKit annotation writes (offline edits + soft-delete
        // tombstones) track `PhotoAnnotation.needsSync` the same way but
        // previously only retried when a photo viewer happened to open —
        // drain them on this same sweep so a stuck tombstone converges on
        // the next sync cycle instead of waiting for a viewer visit.
        await PhotoAnnotationSyncManager.shared.syncPendingAnnotations(modelContext: modelContext)
        guard sessionIsCurrent(session) else { return }
        refreshPendingCount()
    }

    /// Pulls delta changes from the server since the last sync timestamp via InboundProcessor.
    func pullDelta() async {
        await performExecution(name: "sync-delta") { await self.pullDeltaAdmitted() }
    }

    private func pullDeltaAdmitted() async {
        guard await awaitDataActorReadiness() else { return }
        guard let session = sessionScope() else { return }
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
                guard sessionIsCurrent(session) else { return }
                await applySpotlightSnapshot(from: actor)
                guard sessionIsCurrent(session) else { return }
            } else {
                failedEntities = try await inboundProcessor?.deltaSync(
                    context: modelContext,
                    since: sinceTimestamps
                ) ?? []
                guard sessionIsCurrent(session) else { return }
            }

            // Advance the cursor only for entities that did NOT fail this pull.
            // A failed entity keeps its old cursor so the next delta re-pulls its
            // changes; advancing past a transient failure would strand existing
            // rows (the deck-design blackout bug).
            advanceSyncCursors(SyncEntityType.allCases, excluding: failedEntities, to: syncStartedAt)
        } catch {
            guard sessionIsCurrent(session) else { return }
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
        await performExecution(name: "sync-catch-up") { await self.deltaSyncSinceAdmitted(date) }
    }

    private func deltaSyncSinceAdmitted(_ date: Date) async {
        guard await awaitDataActorReadiness() else { return }
        guard let session = sessionScope() else { return }
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
                guard sessionIsCurrent(session) else { return }
                await applySpotlightSnapshot(from: actor)
                guard sessionIsCurrent(session) else { return }
            } else {
                failedEntities = try await inboundProcessor?.deltaSync(
                    context: modelContext,
                    since: sinceTimestamps
                ) ?? []
                guard sessionIsCurrent(session) else { return }
            }

            // Advance the cursor only for entities that did NOT fail this catch-up
            // (a failed entity keeps its old cursor and is retried next sync).
            advanceSyncCursors(SyncEntityType.allCases, excluding: failedEntities, to: syncStartedAt)
            statusText = "Synced"
            kickoffPhotoPrefetch()
        } catch {
            guard sessionIsCurrent(session) else { return }
            print("[SYNC_ENGINE] Catch-up delta error: \(error)")
        }
    }

    // MARK: - Spotlight Snapshot Dispatch

    /// Extracts the DataActor's accumulated Spotlight diff and dispatches it via
    /// the main-side SpotlightSyncTracker. Called after each actor-path sync
    /// (fullSync/pullDelta/deltaSyncSince). Gated on `hasCompletedInitialBackfill`
    /// so we don't fire targeted updates before the full initial index exists.
    private func applySpotlightSnapshot(from actor: DataActor) async {
        guard let session = sessionScope() else { return }
        let snapshot = await actor.extractAndResetSpotlight()
        guard sessionIsCurrent(session) else { return }
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
        await spotlightTracker.dispatch(context: ctx, isCurrent: { [weak self] in
            self?.sessionIsCurrent(session) == true
        })
        guard sessionIsCurrent(session) else { return }

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

    func enqueueOrphanedSiteVisitWrites(siteVisitIds: Set<String>? = nil) {
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
                siteVisitIds: siteVisitIds,
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

    @discardableResult
    func settleDeletedProjectTaskUpdates() -> Bool {
        guard let modelContext else { return false }
        let companyId = UserDefaults.standard.string(
            forKey: "currentUserCompanyId"
        )?.lowercased() ?? ""
        guard !companyId.isEmpty else { return false }
        do {
            let result = try DeletedProjectTaskOperationSettlement.sweep(
                in: modelContext,
                activeCompanyId: companyId
            )
            guard !result.settledOperationIds.isEmpty else { return false }
            print(
                "[SYNC_ENGINE] Settled \(result.settledOperationIds.count) "
                    + "obsolete deleted-task update(s)"
            )
            refreshPendingCount()
            return true
        } catch {
            print("[SYNC_ENGINE] Deleted-task settlement failed: \(error)")
            return false
        }
    }

    @discardableResult
    func releaseRestoredParentSiteVisitChains() -> Bool {
        guard let modelContext else { return false }
        let companyId = UserDefaults.standard.string(
            forKey: "currentUserCompanyId"
        )?.lowercased() ?? ""
        let userId = UserDefaults.standard.string(
            forKey: "currentUserId"
        )?.lowercased() ?? ""
        guard !companyId.isEmpty, !userId.isEmpty else { return false }
        do {
            let result = try SiteVisitRecoveryVault.shared
                .releaseRestoredParentQuarantines(
                    in: modelContext,
                    userId: userId,
                    companyId: companyId
                )
            guard !result.releasedSiteVisitIds.isEmpty else { return false }
            print(
                "[SYNC_ENGINE] Released \(result.releasedSiteVisitIds.count) "
                    + "restored site-visit packet(s); requeued "
                    + "\(result.requeuedOperationIds.count) operation(s)"
            )
            refreshPendingCount()
            return true
        } catch {
            print("[SYNC_ENGINE] Restored-parent release failed: \(error)")
            return false
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
                    guard SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(
                        op, userId: self.currentUserId,
                        companyId: UserDefaults.standard.string(forKey: "currentUserCompanyId")
                    ) else { continue }
                    // A fresh in-flight op (recent lastAttemptedAt) is left alone;
                    // only nil or stale ones are crash-stranded.
                    if let last = op.lastAttemptedAt, last >= staleCutoff { continue }
                    op.status = "pending"
                    revivedInProgress += 1
                }
                for op in failedOps {
                    guard SiteVisitCommandRecoveryPolicy.mayAutomaticallyResume(
                        op, userId: self.currentUserId,
                        companyId: UserDefaults.standard.string(forKey: "currentUserCompanyId")
                    ) else { continue }
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

        // Ops that parked BEFORE the reconcilers existed are invisible to the
        // sweep above — parked is deliberately terminal — but some are now
        // resolvable against server state: a site-visit photo the conversion RPC
        // already inserted transactionally, a task the server has since deleted.
        // Resolve those on the active outbound driver so PENDING WORK empties
        // itself with no user action (bug ba75732a). Best-effort, and off the
        // sweep's critical path — every other parked class stays parked.
        guard connectivity?.shouldAttemptSync == true else { return }
        let generation = lifecycleGeneration
        Task { [weak self] in
            guard let self, generation == self.lifecycleGeneration,
                  await self.awaitDataActorReadiness(),
                  generation == self.lifecycleGeneration else { return }
            if FeatureFlags.useDataActor, let actor = self.dataActor {
                await actor.resolveReconcilableParkedOperations()
            } else if let processor = self.outboundProcessor {
                await processor.resolveReconcilableParkedOperations(context: modelContext)
            }
            self.refreshPendingCount()
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
                    && !ProjectReopenSync.isReopen(operation)
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
                    if ProjectReopenSync.isReopen(persistedOperation), operations.contains(where: {
                        $0.dependsOnId?.lowercased() == persistedOperation.id.uuidString.lowercased()
                            && TaskLifecycleSync.unresolvedStatuses.contains($0.status)
                    }) {
                        rejectionReason = "scheduled work still depends on this project reopening"
                        return
                    }
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
                    let attachmentBaselineRebases = try ProjectNoteMentionEditSync
                        .attachmentBaselineRebasesForDiscard(
                            discardedIds: discardedIds,
                            in: operations
                        )
                    let touchedIds = discardedIds.union(
                        dependencyRewires.map {
                            $0.operation.id
                        }
                    ).union(attachmentBaselineRebases.map { $0.operation.id })
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
                    } else if let reconciledState {
                        // The reconciliation below rewrites the note's photos
                        // only when the edit actually moved them, so only then
                        // does a failed discard own restoring them. A
                        // text-only edit must leave `attachmentsJSON` to
                        // whoever else wrote it — a concurrent inbound merge,
                        // say — exactly as the snapshot leaves `lastSyncedAt`.
                        noteMutation = .mentionUpdate(
                            restatesAttachments:
                                reconciledState.attachments != nil
                        )
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
                            dependencyRewires: dependencyRewires,
                            attachmentBaselineRebases: attachmentBaselineRebases
                        )
                    ProjectNoteMentionEditSync.applyDiscardRewires(
                        dependencyRewires
                    )
                    ProjectNoteMentionEditSync.applyDiscardAttachmentBaselineRebases(
                        attachmentBaselineRebases
                    )
                    if let reconciledState, let reconciledNote {
                        reconciledNote.content = reconciledState.content
                        reconciledNote.mentionedUserIds =
                            reconciledState.mentionedUserIds
                        // nil means cancellation owns no media mutation.
                        // Preserve photos received independently of text edits.
                        if let attachments = reconciledState.attachments {
                            reconciledNote.attachments = attachments
                        }
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

    /// Bug f71113a3 — auto-delete stalled pending work after 30 days.
    /// Reads the same inventory the PENDING WORK screen renders, asks the pure
    /// policy, and applies only the three sanctioned scopes. Never touches
    /// pending/inProgress work, creates, photos, drafts, designs, or custody
    /// packets — see PendingWorkExpiryPolicy.
    @MainActor
    func purgeExpiredPendingWork(now: Date = Date()) {
        guard let modelContext else { return }
        let queue = ClientLeadAutocreateQueue.shared
        let inventory = RecoveryInventory.load(from: modelContext, queue: queue, now: now)
        let outcome = applyPendingWorkExpiry(
            inventory: inventory,
            now: now,
            in: modelContext,
            queue: queue
        )
        guard outcome.total > 0 else { return }

        refreshPendingCount()
        AnalyticsService.shared.track(
            eventType: .lifecycle,
            eventName: "pending_work_expired",
            properties: [
                "operations": outcome.expiredOperations,
                "lead_requests": outcome.expiredLeadRequests,
                "empty_visit_bundles": outcome.expiredEmptyBundles
            ]
        )
        print(
            "[SYNC_ENGINE] Expired 30-day pending work — "
                + "ops: \(outcome.expiredOperations), "
                + "leads: \(outcome.expiredLeadRequests), "
                + "empty bundles: \(outcome.expiredEmptyBundles)"
        )
    }

    /// The acting half of the 30-day expiry, split out so the ONE place that
    /// destroys anything is directly testable against a real store — the load
    /// above is a thin adapter over the same inventory the screen renders.
    ///
    /// Applies only the three sanctioned scopes and nothing else. Returns what
    /// it removed; an empty outcome means nothing was written and nothing saved.
    @MainActor
    @discardableResult
    func applyPendingWorkExpiry(
        inventory: RecoveryInventory,
        now: Date,
        in modelContext: ModelContext,
        queue: ClientLeadAutocreateQueue
    ) -> PendingWorkExpiryOutcome {
        // Predicate-free by rule (see ClientLeadAutocreateQueue.syncOperations):
        // a #Predicate fetch of SyncOperation traps on a never-populated table.
        let allOperations = (try? modelContext.fetch(FetchDescriptor<SyncOperation>())) ?? []
        let liveDependencyIds = Set(allOperations.compactMap { operation -> String? in
            guard TaskLifecycleSync.unresolvedStatuses.contains(operation.status) else { return nil }
            return operation.dependsOnId?.lowercased()
        })
        let clientCreateIds = Set(
            allOperations
                .filter { $0.entityType == SyncEntityType.client.rawValue && $0.operationType == "create" }
                .map { $0.entityId.lowercased() }
        )

        var outcome = PendingWorkExpiryOutcome.none
        for item in inventory.attention {
            let decision = PendingWorkExpiryPolicy.decision(
                for: item,
                now: now,
                clientCreateOpExists: { clientCreateIds.contains($0) }
            )
            guard case .expire(let scope) = decision else { continue }
            switch scope {
            case .deleteOperations(let ids):
                // Re-check the LIVE row status: a retry between the inventory
                // build and this loop must not have its fresh attempt deleted.
                let targets = allOperations.filter {
                    ids.contains($0.id) && ($0.status == "failed" || $0.status == "parked")
                        && !ProjectReopenSync.preservesOrdering($0)
                        && !liveDependencyIds.contains($0.id.uuidString.lowercased())
                }
                guard !targets.isEmpty else { continue }
                targets.forEach { modelContext.delete($0) }
                outcome.expiredOperations += targets.count
            case .removeLeadRequest(let clientId):
                queue.removeRequest(clientId: clientId)
                outcome.expiredLeadRequests += 1
            case .declineBundleSends(let bundle):
                // Declined, never deleted: the decline-sticks contract requires
                // the terminal row to stay so orphan recovery cannot re-derive
                // the send. PendingWorkDecline refuses an in-flight unit itself,
                // and saves the context on success.
                if PendingWorkDecline.queuedSends(bundle, in: modelContext) {
                    outcome.expiredEmptyBundles += 1
                }
            }
        }

        guard outcome.total > 0 else { return .none }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            print("[SYNC_ENGINE] 30-day expiry save failed: \(error)")
            return .none
        }
        return outcome
    }

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
                    return operation.dependsOnId?.lowercased()
                }
            )
            var deletedCount = 0

            for op in completed {
                if let completedAt = op.completedAt,
                   completedAt < cutoff,
                   !liveDependencyIds.contains(op.id.uuidString.lowercased()) {
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
        // A zero pending count must not hide orphaned local work. Historical
        // discovery runs on the timer boundary, independently of upload wakes.
        requestRecovery()
        guard pendingOperationCount > 0 else { return }
        guard !syncInProgress else { return }

        print("[SYNC_ENGINE] Retry timer fired — \(pendingOperationCount) pending operation(s)")

        Task {
            await triggerSync()
        }
    }
}
