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
    
    // Global app state for external views to access
    var appState: AppState?
    
    // MARK: - Dependencies
    let authManager: AuthManager
    let apiService: APIService
    private let keychainManager: KeychainManager
    private let connectivityMonitor: ConnectivityMonitor
    var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Access
    var syncManager: SyncManager!
    var imageSyncManager: ImageSyncManager!
    @Published var simplePINManager = SimplePINManager()
    
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
        
        // Migrate any images from UserDefaults to FileManager
        // This prevents the "attempting to store >= 4194304 bytes" error
        ImageFileManager.shared.migrateAllImages()
        
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
        print("Setting model context")
        self.modelContext = context
        
        // Set up in proper sequence to avoid race conditions
        Task {
            // First clean up any duplicate users that might exist
            print("Running database cleanup")
            await cleanupDuplicateUsers()
            
            // Only after cleanup is done, initialize sync manager if needed
            await MainActor.run {
                if isAuthenticated {
                    print("Initializing sync manager after cleanup")
                    initializeSyncManager()
                }
            }
        }
    }
    
    @MainActor
    private func initializeSyncManager() {
        guard let modelContext = modelContext else { return }
        
        // Create user ID provider closure that returns the current user's ID
        let userIdProvider = { [weak self] in
            return self?.currentUser?.id
        }
        
        // Initialize the standard sync manager
        self.syncManager = SyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor,
            userIdProvider: userIdProvider
        )
        
        // Initialize the image sync manager
        self.imageSyncManager = ImageSyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor
        )
        
        // Immediately check for pending images after initialization
        if isConnected {
            Task {
                print("DataController: Checking for pending images after ImageSyncManager initialization")
                await imageSyncManager?.syncPendingImages()
            }
        }
        
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
        print("DataController: performAppLaunchSync called")
        
        // Always check for pending images, regardless of sync settings
        Task {
            // First, sync pending images if we're online
            if isConnected && isAuthenticated {
                print("DataController: Checking for pending image uploads...")
                if let imageSyncManager = imageSyncManager {
                    await imageSyncManager.syncPendingImages()
                } else {
                    print("DataController: ImageSyncManager not initialized yet, will retry after initialization")
                }
            }
            
            // Then check if we should do a full data sync
            let syncOnLaunch = UserDefaults.standard.bool(forKey: "syncOnLaunch")
            
            guard syncOnLaunch,
                  isAuthenticated,
                  isConnected else {
                print("DataController: Skipping full data sync (syncOnLaunch: \(syncOnLaunch), authenticated: \(isAuthenticated), connected: \(isConnected))")
                return
            }
            
            // Check if we've synced too recently
            if let lastSync = lastSyncTime,
               Date().timeIntervalSince(lastSync) < AppConfiguration.Sync.minimumSyncInterval {
                print("DataController: Skipping sync - too recent (last sync: \(lastSync))")
                return
            }
            
            // Trigger full data sync
            print("DataController: Performing full data sync on app launch")
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
        // First check if we have a direct authentication flag from onboarding
        let isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
        
        print("DataController: Checking auth - is_authenticated=\(isAuthenticated), onboarding_completed=\(onboardingCompleted)")
        
        // Check for incomplete onboarding - user created account but didn't finish onboarding
        if isAuthenticated && !onboardingCompleted {
            print("DataController: User is authenticated but has not completed onboarding")
            
            // Set flag to resume onboarding where they left off
            UserDefaults.standard.set(true, forKey: "resume_onboarding")
            
            // Important: Do NOT set self.isAuthenticated = true here
            // We want to redirect to the login page with onboarding
            print("DataController: Will redirect to login with resumed onboarding")
            return
        }
        
        // Normal case: fully authenticated and completed onboarding
        if isAuthenticated && onboardingCompleted {
            print("DataController: Found is_authenticated=true and onboarding_completed=true")
            
            // Get the user ID if available
            let userId = UserDefaults.standard.string(forKey: "user_id") ?? 
                         UserDefaults.standard.string(forKey: "currentUserId")
            
            // Get the company ID if available
            let companyId = UserDefaults.standard.string(forKey: "company_id") ?? 
                           UserDefaults.standard.string(forKey: "currentUserCompanyId")
            
            if let companyId = companyId {
                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                print("DataController: Using company ID from UserDefaults: \(companyId)")
            }
            
            // Set authentication state
            self.isAuthenticated = true
            
            // Try to get the user from SwiftData if available
            if let userId = userId, let context = modelContext {
                do {
                    let descriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { $0.id == userId }
                    )
                    
                    let users = try context.fetch(descriptor)
                    
                    if let user = users.first {
                        self.currentUser = user
                        print("DataController: Found user in SwiftData: \(user.fullName)")
                        
                        // Initialize sync manager
                        initializeSyncManager()
                        return
                    }
                } catch {
                    print("DataController: Error checking for user in SwiftData: \(error.localizedDescription)")
                }
            }
            
            // Even without a user object, maintain authentication
            print("DataController: Maintaining authenticated state from UserDefaults flag")
            return
        }
        
        // Fall back to traditional authentication check if needed
        // Check for stored credentials
        if let userId = keychainManager.retrieveUserId(),
           let _ = keychainManager.retrieveToken() {
            
            print("DataController: Found token in keychain for user ID: \(userId)")
            
            // Validate token expiration
            if let expiration = keychainManager.retrieveTokenExpiration(),
               expiration > Date() {
                print("DataController: Token is valid until \(expiration)")
                
                // Set the authentication flag in UserDefaults to maintain state across app restarts
                UserDefaults.standard.set(true, forKey: "is_authenticated")
                UserDefaults.standard.set(true, forKey: "onboarding_completed")
                
                // Store user ID in UserDefaults as well for backup
                UserDefaults.standard.set(userId, forKey: "user_id")
                UserDefaults.standard.set(userId, forKey: "currentUserId")
                
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
                                UserDefaults.standard.set(companyId, forKey: "company_id")
                                
                                // Fetch company details if we're connected
                                if isConnected {
                                    Task {
                                        do {
                                            print("Fetching company details on authentication for ID: \(companyId)")
                                            let companyDTO = try await apiService.fetchCompany(id: companyId)
                                            
                                            // Check if company already exists in database
                                            let companyDescriptor = FetchDescriptor<Company>(
                                                predicate: #Predicate<Company> { $0.id == companyId }
                                            )
                                            let existingCompanies = try context.fetch(companyDescriptor)
                                            
                                            if let existingCompany = existingCompanies.first {
                                                // Update existing company
                                                existingCompany.name = companyDTO.companyName ?? existingCompany.name
                                                existingCompany.externalId = companyDTO.companyID
                                                existingCompany.phone = companyDTO.phone
                                                existingCompany.email = companyDTO.officeEmail
                                                
                                                if let loc = companyDTO.location {
                                                    existingCompany.address = loc.formattedAddress
                                                    existingCompany.latitude = loc.lat
                                                    existingCompany.longitude = loc.lng
                                                }
                                                
                                                existingCompany.openHour = companyDTO.openHour
                                                existingCompany.closeHour = companyDTO.closeHour
                                                existingCompany.lastSyncedAt = Date()
                                                
                                                print("Updated existing company on auth: \(existingCompany.name)")
                                            } else {
                                                // Create new company
                                                let newCompany = companyDTO.toModel()
                                                context.insert(newCompany)
                                                print("Created new company on auth: \(newCompany.name)")
                                            }
                                            
                                            try context.save()
                                            print("Successfully saved company to database")
                                        } catch {
                                            print("Error fetching/saving company on auth: \(error)")
                                        }
                                    }
                                }
                            }
                            
                            initializeSyncManager()
                            return
                        }
                    }
                    
                    if isConnected {
                        try await fetchUserFromAPI(userId: userId)
                    } else {
                        // Even without internet, set authenticated if we have a valid token
                        self.isAuthenticated = true
                        
                        // Create a placeholder user
                        let placeholderUser = User(id: userId, firstName: "User", lastName: "", role: .fieldCrew, companyId: "")
                        self.currentUser = placeholderUser
                        
                        if let context = modelContext {
                            context.insert(placeholderUser)
                            try context.save()
                            initializeSyncManager()
                        }
                    }
                } catch {
                    print("Auth check error: \(error.localizedDescription)")
                    clearAuthentication()
                }
            } else {
                print("DataController: Token has expired")
                clearAuthentication()
            }
        } else {
            print("DataController: No token found in keychain")
            clearAuthentication()
        }
    }
    
    @discardableResult
    @MainActor
    func login(username: String, password: String) async -> Bool {
        do {
            // Sign in with the auth manager
            let _ = try await authManager.signIn(username: username, password: password)
            
            // Store the username (only for re-authentication, not displayed to user)
            keychainManager.storeUsername(username)
            keychainManager.storePassword(password)
            
            print("Login successful, token obtained")
            
            if let userId = authManager.getUserId() {
                // Set the authentication flags immediately
                UserDefaults.standard.set(true, forKey: "is_authenticated")
                UserDefaults.standard.set(true, forKey: "onboarding_completed")
                UserDefaults.standard.set(userId, forKey: "user_id")
                UserDefaults.standard.set(userId, forKey: "currentUserId")
                
                print("Stored authentication flags and user ID in UserDefaults")
                
                // Fetch user data
                try await fetchUserFromAPI(userId: userId)
                return isAuthenticated
            } else {
                print("No user ID received from authentication response")
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
        
        // First, check if this user already exists in the database
        let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == userId })
        let existingUsers = try context.fetch(descriptor)
        
        print("Fetching user data for ID: \(userId) from API")
        let userDTO = try await apiService.fetchUser(id: userId)
        print("Successfully fetched user data from API")
        
        var user: User
        
        // Transaction to update or create user
        do {
            if let existingUser = existingUsers.first {
                // Update existing user instead of creating a new one
                print("Found existing user with ID \(userId) - updating instead of creating new")
                user = existingUser
                
                // Store existing projects to preserve relationships
                let existingProjects = existingUser.assignedProjects
                
                // Update the user fields from DTO while preserving relationships
                user.firstName = userDTO.nameFirst ?? user.firstName
                user.lastName = userDTO.nameLast ?? user.lastName
                
                // Handle email - prioritize authentication email if available
                if let emailAuth = userDTO.authentication?.email?.email {
                    user.email = emailAuth
                } else if let email = userDTO.email {
                    user.email = email
                }
                
                // Handle profile image URL
                if let avatarUrl = userDTO.avatar {
                    user.profileImageURL = avatarUrl
                }
                
                // Handle role based on employee type
                if let employeeTypeString = userDTO.employeeType {
                    user.role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
                }
                
                // Handle company ID and fetch company details
                if let companyId = userDTO.company, !companyId.isEmpty {
                    user.companyId = companyId
                    
                    // Fetch and store company details
                    Task {
                        do {
                            print("Fetching company details for ID: \(companyId)")
                            let companyDTO = try await apiService.fetchCompany(id: companyId)
                            
                            // Check if company already exists in database
                            let companyDescriptor = FetchDescriptor<Company>(
                                predicate: #Predicate<Company> { $0.id == companyId }
                            )
                            let existingCompanies = try context.fetch(companyDescriptor)
                            
                            if let existingCompany = existingCompanies.first {
                                // Update existing company
                                existingCompany.name = companyDTO.companyName ?? existingCompany.name
                                existingCompany.externalId = companyDTO.companyID
                                existingCompany.phone = companyDTO.phone
                                existingCompany.email = companyDTO.officeEmail
                                
                                if let loc = companyDTO.location {
                                    existingCompany.address = loc.formattedAddress
                                    existingCompany.latitude = loc.lat
                                    existingCompany.longitude = loc.lng
                                }
                                
                                existingCompany.openHour = companyDTO.openHour
                                existingCompany.closeHour = companyDTO.closeHour
                                existingCompany.lastSyncedAt = Date()
                                
                                print("Updated existing company: \(existingCompany.name)")
                            } else {
                                // Create new company
                                let newCompany = companyDTO.toModel()
                                context.insert(newCompany)
                                print("Created new company: \(newCompany.name)")
                            }
                            
                            try context.save()
                            print("Successfully saved company to database")
                        } catch {
                            print("Error fetching/saving company: \(error)")
                        }
                    }
                }
                
                // Handle user type
                if let userType = userDTO.userType {
                    user.userType = UserType(rawValue: userType) ?? user.userType
                }
                
                // Handle home address
                if let address = userDTO.homeAddress {
                    user.homeAddress = address.formattedAddress
                }
                
                // We don't have these fields in the DTO currently
                // user.phone = userDTO.phone ?? user.phone 
                // user.latitude = userDTO.latitude ?? user.latitude
                // user.longitude = userDTO.longitude ?? user.longitude
                // user.locationName = userDTO.locationName ?? user.locationName
                // user.clientId = userDTO.clientId ?? user.clientId
                // user.isActive = userDTO.isActive ?? true
                
                // Set sync status
                user.lastSyncedAt = Date()
                user.needsSync = false
                
                // Don't overwrite existing project relationships
                if existingProjects.isEmpty && !user.assignedProjects.isEmpty {
                    print("Preserving \(user.assignedProjects.count) existing project relationships")
                }
            } else {
                // Create new user
                print("Creating new user with ID \(userId)")
                user = userDTO.toModel()
                context.insert(user)
            }
            
            try context.save()
            print("Successfully saved user to database")
        } catch {
            print("Error saving user: \(error.localizedDescription)")
            throw error
        }
        
        // Update app state with the current user
        self.currentUser = user
        self.isAuthenticated = true
        
        // Save important IDs to UserDefaults
        if let companyId = user.companyId {
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
            print("Saved company ID to UserDefaults: \(companyId)")
        } else {
            print("Warning: User has no company ID")
        }
        
        // Set authentication flag for consistency with onboarding flow
        UserDefaults.standard.set(true, forKey: "is_authenticated")
        
        UserDefaults.standard.set(user.id, forKey: "currentUserId")
        
        // Initialize sync managers
        initializeSyncManager()
        
        // Fetch company data if needed
        if isConnected, let companyId = user.companyId {
            do {
                print("Fetching company data for ID: \(companyId)")
                try await fetchCompanyData(companyId: companyId)
                print("Successfully fetched company data")
            } catch {
                print("Non-critical error fetching company data: \(error.localizedDescription)")
                // Continue even if company data fetch fails - don't block authentication
            }
        } else if !isConnected {
            print("Skipping company data fetch - offline mode")
        }
    }
    
    @MainActor
    func logout() {
        // Sign out from auth manager
        authManager.signOut()
        
        // Clear PIN settings first
        simplePINManager.removePIN()
        
        // Delete the current user from the database if needed
        if let userId = currentUser?.id, let context = modelContext {
            do {
                let descriptor = FetchDescriptor<User>(
                    predicate: #Predicate<User> { $0.id == userId }
                )
                
                let users = try context.fetch(descriptor)
                
                // Delete the user records
                for user in users {
                    print("DataController: Deleting user record for \(user.fullName)")
                    context.delete(user)
                }
                
                try context.save()
                print("DataController: Successfully cleaned up user database")
            } catch {
                print("DataController: Error cleaning up user database: \(error.localizedDescription)")
            }
        }
        
        
        // Clear all auth state and user defaults
        clearAuthentication()
    }
    
    private func clearAuthentication() {
        print("DataController: Clearing authentication state")
        isAuthenticated = false
        currentUser = nil
        
        // First clear all token data from keychain
        keychainManager.deleteToken()
        keychainManager.deleteTokenExpiration()
        keychainManager.deleteUserId()
        keychainManager.deleteUsername()
        keychainManager.deletePassword()
        
        // Clear all authentication-related UserDefaults
        UserDefaults.standard.removeObject(forKey: "currentUserCompanyId")
        UserDefaults.standard.removeObject(forKey: "is_authenticated")
        UserDefaults.standard.removeObject(forKey: "onboarding_completed")
        UserDefaults.standard.removeObject(forKey: "resume_onboarding")
        UserDefaults.standard.removeObject(forKey: "last_onboarding_step_v2")
        
        // Clear all user data
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "user_email")
        UserDefaults.standard.removeObject(forKey: "user_password")
        UserDefaults.standard.removeObject(forKey: "user_first_name")
        UserDefaults.standard.removeObject(forKey: "user_last_name")
        UserDefaults.standard.removeObject(forKey: "user_phone_number")
        UserDefaults.standard.removeObject(forKey: "company_code")
        UserDefaults.standard.removeObject(forKey: "company_id")
        UserDefaults.standard.removeObject(forKey: "Company Name")
        UserDefaults.standard.removeObject(forKey: "has_joined_company")
        
        // Clear PIN settings
        UserDefaults.standard.removeObject(forKey: "appPIN")
        UserDefaults.standard.removeObject(forKey: "hasPINEnabled")
        
        // Ensure UserDefaults changes are saved immediately
        UserDefaults.standard.synchronize()
        
        // Log the cleanup
        print("DataController: Authentication, PIN, and all user data cleared")
    }
    
    /// Removes sample/test projects from the database
    @MainActor
    func removeSampleProjects() async {
        guard let context = modelContext else {
            print("Cannot remove sample projects: ModelContext is nil")
            return
        }
        
        do {
            // Define patterns that indicate sample/test projects
            let samplePatterns = [
                "Sample Project",
                "Test Project",
                "Demo Project",
                "Example Project"
            ]
            
            // Fetch all projects
            let descriptor = FetchDescriptor<Project>()
            let allProjects = try context.fetch(descriptor)
            
            // Find projects that match sample patterns
            let sampleProjects = allProjects.filter { project in
                return samplePatterns.contains { pattern in
                    project.title.localizedCaseInsensitiveContains(pattern)
                }
            }
            
            if sampleProjects.isEmpty {
                print("No sample projects found to remove")
                return
            }
            
            print("Found \(sampleProjects.count) sample projects to remove:")
            for project in sampleProjects {
                print("  - Removing: \(project.title)")
                context.delete(project)
            }
            
            // Save the changes
            try context.save()
            print("Successfully removed \(sampleProjects.count) sample projects")
            
        } catch {
            print("Error removing sample projects: \(error.localizedDescription)")
        }
    }
    
    /// Cleans up duplicate users in the database
    @MainActor
    func cleanupDuplicateUsers() async {
        guard let context = modelContext else { 
            print("Cannot clean up duplicates: ModelContext is nil")
            return 
        }
        
        do {
            // Fetch all users
            let descriptor = FetchDescriptor<User>()
            let allUsers = try context.fetch(descriptor)
            
            // Group users by ID
            var usersByID: [String: [User]] = [:]
            for user in allUsers {
                if usersByID[user.id] == nil {
                    usersByID[user.id] = [user]
                } else {
                    usersByID[user.id]?.append(user)
                }
            }
            
            // Find duplicate users
            let duplicateIDs = usersByID.filter { $0.value.count > 1 }.keys
            if duplicateIDs.isEmpty {
                print("No duplicate users found")
                return
            }
            
            print("Found \(duplicateIDs.count) user IDs with duplicates. Cleaning up...")
            
            // For each set of duplicates, intelligently merge and clean up
            for id in duplicateIDs {
                guard let duplicates = usersByID[id], duplicates.count > 1 else { continue }
                
                // Sort duplicates by lastSyncedAt - keep the most recently synced one
                let sortedDuplicates = duplicates.sorted { 
                    guard let date1 = $0.lastSyncedAt, let date2 = $1.lastSyncedAt else {
                        // If one doesn't have a sync date, prefer the one that does
                        return $0.lastSyncedAt != nil 
                    }
                    return date1 > date2
                }
                
                let userToKeep = sortedDuplicates[0]
                print("Keeping most recent user \(userToKeep.fullName) (\(userToKeep.id)) and merging/removing \(duplicates.count - 1) duplicates")
                
                // Collect any projects from duplicates to ensure we don't lose relationships
                var allProjects = Set<Project>(userToKeep.assignedProjects)
                
                for i in 1..<sortedDuplicates.count {
                    let dupe = sortedDuplicates[i]
                    
                    // Merge any unique projects from this duplicate
                    for project in dupe.assignedProjects {
                        allProjects.insert(project)
                        
                        // Update project's reference to point to the user we're keeping
                        if let index = project.teamMembers.firstIndex(where: { $0.id == dupe.id }) {
                            // Only update if it's not already pointing to the user we're keeping
                            if !project.teamMembers.contains(where: { $0.id == userToKeep.id }) {
                                project.teamMembers.remove(at: index)
                                project.teamMembers.append(userToKeep)
                            } else {
                                // If we already have this user, just remove the duplicate reference
                                project.teamMembers.remove(at: index)
                            }
                        }
                    }
                    
                    // Now that we've migrated projects, we can safely delete
                    context.delete(dupe)
                }
                
                // Update the user we're keeping with all the projects
                userToKeep.assignedProjects = Array(allProjects)
            }
            
            // Save all changes in a single transaction
            do {
                try context.save()
                print("Cleanup complete - removed duplicate users and preserved relationships")
            } catch {
                print("Error saving after cleanup: \(error.localizedDescription)")
                // We should consider a way to recover from this error in a production app
            }
            
        } catch {
            print("Error cleaning up duplicate users: \(error.localizedDescription)")
        }
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
                    // Variable to track the company we're working with
                    var company: Company
                    
                    if let existingCompany = companies.first {
                        // Update existing
                        updateCompany(existingCompany, from: companyDTO)
                        company = existingCompany
                    } else {
                        // Create new
                        let newCompany = companyDTO.toModel()
                        context.insert(newCompany)
                        company = newCompany
                    }
                    
                    try? context.save()
                    
                    // If team members haven't been synced, or it's been more than a day, sync team members
                    if !company.teamMembersSynced || 
                       company.lastSyncedAt == nil || 
                       Date().timeIntervalSince(company.lastSyncedAt!) > 86400 {
                        
                        // Launch a task to fetch team members
                        Task {
                            await syncManager?.syncCompanyTeamMembers(company)
                        }
                    }
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
        
        // Handle location
        if let location = dto.location {
            company.address = location.formattedAddress
            company.latitude = location.lat
            company.longitude = location.lng
        }
        
        // Handle contact information
        company.phone = dto.phone
        company.email = dto.officeEmail
        company.website = nil // Not in DTO yet
        
        // Handle logo
        if let logoImage = dto.logo, let logoUrl = logoImage.url {
            company.logoURL = logoUrl
        }
        
        // Handle business hours
        company.openHour = dto.openHour
        company.closeHour = dto.closeHour
        
        // Handle admin role update
        if let currentUser = currentUser,
           let adminRefs = dto.admin {
            // Check if current user's ID is in the admin list
            let adminIds = adminRefs.compactMap { $0.stringValue }
            if adminIds.contains(currentUser.id) {
                // Update current user's role to admin
                currentUser.role = .admin
                print("Updated user role to Admin based on company admin list")
            }
        }
        
        // Handle industry, company size, age if needed for display
        // These are currently not displayed but could be added
        
        company.lastSyncedAt = Date()
        company.needsSync = false
    }
    
    /// Ensures project team members are properly synchronized between IDs and User objects
    @MainActor
    func syncProjectTeamMembers(_ project: Project) async {
        guard let context = modelContext else { return }
        
        // Skip if there are no team member IDs stored
        let teamMemberIds = project.getTeamMemberIds()
        if teamMemberIds.isEmpty {
            return
        }
        
        print("DataController: Synchronizing team members for project \(project.id) - \(project.title)")
        print("DataController: Project has \(teamMemberIds.count) team member IDs and \(project.teamMembers.count) team member objects")
        
        // Create a set of existing member IDs for quick lookup
        let existingMemberIds = Set(project.teamMembers.map { $0.id })
        
        // Find members that need to be added to project.teamMembers
        let missingMemberIds = teamMemberIds.filter { !existingMemberIds.contains($0) }
        
        if missingMemberIds.isEmpty {
            print("DataController: All team members are already linked to the project")
            return
        }
        
        print("DataController: Found \(missingMemberIds.count) team member IDs that need linking")
        
        // For each missing ID, find or create the User
        for memberId in missingMemberIds {
            // Try to find existing user
            let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == memberId })
            
            do {
                let existingUsers = try context.fetch(descriptor)
                
                if let existingUser = existingUsers.first {
                    // User exists - link to project
                    print("DataController: Linking existing user \(existingUser.fullName) to project")
                    
                    // Add to project's team members if not already there
                    if !project.teamMembers.contains(where: { $0.id == existingUser.id }) {
                        project.teamMembers.append(existingUser)
                    }
                    
                    // Add project to user's assigned projects if not already there
                    if !existingUser.assignedProjects.contains(where: { $0.id == project.id }) {
                        existingUser.assignedProjects.append(project)
                    }
                } else if isConnected {
                    // User doesn't exist locally but we're online - fetch from API
                    print("DataController: Fetching user \(memberId) from API")
                    do {
                        let userDTO = try await apiService.fetchUser(id: memberId)
                        
                        // Create new user
                        let newUser = userDTO.toModel()
                        
                        // Create bidirectional relationship
                        newUser.assignedProjects.append(project)
                        project.teamMembers.append(newUser)
                        
                        // Insert into database
                        context.insert(newUser)
                        print("DataController: Created and linked new user \(newUser.fullName) from API")
                    } catch {
                        print("DataController: Failed to fetch user \(memberId) from API: \(error.localizedDescription)")
                        
                        // Create placeholder user until we can fetch real data
                        let placeholderUser = User(
                            id: memberId,
                            firstName: "Team Member",
                            lastName: "#\(memberId.suffix(4))",
                            role: .fieldCrew,
                            companyId: project.companyId
                        )
                        
                        // Create bidirectional relationship
                        placeholderUser.assignedProjects.append(project)
                        project.teamMembers.append(placeholderUser)
                        
                        // Insert into database
                        context.insert(placeholderUser)
                        print("DataController: Created placeholder user for ID \(memberId)")
                    }
                } else {
                    // Offline and user doesn't exist - create placeholder
                    print("DataController: Creating offline placeholder for user \(memberId)")
                    
                    // Create placeholder user until we can fetch real data when online
                    let placeholderUser = User(
                        id: memberId,
                        firstName: "Team Member",
                        lastName: "#\(memberId.suffix(4))",
                        role: .fieldCrew,
                        companyId: project.companyId
                    )
                    
                    // Create bidirectional relationship
                    placeholderUser.assignedProjects.append(project)
                    project.teamMembers.append(placeholderUser)
                    
                    // Insert into database
                    context.insert(placeholderUser)
                    print("DataController: Created offline placeholder for ID \(memberId)")
                }
            } catch {
                print("DataController: Error syncing team member \(memberId): \(error.localizedDescription)")
            }
        }
        
        // Save changes
        do {
            try context.save()
            print("DataController: Successfully saved team member relationships")
            print("DataController: Project now has \(project.teamMembers.count) team member objects")
        } catch {
            print("DataController: Error saving team member relationships: \(error.localizedDescription)")
        }
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
    
    func getProjectDetails(projectId: String) async throws -> Project {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }
        
        // Try local first
        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        
        if let localProject = try context.fetch(descriptor).first {
            // If we have a local copy and recent sync, use it
            if localProject.lastSyncedAt != nil &&
               Date().timeIntervalSince(localProject.lastSyncedAt!) < AppConfiguration.Sync.minimumSyncInterval {
                
                // Ensure team members are properly linked
                await syncProjectTeamMembers(localProject)
                return localProject
            }
        }
        
        // If offline, use local version even if outdated
        if !isConnected {
            if let localProject = try context.fetch(descriptor).first {
                // Still ensure team members are properly linked
                await syncProjectTeamMembers(localProject)
                return localProject
            }
            throw NSError(domain: "DataController", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Project not found locally and offline"])
        }
        
        // Online and needing refresh: fetch from API
        do {
            let projectDTO = try await apiService.fetchProject(id: projectId)
            
            // Convert to model and save
            let project = projectDTO.toModel()
            
            // Update or insert
            if let existingProject = try context.fetch(descriptor).first {
                // Update existing (careful not to overwrite local changes)
                if !existingProject.needsSync {
                    // Only update if no pending local changes
                    // Full implementation would merge changes
                }
                
                // Ensure team members are properly linked
                await syncProjectTeamMembers(existingProject)
                return existingProject
            } else {
                // Insert new
                context.insert(project)
                try context.save()
                
                // Ensure team members are properly linked
                await syncProjectTeamMembers(project)
                return project
            }
        } catch {
            // On API error, fall back to local if available
            if let localProject = try context.fetch(descriptor).first {
                // Still ensure team members are properly linked
                await syncProjectTeamMembers(localProject)
                return localProject
            }
            throw error
        }
    }
    
    
    
    func getProjectsForToday(user: User? = nil) async throws -> [Project] {
        let today = Calendar.current.startOfDay(for: Date())
        let _ = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        // Use the user ID if provided, otherwise use current user
        let userId = user?.id ?? currentUser?.id
        
        guard let userId = userId else {
            throw NSError(domain: "DataController", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "No current user"])
        }
        
        // First check local data
        let localProjects = getProjects(for: today, assignedTo: user ?? currentUser)
        
        // If we're offline or have recent data, use local data
        if !isConnected || (lastSyncTime != nil &&
            Date().timeIntervalSince(lastSyncTime!) < AppConfiguration.Sync.minimumSyncInterval) {
            
            // Ensure team member relationships are synchronized for each project
            for project in localProjects {
                await syncProjectTeamMembers(project)
            }
            
            return localProjects
        }
        
        // Otherwise fetch fresh data using our new centralized API
        do {
            // Fetch remote projects but discard them for now
            // In the future, we'll process and merge them with local data
            _ = try await apiService.fetchUserProjectsForDate(
                userId: userId,
                date: today
            )
            
            // Sync team member relationships for each project
            for project in localProjects {
                await syncProjectTeamMembers(project)
            }
            
            // Return local projects for now until full sync is implemented
            return localProjects
        } catch {
            // On error, fall back to local data
            print("Error fetching remote projects: \(error)")
            
            // Still ensure team member relationships are synchronized for projects
            for project in localProjects {
                await syncProjectTeamMembers(project)
            }
            
            return localProjects
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
    
    /// Force refresh company data from API
    @MainActor
    func forceRefreshCompany(id: String) async throws {
        guard isConnected, isAuthenticated, let context = modelContext else {
            if !isConnected {
                throw NSError(domain: "DataController", code: 100, 
                             userInfo: [NSLocalizedDescriptionKey: "No internet connection"])
            }
            if !isAuthenticated {
                throw NSError(domain: "DataController", code: 101, 
                             userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            }
            throw NSError(domain: "DataController", code: 102, 
                         userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }
        
        print("Forcing refresh of company data for ID: \(id)")
        
        // Fetch fresh data from API
        let companyDTO = try await apiService.fetchCompany(id: id)
        print("Successfully fetched company data from API")
        print("Company DTO data:")
        print("  - Name: \(companyDTO.companyName ?? "nil")")
        print("  - Phone: \(companyDTO.phone ?? "nil")")
        print("  - Email: \(companyDTO.officeEmail ?? "nil")")
        print("  - Address: \(companyDTO.location?.formattedAddress ?? "nil")")
        
        // Check if we already have this company locally
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == id }
        )
        let companies = try context.fetch(descriptor)
        
        if let existingCompany = companies.first {
            // Update existing company
            print("Updating existing company: \(existingCompany.name)")
            updateCompany(existingCompany, from: companyDTO)
        } else {
            // Create new company
            print("Creating new company from API data")
            let newCompany = companyDTO.toModel()
            context.insert(newCompany)
        }
        
        // Save changes
        try context.save()
        print("Company data saved to database")
    }
    
    func appDidBecomeActive() {
        if isConnected && isAuthenticated {
            forceSync()
        }
    }
    
    func appDidEnterBackground() {
        // Handled by SyncManager
    }
    
    // MARK: - Settings View Methods
    
    /// Gets a company by ID
    func getCompany(id: String) -> Company? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<Company>(
                predicate: #Predicate<Company> { $0.id == id }
            )
            let companies = try context.fetch(descriptor)
            
            if let company = companies.first {
                return company
            } else {
                // Create a dummy company for preview/testing
                let dummyCompany = Company(id: id, name: "Example Company")
                dummyCompany.address = "123 Main Street, San Francisco, CA 94105"
                dummyCompany.phone = "(555) 123-4567"
                dummyCompany.email = "info@example.com"
                dummyCompany.website = "www.example.com"
                return dummyCompany
            }
        } catch {
            print("Error fetching company: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Gets team members for a company (User model - legacy version)
    func getTeamMembers(companyId: String) -> [User] {
        guard let context = modelContext else { return [] }
        
        do {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.companyId == companyId }
            )
            let users = try context.fetch(descriptor)
            
            if !users.isEmpty {
                return users
            } else {
                // Return sample team members for preview/testing
                // This is just for UI testing - in a real app, we'd fetch from the API
                let sampleUsers: [User] = [
                    createSampleUser(id: "1", firstName: "John", lastName: "Doe", role: .fieldCrew, companyId: companyId),
                    createSampleUser(id: "2", firstName: "Jane", lastName: "Smith", role: .officeCrew, companyId: companyId),
                    createSampleUser(id: "3", firstName: "Michael", lastName: "Johnson", role: .fieldCrew, companyId: companyId)
                ]
                return sampleUsers
            }
        } catch {
            print("Error fetching team members: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Gets lightweight team members for a company using the TeamMember model
    func getCompanyTeamMembers(companyId: String) -> [TeamMember] {
        guard let context = modelContext else { return [] }
        
        do {
            // First try to get the company
            let companyDescriptor = FetchDescriptor<Company>(
                predicate: #Predicate<Company> { $0.id == companyId }
            )
            let companies = try context.fetch(companyDescriptor)
            
            if let company = companies.first {
                // Return team members from the company relationship
                if !company.teamMembers.isEmpty {
                    return company.teamMembers
                }
                
                // If company exists but no team members, trigger a sync if we're connected
                if isConnected && syncManager != nil {
                    Task {
                        await syncManager?.syncCompanyTeamMembers(company)
                    }
                }
            }
            
            // If we got here, either company doesn't exist or has no team members yet
            return []
        } catch {
            print("Error fetching company team members: \(error.localizedDescription)")
            return []
        }
    }
    
    private func createSampleUser(id: String, firstName: String, lastName: String, role: UserRole, companyId: String) -> User {
        let user = User(id: id, firstName: firstName, lastName: lastName, role: role, companyId: companyId)
        user.email = "\(firstName.lowercased()).\(lastName.lowercased())@example.com"
        user.phone = "(555) \(Int.random(in: 100...999))-\(Int.random(in: 1000...9999))"
        user.isActive = true
        return user
    }
    
    /// Gets project history for a user
    func getProjectHistory(for userId: String) -> [Project] {
        guard let context = modelContext else { return [] }
        
        do {
            // Get all projects where the user is a team member
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            
            // Filter projects for the specified user
            let userProjects = allProjects.filter { project in
                project.getTeamMemberIds().contains(userId) || 
                project.teamMembers.contains(where: { $0.id == userId })
            }
            
            // If we have real projects, return them
            if !userProjects.isEmpty {
                // Sort by start date, most recent first
                return userProjects.sorted { 
                    guard let date1 = $0.startDate, let date2 = $1.startDate else {
                        return false
                    }
                    return date1 > date2
                }
            } else {
                // Create sample projects for preview/testing
                let now = Date()
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
                let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: now)!
                let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: now)!
                
                let sampleProjects: [Project] = [
                    createSampleProject(id: "p1", title: "Office Renovation", status: .completed, 
                                      startDate: lastWeek, endDate: yesterday),
                    createSampleProject(id: "p2", title: "Retail Store Buildout", status: .inProgress, 
                                      startDate: yesterday, endDate: nextWeek),
                    createSampleProject(id: "p3", title: "Home Kitchen Remodel", status: .accepted, 
                                      startDate: nextWeek, endDate: nil)
                ]
                
                // Add the user to each project's team members
                for project in sampleProjects {
                    project.setTeamMemberIds([userId])
                }
                
                return sampleProjects
            }
        } catch {
            print("Error fetching project history: \(error.localizedDescription)")
            return []
        }
    }
    
    private func createSampleProject(id: String, title: String, status: Status, 
                                  startDate: Date?, endDate: Date?) -> Project {
        let project = Project(id: id, title: title, status: status)
        project.startDate = startDate
        project.endDate = endDate
        project.clientName = ["Acme Corp", "TechStart Inc", "Smith Family", "City Hospital"].randomElement()!
        project.address = [
            "123 Main St, San Francisco, CA",
            "456 Park Ave, New York, NY",
            "789 Oak Blvd, Chicago, IL",
            "101 Pine St, Seattle, WA"
        ].randomElement()!
        
        // Add some location data
        project.latitude = Double.random(in: 37.7...37.8)
        project.longitude = Double.random(in: -122.5...(-122.4))
        
        return project
    }
    
    /// Updates user profile
    func updateUserProfile(firstName: String, lastName: String, email: String, phone: String, homeAddress: String? = nil) async -> Bool {
        guard let user = currentUser, let context = modelContext else { return false }
        
        // Update local model
        user.firstName = firstName
        user.lastName = lastName
        user.email = email
        user.phone = phone
        if let homeAddress = homeAddress {
            user.homeAddress = homeAddress
        }
        user.needsSync = true
        
        do {
            try context.save()
            
            // Sync to API if connected
            if isConnected {
                await syncManager?.syncUser(user)
            }
            
            return true
        } catch {
            print("Error updating user profile: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Request a password reset email
    /// - Parameter email: The user's email address
    /// - Returns: Tuple with success flag and optional error message
    func requestPasswordReset(email: String) async -> (Bool, String?) {
        do {
            let success = try await authManager.requestPasswordReset(email: email)
            return (success, nil)
        } catch let error as AuthError {
            // Return user-friendly error message
            return (false, error.localizedDescription)
        } catch {
            // Return generic error message
            return (false, "Failed to request password reset. Please try again.")
        }
    }
    
    // We're removing the ability to update profile images for now
    // Instead we'll rely on the API to provide profile images
    
    /// Gets a project by ID
    func getProject(id: String) -> Project? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == id }
            )
            let projects = try context.fetch(descriptor)
            
            if let project = projects.first {
                // Trigger team member sync in background
                Task {
                    await syncProjectTeamMembers(project)
                }
                return project
            }
            return nil
        } catch {
            print("Error fetching project: \(error.localizedDescription)")
            return nil
        }
    }
    
    
    /// Gets a user by ID
    func getUser(id: String) -> User? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.id == id }
            )
            let users = try context.fetch(descriptor)
            return users.first
        } catch {
            print("Error fetching user: \(error.localizedDescription)")
            return nil
        }
    }
}
