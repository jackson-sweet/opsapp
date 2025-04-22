//
//  SyncManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
//
//  SyncManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import Foundation
import SwiftData
import UIKit

/// Manages data synchronization between local storage and backend
/// Uses an offline-first approach with background syncing
@MainActor // Make all properties main-actor isolated by default
class SyncManager {
    private let modelContext: ModelContext
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor
    private let backgroundTaskManager: BackgroundTaskManager
    
    private var syncInProgress = false
    private var syncTimer: Timer?
    
    init(modelContext: ModelContext,
         apiService: APIService,
         connectivityMonitor: ConnectivityMonitor,
         backgroundTaskManager: BackgroundTaskManager = BackgroundTaskManager()) {
        
        self.modelContext = modelContext
        self.apiService = apiService
        self.connectivityMonitor = connectivityMonitor
        self.backgroundTaskManager = backgroundTaskManager
        
        // Set up sync triggers
        setupSyncTriggers()
    }
    
    // MARK: - Setup
    
    /// Configure all the ways sync can be triggered
    private func setupSyncTriggers() {
        // 1. When connectivity changes
        connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
            guard let self = self else { return }
            
            if connectionType != .none {
                self.triggerBackgroundSync()
            }
        }
        
        // 2. Periodic background sync (every 15 minutes when app is active)
        setupPeriodicSync()
        
        // 3. App state changes
        setupAppStateObservers()
    }
    
    /// Set up periodic background sync
    private func setupPeriodicSync() {
        // Sync based on the interval in configuration
        syncTimer = Timer.scheduledTimer(
            withTimeInterval: AppConfiguration.Sync.backgroundSyncInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self = self, self.connectivityMonitor.isConnected else { return }
            
            self.triggerBackgroundSync()
        }
    }
    
    /// Set up observers for app state changes
    private func setupAppStateObservers() {
        // Sync when app comes to foreground - user is looking at data
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Try to finish critical syncs when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    // MARK: - App State Handlers
    
    @objc private func applicationDidBecomeActive() {
        // Always sync when app is opened - user needs fresh data
        triggerBackgroundSync()
    }
    
    @objc private func applicationDidEnterBackground() {
        // Try to finish any critical syncs before suspension
        if syncInProgress {
            backgroundTaskManager.beginTask { [weak self] in
                self?.syncInProgress = false
            }
        }
    }
    
    // MARK: - Sync Triggers
    
    /// Trigger background sync operation
    /// This method doesn't need to be awaited - it starts the sync process and returns immediately
    func triggerBackgroundSync() {
        guard !syncInProgress, connectivityMonitor.isConnected else { return }
        
        syncInProgress = true
        
        Task {
            do {
                // Sync jobs
                try await syncProjects()
                
                // Only mark sync as complete if we weren't cancelled
                if !Task.isCancelled {
                    await MainActor.run {
                        self.syncInProgress = false
                    }
                }
            } catch {
                print("Background sync failed: \(error.localizedDescription)")
                
                await MainActor.run {
                    self.syncInProgress = false
                }
            }
        }
    }
    
    /// Perform a full sync operation
    /// Called when app enters foreground or manually by user
    func performFullSync() async {
        guard !syncInProgress, connectivityMonitor.isConnected else { return }
        
        await MainActor.run {
            syncInProgress = true
        }
        
        do {
            // Sync company first
            try await syncCompany()
            
            // Then users (which might be needed for projects)
            try await syncUsers()
            
            // Finally projects
            try await syncProjects()
            
            await MainActor.run {
                syncInProgress = false
            }
        } catch {
            print("Full sync failed: \(error.localizedDescription)")
            
            await MainActor.run {
                syncInProgress = false
            }
        }
    }
    
    // MARK: - Project-specific Sync Methods
    
    /// Update project status locally and queue for sync
    /// This is a critical function for field workers - it must succeed locally
    /// even when offline
    /// - Parameters:
    ///   - projectId: Project identifier
    ///   - status: New project status
    /// - Returns: Success indicator
    @discardableResult
    func updateProjectStatus(projectId: String, status: Status) -> Bool {
        let predicate = #Predicate<Project> { $0.id == projectId }
        let fetchDescriptor = FetchDescriptor<Project>(predicate: predicate)
        
        do {
            // Get the project
            let projects = try modelContext.fetch(fetchDescriptor)
            guard let project = projects.first else {
                return false
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
            
            // Save local changes
            try modelContext.save()
            
            // Queue sync if online
            if connectivityMonitor.isConnected {
                // Prioritize this specific project for sync
                Task {
                    try await syncProjectStatus(project)
                }
            }
            
            return true
        } catch {
            print("Failed to update project status locally: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Sync a specific project's status to the backend
    /// - Parameter project: The project to sync
    private func syncProjectStatus(_ project: Project) async throws {
        // Only sync if project needs sync
        guard project.needsSync else { return }
        
        do {
            // Try to update status on server
            try await apiService.updateProjectStatus(id: project.id, status: project.status.rawValue)
            
            // Mark as synced if successful
            await MainActor.run {
                project.needsSync = false
                project.lastSyncedAt = Date()
                try? modelContext.save()
            }
        } catch {
            // Leave as needsSync=true to retry later
            print("Failed to sync project status: \(error.localizedDescription)")
            // We don't rethrow - the local update succeeded, server sync can be retried
        }
    }
    
    /// Sync any pending project status changes
    /// - Returns: Success count
    private func syncPendingProjectStatusChanges() async -> Int {
        // Find projects that need sync, ordered by priority
        let predicate = #Predicate<Project> { $0.needsSync == true }
        var fetchDescriptor = FetchDescriptor<Project>(predicate: predicate)
        fetchDescriptor.sortBy = [SortDescriptor(\.syncPriority, order: .reverse)]
        
        do {
            let pendingProjects = try modelContext.fetch(fetchDescriptor)
            var successCount = 0
            
            // Try to sync each project
            for project in pendingProjects {
                do {
                    try await syncProjectStatus(project)
                    successCount += 1
                } catch {
                    // Continue with next project even if one fails
                    continue
                }
            }
            
            return successCount
        } catch {
            print("Failed to fetch pending projects: \(error.localizedDescription)")
            return 0
        }
    }
    
    // MARK: - Sync Operations
    
    /// Sync projects between local storage and backend
    nonisolated private func syncProjects() async throws {
        // First, try to sync any pending local changes
        _ = await syncPendingProjectStatusChanges()
        
        // Fetch remote projects
        let remoteProjects = try await apiService.fetchProjects()
        
        await MainActor.run {
            Task {
                await processRemoteProjects(remoteProjects)
            }
        }
    }
    
    /// Process remote projects and update local database with proper relationship handling
        private func processRemoteProjects(_ remoteProjects: [ProjectDTO]) async {
            do {
                // Fetch local projects
                let fetchDescriptor = FetchDescriptor<Project>()
                let localProjects = try modelContext.fetch(fetchDescriptor)
                
                // Create dictionary for quick lookup
                let localProjectsMap = Dictionary(uniqueKeysWithValues: localProjects.map { ($0.id, $0) })
                
                // Store fetched users in dictionary for assigning to projects
                let usersFetchDescriptor = FetchDescriptor<User>()
                let users = try modelContext.fetch(usersFetchDescriptor)
                let usersMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
                
                // Process remote projects
                for remoteProject in remoteProjects {
                    if let localProject = localProjectsMap[remoteProject.id] {
                        // Update existing project (if not modified locally)
                        if !localProject.needsSync {
                            updateLocalProjectFromRemote(localProject, remoteDTO: remoteProject)
                            
                            // Make sure team member IDs are stored for offline reference
                            localProject.teamMemberIds = remoteProject.teamMembers?.compactMap { $0.uniqueID } ?? []
                            
                            // Update relationship to team members
                            updateProjectTeamMembers(localProject, teamMemberIds: localProject.teamMemberIds, usersMap: usersMap)
                        }
                    } else {
                        // Add new project
                        let newProject = remoteProject.toModel()
                        modelContext.insert(newProject)
                        
                        // Store team member IDs for offline reference
                        newProject.teamMemberIds = remoteProject.teamMembers?.compactMap { $0.uniqueID } ?? []
                        
                        // Set up relationship to team members
                        updateProjectTeamMembers(newProject, teamMemberIds: newProject.teamMemberIds, usersMap: usersMap)
                    }
                }
                
                try modelContext.save()
            } catch {
                print("Failed to process remote projects: \(error)")
            }
        }
        
        /// Update project's team members relationship
        private func updateProjectTeamMembers(_ project: Project, teamMemberIds: [String], usersMap: [String: User]) {
            // Clear existing team members first to avoid duplicates
            project.teamMembers = []
            
            // Add each team member if they exist locally
            for memberId in teamMemberIds {
                if let user = usersMap[memberId] {
                    project.teamMembers.append(user)
                    
                    // Update the inverse relationship if needed
                    if !user.assignedProjects.contains(where: { $0.id == project.id }) {
                        user.assignedProjects.append(project)
                    }
                }
            }
        }
        
        /// Establish relationship between project and users
        func connectProjectToTeamMembers(project: Project, users: [User]) {
            // Clear existing team members to avoid duplicates
            project.teamMembers = []
            
            // Add each user to this project
            for user in users {
                project.teamMembers.append(user)
                
                // Update the inverse relationship
                if !user.assignedProjects.contains(where: { $0.id == project.id }) {
                    user.assignedProjects.append(project)
                }
            }
            
            // Store the IDs for offline reference
            project.teamMemberIds = users.map { $0.id }
        }
    
    /// Sync users between local storage and backend
    private func syncUsers() async throws {
        // Fetch remote users
        let remoteUsers = try await apiService.fetchUsers()
        
        await MainActor.run {
            do {
                // Fetch local users
                let fetchDescriptor = FetchDescriptor<User>()
                let localUsers = try modelContext.fetch(fetchDescriptor)
                
                // Create dictionary for quick lookup
                let localUsersMap = Dictionary(uniqueKeysWithValues: localUsers.map { ($0.id, $0) })
                
                // Process remote users
                for remoteUser in remoteUsers {
                    if let localUser = localUsersMap[remoteUser.id] {
                        // Update existing user (if not modified locally)
                        if !localUser.needsSync {
                            updateLocalUserFromRemote(localUser, remoteDTO: remoteUser)
                        }
                    } else {
                        // Add new user
                        let newUser = remoteUser.toModel()
                        modelContext.insert(newUser)
                    }
                }
                
                try modelContext.save()
            } catch {
                print("Failed to sync users: \(error)")
            }
        }
    }
    
    /// Sync company data between local storage and backend
    private func syncCompany() async throws {
        // For MVP, just handle the current user's company
        guard let currentUserCompanyId = getCurrentUserCompanyId() else {
            return
        }
        
        // Fetch remote company
        let remoteCompany = try await apiService.fetchCompany(id: currentUserCompanyId)
        
        await MainActor.run {
            do {
                // Fetch local company
                let predicate = #Predicate<Company> { $0.id == currentUserCompanyId }
                let fetchDescriptor = FetchDescriptor<Company>(predicate: predicate)
                let localCompanies = try modelContext.fetch(fetchDescriptor)
                
                if let localCompany = localCompanies.first {
                    // Update existing company
                    if !localCompany.needsSync {
                        localCompany.name = remoteCompany.companyName ?? "Unknown Company"
                        localCompany.lastSyncedAt = Date()
                    }
                } else {
                    // Add new company
                    let newCompany = remoteCompany.toModel()
                    modelContext.insert(newCompany)
                }
                
                try modelContext.save()
            } catch {
                print("Failed to sync company: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Update a local project with remote data
    private func updateLocalProjectFromRemote(_ localProject: Project, remoteDTO: ProjectDTO) {
        localProject.title = remoteDTO.projectName
        
        // Client name from client reference
        if let clientRef = remoteDTO.client {
            localProject.clientName = clientRef.text ?? "Unknown Client"
            localProject.clientId = clientRef.uniqueID
        }
        
        // Address and location from Bubble address object
        if let bubbleAddress = remoteDTO.address {
            localProject.address = bubbleAddress.formattedAddress
            localProject.latitude = bubbleAddress.lat
            localProject.longitude = bubbleAddress.lng
        }
        
        // Dates with robust parsing
        if let startDateString = remoteDTO.startDate {
            localProject.startDate = DateFormatter.dateFromBubble(startDateString)
        }
        
        if let completionString = remoteDTO.completion {
            localProject.endDate = DateFormatter.dateFromBubble(completionString)
        }
        
        localProject.status = BubbleFields.JobStatus.toSwiftEnum(remoteDTO.status)
        localProject.notes = remoteDTO.teamNotes ?? remoteDTO.description
        localProject.projectDescription = remoteDTO.description
        localProject.lastSyncedAt = Date()
        
        // Company ID from company reference
        if let companyRef = remoteDTO.company {
            localProject.companyId = companyRef.uniqueID
        }
    }
    
    /// Update a local user with remote data
    private func updateLocalUserFromRemote(_ localUser: User, remoteDTO: UserDTO) {
        localUser.firstName = remoteDTO.nameFirst ?? ""
        localUser.lastName = remoteDTO.nameLast ?? ""
        localUser.email = remoteDTO.email
        
        // Handle role from employee type
        if let employeeTypeString = remoteDTO.employeeType {
            localUser.role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
        }
        
        // Geographic location needs special handling
        if let location = remoteDTO.currentLocation {
            localUser.latitude = location.lat
            localUser.longitude = location.lng
            localUser.locationName = location.formattedAddress
        }
        
        // Company ID from reference
        if let companyRef = remoteDTO.company {
            localUser.companyId = companyRef.uniqueID
        }
        
        localUser.lastSyncedAt = Date()
    }
    
    /// Get the current user's company ID
    private func getCurrentUserCompanyId() -> String? {
        // In a real implementation, would get this from user session
        // For MVP, use a hardcoded ID or fetch from UserDefaults
        return UserDefaults.standard.string(forKey: "currentUserCompanyId")
    }
}
