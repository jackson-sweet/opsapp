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
class SyncManager {
    private let modelContext: ModelContext
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor
    private let backgroundTaskManager: BackgroundTaskManager
    
    private var syncInProgress = false
    private var backgroundSyncTask: Task<Void, Never>?
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
                self?.backgroundSyncTask?.cancel()
                self?.syncInProgress = false
            }
        }
    }
    
    // MARK: - Sync Triggers
    
    /// Trigger background sync operation
    func triggerBackgroundSync() {
        // Cancel any existing sync task
        backgroundSyncTask?.cancel()
        
        // Start a new sync task
        backgroundSyncTask = Task { [weak self] in
            guard let self = self, !self.syncInProgress else { return }
            
            self.syncInProgress = true
            
            do {
                // Sync jobs
                try await self.syncJobs()
                
                // Only mark sync as complete if we weren't cancelled
                if !Task.isCancelled {
                    self.syncInProgress = false
                }
            } catch {
                print("Background sync failed: \(error.localizedDescription)")
                self.syncInProgress = false
            }
        }
    }
    
    /// Perform a full sync operation
    /// Called when app enters foreground or manually by user
    func performFullSync() async {
        guard !syncInProgress, connectivityMonitor.isConnected else { return }
        
        syncInProgress = true
        
        do {
            // Sync organization first
            try await syncOrganization()
            
            // Then users (which might be needed for jobs)
            try await syncUsers()
            
            // Finally jobs
            try await syncJobs()
            
            syncInProgress = false
        } catch {
            print("Full sync failed: \(error.localizedDescription)")
            syncInProgress = false
        }
    }
    
    // MARK: - Job-specific Sync Methods
    
    /// Update job status locally and queue for sync
    /// This is a critical function for field workers - it must succeed locally
    /// even when offline
    /// - Parameters:
    ///   - jobId: Job identifier
    ///   - status: New job status
    /// - Returns: Success indicator
    @discardableResult
    func updateJobStatus(jobId: String, status: JobStatus) -> Bool {
        let predicate = #Predicate<Job> { $0.id == jobId }
        let fetchDescriptor = FetchDescriptor<Job>(predicate: predicate)
        
        do {
            // Get the job
            let jobs = try modelContext.fetch(fetchDescriptor)
            guard let job = jobs.first else {
                return false
            }
            
            // Update status locally
            job.status = status
            job.needsSync = true
            job.syncPriority = 3 // Highest priority
            
            // Update timestamps based on status
            if status == .inProgress && job.startDate == nil {
                job.startDate = Date()
            } else if status == .completed && job.endDate == nil {
                job.endDate = Date()
            }
            
            // Save local changes
            try modelContext.save()
            
            // Queue sync if online
            if connectivityMonitor.isConnected {
                // Prioritize this specific job for sync
                Task {
                    try await syncJobStatus(job)
                }
            }
            
            return true
        } catch {
            print("Failed to update job status locally: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Sync a specific job's status to the backend
    /// - Parameter job: The job to sync
    private func syncJobStatus(_ job: Job) async throws {
        // Only sync if job needs sync
        guard job.needsSync else { return }
        
        do {
            // Try to update status on server
            try await apiService.updateJobStatus(id: job.id, status: job.status.rawValue)
            
            // Mark as synced if successful
            job.needsSync = false
            job.lastSyncedAt = Date()
            try modelContext.save()
        } catch {
            // Leave as needsSync=true to retry later
            print("Failed to sync job status: \(error.localizedDescription)")
            // We don't rethrow - the local update succeeded, server sync can be retried
        }
    }
    
    /// Sync any pending job status changes
    /// - Returns: Success count
    private func syncPendingJobStatusChanges() async -> Int {
        // Find jobs that need sync, ordered by priority
        let predicate = #Predicate<Job> { $0.needsSync == true }
        var fetchDescriptor = FetchDescriptor<Job>(predicate: predicate)
        fetchDescriptor.sortBy = [SortDescriptor(\.syncPriority, order: .reverse)]
        
        do {
            let pendingJobs = try modelContext.fetch(fetchDescriptor)
            var successCount = 0
            
            // Try to sync each job
            for job in pendingJobs {
                do {
                    try await syncJobStatus(job)
                    successCount += 1
                } catch {
                    // Continue with next job even if one fails
                    continue
                }
            }
            
            return successCount
        } catch {
            print("Failed to fetch pending jobs: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// Sync users between local storage and backend
    private func syncUsers() async throws {
        // Fetch remote users
        let remoteUsers = try await apiService.fetchUsers()
        
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
    }
    
    /// Sync organization data between local storage and backend
    private func syncOrganization() async throws {
        // For MVP, just handle the current user's organization
        guard let currentUserOrgId = getCurrentUserOrganizationId() else {
            return
        }
        
        // Fetch remote organization
        let remoteOrg = try await apiService.fetchOrganization(id: currentUserOrgId)
        
        // Fetch local organization
        let predicate = #Predicate<Organization> { $0.id == currentUserOrgId }
        let fetchDescriptor = FetchDescriptor<Organization>(predicate: predicate)
        let localOrgs = try modelContext.fetch(fetchDescriptor)
        
        if let localOrg = localOrgs.first {
            // Update existing organization
            if !localOrg.needsSync {
                localOrg.name = remoteOrg.name
                localOrg.lastSyncedAt = Date()
            }
        } else {
            // Add new organization
            let newOrg = remoteOrg.toModel()
            modelContext.insert(newOrg)
        }
        
        try modelContext.save()
    }
    
    // MARK: - Helper Methods
    
    /// Update a local job with remote data
    private func updateLocalJobFromRemote(_ localJob: Job, remoteDTO: JobDTO) {
        localJob.title = remoteDTO.title
        localJob.clientName = remoteDTO.clientName
        localJob.address = remoteDTO.address
        localJob.latitude = remoteDTO.latitude
        localJob.longitude = remoteDTO.longitude
        
        let dateFormatter = ISO8601DateFormatter()
        if let startDateString = remoteDTO.startDate {
            localJob.startDate = dateFormatter.date(from: startDateString)
        }
        if let endDateString = remoteDTO.endDate {
            localJob.endDate = dateFormatter.date(from: endDateString)
        }
        
        localJob.status = JobStatus(rawValue: remoteDTO.status) ?? .upcoming
        localJob.notes = remoteDTO.notes
        localJob.lastSyncedAt = Date()
    }
    
    /// Update a local user with remote data
    private func updateLocalUserFromRemote(_ localUser: User, remoteDTO: UserDTO) {
        localUser.firstName = remoteDTO.firstName
        localUser.lastName = remoteDTO.lastName
        localUser.phoneNumber = remoteDTO.phoneNumber
        localUser.email = remoteDTO.email
        localUser.role = UserRole(rawValue: remoteDTO.role) ?? .fieldCrew
        localUser.lastSyncedAt = Date()
    }
    
    /// Update job assignments based on user IDs
    private func updateJobAssignments(job: Job, userIds: [String], usersMap: [String: User]) {
        // Clear existing assigned users
        job.assignedUsers = []
        
        // Add new assigned users
        for userId in userIds {
            if let user = usersMap[userId] {
                job.assignedUsers?.append(user)
            }
        }
    }
    
    /// Get the current user's organization ID
    private func getCurrentUserOrganizationId() -> String? {
        // In a real implementation, would get this from user session
        // For MVP, use a hardcoded ID or fetch from UserDefaults
        return UserDefaults.standard.string(forKey: "currentUserOrganizationId")
    }
}