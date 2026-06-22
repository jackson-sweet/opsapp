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
    private var projectPhotoRepo: ProjectPhotoRepository
    private var photoAnnotationRepo: PhotoAnnotationRepository
    private var deckDesignRepo: DeckDesignRepository
    private var wizardStateRepo: WizardStateRepository
    private var invoiceRepo: InvoiceRepository
    private var estimateRepo: EstimateRepository
    private var calendarUserEventRepo: CalendarUserEventRepository
    private var catalogRepo: CatalogRepository
    private var catalogStockUnitRepo: CatalogStockUnitRepository
    private var catalogStockUnitEventRepo: CatalogStockUnitEventRepository
    private var catalogProductOptionMappingRepo: CatalogProductOptionMappingRepository
    private var productRepo: ProductRepository
    private var productRichnessRepo: ProductRichnessRepository
    private var defaultProductRepo: CompanyDefaultProductRepository
    private var orderRepo: CatalogOrderRepository

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
        self.projectPhotoRepo = ProjectPhotoRepository(companyId: companyId)
        self.photoAnnotationRepo = PhotoAnnotationRepository(companyId: companyId)
        self.deckDesignRepo = DeckDesignRepository(companyId: companyId)
        self.wizardStateRepo = WizardStateRepository(userId: userId)
        self.invoiceRepo = InvoiceRepository(companyId: companyId)
        self.estimateRepo = EstimateRepository(companyId: companyId)
        self.calendarUserEventRepo = CalendarUserEventRepository(companyId: companyId)
        self.catalogRepo = CatalogRepository(companyId: companyId)
        self.catalogStockUnitRepo = CatalogStockUnitRepository(companyId: companyId)
        self.catalogStockUnitEventRepo = CatalogStockUnitEventRepository(companyId: companyId)
        self.catalogProductOptionMappingRepo = CatalogProductOptionMappingRepository(companyId: companyId)
        self.productRepo = ProductRepository(companyId: companyId)
        self.productRichnessRepo = ProductRichnessRepository(companyId: companyId)
        self.defaultProductRepo = CompanyDefaultProductRepository(companyId: companyId)
        self.orderRepo = CatalogOrderRepository(companyId: companyId)
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
        self.projectPhotoRepo = ProjectPhotoRepository(companyId: newCompanyId)
        self.photoAnnotationRepo = PhotoAnnotationRepository(companyId: newCompanyId)
        self.deckDesignRepo = DeckDesignRepository(companyId: newCompanyId)
        self.wizardStateRepo = WizardStateRepository(userId: newUserId)
        self.invoiceRepo = InvoiceRepository(companyId: newCompanyId)
        self.estimateRepo = EstimateRepository(companyId: newCompanyId)
        self.calendarUserEventRepo = CalendarUserEventRepository(companyId: newCompanyId)
        self.catalogRepo = CatalogRepository(companyId: newCompanyId)
        self.catalogStockUnitRepo = CatalogStockUnitRepository(companyId: newCompanyId)
        self.catalogStockUnitEventRepo = CatalogStockUnitEventRepository(companyId: newCompanyId)
        self.catalogProductOptionMappingRepo = CatalogProductOptionMappingRepository(companyId: newCompanyId)
        self.productRepo = ProductRepository(companyId: newCompanyId)
        self.productRichnessRepo = ProductRichnessRepository(companyId: newCompanyId)
        self.defaultProductRepo = CompanyDefaultProductRepository(companyId: newCompanyId)
        self.orderRepo = CatalogOrderRepository(companyId: newCompanyId)
    }

    // MARK: - Sync Priority Order

    /// Entity types processed during full/delta sync, ordered by syncPriority
    /// to satisfy foreign key dependencies. New catalog setup tables stay in
    /// order here but are filtered by CatalogSchemaCapabilityGate until the
    /// target schema proves they exist.
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
        .projectPhoto,
        .photoAnnotation,
        .deckDesign,
        .estimate,
        .invoice,
        .calendarUserEvent,   // Bug 1 — user-created time-off / personal events
        // Catalog backbone — units/tags/categories before items, items before
        // their option/value/variant/junction children.
        .catalogCategory,
        .catalogUnit,
        .catalogTag,
        .catalogItem,
        .catalogOption,
        .catalogOptionValue,
        .catalogVariant,
        .catalogStockUnit,
        .catalogStockUnitEvent,
        .catalogVariantOptionValue,
        .catalogItemTag,
        .catalogSnapshot,
        .catalogSnapshotItem,
        // Product configurability layers
        .product,
        .productOption,
        .productOptionValue,
        .catalogProductOptionMapping,
        .productPricingModifier,
        .productMaterial,
        .productBundleItem,
        // Adapter + restock orders (depend on Products / catalog variants).
        .companyDefaultProduct,
        .catalogOrder,
        .catalogOrderItem
    ]

    // MARK: - Full Sync

    /// Pull ALL entities from Supabase in dependency order and merge into local SwiftData.
    /// Returns the set of entity types whose sync THREW (and was isolated). The
    /// caller (SyncEngine) must NOT advance the last-sync cursor for these —
    /// advancing past a transient failure strands every existing row of that
    /// entity. Mirrors `DataActor.fullSync`.
    @discardableResult
    func fullSync(
        context: ModelContext,
        onProgress: ((SyncEntityType, Double) -> Void)? = nil
    ) async throws -> Set<SyncEntityType> {
        // Auto-reconfigure if companyId was empty at init time
        if companyId.isEmpty { reconfigure() }
        guard !companyId.isEmpty else {
            print("[InboundProcessor] FULL SYNC ABORTED — no companyId available")
            return []
        }
        print("[InboundProcessor] ======== FULL SYNC STARTED ========")
        var failedEntities = Set<SyncEntityType>()

        // Reset Spotlight tracker at sync start
        spotlightTracker.reset()

        let capabilities = await CatalogSchemaCapabilityGate.refresh(companyId: companyId)
        let order = Self.syncOrder.filter { capabilities.supportsSync($0) }
        let totalSteps = Double(order.count)

        for (index, entityType) in order.enumerated() {
            let stepProgress = Double(index) / totalSteps
            onProgress?(entityType, stepProgress)

            print("[InboundProcessor] Syncing \(entityType.rawValue)...")
            do {
                try await syncEntityType(entityType, since: nil, context: context)
                print("[InboundProcessor] \(entityType.rawValue) complete")
            } catch {
                // Bug 2837ddae fix: isolate failures to one entity type so a
                // single bad row doesn't abort the entire sync. Telemetry
                // captures the failure for offline diagnosis.
                print("[InboundProcessor] FAILED \(entityType.rawValue): \(error)")
                failedEntities.insert(entityType)
                SyncTelemetry.logError(
                    entityType: entityType.rawValue,
                    error: error,
                    isFullSync: true,
                    companyId: companyId,
                    userId: SupabaseService.shared.currentUserId
                )
            }
        }

        // Link relationships after all entities are pulled
        print("[InboundProcessor] Linking relationships...")
        linkAllRelationships(context: context)

        // Reconcile threshold rail notification (Phase 9). Wrapped in its
        // own try-island so a notification failure can never break sync.
        await reconcileThresholdNotifications(context: context)

        // Dispatch targeted Spotlight index updates based on what this sync touched.
        // Only runs after initial backfill — first-run indexing is coordinated by
        // SpotlightBackfillCoordinator which runs a full bulk index.
        if SpotlightIndexManager.shared.hasCompletedInitialBackfill {
            await spotlightTracker.dispatch(context: context)
        }

        onProgress?(.photoAnnotation, 1.0)
        print("[InboundProcessor] ======== FULL SYNC COMPLETED ========")
        return failedEntities
    }

    // MARK: - Delta Sync

    /// Pull entities updated since the given timestamps and merge into local SwiftData.
    /// Returns the set of entity types whose delta sync THREW (and was isolated).
    /// SyncEngine must NOT advance the last-sync cursor for these (see `fullSync`).
    @discardableResult
    func deltaSync(
        context: ModelContext,
        since: [SyncEntityType: Date]
    ) async throws -> Set<SyncEntityType> {
        // Auto-reconfigure if companyId was empty at init time
        if companyId.isEmpty { reconfigure() }
        guard !companyId.isEmpty else {
            print("[InboundProcessor] DELTA SYNC ABORTED — no companyId available")
            return []
        }
        print("[InboundProcessor] ======== DELTA SYNC STARTED ========")
        var failedEntities = Set<SyncEntityType>()

        // Reset Spotlight tracker at sync start
        spotlightTracker.reset()

        let capabilities = await CatalogSchemaCapabilityGate.refresh(companyId: companyId)

        for entityType in Self.syncOrder {
            guard capabilities.supportsSync(entityType) else { continue }
            let sinceDate = since[entityType]
            // For delta sync, only fetch entity types that have a since date
            guard sinceDate != nil else { continue }

            print("[InboundProcessor] Delta syncing \(entityType.rawValue) since \(sinceDate!)")
            do {
                try await syncEntityType(entityType, since: sinceDate, context: context)
            } catch {
                print("[InboundProcessor] FAILED delta \(entityType.rawValue): \(error)")
                failedEntities.insert(entityType)
                SyncTelemetry.logError(
                    entityType: entityType.rawValue,
                    error: error,
                    isFullSync: false,
                    companyId: companyId,
                    userId: SupabaseService.shared.currentUserId
                )
            }
        }

        // Re-link relationships after pulling updates
        linkAllRelationships(context: context)

        // Reconcile threshold rail notification (Phase 9). Wrapped in its
        // own try-island so a notification failure can never break sync.
        await reconcileThresholdNotifications(context: context)

        // Dispatch targeted Spotlight index updates for the delta
        if SpotlightIndexManager.shared.hasCompletedInitialBackfill {
            await spotlightTracker.dispatch(context: context)
        }

        print("[InboundProcessor] ======== DELTA SYNC COMPLETED ========")
        return failedEntities
    }

    // MARK: - Threshold Notifications (Phase 9)

    /// Recompute the order suggestion list at end-of-sync and ensure the
    /// notification rail reflects current state:
    ///   - count == 0 → mark all unread `threshold_alert` entries as read
    ///     so the rail clears once stock is restored.
    ///   - count > 0 → ensure exactly one unread `threshold_alert` exists.
    ///
    /// Wrapped in a single do/catch — a failure here never breaks sync.
    /// The notification table mutation is idempotent (`hasUnreadOfType`
    /// gate) so retries on next sync are safe.
    private func reconcileThresholdNotifications(context: ModelContext) async {
        guard let userId = SupabaseService.shared.currentUserId, !userId.isEmpty else {
            return
        }
        let companyId = self.companyId
        guard !companyId.isEmpty else { return }

        let variants = (try? context.fetch(FetchDescriptor<CatalogVariant>())) ?? []
        let families = (try? context.fetch(FetchDescriptor<CatalogItem>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<CatalogCategory>())) ?? []

        let scopedVariants = variants.filter { $0.companyId == companyId }
        let scopedFamilies = families.filter { $0.companyId == companyId }
        let scopedCategories = categories.filter { $0.companyId == companyId }

        let suggestions = OrderSuggestionEngine().suggest(
            variants: scopedVariants,
            families: scopedFamilies,
            categories: scopedCategories
        )
        let count = suggestions.count

        do {
            if count == 0 {
                try await NotificationRepository.shared.markAllAsReadByType(
                    type: "threshold_alert",
                    userId: userId
                )
                print("[InboundProcessor] threshold reconcile: 0 below — cleared rail")
            } else {
                let exists = try await NotificationRepository.shared.hasUnreadOfType(
                    type: "threshold_alert",
                    userId: userId
                )
                if !exists {
                    let dto = NotificationRepository.CreateNotificationDTO(
                        userId: userId,
                        companyId: companyId,
                        type: "threshold_alert",
                        title: "// \(count) ITEM\(count == 1 ? "" : "S") BELOW THRESHOLD",
                        body: "Tap to review and draft an order.",
                        deepLinkType: "catalogOrders",
                        persistent: true,
                        actionUrl: "ops://catalog/orders?tab=suggested",
                        actionLabel: "REVIEW"
                    )
                    try await NotificationRepository.shared.createNotification(dto)
                    print("[InboundProcessor] threshold reconcile: created rail entry for \(count) item(s)")
                } else {
                    print("[InboundProcessor] threshold reconcile: \(count) below; existing rail entry kept")
                }
            }
        } catch {
            print("[InboundProcessor] threshold reconcile failed: \(error)")
        }
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
        case .projectPhoto:
            try await syncProjectPhotos(since: since, context: context)
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
        case .catalogCategory:
            try await syncCatalogCategories(since: since, context: context)
        case .catalogUnit:
            try await syncCatalogUnits(since: since, context: context)
        case .catalogTag:
            try await syncCatalogTags(since: since, context: context)
        case .catalogItem:
            try await syncCatalogItems(since: since, context: context)
        case .catalogVariant:
            try await syncCatalogVariants(since: since, context: context)
        case .catalogStockUnit:
            guard CatalogSchemaCapabilityGate.supportsSync(.catalogStockUnit) else { return }
            try await syncCatalogStockUnits(since: since, context: context)
        case .catalogStockUnitEvent:
            guard CatalogSchemaCapabilityGate.supportsSync(.catalogStockUnitEvent) else { return }
            try await syncCatalogStockUnitEvents(since: since, context: context)
        case .catalogOption:
            try await syncCatalogOptions(context: context)
        case .catalogOptionValue:
            try await syncCatalogOptionValues(context: context)
        case .catalogVariantOptionValue:
            try await syncCatalogVariantOptionValues(context: context)
        case .catalogItemTag:
            try await syncCatalogItemTags(context: context)
        case .catalogSnapshot:
            try await syncCatalogSnapshots(since: since, context: context)
        case .catalogSnapshotItem:
            try await syncCatalogSnapshotItems(context: context)
        case .catalogOrder:
            try await syncCatalogOrders(context: context)
        case .catalogOrderItem:
            try await syncCatalogOrderItems(context: context)
        case .companyDefaultProduct:
            try await syncCompanyDefaultProducts(context: context)
        case .product:
            try await syncProducts(context: context)
        case .productOption:
            try await syncProductOptions(context: context)
        case .productOptionValue:
            try await syncProductOptionValues(context: context)
        case .catalogProductOptionMapping:
            guard CatalogSchemaCapabilityGate.supportsSync(.catalogProductOptionMapping) else { return }
            try await syncCatalogProductOptionMappings(since: since, context: context)
        case .productPricingModifier:
            try await syncProductPricingModifiers(context: context)
        case .productMaterial:
            try await syncProductMaterials(context: context)
        case .productBundleItem:
            try await syncProductBundleItems(context: context)
        case .taskTypeReminder:
            try await syncTaskTypeReminders(since: since, context: context)
        case .taskReminder:
            try await syncTaskReminders(since: since, context: context)
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
        if !dtos.isEmpty {
            InboundChangeSignal.post(entityNames: ["TaskType"])
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
        if !dtos.isEmpty {
            InboundChangeSignal.post(entityNames: ["Project"])
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
                    "title", "title_is_auto", "status", "company_id", "client_id", "opportunity_id",
                    "address", "latitude", "longitude",
                    "start_date", "end_date", "duration",
                    "notes", "description", "all_day",
                    "team_member_ids", "project_images", "deleted_at",
                    ProjectVinylOrderFields.status,
                    ProjectVinylOrderFields.orderedAt,
                    ProjectVinylOrderFields.orderedBy
                ],
                context: context
            )

            if accept.contains("title") { existing.title = dto.title }
            if accept.contains("title_is_auto") { existing.titleIsAuto = dto.titleIsAuto ?? false }
            if accept.contains("status") { existing.status = Status(rawValue: dto.status) ?? .rfq }
            if accept.contains("company_id") { existing.companyId = dto.companyId }
            if accept.contains("client_id") {
                existing.clientId = dto.clientId
                // Bug c9b9dd44 — wire the SwiftData relationship inline so
                // the JobBoard card shows the client name as soon as the
                // project upserts, instead of staying blank until the
                // end-of-sync `linkAllRelationships` pass runs. Clients
                // sync earlier in `syncOrder` so the lookup almost always
                // hits; if not, the end-of-sync pass still fixes it up.
                wireProjectClient(existing, clientId: dto.clientId, context: context)
            }
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
            try upsertProjectVinylOrderMarker(dto: dto, acceptedFields: accept, context: context)

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
            context.insert(dto.toVinylOrderMarkerModel())
            // Bug c9b9dd44 — wire the SwiftData relationship inline on
            // first insert too. `dto.toModel()` only sets `clientId`
            // (the scalar foreign key); without the relationship the
            // JobBoard card stays blank until end-of-sync linking.
            wireProjectClient(model, clientId: model.clientId, context: context)

            if model.deletedAt != nil {
                spotlightTracker.markDeleted(domain: SpotlightDomain.project, id: model.id)
            } else {
                spotlightTracker.markDirty(domain: SpotlightDomain.project, id: model.id)
            }
        }

        try context.save()
    }

    private func upsertProjectVinylOrderMarker(
        dto: SupabaseProjectDTO,
        acceptedFields: Set<String>,
        context: ModelContext
    ) throws {
        let projectId = dto.id
        let descriptor = FetchDescriptor<ProjectVinylOrderMarker>(
            predicate: #Predicate { $0.id == projectId }
        )

        if let existing = try context.fetch(descriptor).first {
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
            context.insert(marker)
        }
    }

    /// Bug c9b9dd44 — set `project.client` from `clientId` against the
    /// in-context Client cache. Mirrors the lookup the end-of-sync
    /// `linkAllRelationships` pass uses, but runs inline during the
    /// project upsert so the UI sees the client immediately. Falling
    /// through to nil when no client matches is fine — the end-of-sync
    /// pass will retry once all clients have been merged for this batch.
    private func wireProjectClient(_ project: Project, clientId: String?, context: ModelContext) {
        guard let cid = clientId, !cid.isEmpty else {
            project.client = nil
            return
        }
        if project.client?.id == cid { return }
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == cid })
        if let client = try? context.fetch(descriptor).first {
            project.client = client
        }
    }

    // MARK: - Task Sync

    private func syncTasks(since: Date?, context: ModelContext) async throws {
        let scope = PermissionStore.shared.scope(for: "tasks.view") ?? "all"
        let userId = UserDefaults.standard.string(forKey: "currentUserId")
        let dtos = try await taskRepo.fetchAll(since: since, scope: scope, userId: userId)
        for dto in dtos {
            try mergeTask(dto: dto, context: context)
        }
        if !dtos.isEmpty {
            InboundChangeSignal.post(entityNames: ["ProjectTask"])
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
                    "status", "task_notes", "custom_title", "task_color",
                    "task_type_id", "start_date", "end_date", "duration",
                    "display_order", "team_member_ids",
                    "source_line_item_id", "source_estimate_id",
                    "dependency_overrides", "start_time", "end_time", "deleted_at"
                ],
                context: context
            )

            if accept.contains("status") { existing.status = TaskStatus(rawValue: dto.status) ?? .active }
            if accept.contains("task_notes") { existing.taskNotes = dto.taskNotes }
            if accept.contains("custom_title") { existing.customTitle = dto.customTitle }
            if accept.contains("task_color") { existing.taskColor = dto.taskColor ?? "#59779F" }
            if accept.contains("task_type_id") {
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
            if accept.contains("start_date") { existing.startDate = dto.startDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("end_date") { existing.endDate = dto.endDate.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("duration") { existing.duration = dto.duration ?? 1 }
            if accept.contains("display_order") { existing.displayOrder = dto.displayOrder ?? 0 }
            if accept.contains("team_member_ids") {
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
            if accept.contains("source_line_item_id") { existing.sourceLineItemId = dto.sourceLineItemId }
            if accept.contains("source_estimate_id") { existing.sourceEstimateId = dto.sourceEstimateId }
            if accept.contains("dependency_overrides") {
                if let overrides = dto.dependencyOverrides, !overrides.isEmpty,
                   let data = try? JSONEncoder().encode(overrides),
                   let json = String(data: data, encoding: .utf8) {
                    existing.dependencyOverridesJSON = json
                }
            }
            if accept.contains("start_time") {
                if let st = dto.startTime {
                    if let parsed = Self.parseTime(st) {
                        existing.startTime = parsed
                    }
                }
            }
            if accept.contains("end_time") {
                if let et = dto.endTime {
                    if let parsed = Self.parseTime(et) {
                        existing.endTime = parsed
                    }
                }
            }
            if accept.contains("deleted_at") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

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

    // MARK: - ProjectPhoto Sync

    private func syncProjectPhotos(since: Date?, context: ModelContext) async throws {
        let dtos = try await projectPhotoRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeProjectPhoto(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) project photos")
    }

    private func mergeProjectPhoto(dto: ProjectPhotoDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .projectPhoto,
                entityId: id,
                fields: [
                    "url", "thumbnailURL", "renderedURL", "source", "caption",
                    "isClientVisible", "takenAt", "updatedAt", "deletedAt"
                ],
                context: context
            )

            if accept.contains("url") { existing.url = dto.url }
            if accept.contains("thumbnailURL") { existing.thumbnailURL = dto.thumbnailURL }
            if accept.contains("renderedURL") { existing.renderedURL = dto.renderedURL }
            if accept.contains("source") { existing.source = dto.source ?? existing.source }
            if accept.contains("caption") { existing.caption = dto.caption }
            if accept.contains("isClientVisible") { existing.isClientVisible = dto.isClientVisible ?? existing.isClientVisible }
            if accept.contains("takenAt") { existing.takenAt = dto.takenAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("updatedAt") { existing.updatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) } }
            if accept.contains("deletedAt") { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }

            existing.lastSyncedAt = Date()
            let hasPending = hasPendingOperations(entityType: .projectPhoto, entityId: existing.id, context: context)
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
                    "annotationURL", "renderedPhotoURL", "note", "updatedAt", "deletedAt", "dimensions"
                ],
                context: context
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
                fields: DeckDesign.serverMergeFields,
                context: context
            )

            existing.applyServerSnapshot(dto, accepting: accept)
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

        // Dedupe ProjectTask rows BEFORE fetching for relationship wiring. The
        // 60s origin-suppression window in mergeTask covers most echo races,
        // but a sync that runs after the window has expired (cold-start delta,
        // network reconnect after a >1min outage, etc.) can re-insert a row
        // we already hold locally — leaving two SwiftData rows with the same
        // id. Rendering paths read `project.tasks` directly so duplicates
        // visibly fan out into multiple list rows pointed at the same id.
        // The startup `cleanupDuplicateTasks` only runs once per launch; this
        // pass plugs the mid-session gap so duplicates can't accumulate
        // between launches.
        dedupeProjectTasks(in: context)

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

        // Catalog models keep relationships as id-typed scalars + first-class
        // junction entities (CatalogItemTag, CatalogVariantOptionValue), so
        // there's no SwiftData @Relationship to wire up after a sync. The
        // legacy inventory linker resolved InventoryItem.unit / .tags by id —
        // catalog data stays flat and resolves at query time.
        print("[InboundProcessor] Catalog data has no post-merge linking pass (junctions are first-class)")

        do {
            try context.save()
            print("[InboundProcessor] Relationships linked")
        } catch {
            print("[InboundProcessor] ⚠️ Relationship linking save failed: \(error) — rolling back")
            context.rollback()
        }
    }

    // MARK: - End-of-Sync Dedup

    /// Removes duplicate `ProjectTask` rows by id. Runs at the start of
    /// `linkAllRelationships` so the relationship-wiring pass sees a clean set
    /// of canonical rows. Mirrors `DataController.cleanupDuplicateTasks` —
    /// same winner-selection rule (needsSync row preferred, otherwise
    /// most-recently-synced) — but operates on the inbound sync's context
    /// instead of the main one, so it covers the mid-session gap that
    /// startup-only cleanup misses.
    ///
    /// Bug 3dba878f: project_tasks.id lacks `@Attribute(.unique)`; pre-existing
    /// hardening (lowercase canonicalization + 60s origin suppression +
    /// post-create dedupe in TaskFormSheet) prevents most new duplicates, but
    /// nothing catches a row re-inserted by a sync that runs after the 60s
    /// suppression window expires. Without this pass, the user sees one task
    /// rendered as multiple list rows pointed at the same id.
    private func dedupeProjectTasks(in context: ModelContext) {
        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
            let grouped = Dictionary(grouping: allTasks, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }
            guard !duplicateGroups.isEmpty else { return }

            var totalDeleted = 0
            for (_, copies) in duplicateGroups {
                let winnerIdx = pickFreshestProjectTaskIndex(copies)
                for (idx, dup) in copies.enumerated() where idx != winnerIdx {
                    context.delete(dup)
                    totalDeleted += 1
                }
            }

            if totalDeleted > 0 {
                print("[InboundProcessor] Deduped \(totalDeleted) ProjectTask rows across \(duplicateGroups.count) ids")
            }
        } catch {
            print("[InboundProcessor] ⚠️ ProjectTask dedup failed: \(error)")
        }
    }

    /// Winner-selection rule shared with `DataController.cleanupDuplicateTasks`:
    /// rows with `needsSync == true` win first (never discard unsynced edits),
    /// otherwise the most-recently-synced row wins.
    private func pickFreshestProjectTaskIndex(_ duplicates: [ProjectTask]) -> Int {
        var winnerIdx = 0
        for i in 1..<duplicates.count {
            let cur = duplicates[i]
            let win = duplicates[winnerIdx]

            if cur.needsSync != win.needsSync {
                if cur.needsSync { winnerIdx = i }
                continue
            }

            let curSync = cur.lastSyncedAt ?? .distantPast
            let winSync = win.lastSyncedAt ?? .distantPast
            if curSync > winSync { winnerIdx = i }
        }
        return winnerIdx
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
            try mergeEstimateLineItems(dto: dto, context: context)
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

    private func mergeEstimateLineItems(dto: EstimateDTO, context: ModelContext) throws {
        let freshItems = dto.lineItems ?? []
        let freshIds: Set<String> = Set(freshItems.map { $0.id })
        let estimateId = dto.id

        // Upsert: insert new, update existing
        for liDTO in freshItems {
            let liId = liDTO.id
            let descriptor = FetchDescriptor<EstimateLineItem>(
                predicate: #Predicate { $0.id == liId }
            )
            if let existing = try context.fetch(descriptor).first {
                // Update server-owned fields. `estimateId` is immutable so not written.
                let fresh = liDTO.toModel()
                existing.name = fresh.name
                existing.productId = fresh.productId
                existing.quantity = fresh.quantity
                existing.unit = fresh.unit
                existing.unitPrice = fresh.unitPrice
                existing.lineTotal = fresh.lineTotal
                existing.type = fresh.type
                existing.optional = fresh.optional
                existing.displayOrder = fresh.displayOrder
                existing.taskTypeId = fresh.taskTypeId
                existing.parentLineItemId = fresh.parentLineItemId
                existing.configuredOptionsJSON = fresh.configuredOptionsJSON
                existing.resolvedUnitPrice = fresh.resolvedUnitPrice
                existing.resolvedOptionsLabel = fresh.resolvedOptionsLabel
            } else {
                context.insert(liDTO.toModel())
            }
        }

        // Delete: any local item for this estimate no longer on the server
        let localDescriptor = FetchDescriptor<EstimateLineItem>(
            predicate: #Predicate { $0.estimateId == estimateId }
        )
        let local = (try? context.fetch(localDescriptor)) ?? []
        for item in local where !freshIds.contains(item.id) {
            context.delete(item)
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

    // MARK: - Catalog Categories

    private func syncCatalogCategories(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchCategoriesForSync(since: since)
        for dto in dtos {
            try mergeCatalogCategory(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await catalogRepo.fetchDeletedCategoryIds(since: sinceDate)
            for id in deletedIds {
                try tombstoneCatalogCategory(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) catalog categories")
    }

    private func mergeCatalogCategory(dto: CatalogCategoryDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogCategory,
                entityId: id,
                fields: [
                    "companyId", "name", "parentId", "sortOrder", "colorHex",
                    "defaultWarningThreshold", "defaultCriticalThreshold", "deletedAt"
                ],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    private func tombstoneCatalogCategory(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    // MARK: - Catalog Units

    /// catalog_units lacks a `fetchDeletedUnitIds` repo method; the table has a
    /// soft-delete column but no dedicated delta endpoint yet, so we'd need a
    /// repo addition to match the categories/items/variants pattern. For now,
    /// we rely on `updated_at` bumps to surface tombstones (deletedAt is part
    /// of the row payload).
    private func syncCatalogUnits(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchUnitsForSync(since: since)
        for dto in dtos {
            try mergeCatalogUnit(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) catalog units")
    }

    private func mergeCatalogUnit(dto: CatalogUnitDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogUnit>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogUnit,
                entityId: id,
                fields: [
                    "companyId", "display", "abbreviation", "dimension",
                    "isDefault", "sortOrder", "deletedAt"
                ],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - Catalog Tags

    private func syncCatalogTags(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchTagsForSync(since: since)
        for dto in dtos {
            try mergeCatalogTag(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) catalog tags")
    }

    private func mergeCatalogTag(dto: CatalogTagDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogTag>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogTag,
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

    // MARK: - Catalog Items (variant families)

    private func syncCatalogItems(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchItemsForSync(since: since)
        for dto in dtos {
            try mergeCatalogItem(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await catalogRepo.fetchDeletedItemIds(since: sinceDate)
            for id in deletedIds {
                try tombstoneCatalogItem(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) catalog items")
    }

    private func mergeCatalogItem(dto: CatalogItemDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogItem,
                entityId: id,
                fields: [
                    "companyId", "categoryId", "name", "itemDescription",
                    "defaultPrice", "defaultUnitCost",
                    "defaultWarningThreshold", "defaultCriticalThreshold",
                    "defaultUnitId", "imageUrl", "notes", "isActive", "deletedAt"
                ],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    private func tombstoneCatalogItem(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    // MARK: - Catalog Variants

    private func syncCatalogVariants(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchVariantsForSync(since: since)
        for dto in dtos {
            try mergeCatalogVariant(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await catalogRepo.fetchDeletedVariantIds(since: sinceDate)
            for id in deletedIds {
                try tombstoneCatalogVariant(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) catalog variants")
    }

    private func mergeCatalogVariant(dto: CatalogVariantDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogVariant,
                entityId: id,
                fields: [
                    "companyId", "catalogItemId", "sku", "quantity",
                    "priceOverride", "unitCostOverride",
                    "warningThreshold", "criticalThreshold", "unitId",
                    "isActive", "deletedAt"
                ],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    private func tombstoneCatalogVariant(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    // MARK: - Catalog Stock Units

    private func syncCatalogStockUnits(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogStockUnitRepo.fetchForSync(since: since)
        for dto in dtos {
            try mergeCatalogStockUnit(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await catalogStockUnitRepo.fetchDeletedIds(since: sinceDate)
            for id in deletedIds {
                try tombstoneCatalogStockUnit(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) catalog stock units")
    }

    private func mergeCatalogStockUnit(dto: CatalogStockUnitDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogStockUnit>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogStockUnit,
                entityId: id,
                fields: [
                    "companyId", "catalogVariantId", "unitKind", "label", "lotCode",
                    "widthValue", "widthUnit", "originalLengthValue",
                    "remainingLengthValue", "lengthUnit", "quantityValue",
                    "location", "status", "sourceOrderItemId", "notes", "deletedAt"
                ],
                context: context
            )
            if accept.contains("companyId")             { existing.companyId = dto.companyId }
            if accept.contains("catalogVariantId")      { existing.catalogVariantId = dto.catalogVariantId }
            if accept.contains("unitKind")              { existing.unitKind = CatalogStockUnitKind(rawValue: dto.unitKind) ?? .each }
            if accept.contains("label")                 { existing.label = dto.label }
            if accept.contains("lotCode")               { existing.lotCode = dto.lotCode }
            if accept.contains("widthValue")            { existing.widthValue = dto.widthValue }
            if accept.contains("widthUnit")             { existing.widthUnit = dto.widthUnit }
            if accept.contains("originalLengthValue")   { existing.originalLengthValue = dto.originalLengthValue }
            if accept.contains("remainingLengthValue")  { existing.remainingLengthValue = dto.remainingLengthValue }
            if accept.contains("lengthUnit")            { existing.lengthUnit = dto.lengthUnit }
            if accept.contains("quantityValue")         { existing.quantityValue = dto.quantityValue }
            if accept.contains("location")              { existing.location = dto.location }
            if accept.contains("status")                { existing.status = CatalogStockUnitStatus(rawValue: dto.status) ?? .full }
            if accept.contains("sourceOrderItemId")     { existing.sourceOrderItemId = dto.sourceOrderItemId }
            if accept.contains("notes")                 { existing.notes = dto.notes }
            if accept.contains("deletedAt")             { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }
            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? existing.updatedAt
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

    private func tombstoneCatalogStockUnit(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<CatalogStockUnit>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    // MARK: - Catalog Stock Unit Events

    /// Append-only ledger: insert-or-skip, keyed off `created_at`. No tombstone
    /// path — the table is immutable (no soft-delete column). The delta cursor
    /// overlaps the previous watermark, so re-seeing a boundary row is normal
    /// and the merge is idempotent on the unique `id`.
    private func syncCatalogStockUnitEvents(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogStockUnitEventRepo.fetchForSync(since: since)
        for dto in dtos {
            try mergeCatalogStockUnitEvent(dto: dto, context: context)
        }
        if !dtos.isEmpty { try context.save() }
        print("[InboundProcessor] Merged \(dtos.count) catalog stock unit events")
    }

    private func mergeCatalogStockUnitEvent(dto: CatalogStockUnitEventDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogStockUnitEvent>(predicate: #Predicate { $0.id == id })
        // Immutable rows: an existing event never changes, so skip on hit.
        if try context.fetch(descriptor).first != nil { return }
        let model = dto.toModel()
        model.lastSyncedAt = Date()
        model.needsSync = false
        context.insert(model)
    }

    // MARK: - Catalog Options

    /// Full reconciliation: catalog_options has no updated_at column, so we
    /// pull every option for the company and prune local rows missing from
    /// the response.
    private func syncCatalogOptions(context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchOptionsForCompany()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<CatalogOption>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                existing.catalogItemId = dto.catalogItemId
                existing.name = dto.name
                existing.sortOrder = dto.sortOrder
                existing.lastSyncedAt = Date()
                existing.needsSync = false
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                context.insert(model)
            }
        }

        // Prune local options the server no longer reports.
        let allLocal = try context.fetch(FetchDescriptor<CatalogOption>())
        let localItemIds = Set(try context.fetch(FetchDescriptor<CatalogItem>())
            .filter { $0.companyId == self.companyId }
            .map(\.id))
        for option in allLocal where localItemIds.contains(option.catalogItemId) && !serverIds.contains(option.id) {
            context.delete(option)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) catalog options")
    }

    // MARK: - Catalog Option Values

    private func syncCatalogOptionValues(context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchOptionValuesForCompany()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<CatalogOptionValue>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                existing.optionId = dto.optionId
                existing.value = dto.value
                existing.sortOrder = dto.sortOrder
                existing.lastSyncedAt = Date()
                existing.needsSync = false
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                context.insert(model)
            }
        }

        // Prune values whose option still belongs to this company but whose id
        // is no longer reported by the server.
        let localOptionIds = Set(try context.fetch(FetchDescriptor<CatalogOption>()).map(\.id))
        let allLocal = try context.fetch(FetchDescriptor<CatalogOptionValue>())
        for value in allLocal where localOptionIds.contains(value.optionId) && !serverIds.contains(value.id) {
            context.delete(value)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) catalog option values")
    }

    // MARK: - Catalog Variant ↔ Option-Value joins

    private func syncCatalogVariantOptionValues(context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchVariantOptionValuesForCompany()

        // Junction has no surrogate id from the server; uniqueness is the
        // (variantId, optionValueId) pair. Wipe + insert for variants this
        // company owns is the simplest correctness story.
        let companyVariantIds = Set(try context.fetch(FetchDescriptor<CatalogVariant>())
            .filter { $0.companyId == self.companyId }
            .map(\.id))

        let allLocal = try context.fetch(FetchDescriptor<CatalogVariantOptionValue>())
        for row in allLocal where companyVariantIds.contains(row.variantId) {
            context.delete(row)
        }

        for dto in dtos {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            context.insert(model)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) variant option-value joins")
    }

    // MARK: - Catalog Item Tags

    private func syncCatalogItemTags(context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchItemTagsForCompany()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<CatalogItemTag>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                existing.catalogItemId = dto.catalogItemId
                existing.tagId = dto.tagId
                existing.lastSyncedAt = Date()
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                context.insert(model)
            }
        }

        let companyItemIds = Set(try context.fetch(FetchDescriptor<CatalogItem>())
            .filter { $0.companyId == self.companyId }
            .map(\.id))
        let allLocal = try context.fetch(FetchDescriptor<CatalogItemTag>())
        for row in allLocal where companyItemIds.contains(row.catalogItemId) && !serverIds.contains(row.id) {
            context.delete(row)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) catalog item-tag joins")
    }

    // MARK: - Catalog Snapshots

    /// Snapshots are append-only — no updates, no soft-deletes. Just upsert by id.
    private func syncCatalogSnapshots(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogRepo.fetchSnapshotsForSync(since: since)
        for dto in dtos {
            try mergeCatalogSnapshot(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) catalog snapshots")
    }

    private func mergeCatalogSnapshot(dto: CatalogSnapshotDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogSnapshot>(predicate: #Predicate { $0.id == id })
        if try context.fetch(descriptor).first == nil {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
            try context.save()
        }
    }

    // MARK: - Catalog Snapshot Items

    /// Snapshot items are immutable. For any local snapshot belonging to this
    /// company whose item count is non-zero but whose items are missing
    /// locally, pull its rows in one batched query.
    private func syncCatalogSnapshotItems(context: ModelContext) async throws {
        let snapshots = try context.fetch(FetchDescriptor<CatalogSnapshot>())
            .filter { $0.companyId == self.companyId }

        let needsBackfill = snapshots.filter { snap in
            guard snap.itemCount > 0 else { return false }
            let snapId = snap.id
            let descriptor = FetchDescriptor<CatalogSnapshotItem>(
                predicate: #Predicate { $0.snapshotId == snapId }
            )
            let existingCount = (try? context.fetchCount(descriptor)) ?? 0
            return existingCount == 0
        }

        guard !needsBackfill.isEmpty else {
            print("[InboundProcessor] No catalog snapshots need item backfill")
            return
        }

        let snapshotIds = needsBackfill.map(\.id)
        let dtos = try await catalogRepo.fetchSnapshotItemsForSnapshots(snapshotIds)

        let allItemIds = Set(dtos.map(\.id))
        let existingDescriptor = FetchDescriptor<CatalogSnapshotItem>(
            predicate: #Predicate { allItemIds.contains($0.id) }
        )
        let existingItems = try context.fetch(existingDescriptor)
        let existingIds = Set(existingItems.map(\.id))

        for dto in dtos where !existingIds.contains(dto.id) {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) catalog snapshot items across \(snapshotIds.count) snapshots")
    }

    // MARK: - Catalog Orders

    /// CatalogOrderRepository.fetchAll filters out soft-deleted rows, so every
    /// id we see here is live. Local rows missing from the response are pruned
    /// (treated as server-side deletes) — apart from rows with pending local
    /// SyncOperations, which we leave untouched.
    private func syncCatalogOrders(context: ModelContext) async throws {
        let dtos = try await orderRepo.fetchAll()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            try mergeCatalogOrder(dto: dto, context: context)
        }

        let companyLocal = try context.fetch(FetchDescriptor<CatalogOrder>())
            .filter { $0.companyId == self.companyId }
        for order in companyLocal where !serverIds.contains(order.id) {
            if hasPendingOperations(entityType: .catalogOrder, entityId: order.id, context: context) { continue }
            order.deletedAt = Date()
            order.needsSync = false
        }
        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) catalog orders")
    }

    private func mergeCatalogOrder(dto: CatalogOrderDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogOrder>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogOrder,
                entityId: id,
                fields: [
                    "companyId", "status", "title", "supplierName", "supplierContact",
                    "expectedDeliveryDate", "notes", "createdById",
                    "sentAt", "fulfilledAt", "cancelledAt", "deletedAt"
                ],
                context: context
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
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - Catalog Order Items

    /// Pull items for every local order belonging to this company. Server is
    /// authoritative — we replace the children for each order in one pass.
    private func syncCatalogOrderItems(context: ModelContext) async throws {
        let companyOrders = try context.fetch(FetchDescriptor<CatalogOrder>())
            .filter { $0.companyId == self.companyId }

        var totalMerged = 0
        for order in companyOrders {
            let dtos = try await orderRepo.fetchOrderItems(orderId: order.id)
            let serverIds = Set(dtos.map(\.id))
            let orderId = order.id

            for dto in dtos {
                let id = dto.id
                let descriptor = FetchDescriptor<CatalogOrderItem>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
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
                    context.insert(model)
                }
                totalMerged += 1
            }

            // Remove children the server has deleted. Skip rows with pending
            // local writes — they may be in-flight inserts.
            let localChildren = try context.fetch(FetchDescriptor<CatalogOrderItem>(
                predicate: #Predicate { $0.orderId == orderId }
            ))
            for child in localChildren where !serverIds.contains(child.id) {
                if hasPendingOperations(entityType: .catalogOrderItem, entityId: child.id, context: context) { continue }
                context.delete(child)
            }
        }
        try context.save()
        print("[InboundProcessor] Merged \(totalMerged) catalog order items across \(companyOrders.count) orders")
    }

    // MARK: - Company Default Products

    private func syncCompanyDefaultProducts(context: ModelContext) async throws {
        let dtos = try await defaultProductRepo.fetchAll()
        let serverKeys = Set(dtos.map { "\($0.companyId)::\($0.componentType)" })

        for dto in dtos {
            try mergeCompanyDefaultProduct(dto: dto, context: context)
        }

        // Prune defaults the server no longer reports for this company.
        let local = try context.fetch(FetchDescriptor<CompanyDefaultProduct>())
            .filter { $0.companyId == self.companyId }
        for row in local {
            let key = "\(row.companyId)::\(row.componentType.rawValue)"
            if !serverKeys.contains(key) {
                context.delete(row)
            }
        }
        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) company default products")
    }

    private func mergeCompanyDefaultProduct(dto: CompanyDefaultProductDTO, context: ModelContext) throws {
        // Composite key: (companyId, componentType).
        let companyId = dto.companyId
        let componentTypeRaw = dto.componentType
        let descriptor = FetchDescriptor<CompanyDefaultProduct>(
            predicate: #Predicate { $0.companyId == companyId }
        )

        let existing = try context.fetch(descriptor)
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
            context.insert(model)
        }
        try context.save()
    }

    // MARK: - Products

    private func syncProducts(context: ModelContext) async throws {
        let dtos = try await productRepo.fetchAll(includeInactive: true)
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let accept = acceptableFields(
                entityType: .product,
                entityId: dto.id,
                fields: ProductSyncLocalStore.mergeFields,
                context: context
            )
            try ProductSyncLocalStore.merge(dto: dto, context: context, accepting: accept)
        }

        let localProducts = try context.fetch(FetchDescriptor<Product>())
            .filter { $0.companyId == self.companyId }
        for product in localProducts where !serverIds.contains(product.id) {
            product.isActive = false
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) products")
    }

    // MARK: - Product Options

    private func syncProductOptions(context: ModelContext) async throws {
        let dtos = try await productRichnessRepo.fetchOptionsForCompany()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<ProductOption>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
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
                context.insert(model)
            }
        }

        let companyProductIds = Set(try context.fetch(FetchDescriptor<Product>())
            .filter { $0.companyId == self.companyId }
            .map(\.id))
        let allLocal = try context.fetch(FetchDescriptor<ProductOption>())
        for option in allLocal where companyProductIds.contains(option.productId) && !serverIds.contains(option.id) {
            context.delete(option)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) product options")
    }

    // MARK: - Product Option Values

    private func syncProductOptionValues(context: ModelContext) async throws {
        let dtos = try await productRichnessRepo.fetchOptionValuesForCompany()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<ProductOptionValue>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                existing.optionId = dto.optionId
                existing.value = dto.value
                existing.sortOrder = dto.sortOrder
                existing.lastSyncedAt = Date()
                existing.needsSync = false
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                context.insert(model)
            }
        }

        let localOptionIds = Set(try context.fetch(FetchDescriptor<ProductOption>()).map(\.id))
        let allLocal = try context.fetch(FetchDescriptor<ProductOptionValue>())
        for value in allLocal where localOptionIds.contains(value.optionId) && !serverIds.contains(value.id) {
            context.delete(value)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) product option values")
    }

    // MARK: - Catalog Product Option Mappings

    private func syncCatalogProductOptionMappings(since: Date?, context: ModelContext) async throws {
        let dtos = try await catalogProductOptionMappingRepo.fetchForSync(since: since)
        for dto in dtos {
            try mergeCatalogProductOptionMapping(dto: dto, context: context)
        }

        if let sinceDate = since {
            let deletedIds = try await catalogProductOptionMappingRepo.fetchDeletedIds(since: sinceDate)
            for id in deletedIds {
                try tombstoneCatalogProductOptionMapping(id: id, context: context)
            }
        }

        print("[InboundProcessor] Merged \(dtos.count) catalog-product option mappings")
    }

    private func mergeCatalogProductOptionMapping(dto: CatalogProductOptionMappingDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogProductOptionMapping>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .catalogProductOptionMapping,
                entityId: id,
                fields: [
                    "companyId", "productId", "catalogItemId", "catalogOptionId",
                    "productOptionId", "catalogOptionValueId",
                    "productOptionValueId", "mappingKind", "deletedAt"
                ],
                context: context
            )
            if accept.contains("companyId")              { existing.companyId = dto.companyId }
            if accept.contains("productId")              { existing.productId = dto.productId }
            if accept.contains("catalogItemId")          { existing.catalogItemId = dto.catalogItemId }
            if accept.contains("catalogOptionId")        { existing.catalogOptionId = dto.catalogOptionId }
            if accept.contains("productOptionId")        { existing.productOptionId = dto.productOptionId }
            if accept.contains("catalogOptionValueId")   { existing.catalogOptionValueId = dto.catalogOptionValueId }
            if accept.contains("productOptionValueId")   { existing.productOptionValueId = dto.productOptionValueId }
            if accept.contains("mappingKind")            { existing.mappingKind = CatalogProductOptionMappingKind(rawValue: dto.mappingKind) ?? .axis }
            if accept.contains("deletedAt")              { existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) } }
            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? existing.updatedAt
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

    private func tombstoneCatalogProductOptionMapping(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<CatalogProductOptionMapping>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.deletedAt = Date()
            existing.needsSync = false
            try context.save()
        }
    }

    // MARK: - Product Pricing Modifiers

    private func syncProductPricingModifiers(context: ModelContext) async throws {
        let dtos = try await productRichnessRepo.fetchPricingModifiersForCompany()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<ProductPricingModifier>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
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
                context.insert(model)
            }
        }

        let companyProductIds = Set(try context.fetch(FetchDescriptor<Product>())
            .filter { $0.companyId == self.companyId }
            .map(\.id))
        let allLocal = try context.fetch(FetchDescriptor<ProductPricingModifier>())
        for row in allLocal where companyProductIds.contains(row.productId) && !serverIds.contains(row.id) {
            context.delete(row)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) product pricing modifiers")
    }

    // MARK: - Product Materials (recipes)

    private func syncProductMaterials(context: ModelContext) async throws {
        let dtos = try await productRichnessRepo.fetchMaterialsForCompany()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<ProductMaterial>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
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
                context.insert(model)
            }
        }

        let companyProductIds = Set(try context.fetch(FetchDescriptor<Product>())
            .filter { $0.companyId == self.companyId }
            .map(\.id))
        let allLocal = try context.fetch(FetchDescriptor<ProductMaterial>())
        for row in allLocal where companyProductIds.contains(row.productId) && !serverIds.contains(row.id) {
            context.delete(row)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) product materials")
    }

    /// Pulls bundle composition rows from public.product_bundle_items. Bundle
    /// products themselves come down via the regular Product sync (kind='package');
    /// this method only resolves the parent↔child mapping. Reconciles deletions
    /// scoped to the company's known products to avoid wiping rows for a
    /// different company's bundles.
    private func syncProductBundleItems(context: ModelContext) async throws {
        let repo = ProductBundleItemRepository(companyId: companyId)
        let dtos = try await repo.fetchAll()
        let serverIds = Set(dtos.map(\.id))

        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<ProductBundleItem>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                // Preserve pending local edits — outbound will push them.
                if existing.needsSync {
                    print("[InboundProcessor] Skipping bundle item \(id) — pending local op")
                    continue
                }
                existing.bundleProductId = dto.bundleProductId
                existing.childProductId  = dto.childProductId
                existing.quantity        = dto.quantity
                existing.relationshipKind = dto.relationshipKind.flatMap { ProductBundleRelationshipKind(rawValue: $0) } ?? .required
                existing.suggestionReason = dto.suggestionReason
                existing.compatibilitySelectorJSON = dto.compatibilitySelector?.rawJSONString
                existing.displayOrder    = dto.displayOrder
                existing.updatedAt       = SupabaseDate.parse(dto.updatedAt) ?? existing.updatedAt
                existing.deletedAt       = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
                existing.lastSyncedAt    = Date()
                existing.needsSync       = false
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                context.insert(model)
            }
        }

        // Reconcile deletions only within the current company's product space —
        // a server row that vanished means the row was hard-deleted (RESTRICT
        // FK prevents accidental cascade for child_product_id; CASCADE on
        // bundle_product_id means bundle-level deletes drop the rows server-side).
        let companyProductIds = Set(try context.fetch(FetchDescriptor<Product>())
            .filter { $0.companyId == self.companyId }
            .map(\.id))
        let allLocal = try context.fetch(FetchDescriptor<ProductBundleItem>())
        for row in allLocal where companyProductIds.contains(row.bundleProductId) && !serverIds.contains(row.id) {
            context.delete(row)
        }

        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) product bundle items")
    }

    // MARK: - Task Reminders (bug 4f00c2d7)

    /// Pulls reminder templates for this company. Templates live on a TaskType
    /// and are server-side-propagated into per-task instances via triggers.
    /// Reconciles deletions by comparing the server set to the local set for
    /// the same task_type_id space.
    private func syncTaskTypeReminders(since: Date?, context: ModelContext) async throws {
        let dtos = try await TaskReminderRepository.shared.fetchTemplates(companyId: companyId, since: since)
        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<TaskTypeReminder>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                dto.apply(to: existing)
            } else {
                context.insert(dto.makeLocalRow())
            }
        }

        // Reconcile soft-deletes from the server. Pulling only `since` may
        // miss rows that lost their deleted_at NULL → NOT NULL transition
        // outside the window, so we also accept the dto-level deleted_at flag.
        try context.save()
        print("[InboundProcessor] Merged \(dtos.count) task reminder templates")
    }

    /// Pulls reminder instances for this company. Heavy table — server-side
    /// triggers materialize one row per template per task, so we expect this
    /// to grow with project_tasks count. `since` keeps the delta small.
    private func syncTaskReminders(since: Date?, context: ModelContext) async throws {
        let dtos = try await TaskReminderRepository.shared.fetchInstances(companyId: companyId, since: since)
        for dto in dtos {
            let id = dto.id
            let descriptor = FetchDescriptor<TaskReminder>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first {
                // Skip if the local row has a pending unsynced ack/dismiss
                // (defensive — current UI always pushes immediately, but
                // sync ordering across crashes can land this state).
                if existing.needsSync {
                    print("[InboundProcessor] Skipping reminder \(id) — pending local op")
                    continue
                }
                dto.apply(to: existing)
            } else {
                context.insert(dto.makeLocalRow())
            }
        }
        try context.save()

        // Reschedule local UNCalendarNotificationTriggers for the current user
        // off the freshly synced set so iOS push reflects server state.
        await NotificationManager.shared.refreshTaskReminderSchedules(context: context)

        print("[InboundProcessor] Merged \(dtos.count) task reminder instances")
    }
}

enum ProductSyncLocalStore {
    static let mergeFields = [
        "companyId", "name", "productDescription", "type", "kind",
        "basePrice", "unitCost", "pricingUnit", "unit", "category",
        "categoryId", "sku", "thumbnailUrl", "taxable", "isActive",
        "isFavorite", "minimumCharge", "minimumQuantity",
        "showBomOnEstimate", "showInStorefront", "tieredPricingJSON",
        "taskTypeId", "taskTypeRef", "unitId", "linkedCatalogItemId",
        "bundlePricingMode", "createdAt"
    ]

    static func merge(
        dto: ProductDTO,
        context: ModelContext,
        accepting acceptedFields: Set<String>? = nil
    ) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == id })

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptedFields ?? Set(mergeFields)
            if accept.contains("companyId")             { existing.companyId = dto.companyId }
            if accept.contains("name")                  { existing.name = dto.name }
            if accept.contains("productDescription")    { existing.productDescription = dto.description }
            if accept.contains("type")                  { existing.type = dto.type.flatMap { LineItemType(rawValue: $0) } ?? .labor }
            if accept.contains("kind")                  { existing.kind = dto.kind.flatMap { ProductKind(rawValue: $0) } ?? .service }
            if accept.contains("basePrice")             { existing.basePrice = dto.basePrice }
            if accept.contains("unitCost")              { existing.unitCost = dto.unitCost }
            if accept.contains("pricingUnit")           { existing.pricingUnit = dto.pricingUnit.flatMap { ProductPricingUnit(rawValue: $0) } ?? .each }
            if accept.contains("unit")                  { existing.unit = dto.unit }
            if accept.contains("category")              { existing.category = dto.category }
            if accept.contains("categoryId")            { existing.categoryId = dto.categoryId }
            if accept.contains("sku")                   { existing.sku = dto.sku }
            if accept.contains("thumbnailUrl")          { existing.thumbnailUrl = dto.thumbnailUrl }
            if accept.contains("taxable")               { existing.taxable = dto.isTaxable ?? true }
            if accept.contains("isActive")              { existing.isActive = dto.isActive }
            if accept.contains("isFavorite")            { existing.isFavorite = dto.isFavorite }
            if accept.contains("minimumCharge")         { existing.minimumCharge = dto.minimumCharge }
            if accept.contains("minimumQuantity")       { existing.minimumQuantity = dto.minimumQuantity }
            if accept.contains("showBomOnEstimate")     { existing.showBomOnEstimate = dto.showBomOnEstimate }
            if accept.contains("showInStorefront")      { existing.showInStorefront = dto.showInStorefront }
            if accept.contains("tieredPricingJSON")     { existing.tieredPricingJSON = dto.tieredPricing?.rawJSONString }
            if accept.contains("taskTypeId")            { existing.taskTypeId = dto.taskTypeId }
            if accept.contains("taskTypeRef")           { existing.taskTypeRef = dto.taskTypeRef }
            if accept.contains("unitId")                { existing.unitId = dto.unitId }
            if accept.contains("linkedCatalogItemId")   { existing.linkedCatalogItemId = dto.linkedCatalogItemId }
            if accept.contains("bundlePricingMode")     { existing.bundlePricingMode = dto.bundlePricingMode }
            if accept.contains("createdAt")             { existing.createdAt = SupabaseDate.parse(dto.createdAt) ?? existing.createdAt }
        } else {
            context.insert(dto.toModel())
        }
    }
}
