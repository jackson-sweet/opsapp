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
    private var modelContext: ModelContext?
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
        
        self.syncManager = SyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor
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
