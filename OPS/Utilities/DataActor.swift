//
//  DataActor.swift
//  OPS
//
//  Long-lived @ModelActor that owns all background SwiftData writes.
//  Part of the C-pragmatic ModelActor refactor (Phase 1).
//
//  Design invariants:
//   - One instance per app lifetime, created in DataController.setModelContext.
//   - Uses its own ModelContext (created by @ModelActor macro) — NOT mainContext.
//   - All external callers use async methods; internal work uses
//     ModelContext.transaction { } for atomicity.
//   - Accepts PersistentIdentifier across the actor boundary, never @Model.
//
//  Migration note: the methods on this actor replace the previous
//  @MainActor InboundProcessor, OutboundProcessor, and DataController cleanup
//  implementations. Legacy paths remain behind FeatureFlags.useDataActor
//  until verified and removed.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted on MainActor after DataActor's ModelContext saves.
    /// userInfo keys: "inserted" / "updated" / "deleted" ([PersistentIdentifier]).
    /// Subscribed to by MainContextRefreshBridge to close the iOS 18.2
    /// @Query insert-auto-refresh gap without passing ModelContext across
    /// actor boundaries (which would error under Swift 6 strict concurrency).
    static let dataActorDidSave = Notification.Name("DataActorDidSave")
}

@ModelActor
actor DataActor {
    // MARK: - Observer State

    private var didSaveObserver: NSObjectProtocol?

    // MARK: - Configuration

    /// Called once after init to apply per-context configuration and install
    /// the didSave observer that rebroadcasts a Sendable notification to main.
    /// Must be called before any transaction is run.
    func configure() {
        modelContext.autosaveEnabled = false

        // Subscribe to self's didSave and re-broadcast a Sendable notification on main.
        // This avoids passing the non-Sendable ModelContext across the actor boundary,
        // which would error under Swift 6 strict concurrency. Sendable payload is the
        // PersistentIdentifier arrays from userInfo.
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: modelContext,
            queue: nil
        ) { notification in
            let userInfo = notification.userInfo ?? [:]
            let inserted = (userInfo[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier]) ?? []
            let updated = (userInfo[ModelContext.NotificationKey.updatedIdentifiers.rawValue] as? [PersistentIdentifier]) ?? []
            let deleted = (userInfo[ModelContext.NotificationKey.deletedIdentifiers.rawValue] as? [PersistentIdentifier]) ?? []

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .dataActorDidSave,
                    object: nil,
                    userInfo: [
                        "inserted": inserted,
                        "updated": updated,
                        "deleted": deleted
                    ]
                )
            }
        }
    }

    deinit {
        if let observer = didSaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Sync Priority Order

    /// Entity types processed during full/delta sync, ordered by foreign-key
    /// dependencies (companies/users/clients before projects/tasks etc).
    /// Mirrors InboundProcessor.syncOrder during Phase 1 migration; the source
    /// of truth moves here after legacy is removed.
    static let syncOrder: [SyncEntityType] = [
        .company,
        .user,
        .client,
        .subClient,
        .taskType,
        .project,
        .projectTask,
        .projectNote,
        .photoAnnotation,
        .deckDesign,
        .estimate,
        .invoice
    ]

    // MARK: - Spotlight Accumulator

    /// Actor-local accumulators for Spotlight-tracked entity changes during a sync pass.
    ///
    /// SpotlightSyncTracker is @MainActor-isolated; calling it from each merge would
    /// require one MainActor.run hop per tracked entity (~2000 per full sync on a
    /// mid-size customer, defeating the point of the refactor). We accumulate here
    /// during the sync, then emit a single Sendable snapshot at the end for the
    /// main-side tracker to absorb and dispatch.
    private var spotlightDirty: [String: Set<String>] = [:]
    private var spotlightDeleted: [String: Set<String>] = [:]

    /// Record an entity as dirty for Spotlight. Clears any prior deletion for
    /// this id — a later upsert supersedes an earlier deletion within the same pass.
    func markSpotlightDirty(domain: String, id: String) {
        spotlightDeleted[domain]?.remove(id)
        spotlightDirty[domain, default: []].insert(id)
    }

    /// Record an entity as deleted for Spotlight. Clears any prior dirty mark for
    /// this id — a deletion supersedes an earlier upsert within the same pass.
    func markSpotlightDeleted(domain: String, id: String) {
        spotlightDirty[domain]?.remove(id)
        spotlightDeleted[domain, default: []].insert(id)
    }

    /// Extract the accumulated Spotlight diff and reset internal state.
    /// Called at the end of each sync pass; the returned Sendable snapshot is
    /// handed to the main-side SpotlightSyncTracker (see SyncEngine wiring in T17).
    func extractAndResetSpotlight() -> SpotlightSyncSnapshot {
        let snapshot = SpotlightSyncSnapshot(
            dirty: spotlightDirty,
            deleted: spotlightDeleted
        )
        spotlightDirty.removeAll()
        spotlightDeleted.removeAll()
        return snapshot
    }

    // MARK: - Repository Construction

    /// Build an InboundRepositories bundle from the current companyId.
    /// Called once at the start of each sync pass; repos are cheap to construct
    /// and hold no long-lived state beyond the SupabaseClient reference.
    private func repositories(companyId: String) -> InboundRepositories {
        InboundRepositories(companyId: companyId)
    }

    // MARK: - Full Sync

    /// Pull ALL entities from Supabase in dependency order and merge into local SwiftData.
    /// Runs on the actor's background context; main thread is not blocked.
    /// After this returns, SyncEngine calls `extractAndResetSpotlight()` to dispatch
    /// targeted Spotlight updates on main.
    func fullSync(
        companyId: String,
        onProgress: (@Sendable (SyncEntityType, Double) -> Void)? = nil
    ) async throws {
        guard !companyId.isEmpty else {
            print("[DataActor] FULL SYNC ABORTED — no companyId available")
            return
        }

        print("[DataActor] ======== FULL SYNC STARTED ========")

        // Reset spotlight accumulator at start (matches InboundProcessor behavior).
        spotlightDirty.removeAll()
        spotlightDeleted.removeAll()

        let repos = repositories(companyId: companyId)
        let order = Self.syncOrder
        let totalSteps = Double(order.count)

        for (index, entityType) in order.enumerated() {
            let stepProgress = Double(index) / totalSteps
            onProgress?(entityType, stepProgress)

            print("[DataActor] Syncing \(entityType.rawValue)...")
            try await syncEntityType(entityType, since: nil, repos: repos)
            print("[DataActor] \(entityType.rawValue) complete")
        }

        // Link FK columns into SwiftData relationship references inside a transaction.
        try linkAllRelationships()

        onProgress?(.photoAnnotation, 1.0)
        print("[DataActor] ======== FULL SYNC COMPLETE ========")
    }

    // MARK: - Delta Sync

    /// Pull entities updated since the given timestamps and merge into local SwiftData.
    /// Entity types with no timestamp in the map are SKIPPED (true delta — do not
    /// backfill). Matches InboundProcessor.deltaSync behavior verbatim.
    func deltaSync(
        companyId: String,
        since timestamps: [SyncEntityType: Date]
    ) async throws {
        guard !companyId.isEmpty else {
            print("[DataActor] DELTA SYNC ABORTED — no companyId available")
            return
        }

        print("[DataActor] ======== DELTA SYNC STARTED ========")

        // Reset spotlight accumulator at start (matches InboundProcessor behavior).
        spotlightDirty.removeAll()
        spotlightDeleted.removeAll()

        let repos = repositories(companyId: companyId)

        for entityType in Self.syncOrder {
            let sinceDate = timestamps[entityType]
            guard sinceDate != nil else { continue }

            print("[DataActor] Delta syncing \(entityType.rawValue) since \(sinceDate!)")
            try await syncEntityType(entityType, since: sinceDate, repos: repos)
        }

        try linkAllRelationships()

        print("[DataActor] ======== DELTA SYNC COMPLETE ========")
    }

    // MARK: - Per-Entity Sync Router

    /// Routes a sync call to the appropriate entity-specific method.
    /// Only the 12 entity types InboundProcessor supports are handled; the default
    /// case matches real behavior (log and skip) for the remaining 15 SyncEntityType
    /// cases that are out-of-scope for the inbound path.
    private func syncEntityType(
        _ entityType: SyncEntityType,
        since: Date?,
        repos: InboundRepositories
    ) async throws {
        switch entityType {
        case .company:
            try await syncCompany(repos: repos)
        case .user:
            try await syncUsers(since: since, repos: repos)
        case .client:
            try await syncClients(since: since, repos: repos)
        case .taskType:
            try await syncTaskTypes(since: since, repos: repos)
        case .project:
            try await syncProjects(since: since, repos: repos)
        case .projectTask:
            try await syncTasks(since: since, repos: repos)
        case .subClient:
            try await syncSubClients(since: since, repos: repos)
        case .projectNote:
            try await syncProjectNotes(since: since, repos: repos)
        case .photoAnnotation:
            try await syncPhotoAnnotations(since: since, repos: repos)
        case .deckDesign:
            try await syncDeckDesigns(since: since, repos: repos)
        case .estimate:
            try await syncEstimates(since: since, repos: repos)
        case .invoice:
            try await syncInvoices(since: since, repos: repos)
        default:
            print("[DataActor] Entity type \(entityType.rawValue) not yet supported for inbound sync")
        }
    }
}

// MARK: - Inbound Repositories Helper

/// Collects every Supabase repository needed by the inbound sync path.
/// Initialized fresh from the current companyId at each sync's entry point.
struct InboundRepositories {
    let project: ProjectRepository
    let task: TaskRepository
    let user: UserRepository
    let client: ClientRepository
    let company: CompanyRepository
    let taskType: TaskTypeRepository
    let projectNote: ProjectNoteRepository
    let photoAnnotation: PhotoAnnotationRepository
    let deckDesign: DeckDesignRepository
    let invoice: InvoiceRepository
    let estimate: EstimateRepository

    init(companyId: String) {
        self.project = ProjectRepository(companyId: companyId)
        self.task = TaskRepository(companyId: companyId)
        self.user = UserRepository(companyId: companyId)
        self.client = ClientRepository(companyId: companyId)
        self.company = CompanyRepository()
        self.taskType = TaskTypeRepository(companyId: companyId)
        self.projectNote = ProjectNoteRepository(companyId: companyId)
        self.photoAnnotation = PhotoAnnotationRepository(companyId: companyId)
        self.deckDesign = DeckDesignRepository(companyId: companyId)
        self.invoice = InvoiceRepository(companyId: companyId)
        self.estimate = EstimateRepository(companyId: companyId)
    }
}

// MARK: - Spotlight Snapshot (Sendable)

/// A Sendable snapshot of the DataActor's Spotlight diff produced by
/// `extractAndResetSpotlight()`. Consumed by the main-side SpotlightSyncTracker
/// (see SyncEngine wiring in T17) to issue targeted Spotlight index updates
/// after each sync pass. Crossing an actor boundary requires Sendable; String
/// and Set<String> are Sendable so Dictionary<String, Set<String>> is Sendable.
struct SpotlightSyncSnapshot: Sendable {
    let dirty: [String: Set<String>]
    let deleted: [String: Set<String>]

    var isEmpty: Bool {
        dirty.values.allSatisfy(\.isEmpty) && deleted.values.allSatisfy(\.isEmpty)
    }
}
