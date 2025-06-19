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
import GoogleSignIn

/// Main controller for managing data, authentication, and app state
class DataController: ObservableObject {
    // MARK: - Preview Detection
    private var isRunningInPreview: Bool {
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
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
        self.modelContext = context
        
        // Set up in proper sequence to avoid race conditions
        Task {
            // First clean up any duplicate users that might exist
            await cleanupDuplicateUsers()
            
            // Only after cleanup is done, initialize sync manager if needed
            await MainActor.run {
                if isAuthenticated {
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
        
        // Always check for pending images, regardless of sync settings
        Task {
            // First, sync pending images if we're online
            if isConnected && isAuthenticated {
                if let imageSyncManager = imageSyncManager {
                    await imageSyncManager.syncPendingImages()
                } else {
                }
            }
            
            // Then check if we should do a full data sync
            let syncOnLaunch = UserDefaults.standard.bool(forKey: "syncOnLaunch")
            
            guard syncOnLaunch,
                  isAuthenticated,
                  isConnected else {
                return
            }
            
            // Check if we've synced too recently
            if let lastSync = lastSyncTime,
               Date().timeIntervalSince(lastSync) < AppConfiguration.Sync.minimumSyncInterval {
                return
            }
            
            // Trigger full data sync
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
        
        
        // Check for incomplete onboarding - user created account but didn't finish onboarding
        if isAuthenticated && !onboardingCompleted {
            
            // Set flag to resume onboarding where they left off
            UserDefaults.standard.set(true, forKey: "resume_onboarding")
            
            // Important: Do NOT set self.isAuthenticated = true here
            // We want to redirect to the login page with onboarding
            return
        }
        
        // Normal case: fully authenticated and completed onboarding
        if isAuthenticated && onboardingCompleted {
            
            // Get the user ID if available
            let userId = UserDefaults.standard.string(forKey: "user_id") ?? 
                         UserDefaults.standard.string(forKey: "currentUserId")
            
            // Get the company ID if available
            let companyId = UserDefaults.standard.string(forKey: "company_id") ?? 
                           UserDefaults.standard.string(forKey: "currentUserCompanyId")
            
            if let companyId = companyId {
                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
            }
            
            // Check onboarding status before setting authentication
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            
            // Only set isAuthenticated if onboarding is complete
            if onboardingCompleted {
                self.isAuthenticated = true
            } else {
                self.isAuthenticated = false
            }
            
            // Try to get the user from SwiftData if available
            if let userId = userId, let context = modelContext {
                do {
                    let descriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { $0.id == userId }
                    )
                    
                    let users = try context.fetch(descriptor)
                    
                    if let user = users.first {
                        self.currentUser = user
                        
                        // Initialize sync manager
                        initializeSyncManager()
                        return
                    }
                } catch {
                    print("DataController: Error checking for user in SwiftData: \(error.localizedDescription)")
                }
            }
            
            // Even without a user object, maintain authentication
            return
        }
        
        // Fall back to traditional authentication check if needed
        // Check for stored credentials
        if let userId = keychainManager.retrieveUserId(),
           let _ = keychainManager.retrieveToken() {
            
            
            // Validate token expiration
            if let expiration = keychainManager.retrieveTokenExpiration(),
               expiration > Date() {
                
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
                            
                            // Only set isAuthenticated if user has completed onboarding
                            if user.hasCompletedAppOnboarding {
                                self.isAuthenticated = true
                            } else {
                                self.isAuthenticated = false
                            }
                            
                            if let companyId = user.companyId {
                                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                                UserDefaults.standard.set(companyId, forKey: "company_id")
                                
                                // Fetch company details if we're connected
                                if isConnected {
                                    Task {
                                        do {
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
                                                
                                            } else {
                                                // Create new company
                                                let newCompany = companyDTO.toModel()
                                                context.insert(newCompany)
                                            }
                                            
                                            try context.save()
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
                        // Even without internet, check onboarding status
                        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
                        if onboardingCompleted {
                            self.isAuthenticated = true
                        } else {
                            self.isAuthenticated = false
                        }
                        
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
            // Sign in with the auth manager
            let _ = try await authManager.signIn(username: username, password: password)
            
            // Store the username (only for re-authentication, not displayed to user)
            keychainManager.storeUsername(username)
            keychainManager.storePassword(password)
            
            
            if let userId = authManager.getUserId() {
                // Set the authentication flags immediately
                UserDefaults.standard.set(true, forKey: "is_authenticated")
                // Don't automatically set onboarding_completed - we'll check from server
                UserDefaults.standard.set(userId, forKey: "user_id")
                UserDefaults.standard.set(userId, forKey: "currentUserId")
                
                
                // Fetch user data
                try await fetchUserFromAPI(userId: userId)
                
                // Check if user has completed onboarding from server data
                if let user = currentUser {
                    UserDefaults.standard.set(user.hasCompletedAppOnboarding, forKey: "onboarding_completed")
                    
                    // Log what will happen next
                    if !user.hasCompletedAppOnboarding {
                        print("🟡 User needs to complete onboarding")
                    } else {
                        print("🟢 User has completed onboarding")
                    }
                    
                    // Trigger background sync to fetch projects and team members
                    Task {
                        await self.syncManager?.triggerBackgroundSync()
                    }
                }
                
                // Return true because login succeeded, even if onboarding is needed
                // LoginView will check onboarding status separately
                return true
            } else {
                return false
            }
        } catch {
            print("Login failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Google login
    @MainActor
    func loginWithGoogle(googleUser: GIDGoogleUser) async -> Bool {
        guard let idToken = googleUser.idToken?.tokenString,
              let email = googleUser.profile?.email,
              let name = googleUser.profile?.name else {
            return false
        }
        
        do {
            // Attempt Google login with Bubble
            let loginResult = try await authManager.signInWithGoogle(
                idToken: idToken,
                email: email,
                name: name,
                givenName: googleUser.profile?.givenName,
                familyName: googleUser.profile?.familyName
            )
            
            let userDTO = loginResult.user
            let companyDTO = loginResult.company
            
            print("🔵 Google Login - Processing user data")
            print("   User ID: \(userDTO.id)")
            print("   Company from login response: \(companyDTO?.id ?? "none")")
            print("   User's company ID: \(userDTO.company ?? "none")")
            print("   User type: \(userDTO.userType ?? "none")")
            
            // Immediately set user type if available
            if let userTypeString = userDTO.userType {
                print("🔵 Setting user type from Google login: \(userTypeString)")
                // Map Bubble's user type strings to our UserType enum
                if userTypeString.lowercased() == "company" {
                    UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
                } else if userTypeString.lowercased() == "employee" {
                    UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
                }
                // Also store the raw value as a backup
                UserDefaults.standard.set(userTypeString, forKey: "user_type_raw")
            }
            
            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            // Don't automatically set onboarding_completed for Google login
            // We need to check if they have a company first
            UserDefaults.standard.set(userDTO.id, forKey: "user_id")
            UserDefaults.standard.set(userDTO.id, forKey: "currentUserId")
            
            
            // Fetch and create/update user using existing method
            try await fetchUserFromAPI(userId: userDTO.id)
            
            // If company data was returned, save it in the local database
            if let companyDTO = companyDTO {
                print("🟢 Google Login - Company data received in login response")
                print("   Company ID: \(companyDTO.id)")
                print("   Company Name: \(companyDTO.companyName ?? "unknown")")
                // We already fetched company data in fetchUserFromAPI, so we don't need to save it again
                // The fetchCompanyData method was already called and handled the company save
            } else {
                print("🟡 Google Login - No company data in login response")
            }
            
            // Now check if user has completed onboarding based on their data
            if let user = currentUser {
                let hasCompany = !(user.companyId ?? "").isEmpty
                let hasCompletedAppOnboarding = user.hasCompletedAppOnboarding
                
                print("🔵 Google Login - Onboarding check:")
                print("   Has company: \(hasCompany)")
                print("   Has completed app onboarding: \(hasCompletedAppOnboarding)")
                
                // Set onboarding completed only if they have both
                let needsOnboarding = !hasCompany || !hasCompletedAppOnboarding
                UserDefaults.standard.set(!needsOnboarding, forKey: "onboarding_completed")
                
                // Only set isAuthenticated if they've completed onboarding
                // Otherwise, return true to indicate login succeeded but don't set isAuthenticated
                if !needsOnboarding {
                    self.isAuthenticated = true
                    
                    // Trigger background sync to fetch projects and team members
                    Task {
                        await self.syncManager?.triggerBackgroundSync()
                    }
                } else {
                    // Even if onboarding is needed, we should still sync company data
                    // This ensures team members and projects are available
                    Task {
                        await self.syncManager?.triggerBackgroundSync()
                    }
                }
                
                // Return true to indicate login was successful (even if onboarding is needed)
                return true
            }
            
            return false
        } catch let error as AuthError {
            print("Google login auth error: \(error.localizedDescription)")
            
            // If it's invalid credentials, it means no account exists
            if case .invalidCredentials = error {
            }
            return false
        } catch {
            print("Google login failed: \(error.localizedDescription)")
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
        
        let userDTO = try await apiService.fetchUser(id: userId)
        
        var user: User
        
        // Transaction to update or create user
        do {
            if let existingUser = existingUsers.first {
                // Update existing user instead of creating a new one
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
                
                // Handle phone number
                if let phone = userDTO.phone {
                    user.phone = phone
                }
                
                // Handle role based on employee type
                if let employeeTypeString = userDTO.employeeType {
                    user.role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
                }
                
                // Handle company ID and fetch company details
                if let companyId = userDTO.company, !companyId.isEmpty {
                    user.companyId = companyId
                    print("🔵 User has company ID: \(companyId), fetching company details...")
                    
                    // Fetch and store company details
                    Task {
                        do {
                            let companyDTO = try await apiService.fetchCompany(id: companyId)
                            print("🟢 Successfully fetched company: \(companyDTO.companyName ?? "unknown")")
                            
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
                                
                            } else {
                                // Create new company
                                let newCompany = companyDTO.toModel()
                                context.insert(newCompany)
                            }
                            
                            try context.save()
                        } catch {
                            print("🔴 Error fetching/saving company: \(error)")
                        }
                    }
                } else {
                    print("🟡 User has no company ID in their profile")
                }
                
                // Handle user type
                if let userType = userDTO.userType {
                    user.userType = UserType(rawValue: userType) ?? user.userType
                }
                
                // Handle home address
                if let address = userDTO.homeAddress {
                    user.homeAddress = address.formattedAddress
                }
                
                // Update phone if available in DTO
                if let phone = userDTO.phone {
                    user.phone = phone
                }
                
                // We don't have these fields in the DTO currently
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
                }
            } else {
                // Create new user
                user = userDTO.toModel()
                context.insert(user)
            }
            
            try context.save()
        } catch {
            print("Error saving user: \(error.localizedDescription)")
            throw error
        }
        
        // Update app state with the current user
        self.currentUser = user
        
        // Store user type in UserDefaults for onboarding flow
        if let userTypeString = userDTO.userType {
            print("🔵 Setting user type from API: \(userTypeString)")
            // Map Bubble's user type strings to our UserType enum
            if userTypeString.lowercased() == "company" {
                UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
            } else if userTypeString.lowercased() == "employee" {
                UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
            }
            // Also store the raw value as a backup
            UserDefaults.standard.set(userTypeString, forKey: "user_type_raw")
        }
        
        // Only set isAuthenticated if user has completed onboarding
        // This ensures LoginView can show onboarding overlay if needed
        if user.hasCompletedAppOnboarding {
            self.isAuthenticated = true
        } else {
            self.isAuthenticated = false
        }
        
        // Save important IDs to UserDefaults
        if let companyId = user.companyId {
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
        } else {
        }
        
        // Set authentication flag for consistency with onboarding flow
        UserDefaults.standard.set(true, forKey: "is_authenticated")
        
        UserDefaults.standard.set(user.id, forKey: "currentUserId")
        
        // Initialize sync managers
        initializeSyncManager()
        
        // Fetch company data if needed
        if isConnected, let companyId = user.companyId {
            do {
                try await fetchCompanyData(companyId: companyId)
            } catch {
                print("Non-critical error fetching company data: \(error.localizedDescription)")
                // Continue even if company data fetch fails - don't block authentication
            }
        } else if !isConnected {
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
                    context.delete(user)
                }
                
                try context.save()
            } catch {
                print("DataController: Error cleaning up user database: \(error.localizedDescription)")
            }
        }
        
        
        // Clear all auth state and user defaults
        clearAuthentication()
    }
    
    private func clearAuthentication() {
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
    }
    
    /// Removes sample/test projects from the database
    @MainActor
    func removeSampleProjects() async {
        guard let context = modelContext else {
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
                return
            }
            
            for project in sampleProjects {
                context.delete(project)
            }
            
            // Save the changes
            try context.save()
            
        } catch {
            print("Error removing sample projects: \(error.localizedDescription)")
        }
    }
    
    /// Cleans up duplicate users in the database
    @MainActor
    func cleanupDuplicateUsers() async {
        guard let context = modelContext else { 
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
                return
            }
            
            
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
        company.website = dto.website
        
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
            }
        }
        
        // Handle admin list
        if let adminRefs = dto.admin {
            let adminIds = adminRefs.compactMap { $0.stringValue }
            company.setAdminIds(adminIds)
        }
        
        // Handle company details
        company.setIndustries(dto.industry ?? [])
        company.companySize = dto.companySize
        company.companyAge = dto.companyAge
        
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
        
        
        // Create a set of existing member IDs for quick lookup
        let existingMemberIds = Set(project.teamMembers.map { $0.id })
        
        // Find members that need to be added to project.teamMembers
        let missingMemberIds = teamMemberIds.filter { !existingMemberIds.contains($0) }
        
        if missingMemberIds.isEmpty {
            return
        }
        
        
        // For each missing ID, find or create the User
        for memberId in missingMemberIds {
            // Try to find existing user
            let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == memberId })
            
            do {
                let existingUsers = try context.fetch(descriptor)
                
                if let existingUser = existingUsers.first {
                    // User exists - link to project
                    
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
                    do {
                        let userDTO = try await apiService.fetchUser(id: memberId)
                        
                        // Create new user
                        let newUser = userDTO.toModel()
                        
                        // Create bidirectional relationship
                        newUser.assignedProjects.append(project)
                        project.teamMembers.append(newUser)
                        
                        // Insert into database
                        context.insert(newUser)
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
                    }
                } else {
                    // Offline and user doesn't exist - create placeholder
                    
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
                }
            } catch {
                print("DataController: Error syncing team member \(memberId): \(error.localizedDescription)")
            }
        }
        
        // Save changes
        do {
            try context.save()
        } catch {
            print("DataController: Error saving team member relationships: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Project Fetching
    
    /// Gets projects with flexible filtering options
    /// - Parameters:
    ///   - date: Optional date to filter projects scheduled for that day
    ///   - user: Optional user to filter projects assigned to them (pass nil for Admin/Office to see all)
    /// - Returns: Filtered array of projects
    func getProjects(for date: Date? = nil, assignedTo user: User? = nil) -> [Project] {
        guard let modelContext = modelContext else { return [] }
        
        do {
            // Get user's company ID - essential for filtering
            let companyId = user?.companyId ??
                            currentUser?.companyId ??
                            UserDefaults.standard.string(forKey: "currentUserCompanyId")
            
            
            // Get all projects
            let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.startDate)])
            let allProjects = try modelContext.fetch(descriptor)
            
            
            // First filter by company - this is most important
            var filteredProjects = allProjects.filter { project in
                return project.companyId == companyId
            }
            
            
            // Then filter by date if needed
            if let date = date {
                filteredProjects = filteredProjects.filter { project in
                    guard let projectDate = project.startDate else {
                        return false
                    }
                    return Calendar.current.isDate(projectDate, inSameDayAs: date)
                }
            }
            
            // Finally filter by user assignment if needed
            // Admin and Office Crew users see all projects
            if let user = user, user.role != .admin && user.role != .officeCrew {
                filteredProjects = filteredProjects.filter { project in
                    // Check both relationship and ID string for belt-and-suspenders reliability
                    return project.teamMembers.contains(where: { $0.id == user.id }) || project.getTeamMemberIds().contains(user.id)
                }
            } else if let user = user {
            } else {
            }
            
            return filteredProjects
        } catch {
            print("Failed to fetch projects: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Helper method to get projects for the current user based on their role
    /// - Parameter date: Optional date to filter projects
    /// - Returns: Projects appropriate for the user's role
    func getProjectsForCurrentUser(for date: Date? = nil) -> [Project] {
        guard let user = currentUser else { return [] }
        
        // For Admin and Office Crew, pass nil to see all company projects
        if user.role == .admin || user.role == .officeCrew {
            return getProjects(for: date, assignedTo: nil)
        } else {
            // For Field Crew, pass the user to filter by assignment
            return getProjects(for: date, assignedTo: user)
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
        
        
        // Fetch fresh data from API
        let companyDTO = try await apiService.fetchCompany(id: id)
        
        // Check if we already have this company locally
        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == id }
        )
        let companies = try context.fetch(descriptor)
        
        if let existingCompany = companies.first {
            // Update existing company
            updateCompany(existingCompany, from: companyDTO)
        } else {
            // Create new company
            let newCompany = companyDTO.toModel()
            context.insert(newCompany)
        }
        
        // Save changes
        try context.save()
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
            } else if isRunningInPreview {
                // Return sample team members ONLY for SwiftUI previews
                let sampleUsers: [User] = [
                    createSampleUser(id: "1", firstName: "John", lastName: "Doe", role: .fieldCrew, companyId: companyId),
                    createSampleUser(id: "2", firstName: "Jane", lastName: "Smith", role: .officeCrew, companyId: companyId),
                    createSampleUser(id: "3", firstName: "Michael", lastName: "Johnson", role: .fieldCrew, companyId: companyId)
                ]
                return sampleUsers
            } else {
                return []
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
            } else if isRunningInPreview {
                // Create sample projects ONLY for SwiftUI previews
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
            } else {
                return []
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
    
    /// Delete the current user's account
    /// - Parameter userId: The ID of the user to delete  
    /// - Returns: Success boolean
    @MainActor
    func deleteUserAccount(userId: String) async -> Bool {
        do {
            // Call the API to delete the user account
            let response = try await apiService.deleteUser(id: userId)
            
            // If successful, clean up local data and log out
            logout()
            
            return true
        } catch {
            print("DataController: Error deleting user account: \(error.localizedDescription)")
            return false
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
