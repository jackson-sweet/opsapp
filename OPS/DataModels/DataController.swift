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
    // MARK: - Published Properties
    
    /// Authentication state
    @Published var isAuthenticated = false
    
    /// Current logged in user
    @Published var currentUser: User?
    
    /// Network connectivity status
    @Published var isConnected = false
    
    /// Data synchronization in progress
    @Published var isSyncing = false
    
    /// Current connection type (wifi, cellular, etc)
    @Published var connectionType: ConnectivityMonitor.ConnectionType = .none
    
    // MARK: - Private Properties
    
    /// Authentication manager
    private let authManager: AuthManager
    
    /// API service for network requests
    private let apiService: APIService
    
    /// Keychain manager for secure credential storage
    private let keychainManager: KeychainManager
    
    /// Network connection monitor
    private let connectivityMonitor: ConnectivityMonitor
    
    /// Model context for SwiftData operations
    private var modelContext: ModelContext?
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Properties
    
    /// Sync manager for data synchronization
    var syncManager: SyncManager!
    
    // MARK: - Initialization
    
    init() {
        // Initialize dependencies
        self.keychainManager = KeychainManager()
        self.authManager = AuthManager()
        self.connectivityMonitor = ConnectivityMonitor()
        self.apiService = APIService(authManager: authManager)
        
        // Setup connectivity monitoring
        setupConnectivityMonitoring()
        
        // Check for existing authentication
        Task {
            await checkExistingAuth()
        }
    }
    
    // MARK: - Setup Methods
    
    /// Setup network connectivity monitoring
    private func setupConnectivityMonitoring() {
        // Set initial connection state
        isConnected = connectivityMonitor.isConnected
        connectionType = connectivityMonitor.connectionType
        
        // Handle connection changes
        connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
            DispatchQueue.main.async {
                self?.isConnected = connectionType != .none
                self?.connectionType = connectionType
                
                // Trigger sync when connection is restored
                if connectionType != .none, self?.isAuthenticated == true {
                    self?.syncManager?.triggerBackgroundSync()
                }
            }
        }
    }
    
    /// Set up the model context for data operations
    @MainActor func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        
        // Initialize sync manager if authenticated
        if isAuthenticated {
            initializeSyncManager()
        }
    }
    
    /// Initialize the sync manager with the current context
    @MainActor private func initializeSyncManager() {
        guard let modelContext = modelContext else { return }
        
        self.syncManager = SyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor
        )
    }
    
    // MARK: - Authentication Methods
    
    /// Check for existing authentication credentials
    @MainActor
    private func checkExistingAuth() async {
        // Check for stored credentials
        if let userId = keychainManager.retrieveUserId(),
           let token = keychainManager.retrieveToken() {
            
            // Validate token expiration
            if let expiration = keychainManager.retrieveTokenExpiration(),
               expiration > Date() {
                // Token is still valid
                do {
                    // Try to fetch user from local storage
                    if let context = modelContext {
                        let predicate = #Predicate<User> { $0.id == userId }
                        let descriptor = FetchDescriptor<User>(predicate: predicate)
                        
                        let users = try context.fetch(descriptor)
                        
                        if let user = users.first {
                            // User found locally
                            self.currentUser = user
                            self.isAuthenticated = true
                            print("User authenticated from stored credentials")
                            
                            // Store company ID for background operations
                            if let companyId = user.companyId {
                                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                            }
                            
                            // Initialize sync manager
                            initializeSyncManager()
                            return
                        }
                    }
                    
                    // User not found locally, try to fetch from API
                    if isConnected {
                        try await fetchUserFromAPI(userId: userId)
                    } else {
                        // No connection and no local user - can't authenticate
                        clearAuthentication()
                    }
                } catch {
                    print("Error checking existing auth: \(error.localizedDescription)")
                    clearAuthentication()
                }
            } else {
                // Token expired
                clearAuthentication()
            }
        } else {
            // No stored credentials
            clearAuthentication()
        }
    }
    
    /// Log in with username and password
    @MainActor
    func login(username: String, password: String) async -> Bool {
        do {
            // Attempt to sign in
            let token = try await authManager.signIn(username: username, password: password)
            
            // Fetch user data with valid token
            if let userId = authManager.getUserId() {
                try await fetchUserFromAPI(userId: userId)
                return isAuthenticated
            } else {
                print("No user ID returned after authentication")
                return false
            }
        } catch {
            print("Login failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Fetch user data from API and store locally
    @MainActor
    private func fetchUserFromAPI(userId: String) async throws {
        do {
            // Fetch user data from API
            let userDTO = try await apiService.fetchUser(id: userId)
            
            guard let context = modelContext else {
                throw NSError(domain: "DataController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
            }
            
            // Convert to Swift model
            let user = userDTO.toModel()
            
            // Save to local database
            context.insert(user)
            try context.save()
            
            // Update app state
            self.currentUser = user
            self.isAuthenticated = true
            
            // Store company ID for background operations
            if let companyId = user.companyId {
                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
            }
            
            // Initialize sync manager now that we're authenticated
            initializeSyncManager()
            
            // Fetch company information if connected
            if isConnected, let companyId = user.companyId {
                Task {
                    try await fetchCompanyData(companyId: companyId)
                }
            }
        } catch {
            print("Error fetching user: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Log out the current user
    func logout() {
        authManager.signOut()
        clearAuthentication()
    }
    
    /// Clear authentication state
    private func clearAuthentication() {
        self.isAuthenticated = false
        self.currentUser = nil
        UserDefaults.standard.removeObject(forKey: "currentUserCompanyId")
    }
    
    // MARK: - Data Fetch Methods
    
    /// Fetch projects for map display
    func getProjectsForMap() throws -> [Project] {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }
        
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return try context.fetch(descriptor)
    }
    
    /// Get the current user's company
    func getCurrentUserCompany() -> Company? {
        guard let user = currentUser,
              let companyId = user.companyId,
              let context = modelContext else {
            return nil
        }
        
        do {
            let predicate = #Predicate<Company> { $0.id == companyId }
            let descriptor = FetchDescriptor<Company>(predicate: predicate)
            let companies = try context.fetch(descriptor)
            return companies.first
        } catch {
            print("Error fetching company: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetch company data from API
    private func fetchCompanyData(companyId: String) async throws {
        guard let context = modelContext else { return }
        
        do {
            // Check if company exists locally first
            let predicate = #Predicate<Company> { $0.id == companyId }
            let descriptor = FetchDescriptor<Company>(predicate: predicate)
            let companies = try context.fetch(descriptor)
            
            // If company doesn't exist locally or needs refresh, fetch from API
            if companies.isEmpty || (companies.first?.needsSync == true) {
                let companyDTO = try await apiService.fetchCompany(id: companyId)
                
                if let existingCompany = companies.first {
                    // Update existing company
                    existingCompany.name = companyDTO.companyName ?? "Unknown Company"
                    existingCompany.externalId = companyDTO.companyID
                    existingCompany.companyDescription = companyDTO.companyDescription
                    
                    if let location = companyDTO.location {
                        existingCompany.address = location.formattedAddress
                        existingCompany.latitude = location.lat
                        existingCompany.longitude = location.lng
                    }
                    
                    existingCompany.lastSyncedAt = Date()
                    existingCompany.needsSync = false
                } else {
                    // Create new company
                    let newCompany = companyDTO.toModel()
                    context.insert(newCompany)
                }
                
                try context.save()
            }
        } catch {
            print("Error fetching company data: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Sync Methods
    
    /// Force a sync operation
    @MainActor func forceSync() {
        guard isConnected, isAuthenticated else { return }
        syncManager?.triggerBackgroundSync()
    }
    
    /// Handle app coming to foreground
    @MainActor func appDidBecomeActive() {
        // Check connection and sync if needed
        if isConnected && isAuthenticated {
            forceSync()
        }
    }
    
    /// Handle app going to background
    func appDidEnterBackground() {
        // Finalize any pending operations
        // This is handled by the SyncManager with background tasks
    }
}
