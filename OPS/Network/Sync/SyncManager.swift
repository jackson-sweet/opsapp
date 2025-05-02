//
//  SyncManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation
import SwiftData
import Combine

@MainActor
class SyncManager {
    // MARK: - Sync State Publisher
    // MARK: - Properties
    
    typealias UserIdProvider = () -> String?
    private let userIdProvider: UserIdProvider
    
    let modelContext: ModelContext
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor
    private let backgroundTaskManager: BackgroundTaskManager
    
    private(set) var syncInProgress = false {
        didSet {
            // Publish state changes
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
    
    // MARK: - Initialization
    init(modelContext: ModelContext,
         apiService: APIService,
         connectivityMonitor: ConnectivityMonitor,
         backgroundTaskManager: BackgroundTaskManager = BackgroundTaskManager(),
         userIdProvider: @escaping UserIdProvider = { return nil }) {
        
        self.modelContext = modelContext
        self.apiService = apiService
        self.connectivityMonitor = connectivityMonitor
        self.backgroundTaskManager = backgroundTaskManager
        self.userIdProvider = userIdProvider
    }
    
    // MARK: - Public Methods
    
    /// Sync a user to the API
    func syncUser(_ user: User) async {
        guard !syncInProgress, connectivityMonitor.isConnected else {
            return
        }
        
        syncInProgress = true
        syncStateSubject.send(true)
        
        do {
            // In a real implementation, this would call the API service to update the user
            // apiService.updateUser(user)
            
            // For now, just mark as synced
            user.needsSync = false
            user.lastSyncedAt = Date()
            try modelContext.save()
            
            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
            print("Error syncing user: \(error.localizedDescription)")
        }
        
        syncInProgress = false
        syncStateSubject.send(false)
    }
    
    /// Trigger background sync with intelligent retry
    func triggerBackgroundSync() {
        guard !syncInProgress, connectivityMonitor.isConnected else {
            return
        }
        
        syncInProgress = true
        
        Task {
            do {
                // First sync high-priority items (status changes)
                let highPriorityCount = await syncPendingProjectStatusChanges()
                
                // Then fetch remote data if we didn't exhaust our sync budget
                if highPriorityCount < 10 {
                    try await syncProjects()
                }
                
                syncInProgress = false
            } catch {
                print("Sync failed: \(error.localizedDescription)")
                syncInProgress = false
            }
        }
    }
    
    /// Update project status locally and queue for sync
    @discardableResult
    func updateProjectStatus(projectId: String, status: Status) -> Bool {
        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        
        do {
            let projects = try modelContext.fetch(descriptor)
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
                // Don't await - allow to happen in background
                Task {
                    await syncProjectStatus(project)
                }
            }
            
            return true
        } catch {
            print("Failed to update project status locally: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Sync Methods
    
    /// Sync a specific project's status to the backend
    private func syncProjectStatus(_ project: Project) async {
        // Only sync if project needs sync
        guard project.needsSync else { return }
        
        do {
            // Try to update status on server
            try await apiService.updateProjectStatus(id: project.id, status: project.status.rawValue)
            
            // Mark as synced if successful
            project.needsSync = false
            project.lastSyncedAt = Date()
            try modelContext.save()
        } catch {
            // Leave as needsSync=true to retry later
            print("Failed to sync project status: \(error.localizedDescription)")
        }
    }
    
    /// Sync any pending project status changes
    private func syncPendingProjectStatusChanges() async -> Int {
        // Find projects that need sync, ordered by priority
        let predicate = #Predicate<Project> { $0.needsSync == true }
        var descriptor = FetchDescriptor<Project>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.syncPriority, order: .reverse)]
        
        do {
            let pendingProjects = try modelContext.fetch(descriptor)
            var successCount = 0
            
            // Process in batches of 10 to avoid large transaction costs
            for batch in pendingProjects.chunked(into: 10) {
                await withTaskGroup(of: Bool.self) { group in
                    for project in batch {
                        group.addTask {
                            await self.syncProjectStatus(project)
                            return true
                        }
                    }
                    
                    for await success in group {
                        if success {
                            successCount += 1
                        }
                    }
                }
                
                // Give UI a chance to breathe between batches
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            return successCount
        } catch {
            print("Failed to fetch pending projects: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Sync projects between local storage and backend
    private func syncProjects() async throws {
        // Get user ID from the provider closure
        guard let userId = userIdProvider() else {
            print("Sync skipped: No user ID available")
            return
        }
        
        // Now using the optimized function to fetch only projects where user is a team member
        print("Syncing projects for user ID: \(userId)")
        let remoteProjects = try await apiService.fetchUserProjects(userId: userId)
        
        // Process batches to avoid memory pressure
        for batch in remoteProjects.chunked(into: 20) {
            await processRemoteProjects(batch)
            
            // Small delay between batches to prevent UI stutter
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
    }
    
    /// Process remote projects and update local database
    private func processRemoteProjects(_ remoteProjects: [ProjectDTO]) async {
        do {
            // Efficiently handle the projects in memory to reduce database pressure
            let localProjectIds = try fetchLocalProjectIds()
            let usersMap = try fetchUsersMap()
            
            for remoteProject in remoteProjects {
                if localProjectIds.contains(remoteProject.id) {
                    await updateExistingProject(remoteProject, usersMap: usersMap)
                } else {
                    await insertNewProject(remoteProject, usersMap: usersMap)
                }
            }
            
            // Save once at the end for better performance
            try modelContext.save()
        } catch {
            print("Failed to process remote projects: \(error)")
        }
    }
    
    /// Fetch just the IDs of local projects for efficient existence checking
    private func fetchLocalProjectIds() throws -> Set<String> {
        let descriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(descriptor)
        return Set(projects.map { $0.id })
    }
    
    /// Create a map of users by ID for efficient relationship handling
    private func fetchUsersMap() throws -> [String: User] {
        let descriptor = FetchDescriptor<User>()
        let users = try modelContext.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    }
    
    /// Update an existing project efficiently
    private func updateExistingProject(_ remoteDTO: ProjectDTO, usersMap: [String: User]) async {
        do {
            
            
            
            let predicate = #Predicate<Project> { $0.id == remoteDTO.id }
            let descriptor = FetchDescriptor<Project>(predicate: predicate)
            
            if let localProject = try modelContext.fetch(descriptor).first, !localProject.needsSync {
                // Only update if not modified locally
                updateLocalProjectFromRemote(localProject, remoteDTO: remoteDTO)
                
                print("Found existing project \(remoteDTO.id), needsSync: \(localProject.needsSync ? "true" : "false")")
                
                // Update team members
                if let teamMembers = remoteDTO.teamMembers {
                    let teamMemberIds = teamMembers.map { $0 }
                    localProject.setTeamMemberIds(teamMemberIds)
                    updateProjectTeamMembers(localProject, teamMemberIds: teamMemberIds, usersMap: usersMap)
                }
            }
        } catch {
            print("Error updating project \(remoteDTO.id): \(error.localizedDescription)")
        }
    }
    
    /// Insert a new project efficiently
    private func insertNewProject(_ remoteDTO: ProjectDTO, usersMap: [String: User]) async {
        let newProject = remoteDTO.toModel()
        modelContext.insert(newProject)
        
        // Set up relationships
        if let teamMembers = remoteDTO.teamMembers {
            let teamMemberIds = teamMembers.map { $0 }
            updateProjectTeamMembers(newProject, teamMemberIds: teamMemberIds, usersMap: usersMap)
        }
    }
    
    /// Update project's team members relationship efficiently
    private func updateProjectTeamMembers(_ project: Project, teamMemberIds: [String], usersMap: [String: User]) {
        // Clear existing team members to avoid duplicates
        project.teamMembers = []
        
        // Add only existing users (avoid fetching again)
        for memberId in teamMemberIds {
            if let user = usersMap[memberId] {
                project.teamMembers.append(user)
                
                // Update inverse relationship if needed
                if !user.assignedProjects.contains(where: { $0.id == project.id }) {
                    user.assignedProjects.append(project)
                }
            }
        }
    }
    
    /// Update a local project with remote data
    private func updateLocalProjectFromRemote(_ localProject: Project, remoteDTO: ProjectDTO) {
        // Update project title and basic info
        localProject.title = remoteDTO.projectName
        
        // Update client name directly
        localProject.clientName = remoteDTO.clientName ?? "Unknown Client"
        
        // Update address and location
        if let bubbleAddress = remoteDTO.address {
            localProject.address = bubbleAddress.formattedAddress
            localProject.latitude = bubbleAddress.lat
            localProject.longitude = bubbleAddress.lng
        }
        
        if let projectImages = remoteDTO.projectImages, !projectImages.isEmpty {
            print("🔄 Syncing \(projectImages.count) images for project \(remoteDTO.id)")
            localProject.projectImagesString = projectImages.joined(separator: ",")
        }
        
        // Update dates
        if let startDateString = remoteDTO.startDate {
            localProject.startDate = DateFormatter.dateFromBubble(startDateString)
        }
        
        if let completionString = remoteDTO.completion {
            localProject.endDate = DateFormatter.dateFromBubble(completionString)
        }
        
        // Update status and other fields
        localProject.status = BubbleFields.JobStatus.toSwiftEnum(remoteDTO.status)
        localProject.notes = remoteDTO.teamNotes ?? remoteDTO.description
        localProject.projectDescription = remoteDTO.description
        localProject.lastSyncedAt = Date()
        
        // Update company ID from company reference
        if let companyRef = remoteDTO.company {
            localProject.companyId = companyRef.stringValue
        }
    }
}

// MARK: - Extensions

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
