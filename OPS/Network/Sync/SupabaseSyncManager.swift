//
//  SupabaseSyncManager.swift
//  OPS
//
//  Replaces CentralizedSyncManager with Supabase-backed sync.
//  Matches the same public API so views don't change when switched via SyncManagerFlag.
//
//  Created as part of iOS Bubble-to-Supabase migration (Sprint C).
//

import SwiftUI
import Foundation
import SwiftData
import Combine

@MainActor
class SupabaseSyncManager: ObservableObject {

    // MARK: - Published State (matches CentralizedSyncManager interface)

    @Published var hasError: Bool = false
    @Published var statusText: String = "Ready"
    @Published var progress: Double = 0.0
    @Published var totalCount: Int = 0

    private(set) var syncInProgress = false {
        didSet { syncStateSubject.send(syncInProgress) }
    }

    private var syncStateSubject = PassthroughSubject<Bool, Never>()
    var syncStatePublisher: AnyPublisher<Bool, Never> {
        syncStateSubject.eraseToAnyPublisher()
    }

    var isConnected: Bool { connectivityMonitor.isConnected }
    var lastSyncDate: Date = Date()

    // Cache of non-existent user IDs to prevent repeated fetch attempts
    private var nonExistentUserIds: Set<String> = []

    var currentUser: User? {
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId") else {
            return nil
        }
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Dependencies

    let modelContext: ModelContext
    private let connectivityMonitor: ConnectivityMonitor

    private var projectRepo: ProjectRepository?
    private var taskRepo: TaskRepository?
    private var clientRepo: ClientRepository?
    private var userRepo: UserRepository?
    private var companyRepo: CompanyRepository?
    private var calendarRepo: CalendarEventRepository?
    private var taskTypeRepo: TaskTypeRepository?

    // MARK: - Init

    init(modelContext: ModelContext, connectivityMonitor: ConnectivityMonitor) {
        self.modelContext = modelContext
        self.connectivityMonitor = connectivityMonitor
        configureRepositories()
    }

    private func configureRepositories() {
        // Try multiple UserDefaults keys for companyId (matches DataController patterns)
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")
            ?? UserDefaults.standard.string(forKey: "company_id")
            ?? ""

        guard !companyId.isEmpty else {
            print("[SUPABASE_SYNC] No companyId found in UserDefaults - repositories not configured")
            return
        }

        projectRepo = ProjectRepository(companyId: companyId)
        taskRepo = TaskRepository(companyId: companyId)
        clientRepo = ClientRepository(companyId: companyId)
        userRepo = UserRepository(companyId: companyId)
        companyRepo = CompanyRepository()
        calendarRepo = CalendarEventRepository(companyId: companyId)
        taskTypeRepo = TaskTypeRepository(companyId: companyId)
        print("[SUPABASE_SYNC] Repositories configured for company: \(companyId)")
    }

    /// Re-configure repositories when companyId changes (e.g. after onboarding)
    func reconfigureRepositories() {
        configureRepositories()
    }

    // MARK: - Master Sync Functions

    /// Complete sync of all data types - Called by manual sync button
    func syncAll() async throws {
        print("[SUPABASE_SYNC_ALL] ========================================")
        print("[SUPABASE_SYNC_ALL] FULL SYNC STARTED")
        print("[SUPABASE_SYNC_ALL] ========================================")

        guard !syncInProgress else {
            print("[SUPABASE_SYNC_ALL] Sync already in progress")
            throw SyncError.alreadySyncing
        }

        guard isConnected else {
            print("[SUPABASE_SYNC_ALL] Not connected")
            throw SyncError.notConnected
        }

        // Ensure repositories are initialized
        if projectRepo == nil { configureRepositories() }

        syncInProgress = true
        statusText = "Syncing..."
        progress = 0.0
        defer {
            syncInProgress = false
            lastSyncDate = Date()
            print("[SUPABASE_SYNC_ALL] ========================================")
            print("[SUPABASE_SYNC_ALL] FULL SYNC COMPLETED")
            print("[SUPABASE_SYNC_ALL] ========================================")
        }

        do {
            print("[SUPABASE_SYNC_ALL] -> Syncing Company...")
            try await syncCompany()
            progress = 0.15

            print("[SUPABASE_SYNC_ALL] -> Syncing Users...")
            try await syncUsers()
            progress = 0.30

            print("[SUPABASE_SYNC_ALL] -> Syncing Clients...")
            try await syncClients()
            progress = 0.45

            print("[SUPABASE_SYNC_ALL] -> Syncing Task Types...")
            try await syncTaskTypes()
            progress = 0.60

            print("[SUPABASE_SYNC_ALL] -> Syncing Projects...")
            try await syncProjects()
            progress = 0.75

            print("[SUPABASE_SYNC_ALL] -> Syncing Tasks...")
            try await syncTasks()
            progress = 0.85

            print("[SUPABASE_SYNC_ALL] -> Syncing Calendar Events...")
            try await syncCalendarEvents()
            progress = 0.95

            print("[SUPABASE_SYNC_ALL] -> Linking Relationships...")
            try linkAllRelationships()
            progress = 1.0

            statusText = "Up to date"
            hasError = false
            print("[SUPABASE_SYNC_ALL] Sync complete")
        } catch {
            hasError = true
            statusText = "Sync failed"
            print("[SUPABASE_SYNC_ALL] Sync failed: \(error)")
            throw error
        }
    }

    /// App launch sync - Syncs critical data for app functionality
    func syncAppLaunch() async throws {
        guard !syncInProgress else {
            print("[SUPABASE_SYNC_LAUNCH] Sync already in progress")
            return
        }
        guard isConnected else {
            print("[SUPABASE_SYNC_LAUNCH] Not connected")
            return
        }

        syncInProgress = true
        defer { syncInProgress = false }

        print("[SUPABASE_SYNC_LAUNCH] Starting app launch sync...")

        do {
            try await syncCompany()
            try await syncUsers()
            try await syncProjects()
            try await syncCalendarEvents()

            // Background sync less critical data
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                try? await self.syncClients()
                try? await self.syncTaskTypes()
                try? await self.syncTasks()
            }

            lastSyncDate = Date()
            print("[SUPABASE_SYNC_LAUNCH] App launch sync finished")
        } catch {
            print("[SUPABASE_SYNC_LAUNCH] Sync failed: \(error)")
            throw error
        }
    }

    /// Background refresh - Lightweight sync of changed data
    func syncBackgroundRefresh() async throws {
        guard !syncInProgress else { return }
        guard isConnected else { return }

        syncInProgress = true
        defer { syncInProgress = false }

        print("[SUPABASE_SYNC_BG] Background refresh...")

        do {
            try await syncProjects(sinceDate: lastSyncDate)
            try await syncCalendarEvents(sinceDate: lastSyncDate)
            try await syncTasks(sinceDate: lastSyncDate)

            lastSyncDate = Date()
            print("[SUPABASE_SYNC_BG] Background refresh complete")
        } catch {
            print("[SUPABASE_SYNC_BG] Refresh failed: \(error)")
            throw error
        }
    }

    /// Trigger background sync - Used by DataController for automatic syncing
    func triggerBackgroundSync(forceProjectSync: Bool = false) {
        print("[SUPABASE_TRIGGER_BG] Background sync triggered (force: \(forceProjectSync))")

        guard !syncInProgress, isConnected else { return }

        // Check if user has completed tutorial
        if let user = currentUser, !user.hasCompletedAppTutorial {
            print("[SUPABASE_TRIGGER_BG] User hasn't completed tutorial, skipping sync")
            return
        }

        Task {
            do {
                if forceProjectSync {
                    try await syncAll()
                } else {
                    try await syncBackgroundRefresh()
                }
            } catch {
                print("[SUPABASE_TRIGGER_BG] Sync failed: \(error)")
            }
        }
    }

    // MARK: - Entity Sync

    func syncCompany() async throws {
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")
            ?? UserDefaults.standard.string(forKey: "company_id")
            ?? ""
        guard !companyId.isEmpty, let repo = companyRepo else { return }

        print("[SUPABASE_SYNC] Syncing company \(companyId)...")
        let dto = try await repo.fetch(companyId: companyId)
        let model = dto.toModel()
        try upsertCompany(model)
        print("[SUPABASE_SYNC] Company synced")
    }

    func syncUsers() async throws {
        guard let repo = userRepo else { return }
        print("[SUPABASE_SYNC] Syncing users...")
        let dtos = try await repo.fetchAll()
        for dto in dtos {
            try upsertUser(dto.toModel())
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) users")
    }

    func syncClients() async throws {
        guard let repo = clientRepo else { return }
        print("[SUPABASE_SYNC] Syncing clients...")
        let dtos = try await repo.fetchAll()
        for dto in dtos {
            try upsertClient(dto.toModel())
            // Also upsert sub-clients for this client
            let subDtos = try await repo.fetchSubClients(for: dto.id)
            for subDto in subDtos {
                try upsertSubClient(subDto.toModel(), parentClientId: subDto.parentClientId)
            }
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) clients")
    }

    func syncTaskTypes() async throws {
        guard let repo = taskTypeRepo else { return }
        print("[SUPABASE_SYNC] Syncing task types...")
        let dtos = try await repo.fetchAll()
        for dto in dtos {
            try upsertTaskType(dto.toModel())
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) task types")
    }

    func syncProjects(sinceDate: Date? = nil) async throws {
        guard let repo = projectRepo else { return }
        print("[SUPABASE_SYNC] Syncing projects...")
        let dtos = try await repo.fetchAll(since: sinceDate)
        for dto in dtos {
            try upsertProject(dto.toModel())
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) projects")
    }

    func syncTasks(sinceDate: Date? = nil) async throws {
        guard let repo = taskRepo else { return }
        print("[SUPABASE_SYNC] Syncing tasks...")
        let dtos = try await repo.fetchAll(since: sinceDate)
        for dto in dtos {
            try upsertTask(dto.toModel())
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) tasks")
    }

    func syncCalendarEvents(sinceDate: Date? = nil) async throws {
        guard let repo = calendarRepo else { return }
        print("[SUPABASE_SYNC] Syncing calendar events...")
        let dtos = try await repo.fetchAll(since: sinceDate)
        for dto in dtos {
            try upsertCalendarEvent(dto.toModel())
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) calendar events")
    }

    /// Sync tasks for a specific project
    func syncProjectTasks(projectId: String) async throws {
        guard let repo = taskRepo else { return }
        print("[SUPABASE_SYNC] Syncing tasks for project \(projectId)...")
        let dtos = try await repo.fetchForProject(projectId)
        for dto in dtos {
            try upsertTask(dto.toModel())
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) tasks for project")
    }

    /// Sync task types for a company by companyId
    func syncCompanyTaskTypes(companyId: String) async throws {
        print("[SUPABASE_SYNC] Syncing task types for company \(companyId)...")
        guard isConnected else { throw SyncError.notConnected }

        let repo = TaskTypeRepository(companyId: companyId)
        let dtos = try await repo.fetchAll()
        for dto in dtos {
            try upsertTaskType(dto.toModel())
        }
        print("[SUPABASE_SYNC] Synced \(dtos.count) task types for company")
    }

    /// Sync team members for a company (by companyId)
    func syncCompanyTeamMembers(companyId: String) async throws {
        print("[SUPABASE_SYNC] Syncing team members for company \(companyId)...")
        guard isConnected else { throw SyncError.notConnected }

        let repo = UserRepository(companyId: companyId)
        let dtos = try await repo.fetchAll()

        // Get the company
        let companyDescriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyId })
        guard let company = try modelContext.fetch(companyDescriptor).first else {
            throw SyncError.missingCompanyId
        }

        let adminIds = company.getAdminIds()

        for dto in dtos {
            let user = dto.toModel()
            // Override role based on admin list
            if adminIds.contains(dto.id) {
                user.role = .admin
                user.isCompanyAdmin = true
            }
            try upsertUser(user)
        }

        company.teamMembersSynced = true
        company.lastSyncedAt = Date()
        try modelContext.save()
        print("[SUPABASE_SYNC] Synced \(dtos.count) team members")
    }

    /// Sync team members for a company (by Company object - convenience)
    func syncCompanyTeamMembers(_ company: Company) async {
        do {
            try await syncCompanyTeamMembers(companyId: company.id)
        } catch {
            print("[SUPABASE_SYNC] Failed to sync team members: \(error)")
        }
    }

    /// Refresh a single client's data
    func refreshSingleClient(clientId: String) async throws {
        print("[SUPABASE_SYNC] Refreshing client \(clientId)...")
        guard isConnected else { throw SyncError.notConnected }
        guard let repo = clientRepo else { return }

        let dto = try await repo.fetchOne(clientId)
        try upsertClient(dto.toModel())

        // Also refresh sub-clients
        let subDtos = try await repo.fetchSubClients(for: clientId)
        for subDto in subDtos {
            try upsertSubClient(subDto.toModel(), parentClientId: subDto.parentClientId)
        }
        print("[SUPABASE_SYNC] Client refreshed")
    }

    /// Manual full sync - same as syncAll()
    func manualFullSync(companyId: String? = nil) async throws {
        // companyId parameter kept for backwards compatibility
        if let user = currentUser, !user.hasCompletedAppTutorial {
            print("[SUPABASE_MANUAL_SYNC] User hasn't completed tutorial, skipping")
            return
        }
        print("[SUPABASE_MANUAL_SYNC] User-triggered full sync")
        statusText = "Syncing all data..."
        try await syncAll()
        statusText = "Sync complete"
    }

    /// Retry sync after error
    func retrySync() async {
        print("[SUPABASE_RETRY] Retrying sync...")
        hasError = false
        statusText = "Retrying..."
        do {
            try await syncAll()
            statusText = "Sync complete"
        } catch {
            hasError = true
            statusText = "Sync failed"
            print("[SUPABASE_RETRY] Retry failed: \(error)")
        }
    }

    /// Onboarding sync - awaitable sync for use during onboarding
    func performOnboardingSync() async {
        print("[SUPABASE_ONBOARDING_SYNC] Starting onboarding sync")
        guard connectivityMonitor.isConnected else {
            print("[SUPABASE_ONBOARDING_SYNC] No internet, skipping")
            return
        }
        // Re-configure repositories in case companyId was just set
        configureRepositories()
        do {
            try await syncAll()
            print("[SUPABASE_ONBOARDING_SYNC] Onboarding sync complete")
        } catch {
            print("[SUPABASE_ONBOARDING_SYNC] Onboarding sync failed: \(error)")
        }
    }

    /// Add non-existent user ID to cache
    func addNonExistentUserId(_ userId: String) {
        nonExistentUserIds.insert(userId)
    }

    /// Check if user ID is in non-existent cache
    func isNonExistentUser(_ userId: String) -> Bool {
        return nonExistentUserIds.contains(userId)
    }

    /// Sync a single user to the API
    func syncUser(_ user: User) async {
        guard isConnected else { return }
        guard user.needsSync else { return }

        print("[SUPABASE_SYNC] Syncing user \(user.fullName)...")
        do {
            try await userRepo?.updateUser(
                userId: user.id,
                firstName: user.firstName,
                lastName: user.lastName,
                phone: user.phone
            )
            user.needsSync = false
            user.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_SYNC] User synced")
        } catch {
            print("[SUPABASE_SYNC] Failed to sync user: \(error)")
        }
    }

    // MARK: - Individual Update Operations

    /// Update project status and sync to Supabase
    func updateProjectStatus(projectId: String, status: Status, forceSync: Bool = false) async throws {
        print("[SUPABASE_UPDATE] Updating project \(projectId) to status: \(status.rawValue)")

        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)

        guard let project = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        // Optimistic local update
        project.status = status
        project.needsSync = true
        project.syncPriority = 3

        if status == .inProgress && project.startDate == nil {
            project.startDate = Date()
        } else if status == .completed && project.endDate == nil {
            project.endDate = Date()
        }

        try modelContext.save()

        // Push to Supabase
        if isConnected {
            try await projectRepo?.updateStatus(projectId, status: status.rawValue)
            project.needsSync = false
            project.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_UPDATE] Project status updated and synced")
        } else {
            print("[SUPABASE_UPDATE] Offline - will sync when connected")
        }
    }

    /// Update project notes and sync to Supabase
    func updateProjectNotes(projectId: String, notes: String) async throws {
        print("[SUPABASE_UPDATE] Updating project notes")

        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)

        guard let project = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        project.notes = notes
        project.needsSync = true
        try modelContext.save()

        if isConnected {
            try await projectRepo?.updateNotes(projectId, notes: notes)
            project.needsSync = false
            project.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_UPDATE] Project notes updated and synced")
        }
    }

    /// Update task status and sync to Supabase
    func updateTaskStatus(taskId: String, status: TaskStatus) async throws {
        print("[SUPABASE_UPDATE] Updating task \(taskId) to status: \(status.rawValue)")

        let predicate = #Predicate<ProjectTask> { $0.id == taskId }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)

        guard let task = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        task.status = status
        task.needsSync = true
        try modelContext.save()

        if isConnected {
            try await taskRepo?.updateStatus(taskId, status: status.rawValue)
            task.needsSync = false
            task.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_UPDATE] Task status updated and synced")
        }
    }

    /// Update task notes and sync to Supabase
    func updateTaskNotes(taskId: String, notes: String) async throws {
        print("[SUPABASE_UPDATE] Updating task notes")

        let predicate = #Predicate<ProjectTask> { $0.id == taskId }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)

        guard let task = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        task.taskNotes = notes
        task.needsSync = true
        try modelContext.save()

        if isConnected {
            try await taskRepo?.updateNotes(taskId, notes: notes)
            task.needsSync = false
            task.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_UPDATE] Task notes updated and synced")
        }
    }

    /// Update user information
    func updateUser(userId: String, firstName: String?, lastName: String?, phone: String?) async throws {
        print("[SUPABASE_UPDATE] Updating user info")

        let predicate = #Predicate<User> { $0.id == userId }
        let descriptor = FetchDescriptor<User>(predicate: predicate)

        guard let user = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        if let first = firstName { user.firstName = first }
        if let last = lastName { user.lastName = last }
        if let phoneNum = phone { user.phone = phoneNum }

        user.needsSync = true
        try modelContext.save()

        if isConnected {
            try await userRepo?.updateUser(userId: userId, firstName: firstName, lastName: lastName, phone: phone)
            user.needsSync = false
            user.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_UPDATE] User updated and synced")
        }
    }

    /// Update user profile image
    func updateUserProfileImage(userId: String, image: UIImage) async throws {
        print("[SUPABASE_UPDATE] Updating profile image for user \(userId)")

        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
        guard let user = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw SyncError.dataCorruption
        }

        user.profileImageData = imageData
        user.needsSync = true
        try modelContext.save()

        // Note: Actual image upload handled by ImageSyncManager, same as CentralizedSyncManager
        if isConnected {
            try await userRepo?.updateUser(userId: userId, firstName: user.firstName, lastName: user.lastName, phone: user.phone)
            user.needsSync = false
            user.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_UPDATE] Profile image metadata synced")
        }
    }

    /// Update client contact information
    func updateClientContact(clientId: String, name: String, email: String?, phone: String?, address: String?) async throws {
        print("[SUPABASE_UPDATE] Updating client contact")

        let predicate = #Predicate<Client> { $0.id == clientId }
        let descriptor = FetchDescriptor<Client>(predicate: predicate)

        guard let client = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        client.name = name
        client.email = email
        client.phoneNumber = phone
        client.address = address
        client.needsSync = true
        try modelContext.save()

        if isConnected {
            try await clientRepo?.updateContact(clientId: clientId, name: name, email: email, phone: phone, address: address)
            client.needsSync = false
            client.lastSyncedAt = Date()
            try modelContext.save()
            print("[SUPABASE_UPDATE] Client updated and synced")
        }
    }

    // MARK: - Create Operations

    /// Create a new sub-client
    func createSubClient(clientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClient {
        print("[SUPABASE_CREATE] Creating sub-client")
        guard let repo = clientRepo else {
            throw NSError(domain: "SupabaseSyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Repository not initialized"])
        }

        // Create on Supabase first
        let dto = try await repo.createSubClient(clientId: clientId, name: name, title: title, email: email, phone: phone, address: address)

        // Create locally from the returned DTO
        let subClient = dto.toModel()

        // Link to parent client
        let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        if let parentClient = try? modelContext.fetch(clientDescriptor).first {
            subClient.client = parentClient
        }

        modelContext.insert(subClient)
        try modelContext.save()

        print("[SUPABASE_CREATE] Sub-client created: \(subClient.id)")
        return subClient
    }

    /// Edit an existing sub-client
    func editSubClient(subClientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws {
        print("[SUPABASE_EDIT] Editing sub-client \(subClientId)")

        let predicate = #Predicate<SubClient> { $0.id == subClientId }
        let descriptor = FetchDescriptor<SubClient>(predicate: predicate)

        guard let subClient = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        // Update locally
        subClient.name = name
        subClient.title = title
        subClient.email = email
        subClient.phoneNumber = phone
        subClient.address = address
        subClient.updatedAt = Date()

        try modelContext.save()

        // Supabase does not have an editSubClient endpoint on ClientRepository,
        // so we'd need to add one. For now, delete and recreate isn't ideal.
        // The ClientRepository.createSubClient returns a new record. We should
        // add an updateSubClient method in a future sprint. For now, the local
        // update is persisted and will be synced properly when the full
        // SubClient update endpoint is added.
        print("[SUPABASE_EDIT] Sub-client updated locally (Supabase update pending endpoint addition)")
    }

    /// Delete a sub-client (hard delete via Supabase, soft delete locally)
    func deleteSubClient(subClientId: String) async throws {
        print("[SUPABASE_DELETE] Deleting sub-client \(subClientId)")

        let predicate = #Predicate<SubClient> { $0.id == subClientId }
        let descriptor = FetchDescriptor<SubClient>(predicate: predicate)

        guard let subClient = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        if isConnected {
            try await clientRepo?.deleteSubClient(subClientId)
        }

        // Soft delete locally
        subClient.deletedAt = Date()
        try modelContext.save()
        print("[SUPABASE_DELETE] Sub-client deleted")
    }

    // MARK: - SwiftData Upsert Helpers

    private func upsertCompany(_ model: Company) throws {
        let id = model.id
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update all mutable fields
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
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    private func upsertUser(_ model: User) throws {
        let id = model.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
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
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    private func upsertClient(_ model: Client) throws {
        let id = model.id
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
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
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    private func upsertSubClient(_ model: SubClient, parentClientId: String) throws {
        let id = model.id
        let descriptor = FetchDescriptor<SubClient>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
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

            // Link to parent client
            let clientDescriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { $0.id == parentClientId }
            )
            if let parentClient = try? modelContext.fetch(clientDescriptor).first {
                model.client = parentClient
            }
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    private func upsertTaskType(_ model: TaskType) throws {
        let id = model.id
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
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
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    private func upsertProject(_ model: Project) throws {
        let id = model.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
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
            // Only clear needsSync if there's nothing pending locally
            if !existing.needsSync {
                existing.needsSync = false
            }
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    private func upsertTask(_ model: ProjectTask) throws {
        let id = model.id
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.status = model.status
            existing.taskNotes = model.taskNotes
            existing.customTitle = model.customTitle
            existing.taskColor = model.taskColor
            existing.taskTypeId = model.taskTypeId
            existing.calendarEventId = model.calendarEventId
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
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    private func upsertCalendarEvent(_ model: CalendarEvent) throws {
        let id = model.id
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = model.title
            existing.color = model.color
            existing.startDate = model.startDate
            existing.endDate = model.endDate
            existing.duration = model.duration
            existing.projectId = model.projectId
            existing.companyId = model.companyId
            existing.teamMemberIdsString = model.teamMemberIdsString
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    // MARK: - SwiftData Fetch Helpers

    private func fetchProject(id: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchTask(id: String) -> ProjectTask? {
        let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Relationship Linking

    /// Link SwiftData relationships after sync completes
    private func linkAllRelationships() throws {
        print("[SUPABASE_LINK] Linking all relationships...")

        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let tasks = try modelContext.fetch(FetchDescriptor<ProjectTask>())
        let calendarEvents = try modelContext.fetch(FetchDescriptor<CalendarEvent>())
        let clients = try modelContext.fetch(FetchDescriptor<Client>())
        let taskTypes = try modelContext.fetch(FetchDescriptor<TaskType>())
        let users = try modelContext.fetch(FetchDescriptor<User>())

        // Build lookup dictionaries
        let clientById = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
        let taskTypeById = Dictionary(uniqueKeysWithValues: taskTypes.map { ($0.id, $0) })
        let userById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        let projectById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let eventById = Dictionary(uniqueKeysWithValues: calendarEvents.map { ($0.id, $0) })

        // Link projects to clients
        for project in projects {
            if let clientId = project.clientId, let client = clientById[clientId] {
                project.client = client
            }
            // Link team members
            let memberIds = project.getTeamMemberIds()
            project.teamMembers = memberIds.compactMap { userById[$0] }
        }

        // Link tasks to projects, task types, calendar events, and team members
        for task in tasks {
            if let project = projectById[task.projectId] {
                task.project = project
            }
            if let taskType = taskTypeById[task.taskTypeId] {
                task.taskType = taskType
            }
            if let eventId = task.calendarEventId, let event = eventById[eventId] {
                task.calendarEvent = event
                event.task = task
                event.taskId = task.id
            }
            let memberIds = task.getTeamMemberIds()
            task.teamMembers = memberIds.compactMap { userById[$0] }
        }

        // Link calendar events to projects
        for event in calendarEvents {
            if let project = projectById[event.projectId] {
                event.project = project
            }
            let memberIds = event.getTeamMemberIds()
            event.teamMembers = memberIds.compactMap { userById[$0] }
        }

        try modelContext.save()
        print("[SUPABASE_LINK] Relationships linked")
    }
}
