//
//  RealtimeManager.swift
//  OPS
//
//  Manages Supabase Realtime WebSocket subscriptions.
//  Listens for INSERT/UPDATE/DELETE on all synced tables
//  and upserts changes into SwiftData via the existing DTO -> Model converters.
//

import Foundation
import SwiftData
import Supabase

@MainActor
class RealtimeManager: ObservableObject {

    // MARK: - Published State

    @Published var isConnected: Bool = false
    @Published var lastEventAt: Date?

    // MARK: - Dependencies

    private let supabase: SupabaseClient
    private var modelContext: ModelContext?
    private var channel: RealtimeChannelV2?

    private var companyId: String?

    /// Shared decoder for decoding Realtime records into DTOs.
    private let decoder = JSONDecoder()

    /// Timestamp of the last received event, used for catch-up sync on reconnect.
    private var lastSyncTimestamp: Date?

    // MARK: - Init

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    /// Configure dependencies before calling startListening().
    func configure(modelContext: ModelContext, companyId: String) {
        self.modelContext = modelContext
        self.companyId = companyId
    }

    // MARK: - Subscribe

    func startListening() async {
        guard let companyId = companyId else {
            print("[REALTIME] No companyId set, cannot subscribe")
            return
        }

        // Tear down any existing subscription before creating a new one
        await stopListening()

        let channel = supabase.channel("company-\(companyId)")

        // Core tables filtered by company_id
        let coreTablesWithCompanyFilter = [
            "projects",
            "project_tasks",
            "users",
            "clients",
            "sub_clients",
            "task_types"
        ]
        for table in coreTablesWithCompanyFilter {
            subscribeToTable(channel: channel, table: table, filter: "company_id=eq.\(companyId)")
        }

        // Companies table filters on `id`, not `company_id`
        subscribeToTable(channel: channel, table: "companies", filter: "id=eq.\(companyId)")

        // Pipeline tables (DTOs not yet implemented -- log only)
        let pipelineTables = ["opportunities", "pipeline_stage_configs", "stage_transitions"]
        for table in pipelineTables {
            subscribeToTable(channel: channel, table: table, filter: "company_id=eq.\(companyId)")
        }

        // Accounting tables (DTOs not yet implemented -- log only)
        let accountingTables = [
            "estimates", "invoices", "line_items", "payments",
            "payment_milestones", "products", "tax_rates"
        ]
        for table in accountingTables {
            subscribeToTable(channel: channel, table: table, filter: "company_id=eq.\(companyId)")
        }

        // Supporting tables (DTOs not yet implemented -- log only)
        let supportingTables = [
            "activities", "follow_ups", "notifications",
            "project_photos", "project_notes", "site_visits"
        ]
        for table in supportingTables {
            subscribeToTable(channel: channel, table: table, filter: "company_id=eq.\(companyId)")
        }

        do {
            try await channel.subscribeWithError()
            self.channel = channel
            self.isConnected = true
            print("[REALTIME] Subscribed to all channels for company \(companyId)")
        } catch {
            print("[REALTIME] Subscribe error: \(error)")
            self.isConnected = false
        }
    }

    func stopListening() async {
        guard let channel = channel else { return }
        await channel.unsubscribe()
        await supabase.removeChannel(channel)
        self.channel = nil
        isConnected = false
        print("[REALTIME] Unsubscribed from all channels")
    }

    // MARK: - Table Subscription Helper

    private func subscribeToTable(channel: RealtimeChannelV2, table: String, filter: String) {
        let _ = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: table,
            filter: filter
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleChange(table: table, action: action)
            }
        }
    }

    // MARK: - Change Routing

    private func handleChange(table: String, action: AnyAction) {
        lastEventAt = Date()
        lastSyncTimestamp = Date()

        switch action {
        case .insert(let insertAction):
            print("[REALTIME] INSERT on \(table)")
            upsertRecord(table: table, record: insertAction)

        case .update(let updateAction):
            print("[REALTIME] UPDATE on \(table)")
            upsertRecord(table: table, record: updateAction)

        case .delete(let deleteAction):
            print("[REALTIME] DELETE on \(table)")
            softDeleteRecord(table: table, action: deleteAction)
        }
    }

    // MARK: - Upsert (Insert & Update share the same path)

    /// Decodes the Realtime record into the appropriate DTO, converts to a SwiftData model,
    /// and performs a field-by-field update (or insert if new) in the model context.
    private func upsertRecord(table: String, record: some HasRecord) {
        guard let context = modelContext else { return }

        do {
            switch table {
            case "projects":
                let dto = try record.decodeRecord(as: SupabaseProjectDTO.self, decoder: decoder)
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                try upsertProject(context: context, id: dto.id, model: model)

            case "project_tasks":
                let dto = try record.decodeRecord(as: SupabaseProjectTaskDTO.self, decoder: decoder)
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                try upsertProjectTask(context: context, id: dto.id, model: model)

            case "users":
                let dto = try record.decodeRecord(as: SupabaseUserDTO.self, decoder: decoder)
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                try upsertUser(context: context, id: dto.id, model: model)

            case "clients":
                let dto = try record.decodeRecord(as: SupabaseClientDTO.self, decoder: decoder)
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                try upsertClient(context: context, id: dto.id, model: model)

            case "companies":
                let dto = try record.decodeRecord(as: SupabaseCompanyDTO.self, decoder: decoder)
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                try upsertCompany(context: context, id: dto.id, model: model)

            case "task_types":
                let dto = try record.decodeRecord(as: SupabaseTaskTypeDTO.self, decoder: decoder)
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                try upsertTaskType(context: context, id: dto.id, model: model)

            case "sub_clients":
                let dto = try record.decodeRecord(as: SupabaseSubClientDTO.self, decoder: decoder)
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                // Link parent client relationship
                let parentId = dto.parentClientId
                let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == parentId })
                if let parentClient = try? context.fetch(clientDescriptor).first {
                    model.client = parentClient
                }
                try upsertSubClient(context: context, id: dto.id, model: model)

            default:
                print("[REALTIME] Received change on \(table) (no DTO handler yet)")
            }
        } catch {
            print("[REALTIME] Error upserting record on \(table): \(error)")
        }
    }

    // MARK: - Soft Delete

    private func softDeleteRecord(table: String, action: DeleteAction) {
        guard let context = modelContext else { return }

        struct IdPayload: Decodable { let id: String }

        do {
            let payload = try action.decodeOldRecord(as: IdPayload.self, decoder: decoder)
            let id = payload.id

            switch table {
            case "projects":
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "project_tasks":
                let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "users":
                let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "clients":
                let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "companies":
                let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "task_types":
                let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "sub_clients":
                let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            default:
                print("[REALTIME] Received delete on \(table) (no handler yet)")
            }
        } catch {
            print("[REALTIME] Error handling delete on \(table): \(error)")
        }
    }

    // MARK: - Per-Type Upsert Helpers (field-by-field update to preserve relationships)

    private func upsertProject(context: ModelContext, id: String, model: Project) throws {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.title = model.title
            existing.status = model.status
            existing.companyId = model.companyId
            existing.clientId = model.clientId
            existing.opportunityId = model.opportunityId
            existing.address = model.address
            existing.latitude = model.latitude
            existing.longitude = model.longitude
            existing.startDate = model.startDate
            existing.endDate = model.endDate
            existing.duration = model.duration
            existing.notes = model.notes
            existing.projectDescription = model.projectDescription
            existing.allDay = model.allDay
            existing.teamMemberIdsString = model.teamMemberIdsString
            existing.projectImagesString = model.projectImagesString
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            if !existing.needsSync {
                existing.needsSync = false
            }
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertProjectTask(context: ModelContext, id: String, model: ProjectTask) throws {
        let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.status = model.status
            existing.taskNotes = model.taskNotes
            existing.customTitle = model.customTitle
            existing.taskColor = model.taskColor
            existing.taskTypeId = model.taskTypeId
            existing.startDate = model.startDate
            existing.endDate = model.endDate
            existing.duration = model.duration
            existing.displayOrder = model.displayOrder
            existing.teamMemberIdsString = model.teamMemberIdsString
            existing.sourceLineItemId = model.sourceLineItemId
            existing.sourceEstimateId = model.sourceEstimateId
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            if !existing.needsSync {
                existing.needsSync = false
            }
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertUser(context: ModelContext, id: String, model: User) throws {
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.firstName = model.firstName
            existing.lastName = model.lastName
            if let email = model.email { existing.email = email }
            existing.phone = model.phone
            existing.homeAddress = model.homeAddress
            existing.profileImageURL = model.profileImageURL
            existing.userColor = model.userColor
            existing.role = model.role
            existing.userType = model.userType
            existing.isCompanyAdmin = model.isCompanyAdmin
            existing.hasCompletedAppOnboarding = model.hasCompletedAppOnboarding
            existing.hasCompletedAppTutorial = model.hasCompletedAppTutorial
            existing.devPermission = model.devPermission
            existing.latitude = model.latitude
            existing.longitude = model.longitude
            existing.locationName = model.locationName
            existing.isActive = model.isActive
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertClient(context: ModelContext, id: String, model: Client) throws {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.name = model.name
            existing.email = model.email
            existing.phoneNumber = model.phoneNumber
            existing.address = model.address
            existing.latitude = model.latitude
            existing.longitude = model.longitude
            existing.profileImageURL = model.profileImageURL
            existing.notes = model.notes
            existing.companyId = model.companyId
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertCompany(context: ModelContext, id: String, model: Company) throws {
        let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.name = model.name
            existing.logoURL = model.logoURL
            existing.companyDescription = model.companyDescription
            existing.website = model.website
            existing.phone = model.phone
            existing.email = model.email
            existing.address = model.address
            existing.latitude = model.latitude
            existing.longitude = model.longitude
            existing.defaultProjectColor = model.defaultProjectColor
            existing.adminIdsString = model.adminIdsString
            existing.seatedEmployeeIds = model.seatedEmployeeIds
            existing.maxSeats = model.maxSeats
            existing.subscriptionStatus = model.subscriptionStatus
            existing.subscriptionPlan = model.subscriptionPlan
            existing.subscriptionEnd = model.subscriptionEnd
            existing.subscriptionPeriod = model.subscriptionPeriod
            existing.trialStartDate = model.trialStartDate
            existing.trialEndDate = model.trialEndDate
            existing.hasPrioritySupport = model.hasPrioritySupport
            existing.stripeCustomerId = model.stripeCustomerId
            existing.externalId = model.externalId
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertTaskType(context: ModelContext, id: String, model: TaskType) throws {
        let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.display = model.display
            existing.color = model.color
            existing.icon = model.icon
            existing.isDefault = model.isDefault
            existing.displayOrder = model.displayOrder
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertSubClient(context: ModelContext, id: String, model: SubClient) throws {
        let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.name = model.name
            existing.title = model.title
            existing.email = model.email
            existing.phoneNumber = model.phoneNumber
            existing.address = model.address
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    // MARK: - Catch-Up Sync

    /// Placeholder for incremental catch-up after a reconnection.
    /// Full implementation will fetch rows where updated_at > lastSyncTimestamp.
    func catchUpSync() async {
        guard let timestamp = lastSyncTimestamp else {
            print("[REALTIME] No last sync timestamp, full sync needed")
            return
        }
        print("[REALTIME] Catching up since \(timestamp)")
        // TODO: Incremental fetch from each table where updated_at > timestamp
    }
}
