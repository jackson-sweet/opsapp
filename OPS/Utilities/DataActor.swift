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
import Supabase

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
        .wizardState,
        .projectNote,
        .photoAnnotation,
        .deckDesign,
        .estimate,
        .invoice,
        // Catalog backbone — units/tags/categories before items, items before
        // their option/value/variant/junction children. Matches
        // InboundProcessor.syncOrder so the dependency contract is identical
        // across both code paths.
        .catalogCategory,
        .catalogUnit,
        .catalogTag,
        .catalogItem,
        .catalogOption,
        .catalogOptionValue,
        .catalogVariant,
        .catalogVariantOptionValue,
        .catalogItemTag,
        .catalogSnapshot,
        .catalogSnapshotItem,
        // Product configurability layers
        .productOption,
        .productOptionValue,
        .productPricingModifier,
        .productMaterial,
        // Adapter + restock orders (depend on Products / catalog variants).
        .companyDefaultProduct,
        .catalogOrder,
        .catalogOrderItem,
        // Legacy inventory_* tables (bug 2837ddae). Distinct from catalog_*
        // and backs the Inventory tab. Units/tags before items, items before
        // the item↔tag junction; snapshots last (depend on item rows).
        .inventoryUnit,
        .inventoryTag,
        .inventoryItem,
        .inventoryItemTag,
        .inventorySnapshot,
        .inventorySnapshotItem
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

    // MARK: - Single-Company Sync

    /// Public entry point for SyncEngine.syncCompanyNow — fetches and merges only
    /// the company row. Skips the full/delta sync ceremony (iteration over syncOrder
    /// + linkAllRelationships pass) since the caller just needs the company row to
    /// land before downstream features query it.
    func syncCompanyOnly(companyId: String) async throws {
        guard !companyId.isEmpty else {
            print("[DataActor] syncCompanyOnly aborted — no companyId")
            return
        }
        let repos = repositories(companyId: companyId)
        try await syncCompany(repos: repos)
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
            // Per-entity error isolation (Phase 4 Task 40 / 2837ddae): a single
            // bad entity must not abort the entire sync. Mirrors
            // InboundProcessor.fullSync — telemetry captures the failure for
            // offline diagnosis, the loop continues to the next entity type.
            do {
                try await syncEntityType(entityType, since: nil, repos: repos)
                print("[DataActor] \(entityType.rawValue) complete")
            } catch {
                print("[DataActor] FAILED \(entityType.rawValue): \(error)")
                SyncTelemetry.logError(
                    entityType: entityType.rawValue,
                    error: error,
                    isFullSync: true,
                    companyId: companyId,
                    userId: SupabaseService.shared.currentUserId
                )
            }
        }

        // Link FK columns into SwiftData relationship references inside a transaction.
        linkAllRelationships()

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
            // Per-entity error isolation (Phase 4 Task 40 / 2837ddae). Without
            // this, a single failing entity (e.g. a deckDesign with a broken
            // outbound op) aborts the whole delta and downstream entries
            // (estimate, invoice, catalog*) never sync.
            do {
                try await syncEntityType(entityType, since: sinceDate, repos: repos)
            } catch {
                print("[DataActor] FAILED delta \(entityType.rawValue): \(error)")
                SyncTelemetry.logError(
                    entityType: entityType.rawValue,
                    error: error,
                    isFullSync: false,
                    companyId: companyId,
                    userId: SupabaseService.shared.currentUserId
                )
            }
        }

        linkAllRelationships()

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
        case .wizardState:
            try await syncWizardStates(since: since, repos: repos)
        case .estimate:
            try await syncEstimates(since: since, repos: repos)
        case .invoice:
            try await syncInvoices(since: since, repos: repos)
        case .catalogCategory:
            try await syncCatalogCategories(since: since, repos: repos)
        case .catalogUnit:
            try await syncCatalogUnits(since: since, repos: repos)
        case .catalogTag:
            try await syncCatalogTags(since: since, repos: repos)
        case .catalogItem:
            try await syncCatalogItems(since: since, repos: repos)
        case .catalogVariant:
            try await syncCatalogVariants(since: since, repos: repos)
        case .catalogOption:
            try await syncCatalogOptions(repos: repos)
        case .catalogOptionValue:
            try await syncCatalogOptionValues(repos: repos)
        case .catalogVariantOptionValue:
            try await syncCatalogVariantOptionValues(repos: repos)
        case .catalogItemTag:
            try await syncCatalogItemTags(repos: repos)
        case .catalogSnapshot:
            try await syncCatalogSnapshots(since: since, repos: repos)
        case .catalogSnapshotItem:
            try await syncCatalogSnapshotItems(repos: repos)
        case .catalogOrder:
            try await syncCatalogOrders(repos: repos)
        case .catalogOrderItem:
            try await syncCatalogOrderItems(repos: repos)
        case .companyDefaultProduct:
            try await syncCompanyDefaultProducts(repos: repos)
        case .productOption:
            try await syncProductOptions(repos: repos)
        case .productOptionValue:
            try await syncProductOptionValues(repos: repos)
        case .productPricingModifier:
            try await syncProductPricingModifiers(repos: repos)
        case .productMaterial:
            try await syncProductMaterials(repos: repos)
        case .inventoryUnit:
            try await syncInventoryUnits(since: since, repos: repos)
        case .inventoryTag:
            try await syncInventoryTags(since: since, repos: repos)
        case .inventoryItem:
            try await syncInventoryItems(since: since, repos: repos)
        case .inventoryItemTag:
            try await syncInventoryItemTags(repos: repos)
        case .inventorySnapshot:
            try await syncInventorySnapshots(since: since, repos: repos)
        case .inventorySnapshotItem:
            try await syncInventorySnapshotItems(repos: repos)
        case .taskTypeReminder:
            try await syncTaskTypeReminders(since: since, repos: repos)
        case .taskReminder:
            try await syncTaskReminders(since: since, repos: repos)
        default:
            print("[DataActor] Entity type \(entityType.rawValue) not yet supported for inbound sync")
        }
    }

    // MARK: - Sync: Company (single-row fetch)

    /// Fetch and merge the company row identified by repos.companyId.
    /// Also refreshes SubscriptionManager so seat/plan changes land immediately.
    private func syncCompany(repos: InboundRepositories) async throws {
        guard !repos.companyId.isEmpty else {
            print("[DataActor] No companyId — skipping company sync")
            return
        }

        let dto = try await repos.company.fetch(companyId: repos.companyId)
        try modelContext.transaction {
            try mergeCompany(dto: dto)
        }

        // Refresh subscription status so seat/plan changes from web reflect immediately.
        // Fire-and-forget to MainActor: syncCompany doesn't use the result, and the
        // check publishes to @Published UI state which must write on main. Hopping
        // here also avoids blocking sync completion on the subscription fetch.
        Task { @MainActor in
            await SubscriptionManager.shared.checkSubscriptionStatus()
        }
    }

    private func mergeCompany(dto: SupabaseCompanyDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .company,
                entityId: id,
                fields: [
                    "name", "logoURL", "companyDescription", "website", "phone", "email",
                    "address", "latitude", "longitude", "defaultProjectColor",
                    "adminIdsString", "seatedEmployeeIds", "maxSeats",
                    "subscriptionStatus", "subscriptionPlan", "subscriptionEnd",
                    "subscriptionPeriod", "trialStartDate", "trialEndDate",
                    "hasPrioritySupport", "stripeCustomerId", "externalId",
                    "accountHolderId",
                    "preciseSchedulingEnabled", "skipWeekendsInAutoSchedule", "deletedAt"
                ]
            )

            if accept.contains("name") { existing.name = dto.name }
            if accept.contains("logoURL") { existing.logoURL = dto.logoUrl }
            if accept.contains("companyDescription") { existing.companyDescription = dto.description }
            if accept.contains("website") { existing.website = dto.website }
            if accept.contains("phone") { existing.phone = dto.phone }
            if accept.contains("email") { existing.email = dto.email }
            if accept.contains("address") { existing.address = dto.address }
            if accept.contains("latitude") { existing.latitude = dto.latitude }
            if accept.contains("longitude") { existing.longitude = dto.longitude }
            if accept.contains("defaultProjectColor") { existing.defaultProjectColor = dto.defaultProjectColor ?? "#9CA3AF" }
            if accept.contains("adminIdsString") { existing.adminIdsString = (dto.adminIds ?? []).joined(separator: ",") }
            if accept.contains("seatedEmployeeIds") { existing.seatedEmployeeIds = (dto.seatedEmployeeIds ?? []).joined(separator: ",") }
            if accept.contains("maxSeats") { existing.maxSeats = dto.maxSeats ?? 10 }
            if accept.contains("subscriptionStatus") { existing.subscriptionStatus = dto.subscriptionStatus }
            if accept.contains("subscriptionPlan") { existing.subscriptionPlan = dto.subscriptionPlan }
            if accept.contains("subscriptionEnd") { existing.subscriptionEnd = dto.subscriptionEnd.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("subscriptionPeriod") { existing.subscriptionPeriod = dto.subscriptionPeriod }
            if accept.contains("trialStartDate") { existing.trialStartDate = dto.trialStartDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("trialEndDate") { existing.trialEndDate = dto.trialEndDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("hasPrioritySupport") { existing.hasPrioritySupport = dto.hasPrioritySupport ?? false }
            if accept.contains("stripeCustomerId") { existing.stripeCustomerId = dto.stripeCustomerId }
            if accept.contains("externalId") { existing.externalId = dto.companyCode }
            if accept.contains("accountHolderId") { existing.accountHolderId = dto.accountHolderId }
            if accept.contains("preciseSchedulingEnabled") { existing.preciseSchedulingEnabled = dto.preciseSchedulingEnabled ?? false }
            if accept.contains("skipWeekendsInAutoSchedule") { existing.skipWeekendsInAutoSchedule = dto.skipWeekendsInAutoSchedule ?? true }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Users

    private func syncUsers(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.user.fetchAll(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeUser(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) users")
    }

    private func mergeUser(dto: SupabaseUserDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .user,
                entityId: id,
                fields: [
                    "firstName", "lastName", "email", "phone", "homeAddress",
                    "profileImageURL", "userColor", "role", "userType",
                    "hasCompletedAppOnboarding", "hasCompletedAppTutorial",
                    "devPermission", "latitude", "longitude", "locationName",
                    "isActive", "emergencyContactName", "emergencyContactPhone",
                    "emergencyContactRelationship", "deletedAt"
                ]
            )

            if accept.contains("firstName") { existing.firstName = dto.firstName }
            if accept.contains("lastName") { existing.lastName = dto.lastName }
            if accept.contains("email"), let email = dto.email { existing.email = email }
            if accept.contains("phone") { existing.phone = dto.phone }
            if accept.contains("homeAddress") { existing.homeAddress = dto.homeAddress }
            if accept.contains("profileImageURL") { existing.profileImageURL = dto.profileImageUrl }
            if accept.contains("userColor") { existing.userColor = dto.userColor }
            if accept.contains("role") {
                existing.role = dto.role.flatMap { UserRole(rawValue: $0) } ?? .crew
            }
            if accept.contains("userType") {
                existing.userType = dto.userType.flatMap { UserType(rawValue: $0) }
            }
            if accept.contains("hasCompletedAppOnboarding") {
                existing.hasCompletedAppOnboarding = dto.onboardingCompleted?["ios"] ?? false
            }
            if accept.contains("hasCompletedAppTutorial") {
                existing.hasCompletedAppTutorial = dto.hasCompletedTutorial ?? false
            }
            if accept.contains("devPermission") { existing.devPermission = dto.devPermission ?? false }
            if accept.contains("latitude") { existing.latitude = dto.latitude }
            if accept.contains("longitude") { existing.longitude = dto.longitude }
            if accept.contains("locationName") { existing.locationName = dto.locationName }
            if accept.contains("isActive") { existing.isActive = dto.isActive ?? true }
            if accept.contains("emergencyContactName") { existing.emergencyContactName = dto.emergencyContactName }
            if accept.contains("emergencyContactPhone") { existing.emergencyContactPhone = dto.emergencyContactPhone }
            if accept.contains("emergencyContactRelationship") { existing.emergencyContactRelationship = dto.emergencyContactRelationship }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Clients (permission-scoped)

    private func syncClients(since: Date?, repos: InboundRepositories) async throws {
        let scope = await MainActor.run {
            PermissionStore.shared.scope(for: "clients.view") ?? "all"
        }
        let userId = await MainActor.run {
            UserDefaults.standard.string(forKey: "currentUserId")
        }

        let dtos = try await repos.client.fetchAll(since: since, scope: scope, userId: userId)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeClient(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) clients (scope: \(scope))")
    }

    private func mergeClient(dto: SupabaseClientDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .client,
                entityId: id,
                fields: [
                    "name", "email", "phoneNumber", "address",
                    "latitude", "longitude", "profileImageURL",
                    "notes", "companyId", "deletedAt"
                ]
            )

            if accept.contains("name") { existing.name = dto.name }
            if accept.contains("email") { existing.email = dto.email }
            if accept.contains("phoneNumber") { existing.phoneNumber = dto.phoneNumber }
            if accept.contains("address") { existing.address = dto.address }
            if accept.contains("latitude") { existing.latitude = dto.latitude }
            if accept.contains("longitude") { existing.longitude = dto.longitude }
            if accept.contains("profileImageURL") { existing.profileImageURL = dto.profileImageUrl }
            if accept.contains("notes") { existing.notes = dto.notes }
            if accept.contains("companyId") { existing.companyId = dto.companyId }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            existing.needsSync = false

            if existing.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.client, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.client, id: id)
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)

            if model.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.client, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.client, id: id)
            }
        }
    }

    // MARK: - Sync: SubClients

    private func syncSubClients(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.client.fetchAllSubClients(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeSubClient(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) sub-clients")
    }

    private func mergeSubClient(dto: SupabaseSubClientDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<SubClient>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .subClient,
                entityId: id,
                fields: [
                    "name", "title", "email", "phoneNumber", "address", "deletedAt"
                ]
            )

            if accept.contains("name") { existing.name = dto.name }
            if accept.contains("title") { existing.title = dto.title }
            if accept.contains("email") { existing.email = dto.email }
            if accept.contains("phoneNumber") { existing.phoneNumber = dto.phoneNumber }
            if accept.contains("address") { existing.address = dto.address }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            // Link parent client relationship
            let parentId = dto.parentClientId
            let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == parentId })
            if let parentClient = try? modelContext.fetch(clientDescriptor).first {
                existing.client = parentClient
            }

            existing.lastSyncedAt = Date()
            existing.needsSync = false

            // Bug G4 — propagate to Spotlight via the DataActor's pending tracker.
            if existing.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.subClient, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.subClient, id: id)
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false

            let parentId = dto.parentClientId
            let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == parentId })
            if let parentClient = try? modelContext.fetch(clientDescriptor).first {
                model.client = parentClient
            }

            modelContext.insert(model)

            if model.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.subClient, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.subClient, id: id)
            }
        }
    }

    // MARK: - Sync: TaskTypes

    private func syncTaskTypes(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.taskType.fetchAll(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeTaskType(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) task types")
    }

    private func mergeTaskType(dto: SupabaseTaskTypeDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .taskType,
                entityId: id,
                fields: [
                    "display", "color", "icon", "isDefault",
                    "displayOrder", "dependenciesJSON", "defaultTeamMemberIdsString", "deletedAt"
                ]
            )

            if accept.contains("display") { existing.display = dto.display }
            if accept.contains("color") { existing.color = dto.color }
            if accept.contains("icon") { existing.icon = dto.icon }
            if accept.contains("isDefault") { existing.isDefault = dto.isDefault ?? false }
            if accept.contains("displayOrder") { existing.displayOrder = dto.displayOrder ?? 0 }
            if accept.contains("dependenciesJSON") {
                if let deps = dto.dependencies, !deps.isEmpty,
                   let data = try? JSONEncoder().encode(deps),
                   let json = String(data: data, encoding: .utf8) {
                    existing.dependenciesJSON = json
                }
            }
            if accept.contains("defaultTeamMemberIdsString") {
                existing.defaultTeamMemberIdsString = (dto.defaultTeamMemberIds ?? []).joined(separator: ",")
            }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            // Origin suppression: see mergeTask above. TaskType.id is not
            // @Attribute(.unique), so a duplicate insert here produces two rows
            // with the same id. The UI then resolves task.taskType to either,
            // and when it picks the stale duplicate (missing dependencies /
            // defaultTeamMemberIdsString), downstream code hits nil state and
            // crashes. The "Rail task type crash" repro traces to this path.
            if hasPendingOperations(entityType: .taskType, entityId: id) {
                print("[DataActor] Skipping merge insert for task type \(id) — pending local op exists (origin suppression)")
                return
            }

            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Projects (permission-scoped)

    private func syncProjects(since: Date?, repos: InboundRepositories) async throws {
        let scope = await MainActor.run {
            PermissionStore.shared.scope(for: "projects.view") ?? "all"
        }
        let userId = await MainActor.run {
            UserDefaults.standard.string(forKey: "currentUserId")
        }

        let dtos = try await repos.project.fetchAll(since: since, scope: scope, userId: userId)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeProject(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) projects (scope: \(scope))")
    }

    private func mergeProject(dto: SupabaseProjectDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == id }
        )
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        print("[DUPE_TRACE] DataActor.mergeProject id=\(id) existing_count=\(existingCount)")

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .project,
                entityId: id,
                fields: [
                    "title", "status", "company_id", "client_id", "opportunity_id",
                    "address", "latitude", "longitude",
                    "start_date", "end_date", "duration",
                    "notes", "description", "all_day",
                    "team_member_ids", "project_images", "deleted_at",
                    ProjectVinylOrderFields.status,
                    ProjectVinylOrderFields.orderedAt,
                    ProjectVinylOrderFields.orderedBy
                ]
            )

            if accept.contains("title") { existing.title = dto.title }
            if accept.contains("status") { existing.status = Status(rawValue: dto.status) ?? .rfq }
            if accept.contains("company_id") { existing.companyId = dto.companyId }
            if accept.contains("client_id") { existing.clientId = dto.clientId }
            if accept.contains("opportunity_id") { existing.opportunityId = dto.opportunityId }
            if accept.contains("address") { existing.address = dto.address }
            if accept.contains("latitude") { existing.latitude = dto.latitude }
            if accept.contains("longitude") { existing.longitude = dto.longitude }
            if accept.contains("start_date") { existing.startDate = dto.startDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("end_date") { existing.endDate = dto.endDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("duration") { existing.duration = dto.duration }
            if accept.contains("notes") { existing.notes = dto.notes }
            if accept.contains("description") { existing.projectDescription = dto.description }
            if accept.contains("all_day") { existing.allDay = dto.allDay ?? false }
            if accept.contains("team_member_ids") {
                existing.teamMemberIdsString = (dto.teamMemberIds ?? []).joined(separator: ",")
            }
            if accept.contains("project_images") {
                existing.projectImagesString = (dto.projectImages ?? []).joined(separator: ",")
            }
            if accept.contains("deleted_at") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }
            try upsertProjectVinylOrderMarker(dto: dto, acceptedFields: accept)

            existing.lastSyncedAt = Date()
            // Only clear needsSync if no pending SyncOperations remain for this entity.
            if !hasPendingOperations(entityType: .project, entityId: existing.id) {
                existing.needsSync = false
            }

            if existing.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.project, id: existing.id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.project, id: existing.id)
            }
        } else {
            // Origin suppression: if we wrote this entityId locally within the
            // last 60s — regardless of SyncOperation status (pending, inProgress,
            // completed) — the inbound/realtime payload is our own write echoing
            // back. Inserting here would produce a duplicate because Project.id
            // lacks @Attribute(.unique). Mirrors the ProjectTask suppression
            // below (bug f86cf554 / 858fa5e): under the DataActor path, the
            // outbound push flips the SyncOperation to "completed" before the
            // echo arrives, so the earlier pending-ops check failed silently.
            if hasRecentLocalWrite(entityType: .project, entityId: id, withinSeconds: 60) {
                print("[DUPE_TRACE] DataActor.mergeProject SUPPRESSED id=\(id) — recent local write within 60s")
                return
            }

            print("[DUPE_TRACE] DataActor.mergeProject INSERT id=\(id) — no recent local write, treating as remote create")
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
            modelContext.insert(dto.toVinylOrderMarkerModel())

            if model.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.project, id: model.id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.project, id: model.id)
            }
        }
    }

    private func upsertProjectVinylOrderMarker(
        dto: SupabaseProjectDTO,
        acceptedFields: Set<String>
    ) throws {
        let projectId = dto.id
        let descriptor = FetchDescriptor<ProjectVinylOrderMarker>(
            predicate: #Predicate { $0.id == projectId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            if acceptedFields.contains(ProjectVinylOrderFields.status) {
                existing.status = dto.resolvedVinylOrderStatus
            }
            if acceptedFields.contains(ProjectVinylOrderFields.orderedAt) {
                existing.orderedAt = dto.vinylOrderedAt.flatMap { SupabaseDate.parse($0) }
            }
            if acceptedFields.contains(ProjectVinylOrderFields.orderedBy) {
                existing.orderedBy = dto.vinylOrderedBy
            }
            existing.sourceProjectUpdatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) }
            existing.lastSyncedAt = Date()
        } else {
            let marker = dto.toVinylOrderMarkerModel()
            marker.lastSyncedAt = Date()
            modelContext.insert(marker)
        }
    }

    // MARK: - Sync: Tasks (permission-scoped)

    private func syncTasks(since: Date?, repos: InboundRepositories) async throws {
        let scope = await MainActor.run {
            PermissionStore.shared.scope(for: "tasks.view") ?? "all"
        }
        let userId = await MainActor.run {
            UserDefaults.standard.string(forKey: "currentUserId")
        }

        let dtos = try await repos.task.fetchAll(since: since, scope: scope, userId: userId)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeTask(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) tasks (scope: \(scope))")
    }

    private func mergeTask(dto: SupabaseProjectTaskDTO) throws {
        // Canonicalize to lowercase — Postgres uuid storage is lowercase, so
        // dto.id should already be lowercase, but defense-in-depth in case a
        // payload path ever delivers mixed-case input. Local ProjectTask.id is
        // kept lowercase by normalizeTaskIdsToLowercase + new-write canonicalization.
        let id = dto.id.lowercased()
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id == id }
        )

        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        print("[DUPE_TRACE] ACTOR.mergeTask id=\(id) existing_count=\(existingCount) ctx=\(ObjectIdentifier(modelContext))")

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .projectTask,
                entityId: id,
                fields: [
                    "status", "taskNotes", "customTitle", "taskColor",
                    "taskTypeId", "startDate", "endDate", "duration",
                    "displayOrder", "teamMemberIdsString",
                    "sourceLineItemId", "sourceEstimateId",
                    "dependencyOverridesJSON", "startTime", "endTime", "deletedAt"
                ]
            )

            if accept.contains("status") { existing.status = TaskStatus(rawValue: dto.status) ?? .active }
            if accept.contains("taskNotes") { existing.taskNotes = dto.taskNotes }
            if accept.contains("customTitle") { existing.customTitle = dto.customTitle }
            if accept.contains("taskColor") { existing.taskColor = dto.taskColor ?? "#59779F" }
            if accept.contains("taskTypeId") {
                existing.taskTypeId = dto.taskTypeId ?? ""
                // Rewire the TaskType `@Relationship` to match the new id. Without
                // this, UI that reads `task.taskType` (badge color, display name)
                // stays pointed at the OLD taskType until the next full sync's
                // linkAllRelationships pass. Realtime + single-row merges never
                // triggered that pass, so the badge could lag by minutes.
                if !existing.taskTypeId.isEmpty {
                    let ttId = existing.taskTypeId
                    let ttDescriptor = FetchDescriptor<TaskType>(
                        predicate: #Predicate<TaskType> { $0.id == ttId }
                    )
                    if let newType = try? modelContext.fetch(ttDescriptor).first {
                        if existing.taskType?.id != newType.id { existing.taskType = newType }
                    }
                } else if existing.taskType != nil {
                    existing.taskType = nil
                }
            }
            if accept.contains("startDate") { existing.startDate = dto.startDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("endDate") { existing.endDate = dto.endDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("duration") { existing.duration = dto.duration ?? 1 }
            if accept.contains("displayOrder") { existing.displayOrder = dto.displayOrder ?? 0 }
            if accept.contains("teamMemberIdsString") {
                let newIdString = (dto.teamMemberIds ?? []).joined(separator: ",")
                existing.teamMemberIdsString = newIdString
                // Rewire the `teamMembers: [User]` relationship to match the new
                // id string. Without this, UI that reads `task.teamMembers`
                // (avatars on the task row) stays stale after any realtime edit
                // until the next full sync runs linkAllRelationships. That gap
                // was the source of the "avatars flicker between openings" bug.
                let ids = existing.getTeamMemberIds()
                if ids.isEmpty {
                    if !existing.teamMembers.isEmpty { existing.teamMembers = [] }
                } else {
                    let userDescriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { ids.contains($0.id) }
                    )
                    let users = (try? modelContext.fetch(userDescriptor)) ?? []
                    if Set(existing.teamMembers.map(\.id)) != Set(users.map(\.id)) {
                        existing.teamMembers = users
                    }
                }
            }
            if accept.contains("sourceLineItemId") { existing.sourceLineItemId = dto.sourceLineItemId }
            if accept.contains("sourceEstimateId") { existing.sourceEstimateId = dto.sourceEstimateId }
            if accept.contains("dependencyOverridesJSON") {
                if let overrides = dto.dependencyOverrides, !overrides.isEmpty,
                   let data = try? JSONEncoder().encode(overrides),
                   let json = String(data: data, encoding: .utf8) {
                    existing.dependencyOverridesJSON = json
                }
            }
            if accept.contains("startTime") {
                if let st = dto.startTime, let parsed = Self.parseTime(st) {
                    existing.startTime = parsed
                }
            }
            if accept.contains("endTime") {
                if let et = dto.endTime, let parsed = Self.parseTime(et) {
                    existing.endTime = parsed
                }
            }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            if !hasPendingOperations(entityType: .projectTask, entityId: existing.id) {
                existing.needsSync = false
            }

            if existing.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.task, id: existing.id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.task, id: existing.id)
            }
        } else {
            // Origin suppression: if we wrote this entityId locally recently —
            // regardless of the SyncOperation's current status (pending,
            // inProgress, completed) — the realtime echo/full-sync DTO is our
            // own write coming back. Inserting here produces a duplicate
            // because ProjectTask.id lacks @Attribute(.unique) and the actor's
            // fetch above can miss a row the main context just wrote before
            // cross-context visibility settles.
            //
            // Previous implementation used `hasPendingOperations` (status ==
            // "pending"), but actor serialization guarantees processPending
            // runs BEFORE this merge — meaning the op is already "completed"
            // by the time the echo arrives, so that check always returned
            // false. A timestamp window correctly captures the full write
            // lifecycle. 60s is comfortably wider than typical realtime echo
            // latency while short enough that a stale op couldn't mask a
            // legitimate remote update minutes later.
            if hasRecentLocalWrite(entityType: .projectTask, entityId: id, withinSeconds: 60) {
                print("[DUPE_TRACE] ACTOR.mergeTask SUPPRESSED id=\(id) — recent local write within 60s (origin suppression)")
                return
            }

            print("[DUPE_TRACE] ACTOR.mergeTask INSERT id=\(id) — no recent local write, treating as remote create ctx=\(ObjectIdentifier(modelContext))")
            let model = dto.toModel()
            model.id = id  // enforce lowercase canonicalization
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)

            // Wire relationships on the freshly-inserted row so the UI sees a
            // complete task immediately (project, taskType, teamMembers).
            // Without this, the row renders missing badge and avatars until
            // the next sync's linkAllRelationships pass runs.
            let projId = model.projectId
            if let project = try? modelContext.fetch(
                FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.id == projId })
            ).first {
                model.project = project
            }
            if !model.taskTypeId.isEmpty {
                let ttId = model.taskTypeId
                if let taskType = try? modelContext.fetch(
                    FetchDescriptor<TaskType>(predicate: #Predicate<TaskType> { $0.id == ttId })
                ).first {
                    model.taskType = taskType
                }
            }
            let memberIds = model.getTeamMemberIds()
            if !memberIds.isEmpty {
                let users = (try? modelContext.fetch(
                    FetchDescriptor<User>(predicate: #Predicate<User> { memberIds.contains($0.id) })
                )) ?? []
                if !users.isEmpty { model.teamMembers = users }
            }

            if model.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.task, id: model.id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.task, id: model.id)
            }
        }
    }

    // MARK: - Sync: Project Notes

    private func syncProjectNotes(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.projectNote.fetchAll(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeProjectNote(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) project notes")
    }

    private func mergeProjectNote(dto: ProjectNoteDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .projectNote,
                entityId: id,
                fields: [
                    "content", "attachmentsJSON", "mentionedUserIdsString",
                    "updatedAt", "deletedAt"
                ]
            )

            if accept.contains("content") { existing.content = dto.content }
            if accept.contains("attachmentsJSON") {
                if let attachments = dto.attachments, !attachments.isEmpty,
                   let data = try? JSONEncoder().encode(attachments),
                   let json = String(data: data, encoding: .utf8) {
                    existing.attachmentsJSON = json
                } else if dto.attachments == nil || (dto.attachments?.isEmpty ?? true) {
                    existing.attachmentsJSON = "[]"
                }
            }
            if accept.contains("mentionedUserIdsString") {
                existing.mentionedUserIdsString = (dto.mentionedUserIds ?? []).joined(separator: ",")
            }
            if accept.contains("updatedAt") { existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            if !hasPendingOperations(entityType: .projectNote, entityId: existing.id) {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Photo Annotations

    private func syncPhotoAnnotations(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.photoAnnotation.fetchAll(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergePhotoAnnotation(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) photo annotations")
    }

    private func mergePhotoAnnotation(dto: PhotoAnnotationDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .photoAnnotation,
                entityId: id,
                fields: [
                    "annotationURL", "renderedPhotoURL", "note", "updatedAt", "deletedAt", "dimensions"
                ]
            )

            if accept.contains("annotationURL") { existing.annotationURL = dto.annotationUrl }
            if accept.contains("renderedPhotoURL") { existing.renderedPhotoURL = dto.renderedPhotoUrl }
            if accept.contains("note") { existing.note = dto.note ?? "" }
            if accept.contains("updatedAt") { existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("dimensions"), let dimensionsData = dto.dimensionsData {
                existing.dimensionsData = dimensionsData
            }

            existing.lastSyncedAt = Date()
            if !hasPendingOperations(entityType: .photoAnnotation, entityId: existing.id) {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Deck Designs

    private func syncDeckDesigns(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.deckDesign.fetchAll(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeDeckDesign(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) deck designs")
    }

    private func mergeDeckDesign(dto: SupabaseDeckDesignDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Field names MUST match the keys recorded in
            // `enqueueDeckDesignSync` (snake_case Supabase columns) so the
            // pending-op suppression in `acceptableFields` can detect a
            // local edit that hasn't been pushed yet. Using SwiftData
            // property names here previously broke the lookup — every
            // inbound sync clobbered the user's pending `drawing_data` /
            // `thumbnail_url` / `updated_at` / `deleted_at` with stale
            // server values, which surfaced as "deck designs are not
            // saving" and "missing details" reports
            // (bugs bed3a1fd, 48189db1, b2472c07, ab554b5f).
            let accept = acceptableFields(
                entityType: .deckDesign,
                entityId: id,
                fields: DeckDesign.serverMergeFields
            )

            existing.applyServerSnapshot(dto, accepting: accept)
            existing.lastSyncedAt = Date()
            if !hasPendingOperations(entityType: .deckDesign, entityId: existing.id) {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Wizard States

    private func syncWizardStates(since: Date?, repos: InboundRepositories) async throws {
        // Resolve userId at call time — wizard_states is user-scoped, so a fresh
        // login needs the correct id even if the repos struct was built earlier.
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        guard !userId.isEmpty else {
            print("[DataActor] No userId — skipping wizard_states sync")
            return
        }

        let dtos = try await repos.wizardState.fetchForUser(userId, since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeWizardState(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) wizard states")
    }

    private func mergeWizardState(dto: SupabaseWizardStateDTO) throws {
        let id = dto.id
        // Primary match on id.
        let idDescriptor = FetchDescriptor<WizardState>(
            predicate: #Predicate { $0.id == id }
        )
        var existing = try modelContext.fetch(idDescriptor).first

        // Fallback match on (wizardId, userId) for rows created locally with a
        // different UUID before this sync landed. Adopt the server id on adoption
        // so subsequent pulls resolve directly.
        if existing == nil {
            let wizardId = dto.wizardId
            let userId = dto.userId
            let pairDescriptor = FetchDescriptor<WizardState>(
                predicate: #Predicate { $0.wizardId == wizardId && $0.userId == userId }
            )
            if let fallback = try modelContext.fetch(pairDescriptor).first {
                fallback.id = id
                existing = fallback
            }
        }

        if let existing = existing {
            let accept = acceptableFields(
                entityType: .wizardState,
                entityId: id,
                fields: [
                    "statusRaw", "currentStepIndex", "doNotShow",
                    "completedAt", "totalDurationMs", "stepsSkipped",
                    "lastActiveAt", "currentSessionId"
                ]
            )

            if accept.contains("statusRaw") { existing.statusRaw = dto.status }
            if accept.contains("currentStepIndex") { existing.currentStepIndex = dto.currentStepIndex }
            if accept.contains("doNotShow") { existing.doNotShow = dto.doNotShow }
            if accept.contains("completedAt") { existing.completedAt = dto.completedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("totalDurationMs") { existing.totalDurationMs = dto.totalDurationMs }
            if accept.contains("stepsSkipped") { existing.stepsSkipped = dto.stepsSkipped }
            if accept.contains("lastActiveAt") { existing.lastActiveAt = dto.lastActiveAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("currentSessionId") { existing.currentSessionId = dto.currentSessionId }

            existing.lastSyncedAt = Date()
            if !hasPendingOperations(entityType: .wizardState, entityId: existing.id) {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Estimates (+ soft-deletes on delta)

    private func syncEstimates(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.estimate.fetchAll(since: since)

        try modelContext.transaction {
            for dto in dtos {
                try mergeEstimate(dto: dto)
            }
        }

        // Handle soft deletes for delta sync
        if let sinceDate = since {
            let deletedIds = try await repos.estimate.fetchDeletedIds(since: sinceDate)
            if !deletedIds.isEmpty {
                try modelContext.transaction {
                    for id in deletedIds {
                        try markEstimateDeleted(id: id)
                    }
                }
            }
        }

        print("[DataActor] Merged \(dtos.count) estimates")
    }

    private func mergeEstimate(dto: EstimateDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .estimate,
                entityId: id,
                fields: [
                    "companyId", "estimateNumber", "title", "status", "subtotal", "taxRate",
                    "taxAmount", "total", "internalNotes", "validUntil",
                    "version", "clientId", "projectId", "opportunityId", "deletedAt"
                ]
            )

            if accept.contains("companyId") { existing.companyId = dto.companyId }
            if accept.contains("estimateNumber") { existing.estimateNumber = dto.estimateNumber ?? "" }
            if accept.contains("title") { existing.title = dto.title ?? "" }
            if accept.contains("status") {
                existing.status = EstimateStatus(rawValue: dto.status) ?? .draft
            }
            if accept.contains("subtotal") { existing.subtotal = dto.subtotal }
            if accept.contains("taxRate") { existing.taxRate = dto.taxRate ?? 0 }
            if accept.contains("taxAmount") { existing.taxAmount = dto.taxAmount ?? 0 }
            if accept.contains("total") { existing.total = dto.total }
            if accept.contains("internalNotes") { existing.internalNotes = dto.notes }
            if accept.contains("validUntil") {
                existing.validUntil = dto.expirationDate.flatMap { SupabaseDate.parse($0) }
            }
            if accept.contains("version") { existing.version = dto.version }
            if accept.contains("clientId") { existing.clientId = dto.clientId }
            if accept.contains("projectId") { existing.projectId = dto.projectId }
            if accept.contains("opportunityId") { existing.opportunityId = dto.opportunityId }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }

            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? Date()
            existing.lastSyncedAt = Date()
            existing.needsSync = false

            if existing.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.estimate, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.estimate, id: id)
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)

            if model.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.estimate, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.estimate, id: id)
            }
        }
    }

    private func markEstimateDeleted(id: String) throws {
        let descriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            markSpotlightDeleted(domain: SpotlightDomain.estimate, id: id)
        }
    }

    // MARK: - Sync: Invoices (+ line items + payments + soft-deletes)

    private func syncInvoices(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.invoice.fetchAll(since: since)

        try modelContext.transaction {
            for dto in dtos {
                try mergeInvoice(dto: dto)
                try mergeInvoiceLineItems(dto: dto)
                try mergeInvoicePayments(dto: dto)
            }
        }

        if let sinceDate = since {
            let deletedIds = try await repos.invoice.fetchDeletedIds(since: sinceDate)
            if !deletedIds.isEmpty {
                try modelContext.transaction {
                    for id in deletedIds {
                        try markInvoiceDeleted(id: id)
                    }
                }
            }
        }

        print("[DataActor] Merged \(dtos.count) invoices")
    }

    private func mergeInvoice(dto: InvoiceDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .invoice,
                entityId: id,
                fields: [
                    "companyId", "invoiceNumber", "title", "status", "subtotal", "taxRate",
                    "taxAmount", "total", "amountPaid", "balanceDue",
                    "dueDate", "sentAt", "paidAt", "clientId", "projectId",
                    "estimateId", "opportunityId", "deletedAt"
                ]
            )

            if accept.contains("companyId") { existing.companyId = dto.companyId }
            if accept.contains("invoiceNumber") { existing.invoiceNumber = dto.invoiceNumber ?? "" }
            if accept.contains("title") { existing.title = dto.subject }
            if accept.contains("status") {
                existing.status = InvoiceStatus(rawValue: dto.status ?? "") ?? .draft
            }
            if accept.contains("subtotal") { existing.subtotal = dto.subtotal ?? 0 }
            if accept.contains("taxRate") { existing.taxRate = dto.taxRate ?? 0 }
            if accept.contains("taxAmount") { existing.taxAmount = dto.taxAmount ?? 0 }
            if accept.contains("total") { existing.total = dto.total ?? 0 }
            if accept.contains("amountPaid") { existing.amountPaid = dto.amountPaid ?? 0 }
            if accept.contains("balanceDue") { existing.balanceDue = dto.balanceDue ?? 0 }
            if accept.contains("dueDate") { existing.dueDate = dto.dueDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("sentAt") { existing.sentAt = dto.sentAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("paidAt") { existing.paidAt = dto.paidAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("clientId") { existing.clientId = dto.clientId }
            if accept.contains("projectId") { existing.projectId = dto.projectId }
            if accept.contains("estimateId") { existing.estimateId = dto.estimateId }
            if accept.contains("opportunityId") { existing.opportunityId = dto.opportunityId }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }

            existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } ?? Date()
            existing.lastSyncedAt = Date()
            existing.needsSync = false

            if existing.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.invoice, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.invoice, id: id)
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)

            if model.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.invoice, id: id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.invoice, id: id)
            }
        }
    }

    private func mergeInvoiceLineItems(dto: InvoiceDTO) throws {
        let freshItems = dto.lineItems ?? []
        let freshIds: Set<String> = Set(freshItems.map { $0.id })
        let invoiceId = dto.id

        // Upsert: insert new, update existing
        for liDTO in freshItems {
            let liId = liDTO.id
            let descriptor = FetchDescriptor<InvoiceLineItem>(
                predicate: #Predicate { $0.id == liId }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                let fresh = liDTO.toModel()
                existing.name = fresh.name
                existing.itemDescription = fresh.itemDescription
                existing.quantity = fresh.quantity
                existing.unit = fresh.unit
                existing.unitPrice = fresh.unitPrice
                existing.lineTotal = fresh.lineTotal
                existing.type = fresh.type
                existing.displayOrder = fresh.displayOrder
                existing.parentLineItemId = fresh.parentLineItemId
            } else {
                modelContext.insert(liDTO.toModel())
            }
        }

        // Delete: any local item for this invoice no longer on the server
        let localDescriptor = FetchDescriptor<InvoiceLineItem>(
            predicate: #Predicate { $0.invoiceId == invoiceId }
        )
        let local = (try? modelContext.fetch(localDescriptor)) ?? []
        for item in local where !freshIds.contains(item.id) {
            modelContext.delete(item)
        }
    }

    private func mergeInvoicePayments(dto: InvoiceDTO) throws {
        let freshPayments = dto.payments ?? []
        let freshIds: Set<String> = Set(freshPayments.map { $0.id })
        let invoiceId = dto.id

        for pDTO in freshPayments {
            let pId = pDTO.id
            let descriptor = FetchDescriptor<Payment>(
                predicate: #Predicate { $0.id == pId }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                let fresh = pDTO.toModel()
                existing.amount = fresh.amount
                existing.method = fresh.method
                existing.paidAt = fresh.paidAt
                existing.notes = fresh.notes
            } else {
                modelContext.insert(pDTO.toModel())
            }
        }

        let localDescriptor = FetchDescriptor<Payment>(
            predicate: #Predicate { $0.invoiceId == invoiceId }
        )
        let local = (try? modelContext.fetch(localDescriptor)) ?? []
        for payment in local where !freshIds.contains(payment.id) {
            modelContext.delete(payment)
        }
    }

    private func markInvoiceDeleted(id: String) throws {
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            markSpotlightDeleted(domain: SpotlightDomain.invoice, id: id)
        }
    }

    // MARK: - Sync: Catalog Categories

    /// Mirrors InboundProcessor.syncCatalogCategories: merge by id with
    /// field-level pending-op protection, then tombstone server soft-deletes.
    private func syncCatalogCategories(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchCategoriesForSync(since: since)
        let deletedIds: [String]
        if let sinceDate = since {
            deletedIds = try await repos.catalog.fetchDeletedCategoryIds(since: sinceDate)
        } else {
            deletedIds = []
        }

        guard !dtos.isEmpty || !deletedIds.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeCatalogCategory(dto: dto)
            }
            for id in deletedIds {
                try tombstoneCatalogCategory(id: id)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog categories (tombstoned \(deletedIds.count))")
    }

    private func mergeCatalogCategory(dto: CatalogCategoryDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogCategory,
                entityId: id,
                fields: [
                    "companyId", "name", "parentId", "sortOrder", "colorHex",
                    "defaultWarningThreshold", "defaultCriticalThreshold", "deletedAt"
                ]
            )
            if accept.contains("companyId")                 { existing.companyId = dto.companyId }
            if accept.contains("name")                      { existing.name = dto.name }
            if accept.contains("parentId")                  { existing.parentId = dto.parentId }
            if accept.contains("sortOrder")                 { existing.sortOrder = dto.sortOrder }
            if accept.contains("colorHex")                  { existing.colorHex = dto.colorHex }
            if accept.contains("defaultWarningThreshold")   { existing.defaultWarningThreshold = dto.defaultWarningThreshold }
            if accept.contains("defaultCriticalThreshold")  { existing.defaultCriticalThreshold = dto.defaultCriticalThreshold }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    private func tombstoneCatalogCategory(id: String) throws {
        let descriptor = FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
        }
    }

    // MARK: - Sync: Catalog Units

    /// catalog_units lacks a `fetchDeletedUnitIds` repo method; the table has a
    /// soft-delete column but no dedicated delta endpoint yet. Tombstones come
    /// through as `updated_at` bumps via the deletedAt field on the row payload.
    private func syncCatalogUnits(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchUnitsForSync(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeCatalogUnit(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog units")
    }

    private func mergeCatalogUnit(dto: CatalogUnitDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogUnit>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogUnit,
                entityId: id,
                fields: [
                    "companyId", "display", "abbreviation", "dimension",
                    "isDefault", "sortOrder", "deletedAt"
                ]
            )
            if accept.contains("companyId")     { existing.companyId = dto.companyId }
            if accept.contains("display")       { existing.display = dto.display }
            if accept.contains("abbreviation")  { existing.abbreviation = dto.abbreviation }
            if accept.contains("dimension")     { existing.dimension = dto.dimension }
            if accept.contains("isDefault")     { existing.isDefault = dto.isDefault }
            if accept.contains("sortOrder")     { existing.sortOrder = dto.sortOrder }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Catalog Tags

    private func syncCatalogTags(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchTagsForSync(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeCatalogTag(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog tags")
    }

    private func mergeCatalogTag(dto: CatalogTagDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogTag>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogTag,
                entityId: id,
                fields: ["companyId", "name", "warningThreshold", "criticalThreshold", "deletedAt"]
            )
            if accept.contains("companyId")          { existing.companyId = dto.companyId }
            if accept.contains("name")               { existing.name = dto.name }
            if accept.contains("warningThreshold")   { existing.warningThreshold = dto.warningThreshold }
            if accept.contains("criticalThreshold")  { existing.criticalThreshold = dto.criticalThreshold }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Catalog Items (variant families)

    private func syncCatalogItems(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchItemsForSync(since: since)
        let deletedIds: [String]
        if let sinceDate = since {
            deletedIds = try await repos.catalog.fetchDeletedItemIds(since: sinceDate)
        } else {
            deletedIds = []
        }

        guard !dtos.isEmpty || !deletedIds.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeCatalogItem(dto: dto)
            }
            for id in deletedIds {
                try tombstoneCatalogItem(id: id)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog items (tombstoned \(deletedIds.count))")
    }

    private func mergeCatalogItem(dto: CatalogItemDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogItem,
                entityId: id,
                fields: [
                    "companyId", "categoryId", "name", "itemDescription",
                    "defaultPrice", "defaultUnitCost",
                    "defaultWarningThreshold", "defaultCriticalThreshold",
                    "defaultUnitId", "imageUrl", "notes", "isActive", "deletedAt"
                ]
            )
            if accept.contains("companyId")                 { existing.companyId = dto.companyId }
            if accept.contains("categoryId")                { existing.categoryId = dto.categoryId }
            if accept.contains("name")                      { existing.name = dto.name }
            if accept.contains("itemDescription")           { existing.itemDescription = dto.description }
            if accept.contains("defaultPrice")              { existing.defaultPrice = dto.defaultPrice }
            if accept.contains("defaultUnitCost")           { existing.defaultUnitCost = dto.defaultUnitCost }
            if accept.contains("defaultWarningThreshold")   { existing.defaultWarningThreshold = dto.defaultWarningThreshold }
            if accept.contains("defaultCriticalThreshold")  { existing.defaultCriticalThreshold = dto.defaultCriticalThreshold }
            if accept.contains("defaultUnitId")             { existing.defaultUnitId = dto.defaultUnitId }
            if accept.contains("imageUrl")                  { existing.imageUrl = dto.imageUrl }
            if accept.contains("notes")                     { existing.notes = dto.notes }
            if accept.contains("isActive")                  { existing.isActive = dto.isActive }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    private func tombstoneCatalogItem(id: String) throws {
        let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
        }
    }

    // MARK: - Sync: Catalog Variants

    private func syncCatalogVariants(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchVariantsForSync(since: since)
        let deletedIds: [String]
        if let sinceDate = since {
            deletedIds = try await repos.catalog.fetchDeletedVariantIds(since: sinceDate)
        } else {
            deletedIds = []
        }

        guard !dtos.isEmpty || !deletedIds.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeCatalogVariant(dto: dto)
            }
            for id in deletedIds {
                try tombstoneCatalogVariant(id: id)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog variants (tombstoned \(deletedIds.count))")
    }

    private func mergeCatalogVariant(dto: CatalogVariantDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogVariant,
                entityId: id,
                fields: [
                    "companyId", "catalogItemId", "sku", "quantity",
                    "priceOverride", "unitCostOverride",
                    "warningThreshold", "criticalThreshold", "unitId",
                    "isActive", "deletedAt"
                ]
            )
            if accept.contains("companyId")          { existing.companyId = dto.companyId }
            if accept.contains("catalogItemId")      { existing.catalogItemId = dto.catalogItemId }
            if accept.contains("sku")                { existing.sku = dto.sku }
            if accept.contains("quantity")           { existing.quantity = dto.quantity }
            if accept.contains("priceOverride")      { existing.priceOverride = dto.priceOverride }
            if accept.contains("unitCostOverride")   { existing.unitCostOverride = dto.unitCostOverride }
            if accept.contains("warningThreshold")   { existing.warningThreshold = dto.warningThreshold }
            if accept.contains("criticalThreshold")  { existing.criticalThreshold = dto.criticalThreshold }
            if accept.contains("unitId")             { existing.unitId = dto.unitId }
            if accept.contains("isActive")           { existing.isActive = dto.isActive }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    private func tombstoneCatalogVariant(id: String) throws {
        let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
        }
    }

    // MARK: - Sync: Catalog Options (full reconcile)

    /// catalog_options has no updated_at — full reconcile: pull every option for
    /// the company, prune local rows missing from the response. Mirrors
    /// InboundProcessor.syncCatalogOptions verbatim.
    private func syncCatalogOptions(repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchOptionsForCompany()
        let serverIds = Set(dtos.map(\.id))
        let companyId = repos.companyId

        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<CatalogOption>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    existing.catalogItemId = dto.catalogItemId
                    existing.name = dto.name
                    existing.sortOrder = dto.sortOrder
                    existing.lastSyncedAt = Date()
                    existing.needsSync = false
                } else {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    modelContext.insert(model)
                }
            }

            // Prune local options the server no longer reports — scoped to
            // items owned by this company so we don't touch cross-company rows.
            let allLocal = try modelContext.fetch(FetchDescriptor<CatalogOption>())
            let localItemIds = Set(try modelContext.fetch(FetchDescriptor<CatalogItem>())
                .filter { $0.companyId == companyId }
                .map(\.id))
            for option in allLocal where localItemIds.contains(option.catalogItemId) && !serverIds.contains(option.id) {
                modelContext.delete(option)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog options")
    }

    // MARK: - Sync: Catalog Option Values

    private func syncCatalogOptionValues(repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchOptionValuesForCompany()
        let serverIds = Set(dtos.map(\.id))

        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<CatalogOptionValue>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    existing.optionId = dto.optionId
                    existing.value = dto.value
                    existing.sortOrder = dto.sortOrder
                    existing.lastSyncedAt = Date()
                    existing.needsSync = false
                } else {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    modelContext.insert(model)
                }
            }

            // Prune values whose option still belongs to this company but whose
            // id is no longer reported by the server.
            let localOptionIds = Set(try modelContext.fetch(FetchDescriptor<CatalogOption>()).map(\.id))
            let allLocal = try modelContext.fetch(FetchDescriptor<CatalogOptionValue>())
            for value in allLocal where localOptionIds.contains(value.optionId) && !serverIds.contains(value.id) {
                modelContext.delete(value)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog option values")
    }

    // MARK: - Sync: Catalog Variant ↔ Option-Value joins

    /// Junction has no surrogate id from the server; uniqueness is the
    /// (variantId, optionValueId) pair. Wipe + insert for variants this company
    /// owns is the simplest correctness story — matches InboundProcessor.
    private func syncCatalogVariantOptionValues(repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchVariantOptionValuesForCompany()
        let companyId = repos.companyId

        try modelContext.transaction {
            let companyVariantIds = Set(try modelContext.fetch(FetchDescriptor<CatalogVariant>())
                .filter { $0.companyId == companyId }
                .map(\.id))

            let allLocal = try modelContext.fetch(FetchDescriptor<CatalogVariantOptionValue>())
            for row in allLocal where companyVariantIds.contains(row.variantId) {
                modelContext.delete(row)
            }

            for dto in dtos {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                modelContext.insert(model)
            }
        }
        print("[DataActor] Merged \(dtos.count) variant option-value joins")
    }

    // MARK: - Sync: Catalog Item Tags

    private func syncCatalogItemTags(repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchItemTagsForCompany()
        let serverIds = Set(dtos.map(\.id))
        let companyId = repos.companyId

        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<CatalogItemTag>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    existing.catalogItemId = dto.catalogItemId
                    existing.tagId = dto.tagId
                    existing.lastSyncedAt = Date()
                } else {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    modelContext.insert(model)
                }
            }

            let companyItemIds = Set(try modelContext.fetch(FetchDescriptor<CatalogItem>())
                .filter { $0.companyId == companyId }
                .map(\.id))
            let allLocal = try modelContext.fetch(FetchDescriptor<CatalogItemTag>())
            for row in allLocal where companyItemIds.contains(row.catalogItemId) && !serverIds.contains(row.id) {
                modelContext.delete(row)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog item-tag joins")
    }

    // MARK: - Sync: Catalog Snapshots

    /// Snapshots are append-only — no updates, no soft-deletes. Just upsert by id.
    private func syncCatalogSnapshots(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.catalog.fetchSnapshotsForSync(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeCatalogSnapshot(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog snapshots")
    }

    private func mergeCatalogSnapshot(dto: CatalogSnapshotDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogSnapshot>(predicate: #Predicate { $0.id == id })
        if try modelContext.fetch(descriptor).first == nil {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Catalog Snapshot Items

    /// Snapshot items are immutable. For any local snapshot belonging to this
    /// company whose item count is non-zero but whose items are missing
    /// locally, pull its rows in one batched query.
    private func syncCatalogSnapshotItems(repos: InboundRepositories) async throws {
        let companyId = repos.companyId
        let snapshots = try modelContext.fetch(FetchDescriptor<CatalogSnapshot>())
            .filter { $0.companyId == companyId }

        let needsBackfill = snapshots.filter { snap in
            guard snap.itemCount > 0 else { return false }
            let snapId = snap.id
            let descriptor = FetchDescriptor<CatalogSnapshotItem>(
                predicate: #Predicate { $0.snapshotId == snapId }
            )
            let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
            return existingCount == 0
        }

        guard !needsBackfill.isEmpty else {
            print("[DataActor] No catalog snapshots need item backfill")
            return
        }

        let snapshotIds = needsBackfill.map(\.id)
        let dtos = try await repos.catalog.fetchSnapshotItemsForSnapshots(snapshotIds)

        try modelContext.transaction {
            let allItemIds = Set(dtos.map(\.id))
            let existingDescriptor = FetchDescriptor<CatalogSnapshotItem>(
                predicate: #Predicate { allItemIds.contains($0.id) }
            )
            let existingItems = try modelContext.fetch(existingDescriptor)
            let existingIds = Set(existingItems.map(\.id))

            for dto in dtos where !existingIds.contains(dto.id) {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog snapshot items across \(snapshotIds.count) snapshots")
    }

    // MARK: - Sync: Catalog Orders

    /// CatalogOrderRepository.fetchAll filters out soft-deleted rows, so every
    /// id we see here is live. Local rows missing from the response are pruned
    /// (treated as server-side deletes) — apart from rows with pending local
    /// SyncOperations, which we leave untouched.
    private func syncCatalogOrders(repos: InboundRepositories) async throws {
        let dtos = try await repos.order.fetchAll()
        let serverIds = Set(dtos.map(\.id))
        let companyId = repos.companyId

        try modelContext.transaction {
            for dto in dtos {
                try mergeCatalogOrder(dto: dto)
            }

            let companyLocal = try modelContext.fetch(FetchDescriptor<CatalogOrder>())
                .filter { $0.companyId == companyId }
            for order in companyLocal where !serverIds.contains(order.id) {
                if hasPendingOperations(entityType: .catalogOrder, entityId: order.id) { continue }
                order.deletedAt = Date()
                order.needsSync = false
            }
        }
        print("[DataActor] Merged \(dtos.count) catalog orders")
    }

    private func mergeCatalogOrder(dto: CatalogOrderDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogOrder>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogOrder,
                entityId: id,
                fields: [
                    "companyId", "status", "title", "supplierName", "supplierContact",
                    "expectedDeliveryDate", "notes", "createdById",
                    "sentAt", "fulfilledAt", "cancelledAt", "deletedAt"
                ]
            )
            if accept.contains("companyId")              { existing.companyId = dto.companyId }
            if accept.contains("status")                 { existing.status = CatalogOrderStatus(rawValue: dto.status) ?? .draft }
            if accept.contains("title")                  { existing.title = dto.title }
            if accept.contains("supplierName")           { existing.supplierName = dto.supplierName }
            if accept.contains("supplierContact")        { existing.supplierContact = dto.supplierContact }
            if accept.contains("expectedDeliveryDate")   { existing.expectedDeliveryDate = dto.expectedDeliveryDate.flatMap { SupabaseDate.parseDateOnly($0) } }
            if accept.contains("notes")                  { existing.notes = dto.notes }
            if accept.contains("createdById")            { existing.createdById = dto.createdById }
            if accept.contains("sentAt")                 { existing.sentAt = dto.sentAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("fulfilledAt")            { existing.fulfilledAt = dto.fulfilledAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("cancelledAt")            { existing.cancelledAt = dto.cancelledAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt")              { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? Date()
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Catalog Order Items

    /// Pull items for every local order belonging to this company. Server is
    /// authoritative — we replace the children for each order in one pass.
    private func syncCatalogOrderItems(repos: InboundRepositories) async throws {
        let companyId = repos.companyId
        let companyOrders = try modelContext.fetch(FetchDescriptor<CatalogOrder>())
            .filter { $0.companyId == companyId }

        guard !companyOrders.isEmpty else { return }

        var totalMerged = 0
        // One transaction per order keeps memory bounded for tenants with many
        // orders; mirrors InboundProcessor's per-order save granularity.
        for order in companyOrders {
            let dtos = try await repos.order.fetchOrderItems(orderId: order.id)
            let serverIds = Set(dtos.map(\.id))
            let orderId = order.id

            try modelContext.transaction {
                for dto in dtos {
                    let id = dto.id
                    let descriptor = FetchDescriptor<CatalogOrderItem>(predicate: #Predicate { $0.id == id })
                    if let existing = try modelContext.fetch(descriptor).first {
                        existing.orderId = dto.orderId
                        existing.catalogVariantId = dto.catalogVariantId
                        existing.quantityRequested = dto.quantityRequested
                        existing.costPerUnit = dto.costPerUnit
                        existing.notes = dto.notes
                        existing.lastSyncedAt = Date()
                        existing.needsSync = false
                    } else {
                        let model = dto.toModel()
                        model.lastSyncedAt = Date()
                        model.needsSync = false
                        modelContext.insert(model)
                    }
                    totalMerged += 1
                }

                // Remove children the server has deleted. Skip rows with pending
                // local writes — they may be in-flight inserts.
                let localChildren = try modelContext.fetch(FetchDescriptor<CatalogOrderItem>(
                    predicate: #Predicate { $0.orderId == orderId }
                ))
                for child in localChildren where !serverIds.contains(child.id) {
                    if hasPendingOperations(entityType: .catalogOrderItem, entityId: child.id) { continue }
                    modelContext.delete(child)
                }
            }
        }
        print("[DataActor] Merged \(totalMerged) catalog order items across \(companyOrders.count) orders")
    }

    // MARK: - Sync: Company Default Products

    private func syncCompanyDefaultProducts(repos: InboundRepositories) async throws {
        let dtos = try await repos.defaultProduct.fetchAll()
        let serverKeys = Set(dtos.map { "\($0.companyId)::\($0.componentType)" })
        let companyId = repos.companyId

        try modelContext.transaction {
            for dto in dtos {
                try mergeCompanyDefaultProduct(dto: dto)
            }

            // Prune defaults the server no longer reports for this company.
            let local = try modelContext.fetch(FetchDescriptor<CompanyDefaultProduct>())
                .filter { $0.companyId == companyId }
            for row in local {
                let key = "\(row.companyId)::\(row.componentType.rawValue)"
                if !serverKeys.contains(key) {
                    modelContext.delete(row)
                }
            }
        }
        print("[DataActor] Merged \(dtos.count) company default products")
    }

    private func mergeCompanyDefaultProduct(dto: CompanyDefaultProductDTO) throws {
        // Composite key: (companyId, componentType).
        let companyId = dto.companyId
        let componentTypeRaw = dto.componentType
        let descriptor = FetchDescriptor<CompanyDefaultProduct>(
            predicate: #Predicate { $0.companyId == companyId }
        )

        let existing = try modelContext.fetch(descriptor)
            .first(where: { $0.componentType.rawValue == componentTypeRaw })

        if let existing = existing {
            existing.productId = dto.productId
            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? Date()
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Product Options

    private func syncProductOptions(repos: InboundRepositories) async throws {
        let dtos = try await repos.productRichness.fetchOptionsForCompany()
        let serverIds = Set(dtos.map(\.id))
        let companyId = repos.companyId

        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<ProductOption>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    existing.productId = dto.productId
                    existing.name = dto.name
                    existing.kind = ProductOptionKind(rawValue: dto.kind) ?? .select
                    existing.affectsPrice = dto.affectsPrice
                    existing.affectsRecipe = dto.affectsRecipe
                    existing.required = dto.required
                    existing.defaultValue = dto.defaultValue
                    existing.optionDefaultSource = dto.optionDefaultSource
                    existing.sortOrder = dto.sortOrder
                    existing.lastSyncedAt = Date()
                    existing.needsSync = false
                } else {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    modelContext.insert(model)
                }
            }

            let companyProductIds = Set(try modelContext.fetch(FetchDescriptor<Product>())
                .filter { $0.companyId == companyId }
                .map(\.id))
            let allLocal = try modelContext.fetch(FetchDescriptor<ProductOption>())
            for option in allLocal where companyProductIds.contains(option.productId) && !serverIds.contains(option.id) {
                modelContext.delete(option)
            }
        }
        print("[DataActor] Merged \(dtos.count) product options")
    }

    // MARK: - Sync: Product Option Values

    private func syncProductOptionValues(repos: InboundRepositories) async throws {
        let dtos = try await repos.productRichness.fetchOptionValuesForCompany()
        let serverIds = Set(dtos.map(\.id))

        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<ProductOptionValue>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    existing.optionId = dto.optionId
                    existing.value = dto.value
                    existing.sortOrder = dto.sortOrder
                    existing.lastSyncedAt = Date()
                    existing.needsSync = false
                } else {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    modelContext.insert(model)
                }
            }

            let localOptionIds = Set(try modelContext.fetch(FetchDescriptor<ProductOption>()).map(\.id))
            let allLocal = try modelContext.fetch(FetchDescriptor<ProductOptionValue>())
            for value in allLocal where localOptionIds.contains(value.optionId) && !serverIds.contains(value.id) {
                modelContext.delete(value)
            }
        }
        print("[DataActor] Merged \(dtos.count) product option values")
    }

    // MARK: - Sync: Product Pricing Modifiers

    private func syncProductPricingModifiers(repos: InboundRepositories) async throws {
        let dtos = try await repos.productRichness.fetchPricingModifiersForCompany()
        let serverIds = Set(dtos.map(\.id))
        let companyId = repos.companyId

        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<ProductPricingModifier>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    existing.productId = dto.productId
                    existing.optionId = dto.optionId
                    existing.triggerValueId = dto.triggerValueId
                    existing.triggerIntMin = dto.triggerIntMin
                    existing.triggerIntMax = dto.triggerIntMax
                    existing.modifierKind = PricingModifierKind(rawValue: dto.modifierKind) ?? .addPerUnit
                    existing.amount = dto.amount
                    existing.lastSyncedAt = Date()
                    existing.needsSync = false
                } else {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    modelContext.insert(model)
                }
            }

            let companyProductIds = Set(try modelContext.fetch(FetchDescriptor<Product>())
                .filter { $0.companyId == companyId }
                .map(\.id))
            let allLocal = try modelContext.fetch(FetchDescriptor<ProductPricingModifier>())
            for row in allLocal where companyProductIds.contains(row.productId) && !serverIds.contains(row.id) {
                modelContext.delete(row)
            }
        }
        print("[DataActor] Merged \(dtos.count) product pricing modifiers")
    }

    // MARK: - Sync: Product Materials (recipes)

    private func syncProductMaterials(repos: InboundRepositories) async throws {
        let dtos = try await repos.productRichness.fetchMaterialsForCompany()
        let serverIds = Set(dtos.map(\.id))
        let companyId = repos.companyId

        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<ProductMaterial>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    existing.productId = dto.productId
                    existing.catalogVariantId = dto.catalogVariantId
                    existing.catalogItemId = dto.catalogItemId
                    existing.variantSelectorJSON = dto.variantSelector?.rawJSONString
                    existing.quantityPerUnit = dto.quantityPerUnit
                    existing.scaledByOptionId = dto.scaledByOptionId
                    existing.unitId = dto.unitId
                    existing.notes = dto.notes
                    existing.lastSyncedAt = Date()
                    existing.needsSync = false
                } else {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    modelContext.insert(model)
                }
            }

            let companyProductIds = Set(try modelContext.fetch(FetchDescriptor<Product>())
                .filter { $0.companyId == companyId }
                .map(\.id))
            let allLocal = try modelContext.fetch(FetchDescriptor<ProductMaterial>())
            for row in allLocal where companyProductIds.contains(row.productId) && !serverIds.contains(row.id) {
                modelContext.delete(row)
            }
        }
        print("[DataActor] Merged \(dtos.count) product materials")
    }

    // MARK: - Sync: Inventory Units (legacy)

    /// Pulls `inventory_units` rows from Supabase and upserts into the local
    /// SwiftData store. Distinct from CatalogUnit — these back the Inventory
    /// tab and were silently absent from sync prior to bug 2837ddae.
    private func syncInventoryUnits(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.inventory.fetchUnitsForSync(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeInventoryUnit(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) inventory units")
    }

    private func mergeInventoryUnit(dto: InventoryUnitReadDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventoryUnit>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .inventoryUnit,
                entityId: id,
                fields: ["companyId", "display", "isDefault", "sortOrder", "deletedAt"]
            )
            if accept.contains("companyId") { existing.companyId = dto.companyId }
            if accept.contains("display")   { existing.display = dto.display }
            if accept.contains("isDefault") { existing.isDefault = dto.isDefault }
            if accept.contains("sortOrder") { existing.sortOrder = dto.sortOrder }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Inventory Tags (legacy)

    private func syncInventoryTags(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.inventory.fetchTagsForSync(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeInventoryTag(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) inventory tags")
    }

    private func mergeInventoryTag(dto: InventoryTagReadDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventoryTag>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .inventoryTag,
                entityId: id,
                fields: ["companyId", "name", "warningThreshold", "criticalThreshold", "deletedAt"]
            )
            if accept.contains("companyId")         { existing.companyId = dto.companyId }
            if accept.contains("name")              { existing.name = dto.name }
            if accept.contains("warningThreshold")  { existing.warningThreshold = dto.warningThreshold }
            if accept.contains("criticalThreshold") { existing.criticalThreshold = dto.criticalThreshold }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    // MARK: - Sync: Inventory Items (legacy)

    private func syncInventoryItems(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.inventory.fetchItemsForSync(since: since)
        let deletedIds: [String]
        if let sinceDate = since {
            deletedIds = (try? await repos.inventory.fetchDeletedItemIds(since: sinceDate)) ?? []
        } else {
            deletedIds = []
        }

        guard !dtos.isEmpty || !deletedIds.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeInventoryItem(dto: dto)
            }
            for id in deletedIds {
                try tombstoneInventoryItem(id: id)
            }
        }
        print("[DataActor] Merged \(dtos.count) inventory items (tombstoned \(deletedIds.count))")
    }

    private func mergeInventoryItem(dto: InventoryItemReadDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .inventoryItem,
                entityId: id,
                fields: [
                    "companyId", "name", "itemDescription", "quantity", "unitId",
                    "sku", "notes", "imageUrl",
                    "warningThreshold", "criticalThreshold", "deletedAt"
                ]
            )
            if accept.contains("companyId")         { existing.companyId = dto.companyId }
            if accept.contains("name")              { existing.name = dto.name }
            if accept.contains("itemDescription")   { existing.itemDescription = dto.description }
            if accept.contains("quantity")          { existing.quantity = dto.quantity }
            if accept.contains("unitId")            { existing.unitId = dto.unitId }
            if accept.contains("sku")               { existing.sku = dto.sku }
            if accept.contains("notes")             { existing.notes = dto.notes }
            if accept.contains("imageUrl")          { existing.imageUrl = dto.imageUrl }
            if accept.contains("warningThreshold")  { existing.warningThreshold = dto.warningThreshold }
            if accept.contains("criticalThreshold") { existing.criticalThreshold = dto.criticalThreshold }
            if accept.contains("deletedAt") {
                existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
    }

    private func tombstoneInventoryItem(id: String) throws {
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
        }
    }

    // MARK: - Sync: Inventory Item↔Tag Junction (legacy, full reconcile)

    /// Junction table has no timestamps — we full-reconcile on every sync
    /// pass, computing item-scoped diffs by the parent item's tagIds. The
    /// authoritative row set drives both insertions (tag is added to
    /// `tagIds`) and deletions (tag is removed). This mirrors how
    /// `syncCatalogItemTags` handles the catalog_item_tags table.
    private func syncInventoryItemTags(repos: InboundRepositories) async throws {
        let dtos = try await repos.inventory.fetchItemTagsForCompany()

        // Group server rows by item id for O(1) per-item reconcile.
        var serverByItem: [String: Set<String>] = [:]
        for dto in dtos {
            serverByItem[dto.itemId, default: []].insert(dto.tagId)
        }

        try modelContext.transaction {
            let companyId = repos.companyId
            let allItems = try modelContext.fetch(FetchDescriptor<InventoryItem>())
                .filter { $0.companyId == companyId }

            for item in allItems {
                let serverTagIds = serverByItem[item.id] ?? []
                let localTagIds = Set(item.tagIds)
                guard serverTagIds != localTagIds else { continue }
                item.tagIds = Array(serverTagIds)
                item.needsSync = false
                item.lastSyncedAt = Date()
            }
        }
        print("[DataActor] Reconciled inventory item-tag joins (\(dtos.count) rows)")
    }

    // MARK: - Sync: Inventory Snapshots (legacy)

    private func syncInventorySnapshots(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await repos.inventory.fetchSnapshotsForSync(since: since)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                try mergeInventorySnapshot(dto: dto)
            }
        }
        print("[DataActor] Merged \(dtos.count) inventory snapshots")
    }

    private func mergeInventorySnapshot(dto: InventorySnapshotReadDTO) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventorySnapshot>(predicate: #Predicate { $0.id == id })

        if try modelContext.fetch(descriptor).first == nil {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
        // Snapshots are immutable on the server (no updated_at, no edits) — once
        // a local row exists, there's nothing to update. Skip the existing path.
    }

    private func syncInventorySnapshotItems(repos: InboundRepositories) async throws {
        // Find snapshots that exist locally but have no items yet. Snapshot
        // items are fetched on-demand per snapshot id to avoid a full table
        // scan on accounts with hundreds of snapshots.
        let localSnapshots = try modelContext.fetch(FetchDescriptor<InventorySnapshot>())
            .filter { $0.companyId == repos.companyId }
            .map(\.id)
        guard !localSnapshots.isEmpty else { return }

        let existingItemSnapshotIds: Set<String> = Set(
            try modelContext.fetch(FetchDescriptor<InventorySnapshotItem>())
                .map(\.snapshotId)
        )
        let needsItems = localSnapshots.filter { !existingItemSnapshotIds.contains($0) }
        guard !needsItems.isEmpty else { return }

        let dtos = try await repos.inventory.fetchSnapshotItemsForSnapshots(needsItems)
        guard !dtos.isEmpty else { return }

        try modelContext.transaction {
            for dto in dtos {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }
        print("[DataActor] Merged \(dtos.count) inventory snapshot items across \(needsItems.count) snapshots")
    }

    // MARK: - Sync: Task Reminders (bug 4f00c2d7)

    private func syncTaskTypeReminders(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await TaskReminderRepository.shared.fetchTemplates(companyId: repos.companyId, since: since)
        guard !dtos.isEmpty else { return }
        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<TaskTypeReminder>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    dto.apply(to: existing)
                } else {
                    modelContext.insert(dto.makeLocalRow())
                }
            }
        }
        print("[DataActor] Merged \(dtos.count) task reminder templates")
    }

    private func syncTaskReminders(since: Date?, repos: InboundRepositories) async throws {
        let dtos = try await TaskReminderRepository.shared.fetchInstances(companyId: repos.companyId, since: since)
        guard !dtos.isEmpty else { return }
        try modelContext.transaction {
            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<TaskReminder>(predicate: #Predicate { $0.id == id })
                if let existing = try modelContext.fetch(descriptor).first {
                    if existing.needsSync { continue }
                    dto.apply(to: existing)
                } else {
                    modelContext.insert(dto.makeLocalRow())
                }
            }
        }
        print("[DataActor] Merged \(dtos.count) task reminder instances")
    }

    // MARK: - Field-Level Merge Helpers

    /// Returns true if the server value for `fieldName` should overwrite the local
    /// value — false if there is a pending SyncOperation whose `changedFields`
    /// includes this field (local wins until pushed).
    /// Ported from InboundProcessor.shouldAcceptServerValue; `context` param removed
    /// (actor uses its own modelContext).
    private func shouldAcceptServerValue(
        entityType: SyncEntityType,
        entityId: String,
        fieldName: String
    ) -> Bool {
        let entityTypeRaw = entityType.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.entityType == entityTypeRaw &&
                $0.entityId == entityId &&
                $0.status == "pending"
            }
        )

        guard let pendingOps = try? modelContext.fetch(descriptor) else {
            return true
        }

        for op in pendingOps {
            if op.getChangedFields().contains(fieldName) {
                print("[DataActor] Field '\(fieldName)' on \(entityType.rawValue) \(entityId): keeping local (pending operation exists)")
                return false
            }
        }

        return true
    }

    /// Batch variant — returns the subset of `fields` that should accept server
    /// values (i.e., fields without pending SyncOperations). One fetch per call.
    /// Ported from InboundProcessor.acceptableFields.
    private func acceptableFields(
        entityType: SyncEntityType,
        entityId: String,
        fields: [String]
    ) -> Set<String> {
        let entityTypeRaw = entityType.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.entityType == entityTypeRaw &&
                $0.entityId == entityId &&
                $0.status == "pending"
            }
        )

        guard let pendingOps = try? modelContext.fetch(descriptor) else {
            return Set(fields)
        }

        var pendingFields = Set<String>()
        for op in pendingOps {
            pendingFields.formUnion(op.getChangedFields())
        }

        var accepted = Set<String>()
        for field in fields {
            if pendingFields.contains(field) {
                print("[DataActor] Field '\(field)' on \(entityType.rawValue) \(entityId): keeping local (pending operation exists)")
            } else {
                accepted.insert(field)
            }
        }
        return accepted
    }

    /// Returns true if the entity has any pending SyncOperations.
    /// Used by merges to decide whether `needsSync` should be cleared after a server merge.
    /// Ported from InboundProcessor.hasPendingOperations.
    private func hasPendingOperations(entityType: SyncEntityType, entityId: String) -> Bool {
        let typeStr = entityType.rawValue
        let predicate = #Predicate<SyncOperation> { op in
            op.entityType == typeStr &&
            op.entityId == entityId &&
            op.status == "pending"
        }
        let descriptor = FetchDescriptor<SyncOperation>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    /// Returns true if a SyncOperation for this entity had ANY lifecycle event
    /// (created / attempted / completed) within the given window, regardless of
    /// current status. Used by merge-insert origin suppression to catch an
    /// echo or pull-back of our own local writes.
    ///
    /// Must consider all three timestamps so the window correctly covers:
    ///   - Just-recorded op awaiting push: createdAt is recent.
    ///   - Push-in-flight op (echo arriving before HTTP response): lastAttemptedAt recent.
    ///   - Post-push op (actor serialization means the common case): completedAt recent.
    ///   - User offline for longer than `seconds` before push: createdAt may be
    ///     stale but completedAt/lastAttemptedAt are recent once network returns.
    ///
    /// Predicates on @Model fields are constrained, so the fetch filters by
    /// entity and the timestamp check runs in Swift on the small result set.
    private func hasRecentLocalWrite(
        entityType: SyncEntityType,
        entityId: String,
        withinSeconds seconds: TimeInterval
    ) -> Bool {
        let typeStr = entityType.rawValue
        // Canonicalize both sides of the compare — existing SyncOperation rows
        // were recorded before SyncEngine's recordOperation started canonicalizing,
        // so some may still carry UPPERCASE ids. Match against both cases so an
        // echo of an edited legacy task finds its pending op.
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let predicate = #Predicate<SyncOperation> { op in
            op.entityType == typeStr &&
            (op.entityId == idLower || op.entityId == idUpper || op.entityId == entityId)
        }
        let descriptor = FetchDescriptor<SyncOperation>(predicate: predicate)
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

    // MARK: - Helpers

    /// Parse an "HH:mm" string into a Date with today's date and that time.
    /// Ported verbatim from InboundProcessor.parseTime.
    private static func parseTime(_ timeString: String) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute))
    }

    // MARK: - Duplicate Cleanup Helpers

    /// Picks the "freshest" duplicate to keep based on local-edit state and sync
    /// recency. Returns the index of the winner in the input array.
    /// Ported verbatim from DataController.pickFreshestIndex.
    private func pickFreshestIndex<T>(
        _ duplicates: [T],
        needsSync: (T) -> Bool,
        lastSyncedAt: (T) -> Date?
    ) -> Int {
        var winnerIdx = 0
        for i in 1..<duplicates.count {
            let cur = duplicates[i]
            let win = duplicates[winnerIdx]

            // Local edits (needsSync == true) win — never discard unsynced user changes.
            let curNeedsSync = needsSync(cur)
            let winNeedsSync = needsSync(win)
            if curNeedsSync != winNeedsSync {
                if curNeedsSync { winnerIdx = i }
                continue
            }

            // Otherwise prefer the most recently synced row.
            let curSync = lastSyncedAt(cur) ?? .distantPast
            let winSync = lastSyncedAt(win) ?? .distantPast
            if curSync > winSync { winnerIdx = i }
        }
        return winnerIdx
    }

    // MARK: - Cleanup: Users

    /// Deduplicates local User rows. Merges assignedProjects from discarded duplicates
    /// onto the winner and rewires Project.teamMembers references. Ported from
    /// DataController.cleanupDuplicateUsers; `context` → `modelContext`; trailing
    /// save → single transaction wrap.
    func cleanupDuplicateUsers() async {
        do {
            let allUsers = try modelContext.fetch(FetchDescriptor<User>())
            var usersByID: [String: [User]] = [:]
            for user in allUsers {
                usersByID[user.id, default: []].append(user)
            }

            let duplicateIDs = usersByID.filter { $0.value.count > 1 }.keys
            guard !duplicateIDs.isEmpty else { return }

            try modelContext.transaction {
                for id in duplicateIDs {
                    guard let duplicates = usersByID[id], duplicates.count > 1 else { continue }

                    let sortedDuplicates = duplicates.sorted {
                        guard let d1 = $0.lastSyncedAt, let d2 = $1.lastSyncedAt else {
                            return $0.lastSyncedAt != nil
                        }
                        return d1 > d2
                    }

                    let userToKeep = sortedDuplicates[0]
                    var allProjects = Set<Project>(userToKeep.assignedProjects)

                    for i in 1..<sortedDuplicates.count {
                        let dupe = sortedDuplicates[i]
                        for project in dupe.assignedProjects {
                            allProjects.insert(project)
                            if let index = project.teamMembers.firstIndex(where: { $0.id == dupe.id }) {
                                if !project.teamMembers.contains(where: { $0.id == userToKeep.id }) {
                                    project.teamMembers.remove(at: index)
                                    project.teamMembers.append(userToKeep)
                                } else {
                                    project.teamMembers.remove(at: index)
                                }
                            }
                        }
                        modelContext.delete(dupe)
                    }
                    userToKeep.assignedProjects = Array(allProjects)
                }
            }
        } catch {
            print("[DataActor] cleanupDuplicateUsers failed: \(error)")
        }
    }

    // MARK: - Cleanup: Projects

    /// Deduplicates local Project rows. Rewires tasks and team members from discarded
    /// duplicates onto the winner before delete. Ported from
    /// DataController.cleanupDuplicateProjects.
    func cleanupDuplicateProjects() async {
        do {
            let allProjects = try modelContext.fetch(FetchDescriptor<Project>())
            let grouped = Dictionary(grouping: allProjects, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }
            guard !duplicateGroups.isEmpty else { return }

            print("[DataActor] Found \(duplicateGroups.count) project IDs with duplicates")

            try modelContext.transaction {
                var totalDeleted = 0
                for (id, copies) in duplicateGroups {
                    let winnerIdx = pickFreshestIndex(
                        copies,
                        needsSync: { $0.needsSync },
                        lastSyncedAt: { $0.lastSyncedAt }
                    )
                    let keep = copies[winnerIdx]
                    let dupsToDelete = copies.enumerated()
                        .filter { $0.offset != winnerIdx }
                        .map { $0.element }

                    // Snapshot tasks before mutating — inverse cascades would corrupt the
                    // iteration otherwise. Also update task.projectId so DTOs don't leak
                    // the stale id.
                    let orphanedTasks = dupsToDelete.flatMap { Array($0.tasks) }
                    for task in orphanedTasks {
                        task.project = keep
                        task.projectId = keep.id
                    }

                    // Same snapshot pattern for team members.
                    let existingMemberIds = Set(keep.teamMembers.map { $0.id })
                    let orphanedMembers = dupsToDelete.flatMap { Array($0.teamMembers) }
                    for member in orphanedMembers where !existingMemberIds.contains(member.id) {
                        keep.teamMembers.append(member)
                    }

                    for dup in dupsToDelete {
                        modelContext.delete(dup)
                        totalDeleted += 1
                    }
                    print("[DataActor] Deduped project \(id): kept lastSyncedAt=\(String(describing: keep.lastSyncedAt)), deleted \(copies.count - 1)")
                }
                print("[DataActor] Removed \(totalDeleted) duplicate Project rows total")
            }
        } catch {
            print("[DataActor] cleanupDuplicateProjects failed: \(error)")
        }
    }

    // MARK: - Cleanup: Tasks

    /// Deduplicates local ProjectTask rows. No relationship rewiring needed — tasks
    /// are leaves. Ported from DataController.cleanupDuplicateTasks.
    /// Normalize UUID ids to lowercase across the entities that reference each
    /// other by id-string: `ProjectTask.id`, `User.id`, the
    /// `teamMemberIdsString` CSV columns on `Project` and `ProjectTask`, and
    /// `SyncOperation.entityId`. Postgres canonicalizes uuid storage to
    /// lowercase, but Swift's `UUID().uuidString` returns UPPERCASE — any
    /// entity with an UPPERCASE id stored locally silently fails to match the
    /// lowercase DTO (string compare misses). That produces duplicates on
    /// merge AND failed lookups in `linkAllRelationships` (a lowercase id in
    /// `teamMemberIdsString` can't find an UPPERCASE-id User, so task avatars
    /// resolve empty). Must run BEFORE `cleanupDuplicateTasks` and
    /// `rewireRelationships` so both see consistent casing.
    /// Idempotent — safe to run on every launch.
    func normalizeTaskIdsToLowercase() async {
        do {
            try modelContext.transaction {
                let allTasks = try modelContext.fetch(FetchDescriptor<ProjectTask>())
                var taskIdCount = 0
                var taskMemberStringCount = 0
                for task in allTasks {
                    let lowerId = task.id.lowercased()
                    if task.id != lowerId { task.id = lowerId; taskIdCount += 1 }

                    let original = task.teamMemberIdsString
                    if !original.isEmpty {
                        let normalized = original
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                            .filter { !$0.isEmpty }
                            .joined(separator: ",")
                        if normalized != original {
                            task.teamMemberIdsString = normalized
                            taskMemberStringCount += 1
                        }
                    }
                }

                let allProjects = try modelContext.fetch(FetchDescriptor<Project>())
                var projectMemberStringCount = 0
                for project in allProjects {
                    let original = project.teamMemberIdsString
                    guard !original.isEmpty else { continue }
                    let normalized = original
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }
                        .joined(separator: ",")
                    if normalized != original {
                        project.teamMemberIdsString = normalized
                        projectMemberStringCount += 1
                    }
                }

                let allUsers = try modelContext.fetch(FetchDescriptor<User>())
                var userIdCount = 0
                for user in allUsers {
                    let lower = user.id.lowercased()
                    if user.id != lower { user.id = lower; userIdCount += 1 }
                }

                let taskEntityRaw = SyncEntityType.projectTask.rawValue
                let taskOpDescriptor = FetchDescriptor<SyncOperation>(
                    predicate: #Predicate<SyncOperation> { $0.entityType == taskEntityRaw }
                )
                let taskOps = try modelContext.fetch(taskOpDescriptor)
                var taskOpCount = 0
                for op in taskOps {
                    let lower = op.entityId.lowercased()
                    if op.entityId != lower { op.entityId = lower; taskOpCount += 1 }
                }

                let userEntityRaw = SyncEntityType.user.rawValue
                let userOpDescriptor = FetchDescriptor<SyncOperation>(
                    predicate: #Predicate<SyncOperation> { $0.entityType == userEntityRaw }
                )
                let userOps = try modelContext.fetch(userOpDescriptor)
                var userOpCount = 0
                for op in userOps {
                    let lower = op.entityId.lowercased()
                    if op.entityId != lower { op.entityId = lower; userOpCount += 1 }
                }

                let total = taskIdCount + taskMemberStringCount + projectMemberStringCount + userIdCount + taskOpCount + userOpCount
                if total > 0 {
                    print("[DataActor] Normalized to lowercase: \(taskIdCount) ProjectTask.id, \(taskMemberStringCount) ProjectTask.teamMemberIdsString, \(projectMemberStringCount) Project.teamMemberIdsString, \(userIdCount) User.id, \(taskOpCount) projectTask SyncOps, \(userOpCount) user SyncOps (total \(total))")
                }
            }
        } catch {
            print("[DataActor] normalizeTaskIdsToLowercase failed: \(error)")
        }
    }

    func cleanupDuplicateTasks() async {
        do {
            let allTasks = try modelContext.fetch(FetchDescriptor<ProjectTask>())
            let grouped = Dictionary(grouping: allTasks, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }
            guard !duplicateGroups.isEmpty else { return }

            print("[DataActor] Found \(duplicateGroups.count) task IDs with duplicates")

            try modelContext.transaction {
                var totalDeleted = 0
                for (id, copies) in duplicateGroups {
                    let winnerIdx = pickFreshestIndex(
                        copies,
                        needsSync: { $0.needsSync },
                        lastSyncedAt: { $0.lastSyncedAt }
                    )
                    let dupsToDelete = copies.enumerated()
                        .filter { $0.offset != winnerIdx }
                        .map { $0.element }
                    for dup in dupsToDelete {
                        modelContext.delete(dup)
                        totalDeleted += 1
                    }
                    print("[DataActor] Deduped task \(id): deleted \(copies.count - 1)")
                }
                print("[DataActor] Removed \(totalDeleted) duplicate ProjectTask rows total")
            }
        } catch {
            print("[DataActor] cleanupDuplicateTasks failed: \(error)")
        }
    }

    // MARK: - Cleanup: Clients

    /// Deduplicates local Client rows. Rewires Project.client references before
    /// delete. Ported from DataController.cleanupDuplicateClients.
    func cleanupDuplicateClients() async {
        do {
            let allClients = try modelContext.fetch(FetchDescriptor<Client>())
            let grouped = Dictionary(grouping: allClients, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }
            guard !duplicateGroups.isEmpty else { return }

            print("[DataActor] Found \(duplicateGroups.count) client IDs with duplicates")

            try modelContext.transaction {
                var totalDeleted = 0
                for (id, copies) in duplicateGroups {
                    let winnerIdx = pickFreshestIndex(
                        copies,
                        needsSync: { $0.needsSync },
                        lastSyncedAt: { $0.lastSyncedAt }
                    )
                    let keep = copies[winnerIdx]
                    let dupsToDelete = copies.enumerated()
                        .filter { $0.offset != winnerIdx }
                        .map { $0.element }

                    // Snapshot referenced projects before mutating — setting
                    // project.client triggers the inverse on dup.projects.
                    let orphanedProjects = dupsToDelete.flatMap { Array($0.projects) }
                    for project in orphanedProjects {
                        project.client = keep
                        project.clientId = keep.id
                    }

                    for dup in dupsToDelete {
                        modelContext.delete(dup)
                        totalDeleted += 1
                    }
                    print("[DataActor] Deduped client \(id): deleted \(copies.count - 1)")
                }
                print("[DataActor] Removed \(totalDeleted) duplicate Client rows total")
            }
        } catch {
            print("[DataActor] cleanupDuplicateClients failed: \(error)")
        }
    }

    // MARK: - Cleanup: TaskTypes

    /// Deduplicates local TaskType rows. Rewires ProjectTask.taskType references
    /// before delete. Ported from DataController.cleanupDuplicateTaskTypes.
    func cleanupDuplicateTaskTypes() async {
        do {
            let allTaskTypes = try modelContext.fetch(FetchDescriptor<TaskType>())
            let grouped = Dictionary(grouping: allTaskTypes, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }
            guard !duplicateGroups.isEmpty else { return }

            print("[DataActor] Found \(duplicateGroups.count) task type IDs with duplicates")

            try modelContext.transaction {
                var totalDeleted = 0
                for (id, copies) in duplicateGroups {
                    let winnerIdx = pickFreshestIndex(
                        copies,
                        needsSync: { $0.needsSync },
                        lastSyncedAt: { $0.lastSyncedAt }
                    )
                    let keep = copies[winnerIdx]
                    let dupsToDelete = copies.enumerated()
                        .filter { $0.offset != winnerIdx }
                        .map { $0.element }

                    // Snapshot tasks before mutating — TaskType.tasks inverse would
                    // cascade through the iteration otherwise.
                    let orphanedTasks = dupsToDelete.flatMap { Array($0.tasks) }
                    for task in orphanedTasks {
                        task.taskType = keep
                        task.taskTypeId = keep.id
                    }

                    for dup in dupsToDelete {
                        modelContext.delete(dup)
                        totalDeleted += 1
                    }
                    print("[DataActor] Deduped task type \(id) (\(keep.display)): deleted \(copies.count - 1)")
                }
                print("[DataActor] Removed \(totalDeleted) duplicate TaskType rows total")
            }
        } catch {
            print("[DataActor] cleanupDuplicateTaskTypes failed: \(error)")
        }
    }

    // MARK: - Realtime Merge Entry Point

    /// Apply a single realtime upsert to SwiftData inside a transaction.
    /// Scope guards are enforced on the MainActor side (RealtimeProcessor) before
    /// dispatch — this method trusts the payload.
    ///
    /// Non-throwing by design: realtime events are fire-and-forget from the caller's
    /// perspective. A failed merge is logged and skipped; the next delta sync will
    /// re-pull the affected row.
    func handleRealtimeUpdate(_ update: RealtimeUpdate) async {
        do {
            try modelContext.transaction {
                switch update {
                case .project(let dto):                 try mergeProject(dto: dto)
                case .task(let dto):                    try mergeTask(dto: dto)
                case .user(let dto):                    try mergeUser(dto: dto)
                case .client(let dto):                  try mergeClient(dto: dto)
                case .company(let dto):                 try mergeCompany(dto: dto)
                case .taskType(let dto):                try mergeTaskType(dto: dto)
                case .subClient(let dto):               try mergeSubClient(dto: dto)
                case .projectNote(let dto):             try mergeProjectNote(dto: dto)
                case .photoAnnotation(let dto):         try mergePhotoAnnotation(dto: dto)
                case .deckDesign(let dto):              try mergeDeckDesign(dto: dto)
                case .catalogCategory(let dto):         try mergeCatalogCategory(dto: dto)
                case .catalogUnit(let dto):             try mergeCatalogUnit(dto: dto)
                case .catalogTag(let dto):              try mergeCatalogTag(dto: dto)
                case .catalogItem(let dto):             try mergeCatalogItem(dto: dto)
                case .catalogVariant(let dto):          try mergeCatalogVariant(dto: dto)
                case .catalogSnapshot(let dto):         try mergeCatalogSnapshot(dto: dto)
                case .catalogOrder(let dto):            try mergeCatalogOrder(dto: dto)
                case .companyDefaultProduct(let dto):   try mergeCompanyDefaultProduct(dto: dto)
                }
            }
        } catch {
            print("[DataActor] Realtime merge failed: \(error)")
        }
    }

    // MARK: - Realtime Soft Delete Entry Point

    /// Apply a realtime soft-delete by table name. Sets deletedAt on the matching row
    /// inside a transaction. Non-throwing — a missing row or transaction failure is
    /// logged; the next delta sync re-reconciles.
    func softDeleteFromRealtime(table: String, id: String) async {
        do {
            try modelContext.transaction {
                switch table {
                case "projects":
                    if let m = try modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "project_tasks":
                    if let m = try modelContext.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "users":
                    if let m = try modelContext.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "clients":
                    if let m = try modelContext.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "companies":
                    if let m = try modelContext.fetch(FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "task_types":
                    if let m = try modelContext.fetch(FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "sub_clients":
                    if let m = try modelContext.fetch(FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "project_notes":
                    if let m = try modelContext.fetch(FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "project_photo_annotations":
                    if let m = try modelContext.fetch(FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "deck_designs":
                    if let m = try modelContext.fetch(FetchDescriptor<DeckDesign>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "catalog_categories":
                    if let m = try modelContext.fetch(FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "catalog_units":
                    if let m = try modelContext.fetch(FetchDescriptor<CatalogUnit>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "catalog_tags":
                    if let m = try modelContext.fetch(FetchDescriptor<CatalogTag>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "catalog_items":
                    if let m = try modelContext.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "catalog_variants":
                    if let m = try modelContext.fetch(FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                case "catalog_orders":
                    if let m = try modelContext.fetch(FetchDescriptor<CatalogOrder>(predicate: #Predicate { $0.id == id })).first {
                        m.deletedAt = Date()
                    }
                // catalog_snapshots are append-only — no deletes expected.
                // company_default_products has a composite key (companyId,
                // componentType) and no surrogate id — DELETE events here can't
                // be located by id, so they're left to the next pullDelta to
                // reconcile via syncCompanyDefaultProducts' prune step.
                default:
                    break
                }
            }
        } catch {
            print("[DataActor] Realtime soft-delete failed for \(table) \(id): \(error)")
        }
    }

    // MARK: - Outbound Push

    /// Maximum retry count before an operation is marked as permanently failed.
    /// Mirrors OutboundProcessor.maxRetries.
    private static let maxOutboundRetries = 20

    /// Fetches all pending SyncOperations, coalesces them, and pushes each to Supabase.
    /// Operations in backoff or with unmet dependencies are skipped.
    ///
    /// Connectivity guard is enforced on MainActor by SyncEngine BEFORE this is called
    /// (per PM guidance). This method assumes connectivity is OK.
    ///
    /// Ported from OutboundProcessor.processPendingOperations. Differences:
    ///   - no context/connectivity parameters (actor owns its context; connectivity
    ///     guarded by caller)
    ///   - coalesceOperations runs inside transaction { } so its op.status mutations
    ///     on superseded entries persist atomically
    ///   - executeOperation mutations persist via per-state transactions inside that
    ///     method (no single trailing context.save)
    func processPendingOperations() async {
        // 1. Fetch pending operations sorted by priority ASC, createdAt ASC.
        let pending: [SyncOperation]
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> { $0.status == "pending" },
                sortBy: [
                    SortDescriptor(\.priority, order: .forward),
                    SortDescriptor(\.createdAt, order: .forward)
                ]
            )
            pending = try modelContext.fetch(descriptor)
        } catch {
            print("[DataActor] Failed to fetch pending operations: \(error)")
            return
        }

        guard !pending.isEmpty else {
            print("[DataActor] No pending operations")
            return
        }

        print("[DataActor] Found \(pending.count) pending operation(s)")

        // 2. Filter out operations in backoff or with unmet dependencies.
        let now = Date()
        let eligible = pending.filter { op in
            if op.retryCount > 0, let lastAttempt = op.lastAttemptedAt {
                let earliestRetry = lastAttempt.addingTimeInterval(op.backoffDelay)
                if now < earliestRetry {
                    print("[DataActor] Skipping \(op.entityType) \(op.entityId) — in backoff (retry \(op.retryCount), delay \(op.backoffDelay)s)")
                    return false
                }
            }

            if let depId = op.dependsOnId, !depId.isEmpty {
                let depCompletedInBatch = pending.contains { $0.id.uuidString == depId && $0.status == "completed" }
                if !depCompletedInBatch {
                    let isDepCompleted = isDependencyCompleted(depId)
                    if !isDepCompleted {
                        print("[DataActor] Skipping \(op.entityType) \(op.entityId) — dependency \(depId) not completed")
                        return false
                    }
                }
            }

            return true
        }

        // 3. Coalesce — mutates superseded ops' status; wrap in transaction so those
        //    mutations persist atomically before we begin executing survivors.
        var coalesced: [SyncOperation] = []
        do {
            try modelContext.transaction {
                coalesced = coalesceOperations(eligible)
            }
        } catch {
            print("[DataActor] Failed to commit coalescing state: \(error)")
            return
        }
        print("[DataActor] Coalesced \(eligible.count) → \(coalesced.count) operation(s)")

        // 4. Execute each survivor. Each call manages its own state transitions via
        //    per-state transactions (inProgress → completed/failed/pending).
        for op in coalesced {
            do {
                try await executeOperation(op)
            } catch {
                let classified = classifySyncError(error)
                print("[DataActor] Operation failed for \(op.entityType) \(op.entityId): \(classified.localizedDescription)")
                // Error handling (state mutation) already done inside executeOperation.
            }
        }
    }

    // MARK: - Dependency Check

    /// Checks whether a dependency operation (by UUID string) has status "completed"
    /// in the store. Ported from OutboundProcessor.isDependencyCompleted; context
    /// parameter removed.
    private func isDependencyCompleted(_ dependsOnId: String) -> Bool {
        guard let depUUID = UUID(uuidString: dependsOnId) else { return false }
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate<SyncOperation> { op in
                    op.id == depUUID && op.status == "completed"
                }
            )
            let results = try modelContext.fetch(descriptor)
            return !results.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Per-Operation Execution

    /// Executes a single SyncOperation against Supabase. Transitions status
    /// inProgress → completed/failed/pending; each transition is wrapped in
    /// its own transaction since Swift async/await precludes a single transaction
    /// spanning the network call.
    ///
    /// Ported from OutboundProcessor.executeOperation. Context parameter removed;
    /// state mutations now wrapped in `modelContext.transaction { }` blocks.
    private func executeOperation(_ operation: SyncOperation) async throws {
        print("[DataActor] Pushing \(operation.entityType) \(operation.entityId)...")
        if operation.entityType == SyncEntityType.projectTask.rawValue {
            print("[DUPE_TRACE] ACTOR.outbound.inProgress id=\(operation.entityId) op=\(operation.operationType)")
        }

        try? modelContext.transaction {
            operation.status = "inProgress"
            operation.lastAttemptedAt = Date()
        }

        do {
            guard let payloadDict = decodePayload(operation.payload) else {
                throw SyncError.decodingFailed(detail: "Could not decode payload for \(operation.entityType) \(operation.entityId)")
            }

            try await routeToRepository(
                entityType: operation.entityType,
                entityId: operation.entityId,
                operationType: operation.operationType,
                payload: payloadDict
            )

            try? modelContext.transaction {
                operation.status = "completed"
                operation.completedAt = Date()
            }
            print("[DataActor] Completed \(operation.entityType) \(operation.entityId)")
            if operation.entityType == SyncEntityType.projectTask.rawValue {
                print("[DUPE_TRACE] ACTOR.outbound.completed id=\(operation.entityId) op=\(operation.operationType)")
            }

        } catch {
            let classified = classifySyncError(error)

            // Idempotency: if this is a `create` retry and the server says the row
            // already exists (PK unique-constraint violation), the first push
            // succeeded server-side but the response was lost — network blip,
            // app killed mid-flight, etc. Mark the op completed instead of
            // retrying forever against a server that already has the row.
            // See `errorIndicatesPrimaryKeyViolation` for the detection contract.
            if operation.operationType == "create",
               errorIndicatesPrimaryKeyViolation(error) {
                try? modelContext.transaction {
                    operation.status = "completed"
                    operation.completedAt = Date()
                    operation.lastError = nil
                }
                print("[DataActor] create \(operation.entityType) \(operation.entityId) — server already has row (PK conflict on retry); marking completed")
                if operation.entityType == SyncEntityType.projectTask.rawValue {
                    print("[DUPE_TRACE] ACTOR.outbound.completed.pkConflict id=\(operation.entityId) op=\(operation.operationType)")
                }
                return
            }

            if case .authExpired = classified {
                try? modelContext.transaction {
                    operation.lastError = classified.localizedDescription
                    operation.status = "failed"
                }
                print("[DataActor] Auth expired — stopping sync for \(operation.entityType) \(operation.entityId)")

                // AnalyticsService is @MainActor — hop for the track call.
                let retryCount = operation.retryCount
                let entityType = operation.entityType
                let operationType = operation.operationType
                await MainActor.run {
                    AnalyticsService.shared.track(
                        eventType: .error,
                        eventName: "sync_failed",
                        properties: [
                            "error_type": "auth_expired",
                            "retry_count": retryCount,
                            "entity_type": entityType,
                            "operation_type": operationType
                        ]
                    )
                    NotificationCenter.default.post(name: .syncAuthExpired, object: nil)
                }
                throw error
            }

            try? modelContext.transaction {
                operation.lastError = classified.localizedDescription
                operation.retryCount += 1
                if operation.retryCount >= Self.maxOutboundRetries {
                    operation.status = "failed"
                } else {
                    operation.status = "pending"
                }
            }

            if operation.retryCount >= Self.maxOutboundRetries {
                print("[DataActor] Permanently failed \(operation.entityType) \(operation.entityId) after \(operation.retryCount) retries")

                // AnalyticsService is @MainActor — hop for the track call.
                let retryCount = operation.retryCount
                let entityType = operation.entityType
                let operationType = operation.operationType
                let errorDescription = classified.localizedDescription
                await MainActor.run {
                    AnalyticsService.shared.track(
                        eventType: .error,
                        eventName: "sync_failed",
                        properties: [
                            "error_type": errorDescription,
                            "retry_count": retryCount,
                            "entity_type": entityType,
                            "operation_type": operationType
                        ]
                    )
                }
            } else {
                print("[DataActor] Retry \(operation.retryCount)/\(Self.maxOutboundRetries) for \(operation.entityType) \(operation.entityId): \(classified.localizedDescription)")
            }

            throw error
        }
    }

    // MARK: - Repository Routing

    /// Routes an operation to the correct Supabase repository based on entityType
    /// and operationType. Ported verbatim from OutboundProcessor.routeToRepository —
    /// no ModelContext usage, pure async Supabase calls.
    private func routeToRepository(
        entityType: String,
        entityId: String,
        operationType: String,
        payload: [String: Any]
    ) async throws {
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""

        guard let syncEntityType = SyncEntityType(rawValue: entityType) else {
            print("[DataActor] Unknown entity type: \(entityType) — using generic table push")
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
        case .deckDesign:
            try await handleDeckDesign(entityId: entityId, operationType: operationType, payload: payload, companyId: companyId)
        case .wizardState:
            try await handleWizardState(entityId: entityId, operationType: operationType, payload: payload)
        default:
            // TODO(catalog-outbound): catalog/product entity types fall through
            // to genericTablePush. The catalog sheets write directly via their
            // repositories (immediate, online-only path), so the queue is
            // exercised only for offline-buffered ops where generic upsert is
            // sufficient. Promote to dedicated handlers when we need
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
        let sanitizedPayload = payload.filter { Self.validProjectColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseProjectDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[DataActor] Unknown operation type '\(operationType)' for project")
        }
    }

    private func handleProjectTask(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = TaskRepository(companyId: companyId)
        let sanitizedPayload = payload.filter { Self.validProjectTaskColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseProjectTaskDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[DataActor] Unknown operation type '\(operationType)' for projectTask")
        }
    }

    private func handleUser(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = UserRepository(companyId: companyId)
        let sanitizedPayload = payload.filter { Self.validUserColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseUserDTO.self, from: jsonData)
            try await repo.upsert(dto)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(userId: entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[DataActor] Unknown operation type '\(operationType)' for user")
        }
    }

    private func handleClient(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = ClientRepository(companyId: companyId)
        let sanitizedPayload = payload.filter { Self.validClientColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let dto = try JSONDecoder().decode(SupabaseClientDTO.self, from: jsonData)
            _ = try await repo.create(dto)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await genericUpdateFields(table: "clients", entityId: entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[DataActor] Unknown operation type '\(operationType)' for client")
        }
    }

    private func handleCompany(entityId: String, operationType: String, payload: [String: Any], companyId: String) async throws {
        let repo = CompanyRepository()
        let sanitizedPayload = payload.filter { Self.validCompanyColumns.contains($0.key) }

        switch operationType {
        case "create":
            let jsonData = try JSONSerialization.data(withJSONObject: sanitizedPayload)
            let companyPayload = try JSONDecoder().decode(NewCompanyPayload.self, from: jsonData)
            _ = try await repo.insert(companyPayload)

        case "update":
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(companyId: entityId, fields: fields)

        case "delete":
            let fields: [String: AnyJSON] = [
                "deleted_at": .string(ISO8601DateFormatter().string(from: Date())),
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            try await genericUpdateFields(table: "companies", entityId: entityId, fields: fields)

        default:
            print("[DataActor] Unknown operation type '\(operationType)' for company")
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
            print("[DataActor] Unknown operation type '\(operationType)' for taskType")
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
            let fields = payloadToAnyJSON(sanitizedPayload)
            try await repo.updateFields(entityId, fields: fields)

        case "delete":
            try await repo.softDelete(entityId)

        default:
            print("[DataActor] Unknown operation type '\(operationType)' for deckDesign")
        }
    }

    /// Pushes wizard_states rows. User-scoped; no companyId.
    /// Hard delete path — wizard_states has no deleted_at column per verified schema.
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
            print("[DataActor] Unknown operation type '\(operationType)' for wizardState")
        }
    }

    // MARK: - Generic Table Operations

    /// Generic update for tables without a dedicated updateFields method.
    /// Ported verbatim from OutboundProcessor.genericUpdateFields.
    private func genericUpdateFields(table: String, entityId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        try await SupabaseService.shared.client
            .from(table)
            .update(payload)
            .eq("id", value: entityId)
            .execute()
    }

    /// Generic fallback for entity types without a dedicated handler.
    /// Ported verbatim from OutboundProcessor.genericTablePush.
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
            print("[DataActor] Unknown operation type '\(operationType)' for generic table \(table)")
        }
    }

    // MARK: - Coalescing

    /// Groups operations by (entityType, entityId) and merges redundant ops:
    ///   - "create" + subsequent "update"s → merge changedFields into the create,
    ///     keep latest payload
    ///   - "delete" discards all preceding creates/updates for the same entity
    ///   - Multiple "update"s → merge changedFields, keep latest payload, produce
    ///     one operation
    ///
    /// Superseded ops are mutated to status="completed"; callers must wrap in
    /// `modelContext.transaction { }` so those mutations persist.
    ///
    /// Ported verbatim from OutboundProcessor.coalesceOperations.
    private func coalesceOperations(_ operations: [SyncOperation]) -> [SyncOperation] {
        var groups: [String: [SyncOperation]] = [:]
        for op in operations {
            let key = "\(op.entityType)::\(op.entityId)"
            groups[key, default: []].append(op)
        }

        var result: [SyncOperation] = []

        for (_, ops) in groups {
            guard !ops.isEmpty else { continue }

            if ops.count == 1 {
                result.append(ops[0])
                continue
            }

            // Delete wins over everything.
            if let deleteOp = ops.last(where: { $0.operationType == "delete" }) {
                for op in ops where op.id != deleteOp.id {
                    op.status = "completed"
                    op.completedAt = Date()
                }
                result.append(deleteOp)
                continue
            }

            // Create present — merge subsequent updates in.
            if let createOp = ops.first(where: { $0.operationType == "create" }) {
                var allChangedFields = Set(createOp.getChangedFields())
                var latestPayload = createOp.payload

                for op in ops where op.id != createOp.id {
                    let fields = op.getChangedFields()
                    allChangedFields.formUnion(fields)
                    latestPayload = op.payload
                    op.status = "completed"
                    op.completedAt = Date()
                }

                if let mergedPayload = mergePayloads(base: createOp.payload, overlay: latestPayload) {
                    createOp.payload = mergedPayload
                }
                createOp.changedFields = Array(allChangedFields).joined(separator: ",")
                result.append(createOp)
                continue
            }

            // All updates — merge into latest.
            var allChangedFields = Set<String>()
            for op in ops {
                allChangedFields.formUnion(op.getChangedFields())
            }
            let survivor = ops.last!
            survivor.changedFields = Array(allChangedFields).joined(separator: ",")

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

        return result.sorted { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.createdAt < b.createdAt
        }
    }

    // MARK: - Payload Helpers (pure, ported verbatim)

    private func decodePayload(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func encodePayload(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }

    private func mergePayloads(base: Data, overlay: Data) -> Data? {
        guard var baseDict = decodePayload(base) else { return overlay }
        guard let overlayDict = decodePayload(overlay) else { return base }
        for (key, value) in overlayDict {
            baseDict[key] = value
        }
        return encodePayload(baseDict)
    }

    private func payloadToAnyJSON(_ payload: [String: Any]) -> [String: AnyJSON] {
        var result: [String: AnyJSON] = [:]
        for (key, value) in payload {
            result[key] = convertToAnyJSON(value)
        }
        return result
    }

    private func convertToAnyJSON(_ value: Any) -> AnyJSON {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .integer(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { convertToAnyJSON($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { convertToAnyJSON($0) })
        case is NSNull:
            return .null
        default:
            return .string("\(value)")
        }
    }

    // MARK: - Valid Supabase Column Sets

    /// Used to filter payloads before push; strips local-only SwiftData properties
    /// (e.g. needs_sync, task_index) that would cause "could not find column" errors
    /// on PostgREST. Ported verbatim from OutboundProcessor.validXxxColumns.
    private static let validProjectColumns: Set<String> = [
        "id", "bubble_id", "company_id", "client_id", "opportunity_id",
        "title", "status", "address", "latitude", "longitude",
        "start_date", "end_date", "duration", "notes", "description",
        "all_day", "project_images", "completed_at",
        "deleted_at", "created_at", "updated_at"
    ]

    private static let validProjectTaskColumns: Set<String> = [
        "id", "bubble_id", "company_id", "project_id", "task_type_id",
        "custom_title", "task_notes", "status", "task_color", "display_order",
        "team_member_ids", "source_line_item_id", "source_estimate_id",
        "start_date", "end_date", "duration", "dependency_overrides",
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

    private static let validDeckDesignColumns: Set<String> = [
        "id", "company_id", "project_id", "title", "drawing_data",
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

    // MARK: - Relationship Linking

    /// After all entities are pulled, walk the graph and wire FK string columns
    /// into SwiftData @Relationship properties. Runs inside a single transaction
    /// so partial linking never reaches the store.
    ///
    /// Non-throwing by design (matches InboundProcessor.linkAllRelationships) — a
    /// failed fetch or transaction is logged and the sync continues. The caller
    /// does NOT observe the failure; relationships will re-link on next sync.
    ///
    /// Ported from InboundProcessor.linkAllRelationships. All `context` references
    /// become `self.modelContext`; manual `try context.save()` is replaced by the
    /// surrounding `modelContext.transaction { }` block.
    ///
    /// Public wrapper so callers outside the sync flow can trigger a rewire —
    /// specifically after `cleanupDuplicateTasks` deletes a duplicate, since
    /// `pickFreshestIndex` may keep the copy whose `teamMembers: [User]`
    /// relationship was never wired (the actor-inserted echo copy). The stored
    /// `teamMemberIdsString` is canonical; `linkAllRelationships` rebuilds the
    /// `[User]` array from it so the UI shows avatars without waiting for the
    /// next sync.
    func rewireRelationships() async {
        linkAllRelationships()
    }

    private func linkAllRelationships() {
        print("[DataActor] Linking all relationships...")

        do {
            try modelContext.transaction {
                let projects = try modelContext.fetch(FetchDescriptor<Project>())
                let tasks = try modelContext.fetch(FetchDescriptor<ProjectTask>())
                let clients = try modelContext.fetch(FetchDescriptor<Client>())
                let taskTypes = try modelContext.fetch(FetchDescriptor<TaskType>())
                let users = try modelContext.fetch(FetchDescriptor<User>())

                // Build id-lookup dictionaries — last-wins to safely handle duplicates.
                var clientById: [String: Client] = [:]
                for c in clients { clientById[c.id] = c }
                var taskTypeById: [String: TaskType] = [:]
                for t in taskTypes { taskTypeById[t.id] = t }
                var userById: [String: User] = [:]
                for u in users { userById[u.id] = u }
                var projectById: [String: Project] = [:]
                for p in projects { projectById[p.id] = p }

                // Link projects → client and team members
                for project in projects {
                    if let clientId = project.clientId, let client = clientById[clientId] {
                        if project.client?.id != clientId {
                            project.client = client
                        }
                    }
                    let memberIds = project.getTeamMemberIds()
                    let members = memberIds.compactMap { userById[$0] }
                    if Set(project.teamMembers.map(\.id)) != Set(members.map(\.id)) {
                        project.teamMembers = members
                    }
                }

                // Build a case-insensitive user lookup as a fallback — some User
                // records may have been persisted with UPPERCASE ids from legacy
                // paths even though Supabase canonicalizes to lowercase. A
                // straight dictionary lookup misses those, leaving task avatars
                // blank even when the member string is correct.
                var userByIdCaseInsensitive: [String: User] = [:]
                for u in users { userByIdCaseInsensitive[u.id.lowercased()] = u }

                // Link tasks → project, task type, team members
                for task in tasks {
                    if let project = projectById[task.projectId] {
                        if task.project?.id != project.id {
                            task.project = project
                        }
                    }
                    if let taskType = taskTypeById[task.taskTypeId] {
                        if task.taskType?.id != taskType.id {
                            task.taskType = taskType
                        }
                    }
                    let memberIds = task.getTeamMemberIds()
                    // Try exact match first, then case-insensitive fallback.
                    let members = memberIds.compactMap { id -> User? in
                        userById[id] ?? userByIdCaseInsensitive[id.lowercased()]
                    }

                    // Diagnostic: log when the member string can't be fully
                    // resolved so we can distinguish "users not in store" from
                    // "users in store but id case mismatch" from "partial
                    // miss." Remove once this class of bug is confirmed dead.
                    if !memberIds.isEmpty && members.count != memberIds.count {
                        let missing = memberIds.filter { id in
                            userById[id] == nil && userByIdCaseInsensitive[id.lowercased()] == nil
                        }
                        let totalUsers = userById.count
                        let sampleIds = Array(userById.keys.prefix(3))
                        print("[DataActor] ⚠️ task \(task.id): resolved \(members.count)/\(memberIds.count) member ids. missing=\(missing) storeUserCount=\(totalUsers) sampleStoreIds=\(sampleIds)")
                    }

                    if Set(task.teamMembers.map(\.id)) != Set(members.map(\.id)) {
                        task.teamMembers = members
                    }
                }
            }
            // Catalog models keep relationships as id-typed scalars + first-class
            // junction entities (CatalogItemTag, CatalogVariantOptionValue), so
            // there's no SwiftData @Relationship to wire up after a sync.
            // Mirrors InboundProcessor.linkAllRelationships's catalog no-op.
            print("[DataActor] Catalog data has no post-merge linking pass (junctions are first-class)")

            // Legacy InventoryItem keeps a SwiftData @Relationship to its
            // InventoryUnit and InventoryTags (used by InventoryView for tag
            // chips + unit display). The scalar `unitId` / `tagIds` are the
            // server-authoritative state — wire the @Relationships up after
            // every sync so the queries don't see stale references.
            try modelContext.transaction {
                let inventoryItems = try modelContext.fetch(FetchDescriptor<InventoryItem>())
                let inventoryUnits = try modelContext.fetch(FetchDescriptor<InventoryUnit>())
                let inventoryTags = try modelContext.fetch(FetchDescriptor<InventoryTag>())

                var unitById: [String: InventoryUnit] = [:]
                for u in inventoryUnits { unitById[u.id] = u }
                var tagById: [String: InventoryTag] = [:]
                for t in inventoryTags { tagById[t.id] = t }

                for item in inventoryItems {
                    if let unitId = item.unitId, let unit = unitById[unitId] {
                        if item.unit?.id != unitId {
                            item.unit = unit
                        }
                    } else if item.unit != nil && item.unitId == nil {
                        item.unit = nil
                    }

                    let resolvedTags = item.tagIds.compactMap { tagById[$0] }
                    if Set(item.tags.map(\.id)) != Set(resolvedTags.map(\.id)) {
                        item.tags = resolvedTags
                    }
                }
            }
            print("[DataActor] Linked inventory items → units + tags")
            print("[DataActor] Relationships linked")
        } catch {
            print("[DataActor] Relationship linking failed: \(error) — skipping")
        }
    }
}

// MARK: - Realtime Update Dispatch

/// Payload for a single realtime upsert routed from RealtimeProcessor to DataActor.
/// Scope filtering has already been applied on the MainActor side before the update
/// crosses the actor boundary — actor methods never need to consult PermissionStore.
enum RealtimeUpdate: Sendable {
    case project(SupabaseProjectDTO)
    case task(SupabaseProjectTaskDTO)
    case user(SupabaseUserDTO)
    case client(SupabaseClientDTO)
    case company(SupabaseCompanyDTO)
    case taskType(SupabaseTaskTypeDTO)
    case subClient(SupabaseSubClientDTO)
    case projectNote(ProjectNoteDTO)
    case photoAnnotation(PhotoAnnotationDTO)
    case deckDesign(SupabaseDeckDesignDTO)
    // Catalog parents (Option A — children refetch via next pullDelta).
    case catalogCategory(CatalogCategoryDTO)
    case catalogUnit(CatalogUnitDTO)
    case catalogTag(CatalogTagDTO)
    case catalogItem(CatalogItemDTO)
    case catalogVariant(CatalogVariantDTO)
    case catalogSnapshot(CatalogSnapshotDTO)
    case catalogOrder(CatalogOrderDTO)
    case companyDefaultProduct(CompanyDefaultProductDTO)
}

// MARK: - Inbound Repositories Helper

/// Collects every Supabase repository needed by the inbound sync path.
/// Initialized fresh from the current companyId at each sync's entry point.
struct InboundRepositories {
    /// Retained for single-row fetches like `CompanyRepository.fetch(companyId:)`
    /// that need the raw id at call time, not baked into the repo.
    let companyId: String

    let project: ProjectRepository
    let task: TaskRepository
    let user: UserRepository
    let client: ClientRepository
    let company: CompanyRepository
    let taskType: TaskTypeRepository
    let projectNote: ProjectNoteRepository
    let photoAnnotation: PhotoAnnotationRepository
    let deckDesign: DeckDesignRepository
    let wizardState: WizardStateRepository
    let invoice: InvoiceRepository
    let estimate: EstimateRepository
    let catalog: CatalogRepository
    let inventory: InventoryRepository
    let productRichness: ProductRichnessRepository
    let defaultProduct: CompanyDefaultProductRepository
    let order: CatalogOrderRepository

    init(companyId: String) {
        self.companyId = companyId
        // wizard_states is user-scoped. Read userId eagerly.
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        self.project = ProjectRepository(companyId: companyId)
        self.task = TaskRepository(companyId: companyId)
        self.user = UserRepository(companyId: companyId)
        self.client = ClientRepository(companyId: companyId)
        self.company = CompanyRepository()
        self.taskType = TaskTypeRepository(companyId: companyId)
        self.projectNote = ProjectNoteRepository(companyId: companyId)
        self.photoAnnotation = PhotoAnnotationRepository(companyId: companyId)
        self.deckDesign = DeckDesignRepository(companyId: companyId)
        self.wizardState = WizardStateRepository(userId: userId)
        self.invoice = InvoiceRepository(companyId: companyId)
        self.estimate = EstimateRepository(companyId: companyId)
        self.catalog = CatalogRepository(companyId: companyId)
        self.inventory = InventoryRepository(companyId: companyId)
        self.productRichness = ProductRichnessRepository(companyId: companyId)
        self.defaultProduct = CompanyDefaultProductRepository(companyId: companyId)
        self.order = CatalogOrderRepository(companyId: companyId)
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
