//
//  InboundProcessor.swift
//  OPS
//
//  Pulls data from Supabase and merges into local SwiftData,
//  respecting pending local operations via field-level merge.
//
//  Part of the offline-first sync engine rebuild.
//

import Foundation
import SwiftData

// MARK: - InboundProcessor

/// Handles inbound (server → local) data synchronization with field-level merge.
///
/// Unlike the original SupabaseSyncManager upsert methods which blindly overwrite
/// local values, InboundProcessor checks for pending SyncOperations on each field
/// before accepting server data. Fields with pending local changes are preserved
/// and will be pushed to the server on the next outbound cycle.
@MainActor
final class InboundProcessor {

    // MARK: - Dependencies

    private(set) var companyId: String

    private var projectRepo: ProjectRepository
    private var taskRepo: TaskRepository
    private var userRepo: UserRepository
    private var clientRepo: ClientRepository
    private var companyRepo: CompanyRepository
    private var taskTypeRepo: TaskTypeRepository
    private var projectNoteRepo: ProjectNoteRepository
    private var photoAnnotationRepo: PhotoAnnotationRepository
    private var deckDesignRepo: DeckDesignRepository
    private var wizardStateRepo: WizardStateRepository
    private var invoiceRepo: InvoiceRepository
    private var estimateRepo: EstimateRepository
    private var calendarUserEventRepo: CalendarUserEventRepository
    private var inventoryRepo: InventoryRepository

    /// Tracks entities touched during the current sync pass so Spotlight receives
    /// targeted, minimal updates after each sync instead of a full re-index.
    /// Reset at the start of each full/delta sync; dispatched in linkAllRelationships.
    let spotlightTracker = SpotlightSyncTracker()

    // MARK: - Init

    init() {
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")
            ?? UserDefaults.standard.string(forKey: "company_id")
            ?? ""
        self.companyId = companyId

        // wizard_states is user-scoped (no company_id). Read userId eagerly for repo.
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""

        self.projectRepo = ProjectRepository(companyId: companyId)
        self.taskRepo = TaskRepository(companyId: companyId)
        self.userRepo = UserRepository(companyId: companyId)
        self.clientRepo = ClientRepository(companyId: companyId)
        self.companyRepo = CompanyRepository()
        self.taskTypeRepo = TaskTypeRepository(companyId: companyId)
        self.projectNoteRepo = ProjectNoteRepository(companyId: companyId)
        self.photoAnnotationRepo = PhotoAnnotationRepository(companyId: companyId)
        self.deckDesignRepo = DeckDesignRepository(companyId: companyId)
        self.wizardStateRepo = WizardStateRepository(userId: userId)
        self.invoiceRepo = InvoiceRepository(companyId: companyId)
        self.estimateRepo = EstimateRepository(companyId: companyId)
        self.calendarUserEventRepo = CalendarUserEventRepository(companyId: companyId)
        self.inventoryRepo = InventoryRepository(companyId: companyId)
    }

    // MARK: - Reconfigure

    /// Rebuild all repositories with the current companyId from UserDefaults.
    /// Call after login completes and companyId is confirmed.
    func reconfigure() {
        let newCompanyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")
            ?? UserDefaults.standard.string(forKey: "company_id")
            ?? ""

        guard !newCompanyId.isEmpty else {
            print("[InboundProcessor] reconfigure() called but companyId still empty")
            return
        }

        guard newCompanyId != companyId || companyId.isEmpty else {
            return // Already configured with this companyId
        }

        print("[InboundProcessor] Reconfiguring repositories for company: \(newCompanyId)")
        self.companyId = newCompanyId
        let newUserId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        self.projectRepo = ProjectRepository(companyId: newCompanyId)
        self.taskRepo = TaskRepository(companyId: newCompanyId)
        self.userRepo = UserRepository(companyId: newCompanyId)
        self.clientRepo = ClientRepository(companyId: newCompanyId)
        self.companyRepo = CompanyRepository()
        self.taskTypeRepo = TaskTypeRepository(companyId: newCompanyId)
        self.projectNoteRepo = ProjectNoteRepository(companyId: newCompanyId)
        self.photoAnnotationRepo = PhotoAnnotationRepository(companyId: newCompanyId)
        self.deckDesignRepo = DeckDesignRepository(companyId: newCompanyId)
        self.wizardStateRepo = WizardStateRepository(userId: newUserId)
        self.invoiceRepo = InvoiceRepository(companyId: newCompanyId)
        self.estimateRepo = EstimateRepository(companyId: newCompanyId)
        self.calendarUserEventRepo = CalendarUserEventRepository(companyId: newCompanyId)
        self.inventoryRepo = InventoryRepository(companyId: newCompanyId)
    }

    // MARK: - Sync Priority Order

    /// Entity types processed during full/delta sync, ordered by syncPriority
    /// to satisfy foreign key dependencies.
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
        .calendarUserEvent,   // Bug 1 — user-created time-off / personal events
        .inventoryUnit,
        .inventoryTag,
        .inventoryItem,
        .inventorySnapshot,
        .inventorySnapshotItem
    ]

    // MARK: - Full Sync

    /// Pull ALL entities from Supabase in dependency order and merge into local SwiftData.
    func fullSync(
        context: ModelContext,
        onProgress: ((SyncEntityType, Double) -> Void)? = nil
    ) async throws {
        // Auto-reconfigure if companyId was empty at init time
        if companyId.isEmpty { reconfigure() }
        guard !companyId.isEmpty else {
            print("[InboundProcessor] FULL SYNC ABORTED — no companyId available")
            return
        }
        print("[InboundProcessor] ======== FULL SYNC STARTED ========")

        // Reset Spotlight tracker at sync start
        spotlightTracker.reset()

        let totalSteps = Double(Self.syncOrder.count)

        for (index, entityType) in Self.syncOrder.enumerated() {
            let stepProgress = Double(index) / totalSteps
            onProgress?(entityType, stepProgress)

            print("[InboundProcessor] Syncing \(entityType.rawValue)...")
            try await syncEntityType(entityType, since: nil, context: context)
            print("[InboundProcessor] \(entityType.rawValue) complete")
        }

        // Link relationships after all entities are pulled
        print("[InboundProcessor] Linking relationships...")
        linkAllRelationships(context: context)

        // Dispatch targeted Spotlight index updates based on what this sync touched.
        // Only runs after initial backfill — first-run indexing is coordinated by
        // SpotlightBackfillCoordinator which runs a full bulk index.
        if SpotlightIndexManager.shared.hasCompletedInitialBackfill {
            await spotlightTracker.dispatch(context: context)
        }

        onProgress?(.photoAnnotation, 1.0)
        print("[InboundProcessor] ======== FULL SYNC COMPLETED ========")
    }

    // MARK: - Delta Sync

    /// Pull entities updated since the given timestamps and merge into local SwiftData.
    func deltaSync(
        context: ModelContext,
        since: [SyncEntityType: Date]
    ) async throws {
        // Auto-reconfigure if companyId was empty at init time
        if companyId.isEmpty { reconfigure() }
        guard !companyId.isEmpty else {
            print("[InboundProcessor] DELTA SYNC ABORTED — no companyId available")
            return
        }
        print("[InboundProcessor] ======== DELTA SYNC STARTED ========")

        // Reset Spotlight tracker at sync start
        spotlightTracker.reset()

        for entityType in Self.syncOrder {
            let sinceDate = since[entityType]
            // For delta sync, only fetch entity types that have a since date
            guard sinceDate != nil else { continue }

            print("[InboundProcessor] Delta syncing \(entityType.rawValue) since \(sinceDate!)")
            try await syncEntityType(entityType, since: sinceDate, context: context)
        }

        // Re-link relationships after pulling updates
        linkAllRelationships(context: context)

        // Dispatch targeted Spotlight index updates for the delta
        if SpotlightIndexManager.shared.hasCompletedInitialBackfill {
            await spotlightTracker.dispatch(context: context)
        }

        print("[InboundProcessor] ======== DELTA SYNC COMPLETED ========")
    }

    // MARK: - Entity Type Dispatch

    /// Routes a sync call to the appropriate entity-specific method.
    private func syncEntityType(
        _ entityType: SyncEntityType,
        since: Date?,
        context: ModelContext
    ) async throws {
        switch entityType {
        case .company:
            try await syncCompany(context: context)
        case .user:
            try await syncUsers(since: since, context: context)
        case .client:
            try await syncClients(since: since, context: context)
        case .taskType:
            try await syncTaskTypes(since: since, context: context)
        case .project:
            try await syncProjects(since: since, context: context)
        case .projectTask:
            try await syncTasks(since: since, context: context)
        case .subClient:
            try await syncSubClients(since: since, context: context)
        case .projectNote:
            try await syncProjectNotes(since: since, context: context)
        case .photoAnnotation:
            try await syncPhotoAnnotations(since: since, context: context)
        case .deckDesign:
            try await syncDeckDesigns(since: since, context: context)
        case .wizardState:
            try await syncWizardStates(since: since, context: context)
        case .estimate:
            try await syncEstimates(since: since, context: context)
        case .invoice:
            try await syncInvoices(since: since, context: context)
        case .calendarUserEvent:
            try await syncCalendarUserEvents(context: context)
        case .inventoryUnit:
            try await syncInventoryUnits(since: since, context: context)
        case .inventoryTag:
            try await syncInventoryTags(since: since, context: context)
        case .inventoryItem:
            try await syncInventoryItems(since: since, context: context)
        case .inventorySnapshot:
            try await syncInventorySnapshots(since: since, context: context)
        case .inventorySnapshotItem:
            try await syncInventorySnapshotItems(context: context)
        default:
            print("[InboundProcessor] Entity type \(entityType.rawValue) not yet supported for inbound sync")
        }
    }

    // MARK: - Field-Level Merge Check

    /// Determines whether a server value should overwrite the local value for a specific field.
    ///
    /// Queries SyncOperation for any pending operations matching (entityType, entityId).
    /// If any pending operation's `changedFields` includes this `fieldName`, the local value
    /// is preserved — it will be pushed to the server on the next outbound cycle.
    ///
    /// - Returns: `true` if the server value should be accepted; `false` if the local value should be kept.
    private func shouldAcceptServerValue(
        entityType: SyncEntityType,
        entityId: String,
        fieldName: String,
        context: ModelContext
    ) -> Bool {
        let entityTypeRaw = entityType.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.entityType == entityTypeRaw &&
                $0.entityId == entityId &&
                $0.status == "pending"
            }
        )

        guard let pendingOps = try? context.fetch(descriptor) else {
            // If we can't query, default to accepting server value
            return true
        }

        for op in pendingOps {
            let changedFields = op.getChangedFields()
            if changedFields.contains(fieldName) {
                print("[InboundProcessor] Field '\(fieldName)' on \(entityType.rawValue) \(entityId): keeping local (pending operation exists)")
                return false
            }
        }

        return true
    }

    /// Convenience to check multiple fields and return a Set of field names that should be accepted.
    private func acceptableFields(
        entityType: SyncEntityType,
        entityId: String,
        fields: [String],
        context: ModelContext
    ) -> Set<String> {
        // Batch-fetch pending operations once for efficiency
        let entityTypeRaw = entityType.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.entityType == entityTypeRaw &&
                $0.entityId == entityId &&
                $0.status == "pending"
            }
        )

        guard let pendingOps = try? context.fetch(descriptor) else {
            return Set(fields)
        }

        // Collect all changed fields from all pending operations
        var pendingFields = Set<String>()
        for op in pendingOps {
            pendingFields.formUnion(op.getChangedFields())
        }

        // Return fields that are NOT in the pending set
        var accepted = Set<String>()
        for field in fields {
            if pendingFields.contains(field) {
                print("[InboundProcessor] Field '\(field)' on \(entityType.rawValue) \(entityId): keeping local (pending operation exists)")
            } else {
                accepted.insert(field)
            }
        }
        return accepted
    }

    // MARK: - Company Sync

    func syncCompany(context: ModelContext) async throws {
        guard !companyId.isEmpty else {
            print("[InboundProcessor] No companyId — skipping company sync")
            return
        }

        let dto = try await companyRepo.fetch(companyId: companyId)
        try mergeCompany(dto: dto, context: context)

        // Refresh subscription status so seat/plan changes from web are reflected immediately
        await SubscriptionManager.shared.checkSubscriptionStatus()
    }

    private func mergeCompany(dto: SupabaseCompanyDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
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
                ],
                context: context
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
            // No existing record — insert fresh from DTO
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - User Sync

    private func syncUsers(since: Date?, context: ModelContext) async throws {
        let dtos = try await userRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeUser(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) users")
    }

    private func mergeUser(dto: SupabaseUserDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
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
                ],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - Client Sync

    private func syncClients(since: Date?, context: ModelContext) async throws {
        let scope = PermissionStore.shared.scope(for: "clients.view") ?? "all"
        let userId = UserDefaults.standard.string(forKey: "currentUserId")
        let dtos = try await clientRepo.fetchAll(since: since, scope: scope, userId: userId)
        for dto in dtos {
            try mergeClient(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) clients (scope: \(scope))")
    }

    private func mergeClient(dto: SupabaseClientDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.id == id }
        )
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        print("[DUPE_TRACE] INBOUND.mergeClient id=\(id) existing_count=\(existingCount) ctx=\(ObjectIdentifier(context))")

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .client,
                entityId: id,
                fields: [
                    "name", "email", "phoneNumber", "address",
                    "latitude", "longitude", "profileImageURL",
                    "notes", "companyId", "deletedAt"
                ],
                context: context
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
            // Only clear needsSync if there are no pending SyncOperations for this entity
            let hasPending = hasPendingOperations(entityType: .client, entityId: existing.id, context: context)
            if !hasPending {
                existing.needsSync = false
            }

            // Mark for targeted Spotlight update — deletion wins over upsert
            if existing.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.client, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.client, id: id)
            }
        } else {
            // Origin suppression: if we wrote this entityId locally within the
            // last 60s — regardless of SyncOperation status (pending, inProgress,
            // completed, failed) — the inbound DTO is our own write coming back
            // via pull. Inserting would produce a duplicate because Client.id
            // lacks @Attribute(.unique). Mirrors mergeProject suppression
            // (bug f86cf554) and fixes bug b873deb7 (duplicate client created
            // from the project form sheet when uppercase local UUIDs failed to
            // match the lowercase pull payload).
            if hasRecentLocalWrite(entityType: .client, entityId: id, withinSeconds: 60, context: context) {
                print("[DUPE_TRACE] INBOUND.mergeClient SUPPRESSED id=\(id) — recent local write within 60s")
                return
            }

            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)

            if model.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.client, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.client, id: id)
            }
        }

        try context.save()
    }

    // MARK: - TaskType Sync

    private func syncTaskTypes(since: Date?, context: ModelContext) async throws {
        let dtos = try await taskTypeRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeTaskType(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) task types")
    }

    private func mergeTaskType(dto: SupabaseTaskTypeDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .taskType,
                entityId: id,
                fields: [
                    "display", "color", "icon", "isDefault",
                    "displayOrder", "dependenciesJSON", "defaultTeamMemberIdsString", "deletedAt"
                ],
                context: context
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
            // Origin suppression: if a pending SyncOperation exists for this
            // id, the main context just wrote this row. Inserting here would
            // leave two TaskType rows with the same id (no @Attribute(.unique)),
            // and relationship resolution can pick the stale duplicate.
            if hasPendingOperations(entityType: .taskType, entityId: id, context: context) {
                print("[InboundProcessor] Skipping merge insert for task type \(id) — pending local op exists (origin suppression)")
                return
            }

            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - Project Sync

    private func syncProjects(since: Date?, context: ModelContext) async throws {
        let scope = PermissionStore.shared.scope(for: "projects.view") ?? "all"
        let userId = UserDefaults.standard.string(forKey: "currentUserId")
        let dtos = try await projectRepo.fetchAll(since: since, scope: scope, userId: userId)
        for dto in dtos {
            try mergeProject(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) projects (scope: \(scope))")
    }

    private func mergeProject(dto: SupabaseProjectDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == id }
        )
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        print("[DUPE_TRACE] INBOUND.mergeProject id=\(id) existing_count=\(existingCount) ctx=\(ObjectIdentifier(context))")

        if let existing = try context.fetch(descriptor).first {
            // Bug 209281ba — acceptableFields compares against the changedFields
            // stored on pending SyncOperations, which callers populate with
            // server-side wire names ("project_images", "team_member_ids",
            // "company_id", etc.). The previous version mixed Swift property
            // names ("projectImagesString", "teamMemberIdsString") into this
            // check, so the protection silently failed: pending operations
            // matched no fields here and the inbound DTO overwrote local
            // optimistic writes (e.g., photos appended to projectImagesString
            // by ProjectNotesViewModel.addAttachmentsToProjectGallery
            // disappeared when the next inbound project sync ran). Standardize
            // on the server-side names to match the queue.
            let accept = acceptableFields(
                entityType: .project,
                entityId: id,
                fields: [
                    "title", "status", "company_id", "client_id", "opportunity_id",
                    "address", "latitude", "longitude",
                    "start_date", "end_date", "duration",
                    "notes", "description", "all_day",
                    "team_member_ids", "project_images", "deleted_at"
                ],
                context: context
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

            existing.lastSyncedAt = Date()
            // Only clear needsSync if there are no pending SyncOperations for this entity
            let hasPending = hasPendingOperations(entityType: .project, entityId: existing.id, context: context)
            if !hasPending {
                existing.needsSync = false
            }

            // Mark for targeted Spotlight update
            if existing.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.project, id: existing.id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.project, id: existing.id)
            }
        } else {
            // Origin suppression: if we wrote this entityId locally within the
            // last 60s — regardless of SyncOperation status (pending, inProgress,
            // completed, failed) — the inbound DTO is our own write coming back
            // via pull. Inserting would produce a duplicate because Project.id
            // lacks @Attribute(.unique). Mirrors mergeTask suppression (bug
            // f86cf554 / 858fa5e): the previous `hasPendingOperations` check
            // missed the common case where the outbound push had already
            // flipped the op to "completed" before the pull pass ran.
            if hasRecentLocalWrite(entityType: .project, entityId: id, withinSeconds: 60, context: context) {
                print("[DUPE_TRACE] INBOUND.mergeProject SUPPRESSED id=\(id) — recent local write within 60s")
                return
            }

            print("[DUPE_TRACE] INBOUND.mergeProject INSERT id=\(id) — no recent local write, treating as remote create")
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)

            if model.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.project, id: model.id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.project, id: model.id)
            }
        }

        try context.save()
    }

    // MARK: - Task Sync

    private func syncTasks(since: Date?, context: ModelContext) async throws {
        let scope = PermissionStore.shared.scope(for: "tasks.view") ?? "all"
        let userId = UserDefaults.standard.string(forKey: "currentUserId")
        let dtos = try await taskRepo.fetchAll(since: since, scope: scope, userId: userId)
        for dto in dtos {
            try mergeTask(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) tasks (scope: \(scope))")
    }

    private func mergeTask(dto: SupabaseProjectTaskDTO, context: ModelContext) throws {
        // Canonicalize to lowercase — Postgres uuid storage is lowercase; Swift's
        // historical UPPERCASE id created a case mismatch. Local rows are kept
        // lowercase by DataActor.normalizeTaskIdsToLowercase + new-write canonicalization.
        let id = dto.id.lowercased()
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .projectTask,
                entityId: id,
                fields: [
                    "status", "taskNotes", "customTitle", "taskColor",
                    "taskTypeId", "startDate", "endDate", "duration",
                    "displayOrder", "teamMemberIdsString",
                    "sourceLineItemId", "sourceEstimateId",
                    "dependencyOverridesJSON", "startTime", "endTime", "deletedAt"
                ],
                context: context
            )

            if accept.contains("status") { existing.status = TaskStatus(rawValue: dto.status) ?? .active }
            if accept.contains("taskNotes") { existing.taskNotes = dto.taskNotes }
            if accept.contains("customTitle") { existing.customTitle = dto.customTitle }
            if accept.contains("taskColor") { existing.taskColor = dto.taskColor ?? "#59779F" }
            if accept.contains("taskTypeId") {
                existing.taskTypeId = dto.taskTypeId ?? ""
                // Rewire TaskType `@Relationship` to match the new id. The
                // end-of-sync `linkAllRelationships` pass also does this, but
                // rewiring inline keeps the view consistent if it reads mid-pass.
                if !existing.taskTypeId.isEmpty {
                    let ttId = existing.taskTypeId
                    if let newType = try? context.fetch(
                        FetchDescriptor<TaskType>(predicate: #Predicate<TaskType> { $0.id == ttId })
                    ).first {
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
                existing.teamMemberIdsString = (dto.teamMemberIds ?? []).joined(separator: ",")
                // Rewire `teamMembers` to match the new id string. See the
                // equivalent block in DataActor.mergeTask for rationale.
                let ids = existing.getTeamMemberIds()
                if ids.isEmpty {
                    if !existing.teamMembers.isEmpty { existing.teamMembers = [] }
                } else {
                    let users = (try? context.fetch(
                        FetchDescriptor<User>(predicate: #Predicate<User> { ids.contains($0.id) })
                    )) ?? []
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
                if let st = dto.startTime {
                    if let parsed = Self.parseTime(st) {
                        existing.startTime = parsed
                    }
                }
            }
            if accept.contains("endTime") {
                if let et = dto.endTime {
                    if let parsed = Self.parseTime(et) {
                        existing.endTime = parsed
                    }
                }
            }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            // Only clear needsSync if there are no pending SyncOperations for this entity
            let hasPending = hasPendingOperations(entityType: .projectTask, entityId: existing.id, context: context)
            if !hasPending {
                existing.needsSync = false
            }

            // Mark for targeted Spotlight update
            if existing.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.task, id: existing.id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.task, id: existing.id)
            }
        } else {
            // Origin suppression: if we wrote this entityId locally within the
            // last 60s — regardless of SyncOperation status (pending, inProgress,
            // completed, failed) — the inbound DTO is our own write coming back
            // via pull. Inserting would produce a duplicate because ProjectTask.id
            // lacks @Attribute(.unique). The previous `hasPendingOperations`
            // check missed the common case where the outbound push had already
            // flipped the op to "completed" before the pull pass ran.
            if hasRecentLocalWrite(entityType: .projectTask, entityId: id, withinSeconds: 60, context: context) {
                print("[DUPE_TRACE] INBOUND.mergeTask SUPPRESSED id=\(id) — recent local write within 60s")
                return
            }

            print("[DUPE_TRACE] INBOUND.mergeTask INSERT id=\(id) — no recent local write, treating as remote create")
            let model = dto.toModel()
            model.id = id  // enforce lowercase canonicalization
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)

            // Wire project / taskType / teamMembers on the fresh row so the UI
            // has a complete task from the first render.
            let projId = model.projectId
            if let project = try? context.fetch(
                FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.id == projId })
            ).first {
                model.project = project
            }
            if !model.taskTypeId.isEmpty {
                let ttId = model.taskTypeId
                if let taskType = try? context.fetch(
                    FetchDescriptor<TaskType>(predicate: #Predicate<TaskType> { $0.id == ttId })
                ).first {
                    model.taskType = taskType
                }
            }
            let memberIds = model.getTeamMemberIds()
            if !memberIds.isEmpty {
                let users = (try? context.fetch(
                    FetchDescriptor<User>(predicate: #Predicate<User> { memberIds.contains($0.id) })
                )) ?? []
                if !users.isEmpty { model.teamMembers = users }
            }

            if model.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.task, id: model.id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.task, id: model.id)
            }
        }

        try context.save()
    }

    // MARK: - SubClient Sync

    private func syncSubClients(since: Date?, context: ModelContext) async throws {
        let dtos = try await clientRepo.fetchAllSubClients(since: since)
        for dto in dtos {
            try mergeSubClient(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) sub-clients")
    }

    private func mergeSubClient(dto: SupabaseSubClientDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<SubClient>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .subClient,
                entityId: id,
                fields: [
                    "name", "title", "email", "phoneNumber", "address", "deletedAt"
                ],
                context: context
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
            if let parentClient = try? context.fetch(clientDescriptor).first {
                existing.client = parentClient
            }

            existing.lastSyncedAt = Date()
            existing.needsSync = false

            // Bug G4 — mark for targeted Spotlight update so edits / deletions
            // propagate to the index without a full re-backfill.
            if existing.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.subClient, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.subClient, id: id)
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false

            // Link parent client relationship
            let parentId = dto.parentClientId
            let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == parentId })
            if let parentClient = try? context.fetch(clientDescriptor).first {
                model.client = parentClient
            }

            context.insert(model)

            if model.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.subClient, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.subClient, id: id)
            }
        }

        try context.save()
    }

    // MARK: - ProjectNote Sync

    private func syncProjectNotes(since: Date?, context: ModelContext) async throws {
        let dtos = try await projectNoteRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeProjectNote(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) project notes")
    }

    private func mergeProjectNote(dto: ProjectNoteDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .projectNote,
                entityId: id,
                fields: [
                    "content", "attachmentsJSON", "mentionedUserIdsString",
                    "updatedAt", "deletedAt"
                ],
                context: context
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
            let hasPending = hasPendingOperations(entityType: .projectNote, entityId: existing.id, context: context)
            if !hasPending {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - PhotoAnnotation Sync

    private func syncPhotoAnnotations(since: Date?, context: ModelContext) async throws {
        let dtos = try await photoAnnotationRepo.fetchAll(since: since)
        for dto in dtos {
            try mergePhotoAnnotation(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) photo annotations")
    }

    private func mergePhotoAnnotation(dto: PhotoAnnotationDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .photoAnnotation,
                entityId: id,
                fields: [
                    "annotationURL", "note", "updatedAt", "deletedAt"
                ],
                context: context
            )

            if accept.contains("annotationURL") { existing.annotationURL = dto.annotationUrl }
            if accept.contains("note") { existing.note = dto.note ?? "" }
            if accept.contains("updatedAt") { existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            let hasPending = hasPendingOperations(entityType: .photoAnnotation, entityId: existing.id, context: context)
            if !hasPending {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - DeckDesign Sync

    private func syncDeckDesigns(since: Date?, context: ModelContext) async throws {
        let dtos = try await deckDesignRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeDeckDesign(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) deck designs")
    }

    private func mergeDeckDesign(dto: SupabaseDeckDesignDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .deckDesign,
                entityId: id,
                fields: [
                    "title", "drawingDataJSON", "thumbnailURL",
                    "version", "updatedAt", "deletedAt"
                ],
                context: context
            )

            if accept.contains("title") { existing.title = dto.title }
            if accept.contains("drawingDataJSON") { existing.drawingDataJSON = dto.drawingData.toJSON() }
            if accept.contains("thumbnailURL") { existing.thumbnailURL = dto.thumbnailUrl }
            if accept.contains("version") { existing.version = dto.version }
            if accept.contains("updatedAt") { existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            let hasPending = hasPendingOperations(entityType: .deckDesign, entityId: existing.id, context: context)
            if !hasPending {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - WizardState Sync

    private func syncWizardStates(since: Date?, context: ModelContext) async throws {
        // wizard_states is user-scoped. Resolve userId at call time so a fresh login
        // uses the right value even if reconfigure() hasn't landed yet.
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        guard !userId.isEmpty else {
            print("[InboundProcessor] No userId — skipping wizard_states sync")
            return
        }

        let dtos = try await wizardStateRepo.fetchForUser(userId, since: since)
        for dto in dtos {
            try mergeWizardState(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) wizard states")
    }

    private func mergeWizardState(dto: SupabaseWizardStateDTO, context: ModelContext) throws {
        let id = dto.id
        // Primary match on id (new rows synced from other devices).
        let idDescriptor = FetchDescriptor<WizardState>(
            predicate: #Predicate { $0.id == id }
        )
        var existing = try context.fetch(idDescriptor).first

        // Fallback match on (wizardId, userId) for records created locally BEFORE
        // this sync landed (they were inserted by WizardStateManager with a fresh
        // UUID that the server has never seen). If we find one, adopt the server
        // id so subsequent pulls resolve directly.
        if existing == nil {
            let wizardId = dto.wizardId
            let userId = dto.userId
            let pairDescriptor = FetchDescriptor<WizardState>(
                predicate: #Predicate { $0.wizardId == wizardId && $0.userId == userId }
            )
            if let fallback = try context.fetch(pairDescriptor).first {
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
                ],
                context: context
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
            let hasPending = hasPendingOperations(entityType: .wizardState, entityId: existing.id, context: context)
            if !hasPending {
                existing.needsSync = false
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - Relationship Linking

    /// Link SwiftData relationships after all entities have been pulled.
    /// Ported from SupabaseSyncManager.linkAllRelationships().
    private func linkAllRelationships(context: ModelContext) {
        print("[InboundProcessor] Linking all relationships...")

        let projects: [Project]
        let tasks: [ProjectTask]
        let clients: [Client]
        let taskTypes: [TaskType]
        let users: [User]
        do {
            projects = try context.fetch(FetchDescriptor<Project>())
            tasks = try context.fetch(FetchDescriptor<ProjectTask>())
            clients = try context.fetch(FetchDescriptor<Client>())
            taskTypes = try context.fetch(FetchDescriptor<TaskType>())
            users = try context.fetch(FetchDescriptor<User>())
        } catch {
            print("[InboundProcessor] ⚠️ Failed to fetch entities for linking: \(error)")
            return
        }

        // Build lookup dictionaries — use last-wins to safely handle duplicates
        var clientById: [String: Client] = [:]
        for c in clients { clientById[c.id] = c }
        var taskTypeById: [String: TaskType] = [:]
        for t in taskTypes { taskTypeById[t.id] = t }
        var userById: [String: User] = [:]
        for u in users { userById[u.id] = u }
        var projectById: [String: Project] = [:]
        for p in projects { projectById[p.id] = p }

        // Link projects to clients and team members
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

        // Link tasks to projects, task types, and team members
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
            let members = memberIds.compactMap { userById[$0] }
            if Set(task.teamMembers.map(\.id)) != Set(members.map(\.id)) {
                task.teamMembers = members
            }
        }

        // Link inventory: items → unit (by unitId) and items → tags (by tagIds).
        // Snapshot items → snapshot (by snapshotId).
        let inventoryItems: [InventoryItem]
        let inventoryUnits: [InventoryUnit]
        let inventoryTags: [InventoryTag]
        let inventorySnapshots: [InventorySnapshot]
        let inventorySnapshotItems: [InventorySnapshotItem]
        do {
            inventoryItems = try context.fetch(FetchDescriptor<InventoryItem>())
            inventoryUnits = try context.fetch(FetchDescriptor<InventoryUnit>())
            inventoryTags = try context.fetch(FetchDescriptor<InventoryTag>())
            inventorySnapshots = try context.fetch(FetchDescriptor<InventorySnapshot>())
            inventorySnapshotItems = try context.fetch(FetchDescriptor<InventorySnapshotItem>())
        } catch {
            print("[InboundProcessor] ⚠️ Failed to fetch inventory entities for linking: \(error)")
            do { try context.save() } catch {
                context.rollback()
            }
            return
        }

        var unitById: [String: InventoryUnit] = [:]
        for u in inventoryUnits { unitById[u.id] = u }
        var tagById: [String: InventoryTag] = [:]
        for t in inventoryTags { tagById[t.id] = t }
        var snapshotById: [String: InventorySnapshot] = [:]
        for s in inventorySnapshots { snapshotById[s.id] = s }

        for item in inventoryItems {
            if let unitId = item.unitId, let unit = unitById[unitId] {
                if item.unit?.id != unit.id {
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

        for snapItem in inventorySnapshotItems {
            if let snapshot = snapshotById[snapItem.snapshotId] {
                if snapItem.snapshot?.id != snapshot.id {
                    snapItem.snapshot = snapshot
                }
            }
        }

        do {
            try context.save()
            print("[InboundProcessor] Relationships linked")
        } catch {
            print("[InboundProcessor] ⚠️ Relationship linking save failed: \(error) — rolling back")
            context.rollback()
        }
    }

    // MARK: - Pending Operations Check

    /// Returns true if there are any pending SyncOperations for the given entity.
    /// Used to decide whether `needsSync` should be cleared after an inbound merge.
    private func hasPendingOperations(entityType: SyncEntityType, entityId: String, context: ModelContext) -> Bool {
        let typeStr = entityType.rawValue
        let predicate = #Predicate<SyncOperation> { op in
            op.entityType == typeStr &&
            op.entityId == entityId &&
            op.status == "pending"
        }
        let descriptor = FetchDescriptor<SyncOperation>(predicate: predicate)
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    /// Returns true if a SyncOperation for this entity had ANY lifecycle event
    /// (created / attempted / completed) within the given window, regardless
    /// of current status. Considers all three timestamps so the window covers
    /// freshly-recorded, push-in-flight, recently-completed, and
    /// offline-delayed-push cases.
    private func hasRecentLocalWrite(
        entityType: SyncEntityType,
        entityId: String,
        withinSeconds seconds: TimeInterval,
        context: ModelContext
    ) -> Bool {
        let typeStr = entityType.rawValue
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let predicate = #Predicate<SyncOperation> { op in
            op.entityType == typeStr &&
            (op.entityId == idLower || op.entityId == idUpper || op.entityId == entityId)
        }
        let descriptor = FetchDescriptor<SyncOperation>(predicate: predicate)
        guard let ops = try? context.fetch(descriptor), !ops.isEmpty else {
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
    private static func parseTime(_ timeString: String) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute))
    }

    // MARK: - Estimate Sync

    private func syncEstimates(since: Date?, context: ModelContext) async throws {
        let dtos = try await estimateRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeEstimate(dto: dto, context: context)
        }

        // Handle soft deletes for delta sync
        if let sinceDate = since {
            let deletedIds = try await estimateRepo.fetchDeletedIds(since: sinceDate)
            for id in deletedIds {
                try markEstimateDeleted(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) estimates")
    }

    private func mergeEstimate(dto: EstimateDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .estimate,
                entityId: id,
                fields: [
                    "companyId", "estimateNumber", "title", "status", "subtotal", "taxRate",
                    "taxAmount", "total", "internalNotes", "validUntil",
                    "version", "clientId", "projectId", "opportunityId", "deletedAt"
                ],
                context: context
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

            // Mark for targeted Spotlight update — deletion wins over upsert
            if existing.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.estimate, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.estimate, id: id)
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)

            if model.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.estimate, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.estimate, id: id)
            }
        }

        try context.save()
    }

    private func markEstimateDeleted(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            spotlightTracker.markDeleted(domain: SpotlightDomain.estimate, id: id)
            try context.save()
        }
    }

    // MARK: - Invoice Sync

    private func syncInvoices(since: Date?, context: ModelContext) async throws {
        let dtos = try await invoiceRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeInvoice(dto: dto, context: context)
            try mergeInvoiceLineItems(dto: dto, context: context)
            try mergeInvoicePayments(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await invoiceRepo.fetchDeletedIds(since: sinceDate)
            for id in deletedIds {
                try markInvoiceDeleted(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) invoices")
    }

    private func mergeInvoice(dto: InvoiceDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .invoice,
                entityId: id,
                fields: [
                    "companyId", "invoiceNumber", "title", "status", "subtotal", "taxRate",
                    "taxAmount", "total", "amountPaid", "balanceDue",
                    "dueDate", "sentAt", "paidAt", "clientId", "projectId",
                    "estimateId", "opportunityId", "deletedAt"
                ],
                context: context
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

            // Mark for targeted Spotlight update — deletion wins over upsert
            if existing.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.invoice, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.invoice, id: id)
            }
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)

            if model.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.invoice, id: id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.invoice, id: id)
            }
        }

        try context.save()
    }

    private func mergeInvoiceLineItems(dto: InvoiceDTO, context: ModelContext) throws {
        let freshItems = dto.lineItems ?? []
        let freshIds: Set<String> = Set(freshItems.map { $0.id })
        let invoiceId = dto.id

        // Upsert: insert new, update existing
        for liDTO in freshItems {
            let liId = liDTO.id
            let descriptor = FetchDescriptor<InvoiceLineItem>(
                predicate: #Predicate { $0.id == liId }
            )
            if let existing = try context.fetch(descriptor).first {
                // Update fields from server. `invoiceId` is immutable so not written.
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
                context.insert(liDTO.toModel())
            }
        }

        // Delete: any local item for this invoice no longer on the server
        let localDescriptor = FetchDescriptor<InvoiceLineItem>(
            predicate: #Predicate { $0.invoiceId == invoiceId }
        )
        let local = (try? context.fetch(localDescriptor)) ?? []
        for item in local where !freshIds.contains(item.id) {
            context.delete(item)
        }

        try context.save()
    }

    private func mergeInvoicePayments(dto: InvoiceDTO, context: ModelContext) throws {
        let freshPayments = dto.payments ?? []
        let freshIds: Set<String> = Set(freshPayments.map { $0.id })
        let invoiceId = dto.id

        for pDTO in freshPayments {
            let pId = pDTO.id
            let descriptor = FetchDescriptor<Payment>(
                predicate: #Predicate { $0.id == pId }
            )
            if let existing = try context.fetch(descriptor).first {
                let fresh = pDTO.toModel()
                existing.amount = fresh.amount
                existing.method = fresh.method
                existing.paidAt = fresh.paidAt
                existing.notes = fresh.notes
            } else {
                context.insert(pDTO.toModel())
            }
        }

        // Delete local payments the server has removed
        let localDescriptor = FetchDescriptor<Payment>(
            predicate: #Predicate { $0.invoiceId == invoiceId }
        )
        let local = (try? context.fetch(localDescriptor)) ?? []
        for payment in local where !freshIds.contains(payment.id) {
            context.delete(payment)
        }

        try context.save()
    }

    private func markInvoiceDeleted(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            spotlightTracker.markDeleted(domain: SpotlightDomain.invoice, id: id)
            try context.save()
        }
    }

    // MARK: - Calendar User Events (Bug 1)

    /// Pull the current user's CalendarUserEvents from the server and merge them
    /// into the local SwiftData store. Fetches a ±12-month window around today
    /// so all relevant time-off and personal events are available offline.
    private func syncCalendarUserEvents(context: ModelContext) async throws {
        let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
        guard !userId.isEmpty else { return }

        let cal = Calendar.current
        let now = Date()
        guard let windowStart = cal.date(byAdding: .year, value: -1, to: now),
              let windowEnd   = cal.date(byAdding: .year, value: 1,  to: now) else { return }

        let dtos = try await calendarUserEventRepo.fetchForUser(userId, from: windowStart, to: windowEnd)

        for dto in dtos {
            let eventId = dto.id
            let descriptor = FetchDescriptor<CalendarUserEvent>(
                predicate: #Predicate { $0.id == eventId }
            )
            if let existing = try context.fetch(descriptor).first {
                // Respect pending local edits — only overwrite if no pending sync
                if !existing.needsSync {
                    existing.title      = dto.title
                    existing.startDate  = dto.startDate
                    existing.endDate    = dto.endDate
                    existing.allDay     = dto.allDay
                    existing.notes      = dto.notes
                    existing.status     = dto.status
                    existing.reviewedBy = dto.reviewedBy
                    existing.reviewedAt = dto.reviewedAt
                    existing.deletedAt  = dto.deletedAt
                    existing.seriesId   = dto.seriesId
                    existing.lastSyncedAt = Date()
                }
            } else {
                // Insert new event (skip soft-deleted rows from server)
                guard dto.deletedAt == nil else { continue }
                context.insert(dto.toModel())
            }
        }

        try context.save()

        // Notify calendar views that user events have changed
        NotificationCenter.default.post(name: Notification.Name("CalendarUserEventsDidChange"), object: nil)
        print("[InboundProcessor] Synced \(dtos.count) calendar user events for user \(userId)")
    }

    // MARK: - Inventory Units

    private func syncInventoryUnits(since: Date?, context: ModelContext) async throws {
        let dtos = try await inventoryRepo.fetchUnitsForSync(since: since)
        for dto in dtos {
            try mergeInventoryUnit(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await inventoryRepo.fetchDeletedUnitIds(since: sinceDate)
            for id in deletedIds {
                try markInventoryUnitDeleted(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) inventory units")
    }

    private func mergeInventoryUnit(dto: InventoryUnitReadDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventoryUnit>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .inventoryUnit,
                entityId: id,
                fields: ["companyId", "display", "isDefault", "sortOrder", "deletedAt"],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    private func markInventoryUnitDeleted(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<InventoryUnit>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    // MARK: - Inventory Tags

    private func syncInventoryTags(since: Date?, context: ModelContext) async throws {
        let dtos = try await inventoryRepo.fetchTagsForSync(since: since)
        for dto in dtos {
            try mergeInventoryTag(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await inventoryRepo.fetchDeletedTagIds(since: sinceDate)
            for id in deletedIds {
                try markInventoryTagDeleted(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) inventory tags")
    }

    private func mergeInventoryTag(dto: InventoryTagReadDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventoryTag>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .inventoryTag,
                entityId: id,
                fields: ["companyId", "name", "warningThreshold", "criticalThreshold", "deletedAt"],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    private func markInventoryTagDeleted(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<InventoryTag>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    // MARK: - Inventory Items

    /// Pulls inventory items + the item↔tag join table and rebuilds `tagIds` on each item.
    /// `tagIds` is the source of truth for the SwiftData `tags` relationship, which is
    /// then wired up in `linkAllRelationships`.
    private func syncInventoryItems(since: Date?, context: ModelContext) async throws {
        let dtos = try await inventoryRepo.fetchItemsForSync(since: since)
        for dto in dtos {
            try mergeInventoryItem(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await inventoryRepo.fetchDeletedItemIds(since: sinceDate)
            for id in deletedIds {
                try markInventoryItemDeleted(id: id, context: context)
            }
        }

        // Always refresh the join table — it has no timestamps, so there's no delta.
        // Cost: a single small query (~hundreds of rows max per company).
        try await refreshInventoryItemTags(context: context)

        print("[InboundProcessor] Merged \(dtos.count) inventory items")
    }

    private func mergeInventoryItem(dto: InventoryItemReadDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .inventoryItem,
                entityId: id,
                fields: [
                    "companyId", "name", "itemDescription", "quantity", "unitId",
                    "sku", "notes", "imageUrl",
                    "warningThreshold", "criticalThreshold", "deletedAt"
                ],
                context: context
            )
            if accept.contains("companyId")          { existing.companyId = dto.companyId }
            if accept.contains("name")               { existing.name = dto.name }
            if accept.contains("itemDescription")    { existing.itemDescription = dto.description }
            if accept.contains("quantity")           { existing.quantity = dto.quantity }
            if accept.contains("unitId")             { existing.unitId = dto.unitId }
            if accept.contains("sku")                { existing.sku = dto.sku }
            if accept.contains("notes")              { existing.notes = dto.notes }
            if accept.contains("imageUrl")           { existing.imageUrl = dto.imageUrl }
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
            context.insert(model)
        }

        try context.save()
    }

    private func markInventoryItemDeleted(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    /// Pulls every (item_id, tag_id) row for this company and rewrites each item's
    /// `tagIds` array. The relationship array (`item.tags`) is wired up later by
    /// `linkAllRelationships` once Tag rows are present locally.
    private func refreshInventoryItemTags(context: ModelContext) async throws {
        let joinRows = try await inventoryRepo.fetchItemTagsForCompany()

        // Group tag IDs by item ID.
        var tagsByItem: [String: [String]] = [:]
        for row in joinRows {
            tagsByItem[row.itemId, default: []].append(row.tagId)
        }

        // Apply to every local item belonging to this company. Items not in the
        // join map get an empty array so removed tags clear out.
        let descriptor = FetchDescriptor<InventoryItem>()
        let items = try context.fetch(descriptor)
        for item in items where item.companyId == self.companyId {
            let serverTagIds = (tagsByItem[item.id] ?? []).sorted()
            let localTagIds = item.tagIds.sorted()
            if serverTagIds != localTagIds && !hasPendingOperations(entityType: .inventoryItem, entityId: item.id, context: context) {
                item.tagIds = serverTagIds
            }
        }
        try context.save()
    }

    // MARK: - Inventory Snapshots

    /// Snapshots are append-only — no updates, no soft-deletes. Just upsert by id.
    private func syncInventorySnapshots(since: Date?, context: ModelContext) async throws {
        let dtos = try await inventoryRepo.fetchSnapshotsForSync(since: since)
        for dto in dtos {
            try mergeInventorySnapshot(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) inventory snapshots")
    }

    private func mergeInventorySnapshot(dto: InventorySnapshotReadDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<InventorySnapshot>(
            predicate: #Predicate { $0.id == id }
        )
        if try context.fetch(descriptor).first == nil {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
            try context.save()
        }
    }

    // MARK: - Inventory Snapshot Items

    /// Snapshot items are immutable. For any local snapshot belonging to this company
    /// whose item list is empty, pull its rows in one batched query.
    private func syncInventorySnapshotItems(context: ModelContext) async throws {
        let snapshotDescriptor = FetchDescriptor<InventorySnapshot>()
        let snapshots = try context.fetch(snapshotDescriptor).filter { $0.companyId == self.companyId }

        let snapshotsNeedingItems = snapshots.filter { ($0.items?.isEmpty ?? true) && $0.itemCount > 0 }
        guard !snapshotsNeedingItems.isEmpty else {
            print("[InboundProcessor] No snapshots need item backfill")
            return
        }

        let snapshotIds = snapshotsNeedingItems.map { $0.id }
        let dtos = try await inventoryRepo.fetchSnapshotItemsForSnapshots(snapshotIds)

        // Insert any items not already present locally.
        let allItemIds = Set(dtos.map { $0.id })
        let existingDescriptor = FetchDescriptor<InventorySnapshotItem>(
            predicate: #Predicate { allItemIds.contains($0.id) }
        )
        let existingItems = try context.fetch(existingDescriptor)
        let existingIds = Set(existingItems.map { $0.id })

        for dto in dtos where !existingIds.contains(dto.id) {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()

        print("[InboundProcessor] Merged \(dtos.count) snapshot items across \(snapshotIds.count) snapshots")
    }
}
