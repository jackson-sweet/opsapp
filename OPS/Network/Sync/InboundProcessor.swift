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

    // MARK: - Init

    init() {
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")
            ?? UserDefaults.standard.string(forKey: "company_id")
            ?? ""
        self.companyId = companyId

        self.projectRepo = ProjectRepository(companyId: companyId)
        self.taskRepo = TaskRepository(companyId: companyId)
        self.userRepo = UserRepository(companyId: companyId)
        self.clientRepo = ClientRepository(companyId: companyId)
        self.companyRepo = CompanyRepository()
        self.taskTypeRepo = TaskTypeRepository(companyId: companyId)
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
        self.projectRepo = ProjectRepository(companyId: newCompanyId)
        self.taskRepo = TaskRepository(companyId: newCompanyId)
        self.userRepo = UserRepository(companyId: newCompanyId)
        self.clientRepo = ClientRepository(companyId: newCompanyId)
        self.companyRepo = CompanyRepository()
        self.taskTypeRepo = TaskTypeRepository(companyId: newCompanyId)
    }

    // MARK: - Sync Priority Order

    /// Entity types processed during full/delta sync, ordered by syncPriority
    /// to satisfy foreign key dependencies.
    private static let syncOrder: [SyncEntityType] = [
        .company,
        .user,
        .client,
        .taskType,
        .project,
        .projectTask
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

        onProgress?(.projectTask, 1.0)
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

        for entityType in Self.syncOrder {
            let sinceDate = since[entityType]
            // For delta sync, only fetch entity types that have a since date
            guard sinceDate != nil else { continue }

            print("[InboundProcessor] Delta syncing \(entityType.rawValue) since \(sinceDate!)")
            try await syncEntityType(entityType, since: sinceDate, context: context)
        }

        // Re-link relationships after pulling updates
        linkAllRelationships(context: context)

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

    private func syncCompany(context: ModelContext) async throws {
        guard !companyId.isEmpty else {
            print("[InboundProcessor] No companyId — skipping company sync")
            return
        }

        let dto = try await companyRepo.fetch(companyId: companyId)
        try mergeCompany(dto: dto, context: context)
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
        let dtos = try await clientRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeClient(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) clients")
    }

    private func mergeClient(dto: SupabaseClientDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.id == id }
        )

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
            existing.needsSync = false
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
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
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }

        try context.save()
    }

    // MARK: - Project Sync

    private func syncProjects(since: Date?, context: ModelContext) async throws {
        let dtos = try await projectRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeProject(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) projects")
    }

    private func mergeProject(dto: SupabaseProjectDTO, context: ModelContext) throws {
        let id = dto.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try context.fetch(descriptor).first {
            let accept = acceptableFields(
                entityType: .project,
                entityId: id,
                fields: [
                    "title", "status", "companyId", "clientId", "opportunityId",
                    "address", "latitude", "longitude",
                    "startDate", "endDate", "duration",
                    "notes", "projectDescription", "allDay",
                    "teamMemberIdsString", "projectImagesString", "deletedAt"
                ],
                context: context
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
            // Only clear needsSync if there's nothing pending locally
            if !existing.needsSync {
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

    // MARK: - Task Sync

    private func syncTasks(since: Date?, context: ModelContext) async throws {
        let dtos = try await taskRepo.fetchAll(since: since)
        for dto in dtos {
            try mergeTask(dto: dto, context: context)
        }
        print("[InboundProcessor] Merged \(dtos.count) tasks")
    }

    private func mergeTask(dto: SupabaseProjectTaskDTO, context: ModelContext) throws {
        let id = dto.id
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
            // Only clear needsSync if there's nothing pending locally
            if !existing.needsSync {
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

        do {
            try context.save()
            print("[InboundProcessor] Relationships linked")
        } catch {
            print("[InboundProcessor] ⚠️ Relationship linking save failed: \(error) — rolling back")
            context.rollback()
        }
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
}
