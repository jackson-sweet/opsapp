//
//  RealtimeProcessor.swift
//  OPS
//
//  Activates Supabase Realtime via RealtimeManager with field-level
//  merge protection and reconnect catch-up. Wraps the existing
//  RealtimeManager (which has full subscription/DTO/upsert logic)
//  and adds:
//   1. Pending-operation-aware field merge (skip fields with pending SyncOperations)
//   2. Disconnect / reconnect tracking with catch-up notification
//   3. Clean start / stop lifecycle
//

import Foundation
import SwiftData
import Supabase

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when realtime reconnects after a disconnect.
    /// userInfo contains "disconnectedAt" (Date) so SyncEngine can delta-pull.
    static let realtimeNeedsCatchUp = Notification.Name("realtimeNeedsCatchUp")
}

// MARK: - RealtimeProcessor

@MainActor
final class RealtimeProcessor: ObservableObject {

    // MARK: - Published State

    @Published var isConnected: Bool = false
    var lastEventTimestamp: Date?

    // MARK: - Private State

    private var channel: RealtimeChannelV2?
    private var modelContext: ModelContext?
    private var companyId: String?
    private var disconnectedAt: Date?

    private let supabase: SupabaseClient
    private let decoder = JSONDecoder()

    /// Tables that filter on `company_id=eq.<companyId>`
    private let companyFilteredTables = [
        "projects",
        "project_tasks",
        "users",
        "clients",
        "sub_clients",
        "task_types",
        "project_notes",
        "project_photo_annotations"
    ]

    // MARK: - Init

    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    // MARK: - Start Listening

    /// Subscribe to Supabase Realtime for all core entity tables scoped to a company.
    func startListening(companyId: String, context: ModelContext) async {
        self.companyId = companyId
        self.modelContext = context

        // Tear down any previous subscription
        await stopListening()

        let channel = supabase.channel("company-\(companyId)")

        // Core entity tables filtered by company_id
        for table in companyFilteredTables {
            subscribeToTable(channel: channel, table: table, filter: "company_id=eq.\(companyId)")
        }

        // Companies table filters on `id`, not `company_id`
        subscribeToTable(channel: channel, table: "companies", filter: "id=eq.\(companyId)")

        do {
            try await channel.subscribeWithError()
            self.channel = channel
            self.isConnected = true
            print("[RealtimeProcessor] Subscribed for company \(companyId)")

            // If we had a previous disconnect, trigger catch-up
            if let disconnected = disconnectedAt {
                handleReconnect(disconnectedSince: disconnected)
                disconnectedAt = nil
            }
        } catch {
            print("[RealtimeProcessor] Subscribe error: \(error)")
            self.isConnected = false
        }
    }

    // MARK: - Stop Listening

    func stopListening() async {
        guard let channel = channel else { return }
        await channel.unsubscribe()
        await supabase.removeChannel(channel)
        self.channel = nil
        isConnected = false
        print("[RealtimeProcessor] Unsubscribed")
    }

    // MARK: - Disconnect / Reconnect

    /// Call when the WebSocket or network drops.
    func handleDisconnect() {
        guard isConnected else { return }
        disconnectedAt = Date()
        isConnected = false
        print("[RealtimeProcessor] Disconnected at \(disconnectedAt!)")
    }

    /// Post a notification so SyncEngine can delta-pull from the disconnect timestamp.
    private func handleReconnect(disconnectedSince: Date) {
        print("[RealtimeProcessor] Reconnected — requesting catch-up from \(disconnectedSince)")
        NotificationCenter.default.post(
            name: .realtimeNeedsCatchUp,
            object: nil,
            userInfo: ["disconnectedAt": disconnectedSince]
        )
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
        lastEventTimestamp = Date()

        switch action {
        case .insert(let insertAction):
            print("[RealtimeProcessor] INSERT on \(table)")
            handleUpsert(table: table, record: insertAction)

        case .update(let updateAction):
            print("[RealtimeProcessor] UPDATE on \(table)")
            handleUpsert(table: table, record: updateAction)

        case .delete(let deleteAction):
            print("[RealtimeProcessor] DELETE on \(table)")
            handleDelete(table: table, action: deleteAction)
        }
    }

    // MARK: - Upsert with Field-Level Merge

    /// Decodes the Realtime record into the appropriate DTO, converts to a SwiftData
    /// model, and performs a field-by-field update — skipping any field that has a
    /// pending SyncOperation (to preserve the local value until it syncs).
    private func handleUpsert(table: String, record: some HasRecord) {
        guard let context = modelContext else { return }

        do {
            switch table {
            case "projects":
                let dto = try record.decodeRecord(as: SupabaseProjectDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .project, entityId: dto.id, context: context)
                try upsertProject(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "project_tasks":
                let dto = try record.decodeRecord(as: SupabaseProjectTaskDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .projectTask, entityId: dto.id, context: context)
                try upsertProjectTask(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "users":
                let dto = try record.decodeRecord(as: SupabaseUserDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .user, entityId: dto.id, context: context)
                try upsertUser(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "clients":
                let dto = try record.decodeRecord(as: SupabaseClientDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .client, entityId: dto.id, context: context)
                try upsertClient(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "companies":
                let dto = try record.decodeRecord(as: SupabaseCompanyDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .company, entityId: dto.id, context: context)
                try upsertCompany(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "task_types":
                let dto = try record.decodeRecord(as: SupabaseTaskTypeDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .taskType, entityId: dto.id, context: context)
                try upsertTaskType(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "sub_clients":
                let dto = try record.decodeRecord(as: SupabaseSubClientDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .subClient, entityId: dto.id, context: context)
                // Link parent client relationship
                let parentId = dto.parentClientId
                let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == parentId })
                if let parentClient = try? context.fetch(clientDescriptor).first {
                    model.client = parentClient
                }
                try upsertSubClient(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "project_notes":
                let dto = try record.decodeRecord(as: ProjectNoteDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .projectNote, entityId: dto.id, context: context)
                try upsertProjectNote(context: context, id: dto.id, model: model, pendingFields: pendingFields)
                // Notify views listening for new project notes
                NotificationCenter.default.post(
                    name: .projectNoteReceived,
                    object: nil,
                    userInfo: ["projectId": dto.projectId]
                )

            case "project_photo_annotations":
                let dto = try record.decodeRecord(as: PhotoAnnotationDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = pendingFieldsForEntity(entityType: .photoAnnotation, entityId: dto.id, context: context)
                try upsertPhotoAnnotation(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            default:
                print("[RealtimeProcessor] Received change on \(table) (no handler)")
            }
        } catch {
            print("[RealtimeProcessor] Error upserting on \(table): \(error)")
        }
    }

    // MARK: - Soft Delete

    private func handleDelete(table: String, action: DeleteAction) {
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

            case "project_notes":
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "project_photo_annotations":
                let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            default:
                print("[RealtimeProcessor] Delete on \(table) (no handler)")
            }
        } catch {
            print("[RealtimeProcessor] Error handling delete on \(table): \(error)")
        }
    }

    // MARK: - Pending Fields Check

    /// Returns the set of field names that have pending SyncOperations for a given entity.
    /// These fields should NOT be overwritten by incoming server values.
    private func pendingFieldsForEntity(
        entityType: SyncEntityType,
        entityId: String,
        context: ModelContext
    ) -> Set<String> {
        let entityTypeRaw = entityType.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.entityType == entityTypeRaw
                && $0.entityId == entityId
                && $0.status == "pending"
            }
        )

        guard let ops = try? context.fetch(descriptor) else { return [] }

        var fields = Set<String>()
        for op in ops {
            for field in op.getChangedFields() {
                fields.insert(field)
            }
        }
        return fields
    }

    // MARK: - Per-Type Upsert Helpers (field-level merge with pending check)

    private func upsertProject(context: ModelContext, id: String, model: Project, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("title")                 { existing.title = model.title }
            if !pendingFields.contains("status")                { existing.status = model.status }
            if !pendingFields.contains("companyId")             { existing.companyId = model.companyId }
            if !pendingFields.contains("clientId")              { existing.clientId = model.clientId }
            if !pendingFields.contains("opportunityId")         { existing.opportunityId = model.opportunityId }
            if !pendingFields.contains("address")               { existing.address = model.address }
            if !pendingFields.contains("latitude")              { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")             { existing.longitude = model.longitude }
            if !pendingFields.contains("startDate")             { existing.startDate = model.startDate }
            if !pendingFields.contains("endDate")               { existing.endDate = model.endDate }
            if !pendingFields.contains("duration")              { existing.duration = model.duration }
            if !pendingFields.contains("notes")                 { existing.notes = model.notes }
            if !pendingFields.contains("projectDescription")    { existing.projectDescription = model.projectDescription }
            if !pendingFields.contains("allDay")                { existing.allDay = model.allDay }
            if !pendingFields.contains("teamMemberIdsString")   { existing.teamMemberIdsString = model.teamMemberIdsString }
            if !pendingFields.contains("projectImagesString")   { existing.projectImagesString = model.projectImagesString }
            if !pendingFields.contains("deletedAt")             { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            if !existing.needsSync { existing.needsSync = false }
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertProjectTask(context: ModelContext, id: String, model: ProjectTask, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("status")                { existing.status = model.status }
            if !pendingFields.contains("taskNotes")             { existing.taskNotes = model.taskNotes }
            if !pendingFields.contains("customTitle")           { existing.customTitle = model.customTitle }
            if !pendingFields.contains("taskColor")             { existing.taskColor = model.taskColor }
            if !pendingFields.contains("taskTypeId")            { existing.taskTypeId = model.taskTypeId }
            if !pendingFields.contains("startDate")             { existing.startDate = model.startDate }
            if !pendingFields.contains("endDate")               { existing.endDate = model.endDate }
            if !pendingFields.contains("duration")              { existing.duration = model.duration }
            if !pendingFields.contains("displayOrder")          { existing.displayOrder = model.displayOrder }
            if !pendingFields.contains("teamMemberIdsString")   { existing.teamMemberIdsString = model.teamMemberIdsString }
            if !pendingFields.contains("sourceLineItemId")      { existing.sourceLineItemId = model.sourceLineItemId }
            if !pendingFields.contains("sourceEstimateId")      { existing.sourceEstimateId = model.sourceEstimateId }
            if !pendingFields.contains("deletedAt")             { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            if !existing.needsSync { existing.needsSync = false }
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertUser(context: ModelContext, id: String, model: User, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("firstName")                 { existing.firstName = model.firstName }
            if !pendingFields.contains("lastName")                  { existing.lastName = model.lastName }
            if !pendingFields.contains("email"), let email = model.email { existing.email = email }
            if !pendingFields.contains("phone")                     { existing.phone = model.phone }
            if !pendingFields.contains("homeAddress")               { existing.homeAddress = model.homeAddress }
            if !pendingFields.contains("profileImageURL")           { existing.profileImageURL = model.profileImageURL }
            if !pendingFields.contains("userColor")                 { existing.userColor = model.userColor }
            if !pendingFields.contains("role")                      { existing.role = model.role }
            if !pendingFields.contains("userType")                  { existing.userType = model.userType }
            if !pendingFields.contains("hasCompletedAppOnboarding") { existing.hasCompletedAppOnboarding = model.hasCompletedAppOnboarding }
            if !pendingFields.contains("hasCompletedAppTutorial")   { existing.hasCompletedAppTutorial = model.hasCompletedAppTutorial }
            if !pendingFields.contains("devPermission")             { existing.devPermission = model.devPermission }
            if !pendingFields.contains("latitude")                  { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")                 { existing.longitude = model.longitude }
            if !pendingFields.contains("locationName")              { existing.locationName = model.locationName }
            if !pendingFields.contains("isActive")                  { existing.isActive = model.isActive }
            if !pendingFields.contains("deletedAt")                 { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertClient(context: ModelContext, id: String, model: Client, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("name")              { existing.name = model.name }
            if !pendingFields.contains("email")             { existing.email = model.email }
            if !pendingFields.contains("phoneNumber")       { existing.phoneNumber = model.phoneNumber }
            if !pendingFields.contains("address")           { existing.address = model.address }
            if !pendingFields.contains("latitude")          { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")         { existing.longitude = model.longitude }
            if !pendingFields.contains("profileImageURL")   { existing.profileImageURL = model.profileImageURL }
            if !pendingFields.contains("notes")             { existing.notes = model.notes }
            if !pendingFields.contains("companyId")         { existing.companyId = model.companyId }
            if !pendingFields.contains("deletedAt")         { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertCompany(context: ModelContext, id: String, model: Company, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("name")                  { existing.name = model.name }
            if !pendingFields.contains("logoURL")               { existing.logoURL = model.logoURL }
            if !pendingFields.contains("companyDescription")    { existing.companyDescription = model.companyDescription }
            if !pendingFields.contains("website")               { existing.website = model.website }
            if !pendingFields.contains("phone")                 { existing.phone = model.phone }
            if !pendingFields.contains("email")                 { existing.email = model.email }
            if !pendingFields.contains("address")               { existing.address = model.address }
            if !pendingFields.contains("latitude")              { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")             { existing.longitude = model.longitude }
            if !pendingFields.contains("defaultProjectColor")   { existing.defaultProjectColor = model.defaultProjectColor }
            if !pendingFields.contains("adminIdsString")        { existing.adminIdsString = model.adminIdsString }
            if !pendingFields.contains("seatedEmployeeIds")     { existing.seatedEmployeeIds = model.seatedEmployeeIds }
            if !pendingFields.contains("maxSeats")              { existing.maxSeats = model.maxSeats }
            if !pendingFields.contains("subscriptionStatus")    { existing.subscriptionStatus = model.subscriptionStatus }
            if !pendingFields.contains("subscriptionPlan")      { existing.subscriptionPlan = model.subscriptionPlan }
            if !pendingFields.contains("subscriptionEnd")       { existing.subscriptionEnd = model.subscriptionEnd }
            if !pendingFields.contains("subscriptionPeriod")    { existing.subscriptionPeriod = model.subscriptionPeriod }
            if !pendingFields.contains("trialStartDate")        { existing.trialStartDate = model.trialStartDate }
            if !pendingFields.contains("trialEndDate")          { existing.trialEndDate = model.trialEndDate }
            if !pendingFields.contains("hasPrioritySupport")    { existing.hasPrioritySupport = model.hasPrioritySupport }
            if !pendingFields.contains("stripeCustomerId")      { existing.stripeCustomerId = model.stripeCustomerId }
            if !pendingFields.contains("externalId")            { existing.externalId = model.externalId }
            if !pendingFields.contains("deletedAt")             { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertTaskType(context: ModelContext, id: String, model: TaskType, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("display")                    { existing.display = model.display }
            if !pendingFields.contains("color")                      { existing.color = model.color }
            if !pendingFields.contains("icon")                       { existing.icon = model.icon }
            if !pendingFields.contains("isDefault")                  { existing.isDefault = model.isDefault }
            if !pendingFields.contains("displayOrder")               { existing.displayOrder = model.displayOrder }
            if !pendingFields.contains("defaultTeamMemberIdsString") { existing.defaultTeamMemberIdsString = model.defaultTeamMemberIdsString }
            if !pendingFields.contains("deletedAt")                  { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertSubClient(context: ModelContext, id: String, model: SubClient, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("name")          { existing.name = model.name }
            if !pendingFields.contains("title")         { existing.title = model.title }
            if !pendingFields.contains("email")         { existing.email = model.email }
            if !pendingFields.contains("phoneNumber")   { existing.phoneNumber = model.phoneNumber }
            if !pendingFields.contains("address")       { existing.address = model.address }
            if !pendingFields.contains("deletedAt")     { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertProjectNote(context: ModelContext, id: String, model: ProjectNote, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("content")                   { existing.content = model.content }
            if !pendingFields.contains("attachmentsJSON")           { existing.attachmentsJSON = model.attachmentsJSON }
            if !pendingFields.contains("mentionedUserIdsString")    { existing.mentionedUserIdsString = model.mentionedUserIdsString }
            if !pendingFields.contains("updatedAt")                 { existing.updatedAt = model.updatedAt }
            if !pendingFields.contains("deletedAt")                 { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertPhotoAnnotation(context: ModelContext, id: String, model: PhotoAnnotation, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("annotationURL")     { existing.annotationURL = model.annotationURL }
            if !pendingFields.contains("note")              { existing.note = model.note }
            if !pendingFields.contains("updatedAt")         { existing.updatedAt = model.updatedAt }
            if !pendingFields.contains("deletedAt")         { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }
}
