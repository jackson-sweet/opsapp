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
        await SubscriptionManager.shared.checkSubscriptionStatus()
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

        if let existing = try modelContext.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .project,
                entityId: id,
                fields: [
                    "title", "status", "companyId", "clientId", "opportunityId",
                    "address", "latitude", "longitude",
                    "startDate", "endDate", "duration",
                    "notes", "projectDescription", "allDay",
                    "teamMemberIdsString", "projectImagesString", "deletedAt"
                ]
            )

            if accept.contains("title") { existing.title = dto.title }
            if accept.contains("status") { existing.status = Status(rawValue: dto.status) ?? .rfq }
            if accept.contains("companyId") { existing.companyId = dto.companyId }
            if accept.contains("clientId") { existing.clientId = dto.clientId }
            if accept.contains("opportunityId") { existing.opportunityId = dto.opportunityId }
            if accept.contains("address") { existing.address = dto.address }
            if accept.contains("latitude") { existing.latitude = dto.latitude }
            if accept.contains("longitude") { existing.longitude = dto.longitude }
            if accept.contains("startDate") { existing.startDate = dto.startDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("endDate") { existing.endDate = dto.endDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("duration") { existing.duration = dto.duration }
            if accept.contains("notes") { existing.notes = dto.notes }
            if accept.contains("projectDescription") { existing.projectDescription = dto.description }
            if accept.contains("allDay") { existing.allDay = dto.allDay ?? false }
            if accept.contains("teamMemberIdsString") {
                existing.teamMemberIdsString = (dto.teamMemberIds ?? []).joined(separator: ",")
            }
            if accept.contains("projectImagesString") {
                existing.projectImagesString = (dto.projectImages ?? []).joined(separator: ",")
            }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

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
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)

            if model.deletedAt != nil {
                markSpotlightDeleted(domain: SpotlightDomain.project, id: model.id)
            } else {
                markSpotlightDirty(domain: SpotlightDomain.project, id: model.id)
            }
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
        let id = dto.id
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id == id }
        )

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
            if accept.contains("taskTypeId") { existing.taskTypeId = dto.taskTypeId ?? "" }
            if accept.contains("startDate") { existing.startDate = dto.startDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("endDate") { existing.endDate = dto.endDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("duration") { existing.duration = dto.duration ?? 1 }
            if accept.contains("displayOrder") { existing.displayOrder = dto.displayOrder ?? 0 }
            if accept.contains("teamMemberIdsString") {
                existing.teamMemberIdsString = (dto.teamMemberIds ?? []).joined(separator: ",")
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
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)

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
                    "annotationURL", "note", "updatedAt", "deletedAt"
                ]
            )

            if accept.contains("annotationURL") { existing.annotationURL = dto.annotationUrl }
            if accept.contains("note") { existing.note = dto.note ?? "" }
            if accept.contains("updatedAt") { existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

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
            let accept = acceptableFields(
                entityType: .deckDesign,
                entityId: id,
                fields: [
                    "title", "drawingDataJSON", "thumbnailURL",
                    "version", "updatedAt", "deletedAt"
                ]
            )

            if accept.contains("title") { existing.title = dto.title }
            if accept.contains("drawingDataJSON") { existing.drawingDataJSON = dto.drawingData.toJSON() }
            if accept.contains("thumbnailURL") { existing.thumbnailURL = dto.thumbnailUrl }
            if accept.contains("version") { existing.version = dto.version }
            if accept.contains("updatedAt") { existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

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
    let invoice: InvoiceRepository
    let estimate: EstimateRepository

    init(companyId: String) {
        self.companyId = companyId
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
