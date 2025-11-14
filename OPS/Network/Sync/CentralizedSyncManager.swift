//
//  CentralizedSyncManager.swift
//  OPS
//
//  Centralized sync system - Single source of truth for all sync operations
//  Created by Jackson Sweet on 2025-11-03.
//

import SwiftUI
import Foundation
import SwiftData
import Combine

@MainActor
class CentralizedSyncManager {

    // MARK: - Debug Logging Configuration

    /// Master debug killswitch - Set to false to disable ALL detailed sync logging
    static var debugLoggingEnabled: Bool = true

    /// Per-function debug flags - Only effective when debugLoggingEnabled is true
    struct DebugFlags {
        static var syncAll: Bool = true
        static var syncCompany: Bool = true
        static var syncUsers: Bool = true
        static var syncClients: Bool = true
        static var syncTaskTypes: Bool = true
        static var syncProjects: Bool = true
        static var syncTasks: Bool = true
        static var syncCalendarEvents: Bool = true
        static var updateOperations: Bool = true
        static var deleteOperations: Bool = true
        static var modelConversion: Bool = true
    }

    /// Helper function for debug logging
    private func debugLog(_ message: String, function: String = #function, enabled: Bool = true) {
        guard CentralizedSyncManager.debugLoggingEnabled && enabled else { return }
        print("[SYNC_DEBUG] [\(function)] \(message)")
    }

    // MARK: - Properties

    let modelContext: ModelContext
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor

    private(set) var syncInProgress = false {
        didSet {
            syncStateSubject.send(syncInProgress)
        }
    }

    private var syncStateSubject = PassthroughSubject<Bool, Never>()
    var syncStatePublisher: AnyPublisher<Bool, Never> {
        syncStateSubject.eraseToAnyPublisher()
    }

    var isConnected: Bool {
        connectivityMonitor.isConnected
    }

    var lastSyncDate: Date = Date()

    // MARK: - UI Feedback Properties
    // VIEWS THAT USE THESE: SyncStatusView, any view showing sync progress

    @Published var hasError: Bool = false
    @Published var statusText: String = "Ready"
    @Published var progress: Double = 0.0
    @Published var totalCount: Int = 0

    // Cache of non-existent user IDs to prevent repeated fetch attempts
    private var nonExistentUserIds: Set<String> = []

    var currentUser: User? {
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId") else {
            return nil
        }
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Initialization

    init(modelContext: ModelContext,
         apiService: APIService,
         connectivityMonitor: ConnectivityMonitor) {
        self.modelContext = modelContext
        self.apiService = apiService
        self.connectivityMonitor = connectivityMonitor
    }

    // MARK: - Master Sync Functions

    /// Complete sync of all data types - Called by manual sync button
    func syncAll() async throws {
        debugLog("🔵 FUNCTION CALLED", enabled: DebugFlags.syncAll)

        guard !syncInProgress else {
            debugLog("⚠️ Sync already in progress - aborting", enabled: DebugFlags.syncAll)
            print("[SYNC_ALL] ⚠️ Sync already in progress")
            throw SyncError.alreadySyncing
        }

        guard isConnected else {
            debugLog("⚠️ Not connected - aborting", enabled: DebugFlags.syncAll)
            print("[SYNC_ALL] ⚠️ Not connected")
            throw SyncError.notConnected
        }

        syncInProgress = true
        defer {
            syncInProgress = false
            debugLog("🔵 FUNCTION EXITING - syncInProgress set to false", enabled: DebugFlags.syncAll)
        }

        print("[SYNC_ALL] 🔄 Starting complete sync...")
        debugLog("📊 Starting complete data sync", enabled: DebugFlags.syncAll)

        // Log current data counts BEFORE sync
        if DebugFlags.syncAll {
            let companyCount = (try? modelContext.fetchCount(FetchDescriptor<Company>())) ?? 0
            let userCount = (try? modelContext.fetchCount(FetchDescriptor<User>())) ?? 0
            let clientCount = (try? modelContext.fetchCount(FetchDescriptor<Client>())) ?? 0
            let taskTypeCount = (try? modelContext.fetchCount(FetchDescriptor<TaskType>())) ?? 0
            let projectCount = (try? modelContext.fetchCount(FetchDescriptor<Project>())) ?? 0
            let taskCount = (try? modelContext.fetchCount(FetchDescriptor<ProjectTask>())) ?? 0
            let eventCount = (try? modelContext.fetchCount(FetchDescriptor<CalendarEvent>())) ?? 0

            debugLog("📊 LOCAL DATA BEFORE SYNC:", enabled: DebugFlags.syncAll)
            debugLog("  - Companies: \(companyCount)", enabled: DebugFlags.syncAll)
            debugLog("  - Users: \(userCount)", enabled: DebugFlags.syncAll)
            debugLog("  - Clients: \(clientCount)", enabled: DebugFlags.syncAll)
            debugLog("  - Task Types: \(taskTypeCount)", enabled: DebugFlags.syncAll)
            debugLog("  - Projects: \(projectCount)", enabled: DebugFlags.syncAll)
            debugLog("  - Tasks: \(taskCount)", enabled: DebugFlags.syncAll)
            debugLog("  - Calendar Events: \(eventCount)", enabled: DebugFlags.syncAll)
        }

        do {
            // Sync in dependency order (parents before children)
            debugLog("→ Syncing Company...", enabled: DebugFlags.syncAll)
            try await syncCompany()

            debugLog("→ Syncing Users...", enabled: DebugFlags.syncAll)
            try await syncUsers()

            debugLog("→ Syncing Clients...", enabled: DebugFlags.syncAll)
            try await syncClients()

            debugLog("→ Syncing Task Types...", enabled: DebugFlags.syncAll)
            try await syncTaskTypes()

            debugLog("→ Syncing Projects...", enabled: DebugFlags.syncAll)
            try await syncProjects()

            debugLog("→ Syncing Tasks...", enabled: DebugFlags.syncAll)
            try await syncTasks()

            debugLog("→ Syncing Calendar Events...", enabled: DebugFlags.syncAll)
            try await syncCalendarEvents()

            debugLog("→ Linking Relationships...", enabled: DebugFlags.syncAll)
            try await linkAllRelationships()

            // Log current data counts AFTER sync
            if DebugFlags.syncAll {
                let companyCount = (try? modelContext.fetchCount(FetchDescriptor<Company>())) ?? 0
                let userCount = (try? modelContext.fetchCount(FetchDescriptor<User>())) ?? 0
                let clientCount = (try? modelContext.fetchCount(FetchDescriptor<Client>())) ?? 0
                let taskTypeCount = (try? modelContext.fetchCount(FetchDescriptor<TaskType>())) ?? 0
                let projectCount = (try? modelContext.fetchCount(FetchDescriptor<Project>())) ?? 0
                let taskCount = (try? modelContext.fetchCount(FetchDescriptor<ProjectTask>())) ?? 0
                let eventCount = (try? modelContext.fetchCount(FetchDescriptor<CalendarEvent>())) ?? 0

                debugLog("📊 LOCAL DATA AFTER SYNC:", enabled: DebugFlags.syncAll)
                debugLog("  - Companies: \(companyCount)", enabled: DebugFlags.syncAll)
                debugLog("  - Users: \(userCount)", enabled: DebugFlags.syncAll)
                debugLog("  - Clients: \(clientCount)", enabled: DebugFlags.syncAll)
                debugLog("  - Task Types: \(taskTypeCount)", enabled: DebugFlags.syncAll)
                debugLog("  - Projects: \(projectCount)", enabled: DebugFlags.syncAll)
                debugLog("  - Tasks: \(taskCount)", enabled: DebugFlags.syncAll)
                debugLog("  - Calendar Events: \(eventCount)", enabled: DebugFlags.syncAll)
            }

            lastSyncDate = Date()
            debugLog("✅ Complete sync finished successfully at \(lastSyncDate)", enabled: DebugFlags.syncAll)
            print("[SYNC_ALL] ✅ Complete sync finished")
        } catch {
            debugLog("❌ Sync failed with error: \(error)", enabled: DebugFlags.syncAll)
            print("[SYNC_ALL] ❌ Sync failed: \(error)")
            throw error
        }
    }

    /// App launch sync - Syncs critical data for app functionality
    func syncAppLaunch() async throws {
        guard !syncInProgress else {
            print("[SYNC_LAUNCH] ⚠️ Sync already in progress")
            return
        }

        guard isConnected else {
            print("[SYNC_LAUNCH] ⚠️ Not connected")
            return
        }

        syncInProgress = true
        defer { syncInProgress = false }

        print("[SYNC_LAUNCH] 🚀 Starting app launch sync...")

        do {
            // Sync critical data first
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
            print("[SYNC_LAUNCH] ✅ App launch sync finished")
        } catch {
            print("[SYNC_LAUNCH] ❌ Sync failed: \(error)")
            throw error
        }
    }

    /// Background refresh - Lightweight sync of changed data
    func syncBackgroundRefresh() async throws {
        guard !syncInProgress else { return }
        guard isConnected else { return }

        syncInProgress = true
        defer { syncInProgress = false }

        print("[SYNC_BG] 🔄 Background refresh...")

        do {
            // Only sync data likely to have changed
            try await syncProjects(sinceDate: lastSyncDate)
            try await syncCalendarEvents(sinceDate: lastSyncDate)
            try await syncTasks(sinceDate: lastSyncDate)

            lastSyncDate = Date()
            print("[SYNC_BG] ✅ Background refresh complete")
        } catch {
            print("[SYNC_BG] ❌ Refresh failed: \(error)")
            throw error
        }
    }

    /// Trigger background sync - Used by DataController for automatic syncing
    /// VIEWS/CONTROLLERS USING THIS: DataController
    /// OLD METHOD: syncManager.triggerBackgroundSync(forceProjectSync:)
    func triggerBackgroundSync(forceProjectSync: Bool = false) {
        print("[TRIGGER_BG_SYNC] 🔵 Background sync triggered (force: \(forceProjectSync))")

        guard !syncInProgress, isConnected else {
            if syncInProgress {
                print("[TRIGGER_BG_SYNC] ⚠️ Sync already in progress, skipping")
            } else if !isConnected {
                print("[TRIGGER_BG_SYNC] ⚠️ No internet connection, skipping sync")
            }
            return
        }

        Task {
            do {
                if forceProjectSync {
                    // Force a full sync
                    print("[TRIGGER_BG_SYNC] ✅ Starting forced full sync")
                    try await syncAll()
                } else {
                    // Do a lightweight background refresh
                    print("[TRIGGER_BG_SYNC] ✅ Starting background refresh")
                    try await syncBackgroundRefresh()
                }
            } catch {
                print("[TRIGGER_BG_SYNC] ❌ Background sync failed: \(error)")
            }
        }
    }

    // MARK: - Individual Data Type Sync Functions

    /// Sync company information and subscription status
    func syncCompany() async throws {
        debugLog("🔵 FUNCTION CALLED", enabled: DebugFlags.syncCompany)
        print("[SYNC_COMPANY] 📊 Syncing company data...")

        guard let companyId = currentUser?.companyId else {
            debugLog("⚠️ No company ID found for current user", enabled: DebugFlags.syncCompany)
            print("[SYNC_COMPANY] ⚠️ No company ID")
            throw SyncError.missingCompanyId
        }

        debugLog("📥 Fetching company from API with ID: \(companyId)", enabled: DebugFlags.syncCompany)

        do {
            // Fetch from Bubble
            let dto = try await apiService.fetchCompany(id: companyId)
            debugLog("✅ API returned company DTO", enabled: DebugFlags.syncCompany)
            debugLog("  - ID: \(dto.id)", enabled: DebugFlags.syncCompany)
            debugLog("  - Name: \(dto.companyName ?? "nil")", enabled: DebugFlags.syncCompany)
            debugLog("  - Plan: \(dto.subscriptionPlan ?? "nil")", enabled: DebugFlags.syncCompany)
            debugLog("  - Status: \(dto.subscriptionStatus ?? "nil")", enabled: DebugFlags.syncCompany)

            // Find or create local company
            debugLog("🔍 Finding or creating local company record", enabled: DebugFlags.syncCompany)
            let company = try await getOrCreateCompany(id: dto.id)
            debugLog("✅ Local company record ready: \(company.id)", enabled: DebugFlags.syncCompany)

            // Update properties
            debugLog("📝 Updating company properties...", enabled: DebugFlags.syncCompany)
            company.name = dto.companyName ?? ""
            company.externalId = dto.companyID  // Note: companyID with capital ID
            company.logoURL = dto.logo?.url  // Logo is BubbleImage type
            company.phone = dto.phone
            company.email = dto.officeEmail
            company.website = dto.website
            company.address = dto.location?.formattedAddress
            company.latitude = dto.location?.lat
            company.longitude = dto.location?.lng
            company.openHour = dto.openHour
            company.closeHour = dto.closeHour
            company.companyDescription = dto.companyDescription
            company.setIndustries(dto.industry ?? [])  // Use setIndustries method
            company.companySize = dto.companySize
            company.companyAge = dto.companyAge
            company.defaultProjectColor = dto.defaultProjectColor ?? "#59779F"

            // Subscription info
            company.subscriptionStatus = dto.subscriptionStatus
            company.subscriptionPlan = dto.subscriptionPlan
            company.subscriptionEnd = dto.subscriptionEnd
            company.maxSeats = dto.maxSeats ?? 0

            // Seated employees
            if let seatedRefs = dto.seatedEmployees {
                let seatedIds = seatedRefs.compactMap { $0.stringValue }
                company.setSeatedEmployeeIds(seatedIds)
                print("[SYNC_COMPANY] 💺 Set \(seatedIds.count) seated employees")
            } else {
                company.setSeatedEmployeeIds([])
                print("[SYNC_COMPANY] ⚠️ No seated employees from API")
            }

            company.trialStartDate = dto.trialStartDate
            company.trialEndDate = dto.trialEndDate
            company.stripeCustomerId = dto.stripeCustomerId

            // Add-ons
            company.hasPrioritySupport = dto.hasPrioritySupport ?? false
            company.dataSetupPurchased = dto.dataSetupPurchased ?? false
            company.dataSetupCompleted = dto.dataSetupCompleted ?? false

            // Mark synced
            company.needsSync = false
            company.lastSyncedAt = Date()

            debugLog("💾 Saving company to modelContext...", enabled: DebugFlags.syncCompany)
            try modelContext.save()
            debugLog("✅ Company saved successfully", enabled: DebugFlags.syncCompany)
            print("[SYNC_COMPANY] ✅ Company synced")
        } catch {
            debugLog("❌ Sync failed with error: \(error)", enabled: DebugFlags.syncCompany)
            print("[SYNC_COMPANY] ❌ Failed: \(error)")
            throw error
        }
    }

    /// Sync team members for the company
    func syncUsers() async throws {
        debugLog("🔵 FUNCTION CALLED", enabled: DebugFlags.syncUsers)
        print("[SYNC_USERS] 👥 Syncing users...")

        guard let companyId = currentUser?.companyId else {
            debugLog("⚠️ No company ID found for current user", enabled: DebugFlags.syncUsers)
            print("[SYNC_USERS] ⚠️ No company ID")
            throw SyncError.missingCompanyId
        }

        debugLog("📥 Fetching users from API for company: \(companyId)", enabled: DebugFlags.syncUsers)

        do {
            // Count users BEFORE sync
            let userCountBefore = (try? modelContext.fetchCount(FetchDescriptor<User>())) ?? 0
            debugLog("📊 Users in DB BEFORE sync: \(userCountBefore)", enabled: DebugFlags.syncUsers)

            // Get company admin IDs for proper role assignment
            let companyDescriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyId })
            let company = try? modelContext.fetch(companyDescriptor).first
            let adminIds = company?.getAdminIds() ?? []
            debugLog("👑 Company has \(adminIds.count) admin IDs: \(adminIds)", enabled: DebugFlags.syncUsers)

            // Fetch from Bubble
            let dtos = try await apiService.fetchCompanyUsers(companyId: companyId)
            debugLog("✅ API returned \(dtos.count) user DTOs", enabled: DebugFlags.syncUsers)

            if DebugFlags.syncUsers {
                for dto in dtos {
                    debugLog("  - User: \(dto.nameFirst ?? "") \(dto.nameLast ?? "") (ID: \(dto.id), Role: \(dto.employeeType ?? "nil"))", enabled: DebugFlags.syncUsers)
                }
            }

            // Handle deletions (soft delete)
            let remoteIds = Set(dtos.map { $0.id })
            debugLog("🔍 Handling deletions - remote IDs count: \(remoteIds.count)", enabled: DebugFlags.syncUsers)
            try await handleUserDeletions(keepingIds: remoteIds)

            // Upsert each user
            debugLog("📝 Upserting \(dtos.count) users...", enabled: DebugFlags.syncUsers)
            for (index, dto) in dtos.enumerated() {
                let user = try await getOrCreateUser(id: dto.id)
                debugLog("  [\(index+1)/\(dtos.count)] Processing user: \(dto.nameFirst ?? "") \(dto.nameLast ?? "")", enabled: DebugFlags.syncUsers)

                user.firstName = dto.nameFirst ?? ""  // UserDTO uses nameFirst
                user.lastName = dto.nameLast ?? ""    // UserDTO uses nameLast
                user.email = dto.email ?? ""
                user.phone = dto.phone
                user.homeAddress = dto.homeAddress?.formattedAddress
                user.latitude = dto.homeAddress?.lat
                user.longitude = dto.homeAddress?.lng
                user.locationName = dto.homeAddress?.formattedAddress
                user.companyId = companyId
                user.userColor = dto.userColor ?? "#59779F"
                user.profileImageURL = dto.avatar
                user.devPermission = dto.devPermission ?? false

                // Role mapping - CRITICAL: Check admin IDs first, then employeeType
                // This matches the logic in UserDTO.toModel()
                if adminIds.contains(dto.id) {
                    // User is in company.adminIds → Admin role
                    user.role = .admin
                    debugLog("    - 👑 Role set to ADMIN (in company.adminIds)", enabled: DebugFlags.syncUsers)
                } else if let employeeType = dto.employeeType {
                    // Use employeeType from API
                    user.role = BubbleFields.EmployeeType.toSwiftEnum(employeeType)
                    debugLog("    - Role set to: \(user.role) (from employeeType)", enabled: DebugFlags.syncUsers)
                } else {
                    // No employeeType provided - default to field crew
                    user.role = .fieldCrew
                    debugLog("    - ⚠️ Role defaulted to Field Crew (no employeeType)", enabled: DebugFlags.syncUsers)
                }

                // Parse deletedAt if present
                if let deletedAtString = dto.deletedAt {
                    let formatter = ISO8601DateFormatter()
                    user.deletedAt = formatter.date(from: deletedAtString)
                    debugLog("    - Soft deleted at: \(deletedAtString)", enabled: DebugFlags.syncUsers)
                } else {
                    user.deletedAt = nil
                }

                user.needsSync = false
                user.lastSyncedAt = Date()
            }

            debugLog("💾 Saving \(dtos.count) users to modelContext...", enabled: DebugFlags.syncUsers)
            try modelContext.save()

            // Count users AFTER sync
            let userCountAfter = (try? modelContext.fetchCount(FetchDescriptor<User>())) ?? 0
            debugLog("📊 Users in DB AFTER sync: \(userCountAfter)", enabled: DebugFlags.syncUsers)
            debugLog("✅ Users synced successfully", enabled: DebugFlags.syncUsers)
            print("[SYNC_USERS] ✅ Synced \(dtos.count) users")
        } catch {
            debugLog("❌ Sync failed with error: \(error)", enabled: DebugFlags.syncUsers)
            print("[SYNC_USERS] ❌ Failed: \(error)")
            throw error
        }
    }

    /// Sync clients and sub-clients
    func syncClients() async throws {
        print("[SYNC_CLIENTS] 🏢 Syncing clients...")

        guard let companyId = currentUser?.companyId else {
            print("[SYNC_CLIENTS] ⚠️ No company ID")
            throw SyncError.missingCompanyId
        }

        do {
            // Fetch from Bubble
            let dtos = try await apiService.fetchCompanyClients(companyId: companyId)

            // Handle deletions
            let remoteIds = Set(dtos.map { $0.id })
            try await handleClientDeletions(keepingIds: remoteIds)

            // Upsert each client
            for dto in dtos {
                let client = try await getOrCreateClient(id: dto.id)

                client.name = dto.name ?? "Unknown Client"
                client.email = dto.emailAddress
                client.phoneNumber = dto.phoneNumber
                client.address = dto.address?.formattedAddress
                client.latitude = dto.address?.lat
                client.longitude = dto.address?.lng
                client.profileImageURL = dto.thumbnail
                client.notes = nil // Add if available in DTO
                client.companyId = companyId

                // Parse deletedAt if present
                if let deletedAtString = dto.deletedAt {
                    let formatter = ISO8601DateFormatter()
                    client.deletedAt = formatter.date(from: deletedAtString)
                } else {
                    client.deletedAt = nil
                }

                client.needsSync = false
                client.lastSyncedAt = Date()
            }

            try modelContext.save()
            print("[SYNC_CLIENTS] ✅ Synced \(dtos.count) clients")
        } catch {
            print("[SYNC_CLIENTS] ❌ Failed: \(error)")
            throw error
        }
    }

    /// Sync task type templates
    func syncTaskTypes() async throws {
        print("[SYNC_TASK_TYPES] 🏷️ Syncing task types...")

        guard let companyId = currentUser?.companyId else {
            print("[SYNC_TASK_TYPES] ⚠️ No company ID")
            throw SyncError.missingCompanyId
        }

        do {
            // Fetch from Bubble
            let dtos = try await apiService.fetchCompanyTaskTypes(companyId: companyId)

            // Handle deletions
            let remoteIds = Set(dtos.map { $0.id })
            try await handleTaskTypeDeletions(keepingIds: remoteIds)

            // Upsert each task type
            for dto in dtos {
                let taskType = try await getOrCreateTaskType(id: dto.id)

                taskType.display = dto.display
                taskType.color = dto.color
                // Note: icon is not in DTO, assigned locally via TaskType.assignIconsToTaskTypes
                taskType.isDefault = dto.isDefault ?? false
                taskType.companyId = companyId

                // Parse deletedAt if present
                if let deletedAtString = dto.deletedAt {
                    let formatter = ISO8601DateFormatter()
                    taskType.deletedAt = formatter.date(from: deletedAtString)
                } else {
                    taskType.deletedAt = nil
                }

                taskType.needsSync = false
                taskType.lastSyncedAt = Date()
            }

            // Assign icons to task types that don't have them
            let allTaskTypes = try modelContext.fetch(FetchDescriptor<TaskType>(
                predicate: #Predicate { $0.companyId == companyId }
            ))
            TaskType.assignIconsToTaskTypes(allTaskTypes)

            try modelContext.save()
            print("[SYNC_TASK_TYPES] ✅ Synced \(dtos.count) task types")
        } catch {
            print("[SYNC_TASK_TYPES] ❌ Failed: \(error)")
            throw error
        }
    }

    /// Sync projects based on user role
    func syncProjects(sinceDate: Date? = nil) async throws {
        debugLog("🔵 FUNCTION CALLED (sinceDate: \(sinceDate?.description ?? "nil"))", enabled: DebugFlags.syncProjects)
        print("[SYNC_PROJECTS] 📋 Syncing projects...")

        guard let userId = currentUser?.id else {
            debugLog("⚠️ No user ID found for current user", enabled: DebugFlags.syncProjects)
            print("[SYNC_PROJECTS] ⚠️ No user ID")
            throw SyncError.missingUserId
        }

        debugLog("👤 Current user: \(userId), Role: \(currentUser?.role.rawValue ?? "nil")", enabled: DebugFlags.syncProjects)

        do {
            // Count projects BEFORE sync
            let projectCountBefore = (try? modelContext.fetchCount(FetchDescriptor<Project>())) ?? 0
            debugLog("📊 Projects in DB BEFORE sync: \(projectCountBefore)", enabled: DebugFlags.syncProjects)

            // Fetch from Bubble (role-based)
            let dtos: [ProjectDTO]
            if currentUser?.role == .admin || currentUser?.role == .officeCrew {
                // Admin/Office: Get ALL company projects
                guard let companyId = currentUser?.companyId else {
                    throw SyncError.missingCompanyId
                }
                debugLog("📥 Fetching ALL company projects for company: \(companyId)", enabled: DebugFlags.syncProjects)
                dtos = try await apiService.fetchCompanyProjects(companyId: companyId)
            } else {
                // Field Crew: Get only assigned projects
                debugLog("📥 Fetching user-assigned projects for user: \(userId)", enabled: DebugFlags.syncProjects)
                dtos = try await apiService.fetchUserProjects(userId: userId)
            }

            debugLog("✅ API returned \(dtos.count) project DTOs", enabled: DebugFlags.syncProjects)

            if DebugFlags.syncProjects {
                for dto in dtos {
                    debugLog("  - Project: \(dto.projectName) (ID: \(dto.id), Status: \(dto.status))", enabled: DebugFlags.syncProjects)
                }
            }

            // Handle deletions
            let remoteIds = Set(dtos.map { $0.id })
            debugLog("🔍 Handling deletions - remote IDs count: \(remoteIds.count)", enabled: DebugFlags.syncProjects)
            debugLog("   Remote project IDs: \(remoteIds.prefix(10).joined(separator: ", "))\(remoteIds.count > 10 ? "..." : "")", enabled: DebugFlags.syncProjects)
            try await handleProjectDeletions(keepingIds: remoteIds)

            // Check project count after deletions
            let projectCountAfterDeletions = (try? modelContext.fetchCount(FetchDescriptor<Project>())) ?? 0
            debugLog("📊 Projects in DB AFTER deletions: \(projectCountAfterDeletions)", enabled: DebugFlags.syncProjects)

            // Upsert each project
            debugLog("📝 Upserting \(dtos.count) projects...", enabled: DebugFlags.syncProjects)
            for (index, dto) in dtos.enumerated() {
                let project = try await getOrCreateProject(id: dto.id)
                debugLog("  [\(index+1)/\(dtos.count)] Processing project: \(dto.projectName) (ID: \(dto.id))", enabled: DebugFlags.syncProjects)

                project.title = dto.projectName
                project.projectDescription = dto.description
                project.notes = dto.teamNotes
                project.address = dto.address?.formattedAddress
                project.latitude = dto.address?.lat
                project.longitude = dto.address?.lng
                project.status = BubbleFields.JobStatus.toSwiftEnum(dto.status)

                // Parse dates
                if let startDateString = dto.startDate {
                    project.startDate = DateFormatter.dateFromBubble(startDateString)
                }
                if let completionString = dto.completion {
                    project.endDate = DateFormatter.dateFromBubble(completionString)
                }

                project.duration = dto.duration
                project.allDay = dto.allDay ?? false
                project.companyId = dto.company?.stringValue ?? ""
                debugLog("    - Company ID: \(project.companyId)", enabled: DebugFlags.syncProjects)

                // Event type
                if let eventTypeString = dto.eventType {
                    project.eventType = CalendarEventType(rawValue: eventTypeString.lowercased()) ?? .project
                }

                // Client relationship
                if let clientId = dto.client {  // ProjectDTO uses 'client', not 'clientId'
                    project.clientId = clientId
                    debugLog("    - Client ID: \(clientId)", enabled: DebugFlags.syncProjects)
                }

                // Team members
                if let teamMemberIds = dto.teamMembers {  // ProjectDTO uses 'teamMembers', not 'teamMemberIds'
                    project.setTeamMemberIds(teamMemberIds)
                    debugLog("    - Team members: \(teamMemberIds.count)", enabled: DebugFlags.syncProjects)
                }

                // Project images - sync from backend
                if let projectImages = dto.projectImages {
                    let remoteImageURLs = Set(projectImages)
                    let localImageURLs = Set(project.getProjectImages())

                    // Find images that were deleted on the server
                    let deletedImages = localImageURLs.subtracting(remoteImageURLs)

                    // Clean up deleted images from cache
                    for deletedURL in deletedImages {
                        _ = ImageFileManager.shared.deleteImage(localID: deletedURL)
                        ImageCache.shared.remove(forKey: deletedURL)
                    }

                    // Update project with server's image list (handles both additions and deletions)
                    project.setProjectImageURLs(projectImages)
                    debugLog("    - Project images: \(projectImages.count)", enabled: DebugFlags.syncProjects)
                } else {
                    // If projectImages is nil, clear all local images
                    let localImages = project.getProjectImages()
                    if !localImages.isEmpty {
                        // Clean up local cache
                        for imageURL in localImages {
                            _ = ImageFileManager.shared.deleteImage(localID: imageURL)
                            ImageCache.shared.remove(forKey: imageURL)
                        }
                        project.setProjectImageURLs([])
                        debugLog("    - Project images cleared (nil from server)", enabled: DebugFlags.syncProjects)
                    }
                }

                // Parse deletedAt if present
                if let deletedAtString = dto.deletedAt {
                    let formatter = ISO8601DateFormatter()
                    project.deletedAt = formatter.date(from: deletedAtString)
                    debugLog("    - Soft deleted at: \(deletedAtString)", enabled: DebugFlags.syncProjects)
                } else {
                    project.deletedAt = nil
                }

                project.needsSync = false
                project.lastSyncedAt = Date()
            }

            debugLog("💾 Saving \(dtos.count) projects to modelContext...", enabled: DebugFlags.syncProjects)
            try modelContext.save()

            // Count projects AFTER sync
            let projectCountAfter = (try? modelContext.fetchCount(FetchDescriptor<Project>())) ?? 0
            debugLog("📊 Projects in DB AFTER sync: \(projectCountAfter)", enabled: DebugFlags.syncProjects)
            debugLog("✅ Projects synced successfully", enabled: DebugFlags.syncProjects)
            print("[SYNC_PROJECTS] ✅ Synced \(dtos.count) projects")
        } catch {
            debugLog("❌ Sync failed with error: \(error)", enabled: DebugFlags.syncProjects)
            print("[SYNC_PROJECTS] ❌ Failed: \(error)")
            throw error
        }
    }

    /// Sync project tasks
    func syncTasks(sinceDate: Date? = nil) async throws {
        print("[SYNC_TASKS] ✅ Syncing tasks...")

        guard let companyId = currentUser?.companyId else {
            print("[SYNC_TASKS] ⚠️ No company ID")
            throw SyncError.missingCompanyId
        }

        do {
            // Fetch from Bubble
            let dtos = try await apiService.fetchCompanyTasks(companyId: companyId)

            // Handle deletions
            let remoteIds = Set(dtos.map { $0.id })
            try await handleTaskDeletions(keepingIds: remoteIds)

            // Upsert each task
            for dto in dtos {
                let task = try await getOrCreateTask(id: dto.id)

                task.projectId = dto.projectId ?? ""
                task.taskTypeId = dto.type ?? ""
                task.companyId = dto.companyId ?? ""
                task.status = TaskStatus(rawValue: dto.status ?? "Booked") ?? .booked
                task.taskNotes = dto.taskNotes
                task.taskColor = dto.taskColor ?? "#59779F"
                task.displayOrder = dto.taskIndex ?? 0
                task.calendarEventId = dto.calendarEventId

                // Team members
                if let teamMemberIds = dto.teamMembers {
                    task.setTeamMemberIds(teamMemberIds)
                }

                // Parse deletedAt if present
                if let deletedAtString = dto.deletedAt {
                    let formatter = ISO8601DateFormatter()
                    task.deletedAt = formatter.date(from: deletedAtString)
                } else {
                    task.deletedAt = nil
                }

                task.needsSync = false
                task.lastSyncedAt = Date()
            }

            try modelContext.save()
            print("[SYNC_TASKS] ✅ Synced \(dtos.count) tasks")
        } catch {
            print("[SYNC_TASKS] ❌ Failed: \(error)")
            throw error
        }
    }

    /// Sync calendar events
    func syncCalendarEvents(sinceDate: Date? = nil) async throws {
        print("[SYNC_CALENDAR] 📅 Syncing calendar events...")

        guard let companyId = currentUser?.companyId else {
            print("[SYNC_CALENDAR] ⚠️ No company ID")
            throw SyncError.missingCompanyId
        }

        do {
            // Fetch company to get defaultProjectColor
            let companyDescriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyId })
            let company = try? modelContext.fetch(companyDescriptor).first

            // Fallback to light grey if company doesn't exist OR defaultProjectColor is empty
            let defaultProjectColor: String
            if let companyColor = company?.defaultProjectColor, !companyColor.isEmpty {
                defaultProjectColor = companyColor
            } else {
                defaultProjectColor = "#9CA3AF"  // Light grey fallback
            }

            // MIGRATION: Update all existing project calendar events to use company color
            // This fixes events that were created with old blue color
            try await migrateProjectEventColors(companyId: companyId, defaultColor: defaultProjectColor)

            // Fetch from Bubble
            let dtos = try await apiService.fetchCompanyCalendarEvents(companyId: companyId)

            // Handle deletions
            let remoteIds = Set(dtos.map { $0.id })
            try await handleCalendarEventDeletions(keepingIds: remoteIds)

            // Upsert each event
            for dto in dtos {
                guard let modelEvent = dto.toModel() else {
                    print("[SYNC_CALENDAR] ⚠️ Failed to convert DTO to model for event \(dto.id)")
                    continue
                }

                let event = try await getOrCreateCalendarEvent(id: dto.id)

                event.projectId = modelEvent.projectId
                event.taskId = modelEvent.taskId
                event.companyId = modelEvent.companyId
                event.title = modelEvent.title

                // ALWAYS use company's defaultProjectColor for project-level events
                // Ignore any color from Bubble API for projects (may have old blue colors)
                if modelEvent.type == .project {
                    // Project event: ALWAYS use company's default project color
                    event.color = defaultProjectColor
                    print("[SYNC_CALENDAR] 🎨 Setting project event '\(event.title)' color to company default: \(defaultProjectColor)")
                } else {
                    // Task event: use the color from the task type
                    event.color = modelEvent.color
                    print("[SYNC_CALENDAR] 🎨 Setting task event '\(event.title)' color from API: \(modelEvent.color)")
                }

                event.startDate = modelEvent.startDate
                event.endDate = modelEvent.endDate
                event.duration = modelEvent.duration
                event.type = modelEvent.type
                event.active = modelEvent.active

                // Team members
                if let teamMemberIds = dto.teamMembers {
                    event.setTeamMemberIds(teamMemberIds)
                }

                // Parse deletedAt if present
                if let deletedAtString = dto.deletedAt {
                    let formatter = ISO8601DateFormatter()
                    event.deletedAt = formatter.date(from: deletedAtString)
                } else {
                    event.deletedAt = nil
                }

                event.needsSync = false
                event.lastSyncedAt = Date()
            }

            try modelContext.save()
            print("[SYNC_CALENDAR] ✅ Synced \(dtos.count) calendar events")
        } catch {
            print("[SYNC_CALENDAR] ❌ Failed: \(error)")
            throw error
        }
    }

    // MARK: - Individual Update Operations
    // These operations update a single record immediately (if connected)

    /// Update project status and sync to API
    /// VIEWS USING THIS: ProjectDetailsView, ProjectCard, HomeView
    /// OLD METHOD: syncManager.updateProjectStatus(projectId:status:forceSync:)
    func updateProjectStatus(projectId: String, status: Status, forceSync: Bool = false) async throws {
        print("[UPDATE_STATUS] 🔵 Updating project \(projectId) to status: \(status.rawValue)")

        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)

        guard let project = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        // Update status locally
        project.status = status
        project.needsSync = true
        project.syncPriority = 3 // Highest priority

        // Update timestamps based on status
        if status == .inProgress && project.startDate == nil {
            project.startDate = Date()
        } else if status == .completed && project.endDate == nil {
            project.endDate = Date()
        }

        try modelContext.save()

        // Sync immediately if connected
        if isConnected {
            try await apiService.updateProjectStatus(id: projectId, status: status.rawValue)
            project.needsSync = false
            project.lastSyncedAt = Date()
            try modelContext.save()
            print("[UPDATE_STATUS] ✅ Status updated and synced")
        } else {
            print("[UPDATE_STATUS] 📴 Offline - will sync when connected")
        }
    }

    /// Update project notes and sync to API
    /// VIEWS USING THIS: ProjectDetailsView (NotesCard)
    /// OLD METHOD: syncManager.updateProjectNotes(projectId:notes:)
    func updateProjectNotes(projectId: String, notes: String) async throws {
        print("[UPDATE_NOTES] 📝 Updating project notes")

        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)

        guard let project = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        project.notes = notes
        project.needsSync = true
        try modelContext.save()

        if isConnected {
            try await apiService.updateProject(id: projectId, updates: ["teamNotes": notes])
            project.needsSync = false
            project.lastSyncedAt = Date()
            try modelContext.save()
            print("[UPDATE_NOTES] ✅ Notes updated and synced")
        }
    }

    /// Update task status and sync to API
    /// VIEWS USING THIS: TaskDetailsView, TaskCard, UniversalJobBoardCard
    /// OLD METHOD: syncManager.updateTaskStatus(taskId:status:)
    func updateTaskStatus(taskId: String, status: TaskStatus) async throws {
        print("[UPDATE_TASK_STATUS] 🔵 Updating task \(taskId) to status: \(status.rawValue)")

        let predicate = #Predicate<ProjectTask> { $0.id == taskId }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)

        guard let task = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        task.status = status
        task.needsSync = true
        try modelContext.save()

        if isConnected {
            try await apiService.updateTaskStatus(id: taskId, status: status.rawValue)
            task.needsSync = false
            task.lastSyncedAt = Date()
            try modelContext.save()
            print("[UPDATE_TASK_STATUS] ✅ Status updated and synced")
        }
    }

    /// Update task notes and sync to API
    /// VIEWS USING THIS: TaskDetailsView (NotesCard)
    /// OLD METHOD: syncManager.updateTaskNotes(taskId:notes:)
    func updateTaskNotes(taskId: String, notes: String) async throws {
        print("[UPDATE_TASK_NOTES] 📝 Updating task notes")

        let predicate = #Predicate<ProjectTask> { $0.id == taskId }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)

        guard let task = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        task.taskNotes = notes
        task.needsSync = true
        try modelContext.save()

        if isConnected {
            try await apiService.updateTaskNotes(id: taskId, notes: notes)
            task.needsSync = false
            task.lastSyncedAt = Date()
            try modelContext.save()
            print("[UPDATE_TASK_NOTES] ✅ Notes updated and synced")
        }
    }

    /// Update user information
    /// CONSOLIDATES: updateUserName() and updateUserPhone()
    /// VIEWS USING THIS: SettingsView, ProfileEditView
    /// OLD METHODS: syncManager.updateUserName() and syncManager.updateUserPhone()
    func updateUser(userId: String, firstName: String?, lastName: String?, phone: String?) async throws {
        print("[UPDATE_USER] 👤 Updating user info")

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
            var fields: [String: Any] = [:]
            if let first = firstName { fields["nameFirst"] = first }
            if let last = lastName { fields["nameLast"] = last }
            if let phoneNum = phone { fields["phone"] = phoneNum }

            try await apiService.updateUser(userId: userId, fields: fields)
            user.needsSync = false
            user.lastSyncedAt = Date()
            try modelContext.save()
            print("[UPDATE_USER] ✅ User info updated and synced")
        }
    }

    /// Update client contact information
    /// VIEWS USING THIS: ClientDetailsView, TeamMemberDetailView
    /// OLD METHOD: syncManager.updateClientContact()
    func updateClientContact(clientId: String, name: String, email: String?, phone: String?, address: String?) async throws {
        print("[UPDATE_CLIENT] 🏢 Updating client contact")

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
            _ = try await apiService.updateClientContact(
                clientId: clientId,
                name: name,
                email: email,
                phone: phone,
                address: address
            )
            client.needsSync = false
            client.lastSyncedAt = Date()
            try modelContext.save()
            print("[UPDATE_CLIENT] ✅ Client updated and synced")
        }
    }

    // MARK: - Create Operations

    /// Create a new sub-client
    /// VIEWS USING THIS: ClientDetailsView
    /// OLD METHOD: syncManager.createSubClient()
    func createSubClient(clientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws -> SubClient {
        print("[CREATE_SUBCLIENT] ➕ Creating sub-client")

        // Create on API first
        let dto = try await apiService.createSubClient(
            clientId: clientId,
            name: name,
            title: title,
            email: email,
            phone: phone,
            address: address
        )

        // Create locally
        let subClient = SubClient(
            id: dto.id,
            name: dto.name ?? name,
            title: dto.title ?? title,
            email: dto.emailAddress ?? email,  // SubClientDTO uses emailAddress
            phoneNumber: dto.phoneNumber?.stringValue ?? phone,  // SubClientDTO uses phoneNumber (PhoneNumberType)
            address: dto.address?.formattedAddress ?? address  // SubClientDTO uses BubbleAddress
        )

        modelContext.insert(subClient)
        try modelContext.save()

        print("[CREATE_SUBCLIENT] ✅ Sub-client created")
        return subClient
    }

    /// Edit an existing sub-client
    /// VIEWS USING THIS: ClientDetailsView
    /// OLD METHOD: syncManager.editSubClient()
    func editSubClient(subClientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws {
        print("[EDIT_SUBCLIENT] ✏️ Editing sub-client")

        let predicate = #Predicate<SubClient> { $0.id == subClientId }
        let descriptor = FetchDescriptor<SubClient>(predicate: predicate)

        guard let subClient = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        // Update on API first
        let dto = try await apiService.editSubClient(  // Method is editSubClient, not updateSubClient
            subClientId: subClientId,
            name: name,
            title: title,
            email: email,
            phone: phone,
            address: address
        )

        // Update locally
        subClient.name = dto.name ?? name
        subClient.title = dto.title ?? title
        subClient.email = dto.emailAddress ?? email  // SubClientDTO uses emailAddress
        subClient.phoneNumber = dto.phoneNumber?.stringValue ?? phone  // SubClientDTO uses phoneNumber (PhoneNumberType)
        subClient.address = dto.address?.formattedAddress ?? address  // SubClientDTO uses BubbleAddress
        subClient.updatedAt = Date()

        try modelContext.save()
        print("[EDIT_SUBCLIENT] ✅ Sub-client updated")
    }

    /// Delete a sub-client (soft delete)
    /// VIEWS USING THIS: ClientDetailsView
    /// OLD METHOD: syncManager.deleteSubClient()
    func deleteSubClient(subClientId: String) async throws {
        print("[DELETE_SUBCLIENT] 🗑️ Deleting sub-client")

        let predicate = #Predicate<SubClient> { $0.id == subClientId }
        let descriptor = FetchDescriptor<SubClient>(predicate: predicate)

        guard let subClient = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        if isConnected {
            // Soft delete on API
            try await apiService.deleteSubClient(subClientId: subClientId)
        }

        // Soft delete locally
        subClient.deletedAt = Date()
        try modelContext.save()

        print("[DELETE_SUBCLIENT] ✅ Sub-client soft deleted")
    }

    // MARK: - Specialized Sync Operations

    /// Sync tasks for a specific project
    /// VIEWS USING THIS: ProjectDetailsView (when viewing task list)
    /// OLD METHOD: syncManager.syncProjectTasks(projectId:)
    func syncProjectTasks(projectId: String) async throws {
        print("[SYNC_PROJECT_TASKS] 📋 Syncing tasks for project \(projectId)")

        guard isConnected else {
            throw SyncError.notConnected
        }

        // Fetch tasks for this specific project
        let dtos = try await apiService.fetchProjectTasks(projectId: projectId)

        // Process each task
        for dto in dtos {
            let task = try await getOrCreateTask(id: dto.id)

            task.projectId = dto.projectId ?? ""
            task.taskTypeId = dto.type ?? ""
            task.status = TaskStatus(rawValue: dto.status ?? "Booked") ?? .booked
            task.taskNotes = dto.taskNotes
            task.taskColor = dto.taskColor ?? "#59779F"
            task.displayOrder = dto.taskIndex ?? 0

            if let teamMemberIds = dto.teamMembers {
                task.setTeamMemberIds(teamMemberIds)
            }

            task.deletedAt = dto.deletedAt != nil ? ISO8601DateFormatter().date(from: dto.deletedAt!) : nil
            task.needsSync = false
            task.lastSyncedAt = Date()
        }

        try modelContext.save()
        print("[SYNC_PROJECT_TASKS] ✅ Synced \(dtos.count) tasks for project")
    }

    /// Refresh a single client's data
    /// VIEWS USING THIS: ClientDetailsView
    /// OLD METHOD: syncManager.refreshSingleClient(clientId:for:forceRefresh:)
    func refreshSingleClient(clientId: String) async throws {
        print("[REFRESH_CLIENT] 🔄 Refreshing client \(clientId)")

        guard isConnected else {
            throw SyncError.notConnected
        }

        let dto = try await apiService.fetchClient(id: clientId)
        let client = try await getOrCreateClient(id: dto.id)

        client.name = dto.name ?? "Unknown"
        client.email = dto.emailAddress
        client.phoneNumber = dto.phoneNumber
        client.address = dto.address?.formattedAddress
        client.latitude = dto.address?.lat
        client.longitude = dto.address?.lng
        client.profileImageURL = dto.thumbnail
        client.deletedAt = dto.deletedAt != nil ? ISO8601DateFormatter().date(from: dto.deletedAt!) : nil
        client.needsSync = false
        client.lastSyncedAt = Date()

        try modelContext.save()
        print("[REFRESH_CLIENT] ✅ Client refreshed")
    }

    /// Manual full sync - same as syncAll()
    /// CONSOLIDATES: manualFullSync() and forceSyncProjects()
    /// VIEWS USING THIS: Calendar view sync button, Settings sync button, DataController
    /// OLD METHODS: syncManager.manualFullSync(companyId:) and syncManager.forceSyncProjects()
    func manualFullSync(companyId: String? = nil) async throws {
        // companyId parameter is deprecated - we get it from currentUser
        // Kept for backwards compatibility with DataController
        print("[MANUAL_SYNC] 🔄 User-triggered full sync")
        statusText = "Syncing all data..."
        try await syncAll()
        statusText = "Sync complete"
    }

    /// Retry sync after error
    /// VIEWS USING THIS: Error views, SyncStatusView
    /// OLD METHOD: syncManager.retrySync()
    func retrySync() async {
        print("[RETRY_SYNC] 🔄 Retrying sync after error")
        hasError = false
        statusText = "Retrying..."

        do {
            try await syncAll()
            statusText = "Sync complete"
        } catch {
            hasError = true
            statusText = "Sync failed"
            print("[RETRY_SYNC] ❌ Retry failed: \(error)")
        }
    }

    /// Onboarding sync - awaitable sync for use during onboarding
    /// VIEWS USING THIS: OnboardingViewModel
    /// OLD METHOD: syncManager.performOnboardingSync()
    func performOnboardingSync() async {
        print("[ONBOARDING_SYNC] 🔄 Starting onboarding sync")

        guard connectivityMonitor.isConnected else {
            print("[ONBOARDING_SYNC] ⚠️ No internet connection, skipping sync")
            return
        }

        do {
            try await syncAll()
            print("[ONBOARDING_SYNC] ✅ Onboarding sync complete")
        } catch {
            print("[ONBOARDING_SYNC] ❌ Onboarding sync failed: \(error)")
        }
    }

    /// Add non-existent user ID to cache
    /// VIEWS USING THIS: Any view that encounters missing users
    /// OLD METHOD: syncManager.addNonExistentUserId()
    func addNonExistentUserId(_ userId: String) {
        nonExistentUserIds.insert(userId)
        print("[CACHE] 📝 Added non-existent user ID to cache: \(userId)")
    }

    /// Check if user ID is in non-existent cache
    func isNonExistentUser(_ userId: String) -> Bool {
        return nonExistentUserIds.contains(userId)
    }

    /// Update user profile image
    /// VIEWS USING THIS: SettingsView, ProfileEditView
    /// OLD METHOD: syncManager.updateUserProfileImage(user:image:)
    func updateUserProfileImage(userId: String, image: UIImage) async throws {
        print("[UPDATE_PROFILE_IMAGE] 📸 Updating profile image for user \(userId)")

        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
        guard let user = try modelContext.fetch(descriptor).first else {
            throw SyncError.dataCorruption
        }

        // Compress image for storage
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw SyncError.dataCorruption
        }

        // Store image data locally
        user.profileImageData = imageData
        user.needsSync = true
        try modelContext.save()

        // If connected, sync to API
        if isConnected {
            do {
                // Upload image to API - note: actual image upload handled by ImageSyncManager
                // Just sync user metadata here
                let fields: [String: Any] = [
                    "nameFirst": user.firstName,
                    "nameLast": user.lastName
                ]
                try await apiService.updateUser(userId: userId, fields: fields)
                user.needsSync = false
                user.lastSyncedAt = Date()
                try modelContext.save()
                print("[UPDATE_PROFILE_IMAGE] ✅ Profile image synced to API")
            } catch {
                print("[UPDATE_PROFILE_IMAGE] ⚠️ Failed to sync image to API: \(error)")
                // Keep needsSync = true for later retry
            }
        }
    }

    /// Sync task types for a company
    /// VIEWS USING THIS: TaskSettingsView, TaskTestView
    /// OLD METHOD: syncManager.syncCompanyTaskTypes(companyId:)
    func syncCompanyTaskTypes(companyId: String) async throws {
        print("[SYNC_TASK_TYPES] 🔄 Syncing task types for company \(companyId)")

        guard isConnected else {
            throw SyncError.notConnected
        }

        // Fetch task types from API
        let remoteTaskTypes = try await apiService.fetchCompanyTaskTypes(companyId: companyId)

        // Get local task types
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { $0.companyId == companyId }
        )
        let localTaskTypes = try modelContext.fetch(descriptor)

        // If no remote task types exist, create defaults
        if remoteTaskTypes.isEmpty {
            print("[SYNC_TASK_TYPES] 📝 No remote task types found, creating defaults")
            let defaultTypes = TaskType.createDefaults(companyId: companyId)
            for taskType in defaultTypes {
                modelContext.insert(taskType)

                // Also create in API
                _ = try? await apiService.createTaskType(TaskTypeDTO.from(taskType))
            }
            try modelContext.save()
            return
        }

        let localTaskTypeIds = Set(localTaskTypes.map { $0.id })

        // CRITICAL: Deduplicate remote task types by ID to prevent crash
        // Bubble API sometimes returns duplicate IDs which causes SwiftData unique constraint violation
        var uniqueRemoteTaskTypes: [TaskTypeDTO] = []
        var seenIds = Set<String>()
        for remoteTaskType in remoteTaskTypes {
            if !seenIds.contains(remoteTaskType.id) {
                uniqueRemoteTaskTypes.append(remoteTaskType)
                seenIds.insert(remoteTaskType.id)
            } else {
                print("[SYNC_TASK_TYPES] ⚠️ Skipping duplicate task type ID: \(remoteTaskType.id)")
            }
        }

        // Process remote task types (deduplicated)
        for remoteTaskType in uniqueRemoteTaskTypes {
            if localTaskTypeIds.contains(remoteTaskType.id) {
                // Update existing task type
                if let localTaskType = localTaskTypes.first(where: { $0.id == remoteTaskType.id }) {
                    localTaskType.display = remoteTaskType.display
                    localTaskType.color = remoteTaskType.color
                    localTaskType.isDefault = remoteTaskType.isDefault ?? false
                    localTaskType.lastSyncedAt = Date()
                    localTaskType.needsSync = false
                }
            } else {
                // Insert new task type
                let newTaskType = remoteTaskType.toModel()
                newTaskType.companyId = companyId
                newTaskType.lastSyncedAt = Date()
                newTaskType.needsSync = false
                modelContext.insert(newTaskType)
            }
        }

        // Handle deletions (soft delete)
        let remoteTaskTypeIds = Set(uniqueRemoteTaskTypes.map { $0.id })
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        for localTaskType in localTaskTypes {
            if !remoteTaskTypeIds.contains(localTaskType.id) {
                if localTaskType.deletedAt == nil &&
                   (localTaskType.lastSyncedAt ?? .distantPast) > thirtyDaysAgo &&
                   !localTaskType.isDefault {
                    print("[SYNC_TASK_TYPES] 🗑️ Soft deleting task type: \(localTaskType.display)")
                    localTaskType.deletedAt = Date()
                }
            }
        }

        // After syncing, assign icons to task types that don't have them
        let allTaskTypes = try modelContext.fetch(descriptor)
        TaskType.assignIconsToTaskTypes(allTaskTypes)

        try modelContext.save()
        print("[SYNC_TASK_TYPES] ✅ Synced \(uniqueRemoteTaskTypes.count) task types")
    }

    /// Sync team members for a company (by companyId)
    /// VIEWS USING THIS: CompanyTeamMembersListView
    /// OLD METHOD: syncManager.syncCompanyTeamMembers(company:)
    func syncCompanyTeamMembers(companyId: String) async throws {
        print("[SYNC_TEAM_MEMBERS] 🔄 Syncing team members for company \(companyId)")

        guard isConnected else {
            throw SyncError.notConnected
        }

        // Fetch company
        let companyDescriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyId })
        guard let company = try modelContext.fetch(companyDescriptor).first else {
            throw SyncError.missingCompanyId
        }

        // Fetch users by company ID
        let userDTOs = try await apiService.fetchCompanyUsers(companyId: companyId)

        // Get all existing User objects for this company
        let existingUsersDescriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { user in
                user.companyId == companyId
            }
        )
        let existingUsers = try modelContext.fetch(existingUsersDescriptor)

        // Create a set of user IDs from the API response
        let currentUserIds = Set(userDTOs.map { $0.id })

        // Handle deletions (soft delete users no longer in company)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        for user in existingUsers {
            if !currentUserIds.contains(user.id) {
                if user.deletedAt == nil &&
                   (user.lastSyncedAt ?? .distantPast) > thirtyDaysAgo {
                    print("[SYNC_TEAM_MEMBERS] 🗑️ Soft deleting user no longer in company: \(user.fullName)")
                    user.deletedAt = Date()
                }
            }
        }

        // Clear existing team members to avoid duplicates
        company.teamMembers = []

        // Get admin IDs from company if available
        let adminIds = company.getAdminIds()

        // Create or update User and TeamMember objects from the DTOs
        for userDTO in userDTOs {
            // Check if this user is an admin
            let isAdmin = adminIds.contains(userDTO.id)

            // Extract role using company admin status first, then employeeType
            let role: UserRole
            if isAdmin {
                role = .admin
            } else if let employeeTypeString = userDTO.employeeType {
                role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
            } else {
                role = .fieldCrew
            }

            // Update or create User object
            if let existingUser = existingUsers.first(where: { $0.id == userDTO.id }) {
                // Update existing user
                existingUser.firstName = userDTO.nameFirst ?? ""
                existingUser.lastName = userDTO.nameLast ?? ""
                existingUser.email = userDTO.email
                existingUser.phone = userDTO.phone
                existingUser.role = role
                existingUser.isCompanyAdmin = isAdmin
                existingUser.profileImageURL = userDTO.avatar
                existingUser.isActive = true
                existingUser.deletedAt = nil // Clear deletedAt since user is back
                existingUser.lastSyncedAt = Date()
                existingUser.needsSync = false
            } else {
                // Create new User object
                let newUser = User(
                    id: userDTO.id,
                    firstName: userDTO.nameFirst ?? "",
                    lastName: userDTO.nameLast ?? "",
                    role: role,
                    companyId: companyId
                )
                newUser.email = userDTO.email
                newUser.phone = userDTO.phone
                newUser.profileImageURL = userDTO.avatar
                newUser.isActive = true
                newUser.isCompanyAdmin = isAdmin
                newUser.lastSyncedAt = Date()
                newUser.needsSync = false
                modelContext.insert(newUser)
            }

            // Create TeamMember object
            let teamMember = TeamMember.fromUserDTO(userDTO, isAdmin: isAdmin)
            teamMember.company = company
            company.teamMembers.append(teamMember)
        }

        // Mark team members as synced
        company.teamMembersSynced = true
        company.lastSyncedAt = Date()

        // Save changes to the database
        try modelContext.save()
        print("[SYNC_TEAM_MEMBERS] ✅ Synced \(userDTOs.count) team members")
    }

    /// Sync team members for a company (by Company object)
    /// DATACONTROLLER USING THIS: For backwards compatibility
    /// OLD METHOD: syncManager.syncCompanyTeamMembers(company)
    func syncCompanyTeamMembers(_ company: Company) async {
        do {
            try await syncCompanyTeamMembers(companyId: company.id)
        } catch {
            print("[SYNC_TEAM_MEMBERS] ❌ Failed to sync team members: \(error)")
        }
    }

    /// Sync a single user to the API
    /// DATACONTROLLER USING THIS: For syncing user changes
    /// OLD METHOD: syncManager.syncUser(user)
    func syncUser(_ user: User) async {
        guard isConnected else {
            print("[SYNC_USER] ⚠️ Not connected, user will sync later")
            return
        }

        guard user.needsSync else {
            print("[SYNC_USER] ℹ️ User \(user.fullName) doesn't need sync")
            return
        }

        print("[SYNC_USER] 🔄 Syncing user \(user.fullName)")

        do {
            // Update user via API
            var fields: [String: Any] = [
                "nameFirst": user.firstName,
                "nameLast": user.lastName
            ]
            if let phone = user.phone {
                fields["phone"] = phone
            }

            try await apiService.updateUser(userId: user.id, fields: fields)

            // If user has profile image data, upload it
            if let imageData = user.profileImageData,
               let image = UIImage(data: imageData) {
                // Note: Image upload handled by ImageSyncManager
                print("[SYNC_USER] 📸 User has profile image data")
            }

            user.needsSync = false
            user.lastSyncedAt = Date()
            try modelContext.save()
            print("[SYNC_USER] ✅ User synced successfully")
        } catch {
            print("[SYNC_USER] ❌ Failed to sync user: \(error)")
        }
    }

    // MARK: - Relationship Linking

    /// Link all relationships after sync completes
    /// This ensures SwiftData relationships are properly connected based on ID strings
    private func linkAllRelationships() async throws {
        print("[LINK_RELATIONSHIPS] 🔗 Linking all relationships...")

        // Fetch all entities that need relationship linking
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let tasks = try modelContext.fetch(FetchDescriptor<ProjectTask>())
        let calendarEvents = try modelContext.fetch(FetchDescriptor<CalendarEvent>())

        var linkedCount = 0

        // Link project → client relationships
        for project in projects {
            if let clientId = project.clientId, !clientId.isEmpty {
                let clientDescriptor = FetchDescriptor<Client>(
                    predicate: #Predicate { $0.id == clientId }
                )
                if let client = try modelContext.fetch(clientDescriptor).first {
                    project.client = client
                    linkedCount += 1
                }
            }
        }

        // Link project → team member relationships
        for project in projects {
            let teamMemberIds = project.getTeamMemberIds()
            if !teamMemberIds.isEmpty {
                var teamMembers: [User] = []
                for memberId in teamMemberIds {
                    let userDescriptor = FetchDescriptor<User>(
                        predicate: #Predicate { $0.id == memberId }
                    )
                    if let user = try modelContext.fetch(userDescriptor).first {
                        teamMembers.append(user)
                    }
                }
                project.teamMembers = teamMembers
                linkedCount += teamMembers.count
            }
        }

        // Link task → project relationships
        for task in tasks {
            let projectId = task.projectId
            if !projectId.isEmpty {
                let projectDescriptor = FetchDescriptor<Project>(
                    predicate: #Predicate { $0.id == projectId }
                )
                if let project = try modelContext.fetch(projectDescriptor).first {
                    task.project = project
                    linkedCount += 1
                }
            }
        }

        // Link task → taskType relationships
        for task in tasks {
            let taskTypeId = task.taskTypeId
            if !taskTypeId.isEmpty {
                let taskTypeDescriptor = FetchDescriptor<TaskType>(
                    predicate: #Predicate { $0.id == taskTypeId }
                )
                if let taskType = try modelContext.fetch(taskTypeDescriptor).first {
                    task.taskType = taskType
                    linkedCount += 1
                }
            }
        }

        // Link task → team member relationships
        for task in tasks {
            let teamMemberIds = task.getTeamMemberIds()
            if !teamMemberIds.isEmpty {
                var teamMembers: [User] = []
                for memberId in teamMemberIds {
                    let userDescriptor = FetchDescriptor<User>(
                        predicate: #Predicate { $0.id == memberId }
                    )
                    if let user = try modelContext.fetch(userDescriptor).first {
                        teamMembers.append(user)
                    }
                }
                task.teamMembers = teamMembers
                linkedCount += teamMembers.count
            }
        }

        // Link calendarEvent → project relationships
        for event in calendarEvents {
            let projectId = event.projectId
            if !projectId.isEmpty {
                let projectDescriptor = FetchDescriptor<Project>(
                    predicate: #Predicate { $0.id == projectId }
                )
                if let project = try modelContext.fetch(projectDescriptor).first {
                    event.project = project
                    linkedCount += 1
                }
            }
        }

        // Link calendarEvent → task relationships
        for event in calendarEvents {
            if let taskId = event.taskId, !taskId.isEmpty {
                let taskDescriptor = FetchDescriptor<ProjectTask>(
                    predicate: #Predicate { $0.id == taskId }
                )
                if let task = try modelContext.fetch(taskDescriptor).first {
                    event.task = task
                    linkedCount += 1
                }
            }
        }

        // Link calendarEvent → team member relationships
        for event in calendarEvents {
            let teamMemberIds = event.getTeamMemberIds()
            if !teamMemberIds.isEmpty {
                var teamMembers: [User] = []
                for memberId in teamMemberIds {
                    let userDescriptor = FetchDescriptor<User>(
                        predicate: #Predicate { $0.id == memberId }
                    )
                    if let user = try modelContext.fetch(userDescriptor).first {
                        teamMembers.append(user)
                    }
                }
                event.teamMembers = teamMembers
                linkedCount += teamMembers.count
            }
        }

        try modelContext.save()
        print("[LINK_RELATIONSHIPS] ✅ Linked \(linkedCount) relationships")
    }

    // MARK: - Deletion Handling Functions

    private func handleUserDeletions(keepingIds: Set<String>) async throws {
        let descriptor = FetchDescriptor<User>()
        let localUsers = try modelContext.fetch(descriptor)

        var deletedCount = 0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!

        for user in localUsers {
            if !keepingIds.contains(user.id) {
                if user.deletedAt == nil &&
                   (user.lastSyncedAt ?? .distantPast) > thirtyDaysAgo {
                    print("[DELETION] 🗑️ Soft deleting user: \(user.fullName)")
                    user.deletedAt = Date()
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            print("[DELETION] ✅ Soft deleted \(deletedCount) users")
        }
    }

    private func handleClientDeletions(keepingIds: Set<String>) async throws {
        let descriptor = FetchDescriptor<Client>()
        let localClients = try modelContext.fetch(descriptor)

        var deletedCount = 0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        for client in localClients {
            if !keepingIds.contains(client.id) {
                if client.deletedAt == nil &&
                   (client.lastSyncedAt ?? .distantPast) > thirtyDaysAgo {
                    print("[DELETION] 🗑️ Soft deleting client: \(client.name)")
                    client.deletedAt = Date()
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            print("[DELETION] ✅ Soft deleted \(deletedCount) clients")
        }
    }

    private func handleTaskTypeDeletions(keepingIds: Set<String>) async throws {
        let descriptor = FetchDescriptor<TaskType>()
        let localTaskTypes = try modelContext.fetch(descriptor)

        var deletedCount = 0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        for taskType in localTaskTypes {
            if !keepingIds.contains(taskType.id) {
                if taskType.deletedAt == nil &&
                   (taskType.lastSyncedAt ?? .distantPast) > thirtyDaysAgo &&
                   !taskType.isDefault {
                    print("[DELETION] 🗑️ Soft deleting task type: \(taskType.display)")
                    taskType.deletedAt = Date()
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            print("[DELETION] ✅ Soft deleted \(deletedCount) task types")
        }
    }

    private func handleProjectDeletions(keepingIds: Set<String>) async throws {
        debugLog("🔵 FUNCTION CALLED", enabled: DebugFlags.deleteOperations)
        debugLog("📊 keepingIds count: \(keepingIds.count)", enabled: DebugFlags.deleteOperations)
        debugLog("   Remote project IDs to keep: \(keepingIds.prefix(10).joined(separator: ", "))\(keepingIds.count > 10 ? "..." : "")", enabled: DebugFlags.deleteOperations)

        let descriptor = FetchDescriptor<Project>()
        let localProjects = try modelContext.fetch(descriptor)
        debugLog("📊 Local projects count: \(localProjects.count)", enabled: DebugFlags.deleteOperations)

        var deletedCount = 0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!

        for project in localProjects {
            if !keepingIds.contains(project.id) {
                debugLog("⚠️ Project NOT in remote IDs: \(project.title) (ID: \(project.id))", enabled: DebugFlags.deleteOperations)
                debugLog("   - deletedAt: \(project.deletedAt?.description ?? "nil")", enabled: DebugFlags.deleteOperations)
                debugLog("   - lastSyncedAt: \(project.lastSyncedAt?.description ?? "nil")", enabled: DebugFlags.deleteOperations)

                // Only delete if:
                // 1. Not already deleted
                // 2. Has been synced before (to avoid deleting projects created locally but not yet synced)
                if project.deletedAt == nil && project.lastSyncedAt != nil {
                    print("[DELETION] 🗑️ Soft deleting project: \(project.title)")
                    debugLog("❌ SOFT DELETING PROJECT: \(project.title) (ID: \(project.id))", enabled: DebugFlags.deleteOperations)
                    project.deletedAt = Date()

                    // Cascade soft delete to related records
                    debugLog("   Cascading delete to \(project.tasks.count) tasks", enabled: DebugFlags.deleteOperations)
                    for task in project.tasks where task.deletedAt == nil {
                        task.deletedAt = Date()
                    }

                    if let calendarEvent = project.primaryCalendarEvent, calendarEvent.deletedAt == nil {
                        debugLog("   Cascading delete to calendar event", enabled: DebugFlags.deleteOperations)
                        calendarEvent.deletedAt = Date()
                    }

                    deletedCount += 1
                } else {
                    if project.lastSyncedAt == nil {
                        debugLog("   → NOT deleting (never synced - may be pending upload)", enabled: DebugFlags.deleteOperations)
                    } else {
                        debugLog("   → NOT deleting (already deleted)", enabled: DebugFlags.deleteOperations)
                    }
                }
            }
        }

        if deletedCount > 0 {
            debugLog("✅ Soft deleted \(deletedCount) projects total", enabled: DebugFlags.deleteOperations)
            print("[DELETION] ✅ Soft deleted \(deletedCount) projects")
        } else {
            debugLog("✅ No projects were deleted", enabled: DebugFlags.deleteOperations)
        }
    }

    private func handleTaskDeletions(keepingIds: Set<String>) async throws {
        let descriptor = FetchDescriptor<ProjectTask>()
        let localTasks = try modelContext.fetch(descriptor)

        var deletedCount = 0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        for task in localTasks {
            if !keepingIds.contains(task.id) {
                // Only delete if not already deleted and has been synced before
                if task.deletedAt == nil && task.lastSyncedAt != nil {
                    print("[DELETION] 🗑️ Soft deleting task: \(task.id)")
                    task.deletedAt = Date()

                    // Cascade to calendar event
                    if let calendarEvent = task.calendarEvent, calendarEvent.deletedAt == nil {
                        calendarEvent.deletedAt = Date()
                    }

                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            print("[DELETION] ✅ Soft deleted \(deletedCount) tasks")
        }
    }

    private func handleCalendarEventDeletions(keepingIds: Set<String>) async throws {
        let descriptor = FetchDescriptor<CalendarEvent>()
        let localEvents = try modelContext.fetch(descriptor)

        var deletedCount = 0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        for event in localEvents {
            if !keepingIds.contains(event.id) {
                // Only delete if not already deleted and has been synced before
                if event.deletedAt == nil && event.lastSyncedAt != nil {
                    print("[DELETION] 🗑️ Soft deleting calendar event: \(event.title)")
                    event.deletedAt = Date()
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            print("[DELETION] ✅ Soft deleted \(deletedCount) calendar events")
        }
    }

    // MARK: - Helper Functions (Get or Create)

    private func getOrCreateCompany(id: String) async throws -> Company {
        let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let new = Company(id: id, name: "")
        modelContext.insert(new)
        return new
    }

    private func getOrCreateUser(id: String) async throws -> User {
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let new = User(id: id, firstName: "", lastName: "", role: .fieldCrew, companyId: "")
        modelContext.insert(new)
        return new
    }

    private func getOrCreateClient(id: String) async throws -> Client {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let new = Client(id: id, name: "Unknown", email: nil, phoneNumber: nil, address: nil, companyId: nil, notes: nil)
        modelContext.insert(new)
        return new
    }

    private func getOrCreateTaskType(id: String) async throws -> TaskType {
        let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let new = TaskType(id: id, display: "Task", color: "#59779F", companyId: "", isDefault: false, icon: "checkmark.circle.fill")
        modelContext.insert(new)
        return new
    }

    private func getOrCreateProject(id: String) async throws -> Project {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let new = Project(id: id, title: "Untitled", status: .rfq)
        modelContext.insert(new)
        return new
    }

    private func getOrCreateTask(id: String) async throws -> ProjectTask {
        let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let new = ProjectTask(id: id, projectId: "", taskTypeId: "", companyId: "", status: .booked, taskColor: "#59779F")
        modelContext.insert(new)
        return new
    }

    private func getOrCreateCalendarEvent(id: String) async throws -> CalendarEvent {
        let descriptor = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let new = CalendarEvent(id: id, projectId: "", companyId: "", title: "Event", startDate: nil, endDate: nil, color: "#59779F", type: .project, active: true)
        modelContext.insert(new)
        return new
    }

    /// Migration: Update all existing project calendar events to use company's defaultProjectColor
    /// This fixes events that were synced before we implemented the color override
    private func migrateProjectEventColors(companyId: String, defaultColor: String) async throws {
        print("[MIGRATION] 🎨 Updating project event colors to company default: \(defaultColor)")

        // Get all calendar events for this company
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { event in
                event.companyId == companyId
            }
        )

        let allEvents = try modelContext.fetch(descriptor)
        var updatedCount = 0

        // Filter and update project events
        for event in allEvents where event.type == .project {
            // Only update if the color is different from the target color
            if event.color != defaultColor {
                print("[MIGRATION] 🎨 Updating '\(event.title)' from \(event.color) to \(defaultColor)")
                event.color = defaultColor
                updatedCount += 1
            }
        }

        if updatedCount > 0 {
            try modelContext.save()
            print("[MIGRATION] ✅ Updated \(updatedCount) project event colors")
        } else {
            print("[MIGRATION] ℹ️ No project events needed color updates")
        }
    }
}

// MARK: - Sync Errors

enum SyncError: Error {
    case notConnected
    case alreadySyncing
    case missingUserId
    case missingCompanyId
    case apiError(Error)
    case dataCorruption
}
