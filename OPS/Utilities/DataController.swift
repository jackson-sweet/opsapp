//
//  DataController.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Main controller for managing data, authentication, and app state
class DataController: ObservableObject {
    // MARK: - Published States
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var connectionType: ConnectivityMonitor.ConnectionType = .none
    @Published var lastSyncTime: Date?
    
    // MARK: - Dependencies
    private let authManager: AuthManager
    private let apiService: APIService
    private let keychainManager: KeychainManager
    private let connectivityMonitor: ConnectivityMonitor
    var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Access
    var syncManager: SyncManager!
    
    // MARK: - Initialization
    init() {
        // Create dependencies in a predictable order
        self.keychainManager = KeychainManager()
        self.authManager = AuthManager()
        self.connectivityMonitor = ConnectivityMonitor()
        self.apiService = APIService(authManager: authManager)
        
        // Set initial connection state
        isConnected = connectivityMonitor.isConnected
        connectionType = connectivityMonitor.connectionType
        
        // Setup connectivity monitoring
        setupConnectivityMonitoring()
        
        // Check for existing authentication - plain Task for async work
        Task {
            await checkExistingAuth()
        }
    }
    
    // MARK: - Setup
    private func setupConnectivityMonitoring() {
        // Set initial state
        isConnected = connectivityMonitor.isConnected
        connectionType = connectivityMonitor.connectionType
        
        // Handle connection changes
        connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConnected = connectionType != .none
                self.connectionType = connectionType
                
                if connectionType != .none, self.isAuthenticated {
                    Task {
                        self.syncManager?.triggerBackgroundSync()
                    }
                }
            }
        }
    }
    
    @MainActor
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        if isAuthenticated {
            initializeSyncManager()
        }
    }
    
    @MainActor
    private func initializeSyncManager() {
        guard let modelContext = modelContext else { return }
        
        // Create user ID provider closure that returns the current user's ID
        let userIdProvider = { [weak self] in
            return self?.currentUser?.id
        }
        
        self.syncManager = SyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor,
            userIdProvider: userIdProvider
        )
        
        // Listen for sync state changes
        self.syncManager.syncStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isSyncing in
                self?.isSyncing = isSyncing
                if !isSyncing {
                    self?.lastSyncTime = Date()
                }
            }
            .store(in: &cancellables)
    }
    
    // Method to perform sync on app launch
    func performAppLaunchSync() {
        
        let syncOnLaunch = UserDefaults.standard.bool(forKey: "syncOnLaunch")
            
        guard syncOnLaunch,
              isAuthenticated,
              isConnected else { return }
        
        // Check if we've synced too recently
        if let lastSync = lastSyncTime,
           Date().timeIntervalSince(lastSync) < AppConfiguration.Sync.minimumSyncInterval {
            return
        }
        
        // Trigger sync
        Task {
            print("PERFORMING SYNC ON APP LAUNCH")
            await syncManager?.triggerBackgroundSync()
            lastSyncTime = Date()
        }
    }
        
        // Method to check if we're due for a sync
        func shouldSync() -> Bool {
            guard isAuthenticated, isConnected else { return false }
            
            if let lastSync = lastSyncTime {
                return Date().timeIntervalSince(lastSync) >= AppConfiguration.Sync.minimumSyncInterval
            }
            
            return true // Never synced before
        }
    
    // MARK: - Authentication
    @MainActor
    private func checkExistingAuth() async {
        // Check for stored credentials
        if let userId = keychainManager.retrieveUserId(),
           let token = keychainManager.retrieveToken() {
            
            // Validate token expiration
            if let expiration = keychainManager.retrieveTokenExpiration(),
               expiration > Date() {
                do {
                    if let context = modelContext {
                        let descriptor = FetchDescriptor<User>(
                            predicate: #Predicate<User> { $0.id == userId }
                        )
                        
                        let users = try context.fetch(descriptor)
                        
                        if let user = users.first {
                            self.currentUser = user
                            self.isAuthenticated = true
                            
                            if let companyId = user.companyId {
                                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                            }
                            
                            initializeSyncManager()
                            return
                        }
                    }
                    
                    if isConnected {
                        try await fetchUserFromAPI(userId: userId)
                    } else {
                        clearAuthentication()
                    }
                } catch {
                    print("Auth check error: \(error.localizedDescription)")
                    clearAuthentication()
                }
            } else {
                clearAuthentication()
            }
        } else {
            clearAuthentication()
        }
    }
    
    @discardableResult
    @MainActor
    func login(username: String, password: String) async -> Bool {
        do {
            _ = try await authManager.signIn(username: username, password: password)
            
            if let userId = authManager.getUserId() {
                try await fetchUserFromAPI(userId: userId)
                return isAuthenticated
            } else {
                return false
            }
        } catch {
            print("Login failed: \(error.localizedDescription)")
            return false
        }
    }
    
    @MainActor
    private func fetchUserFromAPI(userId: String) async throws {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }
        
        let userDTO = try await apiService.fetchUser(id: userId)
        let user = userDTO.toModel()
        
        context.insert(user)
        try context.save()
        
        self.currentUser = user
        self.isAuthenticated = true
        
        if let companyId = user.companyId {
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
        }
        
        UserDefaults.standard.set(user.id, forKey: "currentUserId")
        
        initializeSyncManager()
        
        if isConnected, let companyId = user.companyId {
            Task {
                try await fetchCompanyData(companyId: companyId)
            }
        }
    }
    
    func logout() {
        authManager.signOut()
        clearAuthentication()
    }
    
    private func clearAuthentication() {
        isAuthenticated = false
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: "currentUserCompanyId")
    }
    
    // MARK: - Data Operations
    
    /// Fetch company data from API - optimized for reliability
    @MainActor
    private func fetchCompanyData(companyId: String) async throws {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Company>(
                predicate: #Predicate<Company> { $0.id == companyId }
            )
            
            let companies = try context.fetch(descriptor)
            
            if companies.isEmpty || (companies.first?.needsSync == true) {
                let companyDTO = try await apiService.fetchCompany(id: companyId)
                
                await MainActor.run {
                    if let existingCompany = companies.first {
                        // Update existing
                        updateCompany(existingCompany, from: companyDTO)
                    } else {
                        // Create new
                        let newCompany = companyDTO.toModel()
                        context.insert(newCompany)
                    }
                    
                    try? context.save()
                }
            }
        } catch {
            print("Company fetch error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Helper to update company from DTO
    private func updateCompany(_ company: Company, from dto: CompanyDTO) {
        company.name = dto.companyName ?? "Unknown Company"
        company.externalId = dto.companyID
        company.companyDescription = dto.companyDescription
        
        if let location = dto.location {
            company.address = location.formattedAddress
            company.latitude = location.lat
            company.longitude = location.lng
        }
        
        company.lastSyncedAt = Date()
        company.needsSync = false
    }
    
    // MARK: - Project Fetching
    
    /// Gets projects with flexible filtering options
    /// - Parameters:
    ///   - date: Optional date to filter projects scheduled for that day
    ///   - user: Optional user to filter projects assigned to them
    /// - Returns: Filtered array of projects
    func getProjects(for date: Date? = nil, assignedTo user: User? = nil) -> [Project] {
        guard let modelContext = modelContext else { return [] }
        
        do {
            // Get user's company ID - essential for filtering
            let companyId = user?.companyId ??
                            currentUser?.companyId ??
                            UserDefaults.standard.string(forKey: "currentUserCompanyId")
            
            print("DEBUG: Filtering projects for company ID: \(companyId ?? "Unknown")")
            
            // Get all projects
            let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.startDate)])
            let allProjects = try modelContext.fetch(descriptor)
            
            print("DEBUG: Found \(allProjects.count) total projects in database")
            
            // First filter by company - this is most important
            var filteredProjects = allProjects.filter { project in
                return project.companyId == companyId
            }
            
            print("DEBUG: \(filteredProjects.count) projects match company ID")
            
            // Then filter by date if needed
            if let date = date {
                filteredProjects = filteredProjects.filter { project in
                    guard let projectDate = project.startDate else {
                        return false
                    }
                    return Calendar.current.isDate(projectDate, inSameDayAs: date)
                }
                print("DEBUG: \(filteredProjects.count) projects match date filter")
            }
            
            // Finally filter by user assignment if needed
            if let user = user {
                filteredProjects = filteredProjects.filter { project in
                    // Check both relationship and ID string for belt-and-suspenders reliability
                    print("Team Member ID String")
                    print(project.teamMemberIdsString)
                    
                    print("Get TeamMember IDS")
                    print(project.getTeamMemberIds())
                    
                    return project.teamMembers.contains(where: { $0.id == user.id }) || project.getTeamMemberIds().contains(user.id)
                }
                print("DEBUG: Filtering projects for USER ID: \(user.id)")
                print("DEBUG: \(filteredProjects.count) projects match userID filter")
            }
            
            // Log what we're actually returning
            for project in filteredProjects {
                print("DEBUG: Returning project: \(project.title), company: \(project.companyId), date: \(project.startDate?.description ?? "nil")")
            }
            
            return filteredProjects
        } catch {
            print("Failed to fetch projects: \(error.localizedDescription)")
            return []
        }
    }
    
    func getProjectsForMap() throws -> [Project] {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }
        
        // Simple, reliable sort by start date
        var descriptor = FetchDescriptor<Project>()
        descriptor.sortBy = [SortDescriptor(\.startDate, order: .forward)]
        
        return try context.fetch(descriptor)
    }
    
    func getCurrentUserCompany() -> Company? {
        guard let user = currentUser,
              let companyId = user.companyId,
              let context = modelContext else {
            return nil
        }
        
        do {
            let descriptor = FetchDescriptor<Company>(
                predicate: #Predicate<Company> { $0.id == companyId }
            )
            let companies = try context.fetch(descriptor)
            return companies.first
        } catch {
            print("Error fetching company: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Sync Operations
    func forceSync() {
        guard isConnected, isAuthenticated else { return }
        Task {
            await syncManager?.triggerBackgroundSync()
        }
    }
    
    func appDidBecomeActive() {
        if isConnected && isAuthenticated {
            forceSync()
        }
    }
    
    func appDidEnterBackground() {
        // Handled by SyncManager
    }
}
