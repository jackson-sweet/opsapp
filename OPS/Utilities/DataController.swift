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

    // Sync status tracking
    @Published var hasPendingSyncs = false
    @Published var pendingSyncCount = 0
    @Published var showSyncRestoredAlert = false
    @Published var isPerformingInitialSync = false // Track post-login initial sync
    @Published var syncStatusMessage = "" // Console-style sync status messages
    @Published var calendarEventsDidChange = false // Toggle to trigger calendar refresh
    private var hasCompletedInitialConnectionCheck = false // Track if we've done initial setup

    // Global app state for external views to access
    var appState: AppState?
    
    // MARK: - Dependencies
    let authManager: AuthManager
    let apiService: APIService
    private let keychainManager: KeychainManager
    private let connectivityMonitor: ConnectivityMonitor
    var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // Periodic sync retry timer
    private var pendingSyncRetryTimer: Timer?
    private let syncRetryInterval: TimeInterval = 180 // 3 minutes

    // MARK: - Public Access
    var syncManager: CentralizedSyncManager!
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

        print("[SYNC] 📱 Initial connection state: \(isConnected ? "Connected" : "Disconnected")")

        // Check for pending syncs on startup
        Task { @MainActor in
            await checkPendingSyncs()

            // Start retry timer if we have pending syncs
            if hasPendingSyncs {
                startPendingSyncRetryTimer()

                // If we have pending syncs AND we're connected, trigger immediate sync
                // (but don't show the alert - this is initial load, not a reconnection)
                if isConnected && isAuthenticated {
                    print("[SYNC] 🚀 App startup with \(pendingSyncCount) pending items - triggering sync")
                    syncManager?.triggerBackgroundSync()
                }
            }

            // Mark that we've completed initial setup
            hasCompletedInitialConnectionCheck = true
        }

        // Handle connection changes
        connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let wasDisconnected = !self.isConnected
                self.isConnected = connectionType != .none
                self.connectionType = connectionType

                print("[SYNC] 🔌 Network state changed: \(self.isConnected ? "Connected" : "Disconnected")")

                if connectionType != .none, self.isAuthenticated {
                    Task { @MainActor in
                        // Check if we have pending syncs before triggering sync
                        await self.checkPendingSyncs()

                        // ONLY show alert if:
                        // 1. We've completed initial setup (not first load)
                        // 2. We were actually disconnected before
                        // 3. We have pending syncs
                        if self.hasCompletedInitialConnectionCheck && wasDisconnected && self.hasPendingSyncs {
                            print("[SYNC] 🔄 Connection restored with \(self.pendingSyncCount) pending items - showing alert")
                            self.showSyncRestoredAlert = true
                        } else {
                            print("[SYNC] 🔄 Connection active - triggering background sync (no alert)")
                        }

                        // Trigger background sync
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
                // Initialize sync manager if authenticated OR if we have a current user (onboarding)
                // This ensures sync is available during company creation in onboarding
                if isAuthenticated || currentUser != nil {
                    initializeSyncManager()
                }
            }
        }
    }
    
    @MainActor
    func initializeSyncManager() {
        guard let modelContext = modelContext else {
            print("[DATA_CONTROLLER] ⚠️ Cannot initialize SyncManager - no modelContext")
            return
        }

        // Skip if already initialized
        guard syncManager == nil else {
            print("[DATA_CONTROLLER] SyncManager already initialized")
            return
        }

        print("[DATA_CONTROLLER] Initializing SyncManager...")

        // Initialize the centralized sync manager
        self.syncManager = CentralizedSyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor
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
        
        // Listen for force logout notification
        NotificationCenter.default.publisher(for: .forceLogout)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let reason = notification.userInfo?["reason"] as? String {
                    print("[SUBSCRIPTION] Force logout triggered: \(reason)")
                }
                self?.logout()
            }
            .store(in: &cancellables)
    }
    
    // Method to perform sync on app launch
    func performAppLaunchSync() {
        print("[APP_LAUNCH_SYNC] 🚀 Starting app launch sync")
        print("[APP_LAUNCH_SYNC] - isConnected: \(isConnected)")
        print("[APP_LAUNCH_SYNC] - isAuthenticated: \(isAuthenticated)")
        print("[APP_LAUNCH_SYNC] - currentUser: \(currentUser != nil ? currentUser!.fullName : "nil")")
        print("[APP_LAUNCH_SYNC] - syncManager: \(syncManager != nil ? "available" : "nil")")

        Task {
            // Always trigger full sync on app launch if authenticated
            if isConnected && isAuthenticated {
                if let syncManager = syncManager {
                    print("[APP_LAUNCH_SYNC] ✅ Triggering FULL SYNC (syncAll)")
                    await syncManager.triggerBackgroundSync(forceProjectSync: true)
                    print("[APP_LAUNCH_SYNC] ✅ Full sync completed")
                } else {
                    print("[APP_LAUNCH_SYNC] ❌ Cannot sync - syncManager is nil")
                }

                // Then sync pending images
                if let imageSyncManager = imageSyncManager {
                    await imageSyncManager.syncPendingImages()
                }
            } else {
                print("[APP_LAUNCH_SYNC] ⚠️ Skipping sync - not connected or not authenticated")
            }
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

                        // Link user to OneSignal for push notifications
                        NotificationManager.shared.linkUserToOneSignal()

                        // Configure OneSignal service for sending notifications
                        Task {
                            await OneSignalService.shared.configure()
                        }

                        // Initialize sync manager
                        initializeSyncManager()
                        return
                    }
                } catch {
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

                            // Link user to OneSignal for push notifications
                            NotificationManager.shared.linkUserToOneSignal()

                            // Configure OneSignal service for sending notifications
                            Task {
                                await OneSignalService.shared.configure()
                            }

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

                    // Track login conversion for Google Ads
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .email)
                    AnalyticsManager.shared.setUserType(user.userType)
                    AnalyticsManager.shared.setUserId(userId)

                    // Log what will happen next
                    if !user.hasCompletedAppOnboarding {
                    } else {
                        // Projects sync already triggered in fetchUserFromAPI after company fetch
                    }
                }

                // Return true because login succeeded, even if onboarding is needed
                // LoginView will check onboarding status separately
                return true
            } else {
                return false
            }
        } catch {
            return false
        }
    }
    
    /// Apple login
    @MainActor
    func loginWithApple(appleResult: AppleSignInManager.AppleSignInResult) async -> Bool {
        do {
            // Attempt Apple login with Bubble
            let loginResult = try await authManager.signInWithApple(
                identityToken: appleResult.identityToken,
                userIdentifier: appleResult.userIdentifier,
                email: appleResult.email,
                givenName: appleResult.givenName,
                familyName: appleResult.familyName
            )
            
            let userDTO = loginResult.user
            
            
            // Store Apple user identifier for future logins
            UserDefaults.standard.set(appleResult.userIdentifier, forKey: "apple_user_identifier")
            
            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            UserDefaults.standard.set(userDTO.id, forKey: "user_id")
            UserDefaults.standard.set(userDTO.id, forKey: "currentUserId")
            
            // Store user type if available
            if let userTypeString = userDTO.userType {
                if userTypeString.lowercased() == "company" {
                    UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
                } else if userTypeString.lowercased() == "employee" {
                    UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
                }
                UserDefaults.standard.set(userTypeString, forKey: "user_type_raw")
            }
            
            // Fetch and create/update user
            try await fetchUserFromAPI(userId: userDTO.id)
            
            // Check onboarding status
            if let user = currentUser {
                let hasCompany = !(user.companyId ?? "").isEmpty
                let hasCompletedAppOnboarding = user.hasCompletedAppOnboarding
                let hasUserType = user.userType != nil

                // Determine if onboarding is needed (indicates new user)
                let needsOnboarding = !hasCompany || !hasCompletedAppOnboarding || !hasUserType

                // Track analytics for Google Ads (Apple sign-in)
                if needsOnboarding {
                    // New user - track as sign-up
                    AnalyticsManager.shared.trackSignUp(userType: user.userType, method: .apple)
                } else {
                    // Returning user - track as login
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .apple)
                }
                AnalyticsManager.shared.setUserType(user.userType)
                AnalyticsManager.shared.setUserId(userDTO.id)

                UserDefaults.standard.set(!needsOnboarding, forKey: "onboarding_completed")

                if !needsOnboarding {
                    self.isAuthenticated = true
                    // Projects will sync after company fetch in fetchUserFromAPI
                } else {
                    // Don't set isAuthenticated - let LoginView handle onboarding
                }

                return true
            }

            return false
        } catch {

            // Check for specific errors
            if let authError = error as? AuthError {
                switch authError {
                case .invalidCredentials:
                    // User doesn't exist yet - this is expected for new users
                    print("Invalid Credentials")
                default: break
                }
            }

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
            
            
            // Immediately set user type if available
            if let userTypeString = userDTO.userType {
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
                
                // Check if user is admin from the login response
                if let adminRefs = companyDTO.admin {
                    let adminIds = adminRefs.compactMap { $0.stringValue }
                    
                    if adminIds.contains(userDTO.id), let user = currentUser {
                        user.role = .admin
                        try? modelContext?.save()
                    }
                }
                // We already fetched company data in fetchUserFromAPI, so we don't need to save it again
                // The fetchCompanyData method was already called and handled the company save
            } else {
            }
            
            // Now check if user has completed onboarding based on their data
            if let user = currentUser {
                let hasCompany = !(user.companyId ?? "").isEmpty
                let hasCompletedAppOnboarding = user.hasCompletedAppOnboarding

                // Determine if onboarding is needed (indicates new user)
                let needsOnboarding = !hasCompany || !hasCompletedAppOnboarding

                // Track analytics for Google Ads (Google sign-in)
                if needsOnboarding {
                    // New user - track as sign-up
                    AnalyticsManager.shared.trackSignUp(userType: user.userType, method: .google)
                } else {
                    // Returning user - track as login
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .google)
                }
                AnalyticsManager.shared.setUserType(user.userType)
                AnalyticsManager.shared.setUserId(userDTO.id)

                UserDefaults.standard.set(!needsOnboarding, forKey: "onboarding_completed")

                // Only set isAuthenticated if they've completed onboarding
                // Otherwise, return true to indicate login succeeded but don't set isAuthenticated
                if !needsOnboarding {
                    self.isAuthenticated = true
                    // Projects sync already triggered in fetchUserFromAPI after company fetch
                } else {
                    // Onboarding is needed - sync will happen in fetchUserFromAPI
                }

                // Return true to indicate login was successful (even if onboarding is needed)
                return true
            }

            return false
        } catch let error as AuthError {

            // If it's invalid credentials, it means no account exists
            if case .invalidCredentials = error {
            }
            return false
        } catch {
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
                } else {
                    // If no employee type is set, default to field crew
                    // This will be corrected when company data is fetched
                    user.role = .fieldCrew
                }
                
                // Handle company ID
                if let companyId = userDTO.company, !companyId.isEmpty {
                    user.companyId = companyId
                    // Company will be fetched below after sync manager is initialized
                } else {
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

                // Update tutorial/onboarding completion flags
                // Use API value if true (API is source of truth once synced)
                // Keep local value if API returns false/nil (allows offline completion to persist)
                if userDTO.hasCompletedAppTutorial == true {
                    user.hasCompletedAppTutorial = true
                }
                if userDTO.hasCompletedAppOnboarding == true {
                    user.hasCompletedAppOnboarding = true
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
            throw error
        }
        
        // Update app state with the current user
        self.currentUser = user
        
        // Store user type in UserDefaults for onboarding flow
        if let userTypeString = userDTO.userType {
            // Map Bubble's user type strings to our UserType enum
            if userTypeString.lowercased() == "company" {
                UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
            } else if userTypeString.lowercased() == "employee" {
                UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
            }
            // Also store the raw value as a backup
            UserDefaults.standard.set(userTypeString, forKey: "user_type_raw")
        }
        
        // Save important IDs to UserDefaults
        if let companyId = user.companyId {
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
        } else {
        }

        // Set authentication flag for consistency with onboarding flow
        UserDefaults.standard.set(true, forKey: "is_authenticated")

        UserDefaults.standard.set(user.id, forKey: "currentUserId")

        // Link user to OneSignal for push notifications
        NotificationManager.shared.linkUserToOneSignal()

        // Configure OneSignal service for sending notifications
        Task {
            await OneSignalService.shared.configure()
        }

        // Initialize sync managers first
        initializeSyncManager()

        // IMPORTANT: Set isPerformingInitialSync BEFORE isAuthenticated
        // This ensures the loading screen is ready when HomeView first appears
        await MainActor.run {
            isPerformingInitialSync = true
        }

        // Only set isAuthenticated if user has completed onboarding
        // This ensures LoginView can show onboarding overlay if needed
        if user.hasCompletedAppOnboarding {
            self.isAuthenticated = true
        } else {
            self.isAuthenticated = false
        }

        // Fetch company data if needed
        if isConnected, let companyId = user.companyId, !companyId.isEmpty {
            do {
                await MainActor.run {
                    syncStatusMessage = "FETCHING COMPANY DATA... [\(companyId.prefix(8))]"
                }
                try await fetchCompanyData(companyId: companyId)

                // After fetching company data, the user's role may have been updated to admin
                // Log the updated role

                await MainActor.run {
                    syncStatusMessage = "LOADING TEAM MEMBERS..."
                }

                // Fetch OPS Contacts option set (only on initial login, not every sync)
                await fetchOpsContacts()

                // Now that we have company data, perform a full sync to get all data
                // This ensures user sees their projects immediately after login
                print("[LOGIN] 🔄 Starting full sync after login...")
                await MainActor.run {
                    syncStatusMessage = "SYNCING PROJECTS..."
                }
                do {
                    try await syncManager?.syncAll()
                    print("[LOGIN] ✅ Full sync completed successfully")
                    await MainActor.run {
                        syncStatusMessage = "SYNC COMPLETE ✓"
                    }
                } catch {
                    print("[LOGIN] ⚠️ Full sync failed: \(error)")
                    // Continue anyway - user is logged in even if sync fails
                    await MainActor.run {
                        syncStatusMessage = "SYNC COMPLETED WITH WARNINGS"
                    }
                }
                // Wait a moment so user can see completion message
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                await MainActor.run {
                    isPerformingInitialSync = false
                    syncStatusMessage = ""
                }
            } catch {
                // Continue even if company data fetch fails - don't block authentication
                // But still try to sync what we can
                print("[LOGIN] ⚠️ Company fetch failed, attempting sync anyway...")
                await MainActor.run {
                    syncStatusMessage = "SYNCING PROJECTS..."
                }
                do {
                    try await syncManager?.syncAll()
                    print("[LOGIN] ✅ Full sync completed after company fetch failure")
                    await MainActor.run {
                        syncStatusMessage = "SYNC COMPLETE ✓"
                    }
                } catch {
                    print("[LOGIN] ⚠️ Full sync also failed: \(error)")
                    // Continue anyway - user is logged in even if sync fails
                    await MainActor.run {
                        syncStatusMessage = "SYNC COMPLETED WITH WARNINGS"
                    }
                }
                // Wait a moment so user can see completion message
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                await MainActor.run {
                    isPerformingInitialSync = false
                    syncStatusMessage = ""
                }
            }
        } else if !isConnected {
            // No internet connection - can't sync, so dismiss loading screen
            print("[LOGIN] ⚠️ No internet connection, skipping sync")
            await MainActor.run {
                isPerformingInitialSync = false
                syncStatusMessage = ""
            }
        } else {
            // No company ID - dismiss loading screen
            print("[LOGIN] ⚠️ No company ID, skipping sync")
            await MainActor.run {
                isPerformingInitialSync = false
                syncStatusMessage = ""
            }
        }
    }
    
    @MainActor
    func logout() {
        print("[LOGOUT] Starting logout process...")

        // Unlink user from OneSignal
        NotificationManager.shared.unlinkUserFromOneSignal()

        // Clear OneSignal service configuration
        OneSignalService.shared.clearConfiguration()

        // Reset subscription manager state to prevent lockout screen from showing after logout
        SubscriptionManager.shared.resetForLogout()

        // First, clear the current user reference to prevent views from accessing it
        self.currentUser = nil

        // Post notification to reset app state and dismiss views
        NotificationCenter.default.post(name: NSNotification.Name("LogoutInitiated"), object: nil)

        // IMPORTANT: Clear auth state to trigger view dismissal
        clearAuthentication()

        // Sign out from auth manager
        authManager.signOut()
        
        // Clear PIN settings
        simplePINManager.removePIN()

        // Clear onboarding state to prevent stale flow data on next login
        OnboardingState.clear()
        UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.completed)

        // Give views MORE time to fully dismiss and release references
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            print("[LOGOUT] Performing complete data wipe...")
            
            // Perform complete data wipe on main thread
            Task { @MainActor in
                self.performCompleteDataWipe()
                print("[LOGOUT] Data wipe complete")
            }
        }
    }
    
    /// Completely wipes all data from the SwiftData store
    @MainActor
    private func performCompleteDataWipe() {
        guard let context = modelContext else {
            print("[LOGOUT] No model context available for data wipe")
            return
        }
        
        print("[LOGOUT] Deleting all SwiftData models...")
        
        // Wrap in autoreleasepool to manage memory properly
        autoreleasepool {
            // Delete in correct order to avoid relationship issues
            // Start with leaf entities that don't have critical relationships
            
            // 1. Delete CalendarEvents first (they reference tasks and projects)
            if let calendarEvents = try? context.fetch(FetchDescriptor<CalendarEvent>()) {
                print("[LOGOUT] Deleting \(calendarEvents.count) calendar events...")
                for event in calendarEvents {
                    context.delete(event)
                }
            }
            
            // 2. Delete ProjectTasks (they reference projects)
            if let tasks = try? context.fetch(FetchDescriptor<ProjectTask>()) {
                print("[LOGOUT] Deleting \(tasks.count) tasks...")
                for task in tasks {
                    context.delete(task)
                }
            }
            
            // 3. Delete TaskTypes
            if let taskTypes = try? context.fetch(FetchDescriptor<TaskType>()) {
                print("[LOGOUT] Deleting \(taskTypes.count) task types...")
                for taskType in taskTypes {
                    context.delete(taskType)
                }
            }
            
            // 4. Delete Projects (they have relationships to companies and users)
            if let projects = try? context.fetch(FetchDescriptor<Project>()) {
                print("[LOGOUT] Deleting \(projects.count) projects...")
                for project in projects {
                    // Clear relationships first to avoid crashes
                    project.teamMembers.removeAll()
                    context.delete(project)
                }
            }
            
            // 5. Delete Clients
            if let clients = try? context.fetch(FetchDescriptor<Client>()) {
                print("[LOGOUT] Deleting \(clients.count) clients...")
                for client in clients {
                    context.delete(client)
                }
            }
            
            // 6. Delete TeamMembers (they reference companies)
            if let teamMembers = try? context.fetch(FetchDescriptor<TeamMember>()) {
                print("[LOGOUT] Deleting \(teamMembers.count) team members...")
                for member in teamMembers {
                    // Clear company relationship first
                    member.company = nil
                    context.delete(member)
                }
            }
            
            // 7. Delete Users
            if let users = try? context.fetch(FetchDescriptor<User>()) {
                print("[LOGOUT] Deleting \(users.count) users...")
                for user in users {
                    // Clear relationships first
                    user.assignedProjects.removeAll()
                    context.delete(user)
                }
            }
            
            // 8. Delete Companies last (they have relationships to many entities)
            if let companies = try? context.fetch(FetchDescriptor<Company>()) {
                print("[LOGOUT] Deleting \(companies.count) companies...")
                for company in companies {
                    // Clear relationships first
                    company.teamMembers.removeAll()
                    context.delete(company)
                }
            }
        }
        
        // Save all deletions outside autoreleasepool
        do {
            try context.save()
            print("[LOGOUT] All data deleted and saved")
        } catch {
            print("[LOGOUT] Error saving after data wipe: \(error)")
        }
        
        // Clear any cached data
        clearAllCaches()
    }
    
    /// Clears all cached data
    private func clearAllCaches() {
        // Clear image cache
        ImageCache.shared.clear()
        
        // Clear any other app-specific caches
        UserDefaults.standard.synchronize()
        
        print("[LOGOUT] All caches cleared")
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

        // Clear onboarding state to prevent auto-triggering onboarding after logout
        UserDefaults.standard.removeObject(forKey: "onboarding_state_v2")
        
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
        
        // Clear user type data - CRITICAL for proper onboarding
        UserDefaults.standard.removeObject(forKey: "selected_user_type")
        UserDefaults.standard.removeObject(forKey: "user_type_raw")
        UserDefaults.standard.removeObject(forKey: "user_type")  // This was missing!
        
        // Clear Apple Sign-In data
        UserDefaults.standard.removeObject(forKey: "apple_user_identifier")
        
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
                // We should consider a way to recover from this error in a production app
            }
            
        } catch {
        }
    }
    
    // MARK: - Data Operations
    
    /// Fetch company data from API - optimized for reliability
    @MainActor
    private func fetchCompanyData(companyId: String) async throws {
        guard let context = modelContext else { 
            return 
        }
        
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
                    
                    // Log final subscription state after update
                    
                    try? context.save()
                    
                    // If team members haven't been synced, or it's been more than a day, sync team members
                    if !company.teamMembersSynced || 
                       company.lastSyncedAt == nil || 
                       Date().timeIntervalSince(company.lastSyncedAt!) > 86400 {
                        
                        // Launch a task to fetch team members
                        Task {
                            await syncManager?.syncCompanyTeamMembers(company)
                        }
                    } else {
                    }
                }
            } else {
            }
        } catch {
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
        
        // Log subscription data from DTO if available
        if let subscriptionStatus = dto.subscriptionStatus {
            // CRITICAL FIX: Normalize status to lowercase to match enum values
            let normalizedStatus = subscriptionStatus.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let oldStatus = company.subscriptionStatus
            company.subscriptionStatus = normalizedStatus
            print("[SUBSCRIPTION] Status changed: \(oldStatus ?? "nil") -> \(normalizedStatus)")
        } else {
            print("[SUBSCRIPTION] Status update: nil (no change)")
        }
        
        if let subscriptionPlan = dto.subscriptionPlan {
            // CRITICAL FIX: Normalize plan to lowercase to match enum values
            let normalizedPlan = subscriptionPlan.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let oldPlan = company.subscriptionPlan
            company.subscriptionPlan = normalizedPlan
            print("[SUBSCRIPTION] Plan changed: \(oldPlan ?? "nil") -> \(normalizedPlan)")
        } else {
            print("[SUBSCRIPTION] Plan update: nil (no change)")
        }
        
        if let subscriptionEnd = dto.subscriptionEnd {
            company.subscriptionEnd = subscriptionEnd
        } else {
        }
        
        if let subscriptionPeriod = dto.subscriptionPeriod {
            company.subscriptionPeriod = subscriptionPeriod
        } else {
        }
        
        if let maxSeats = dto.maxSeats {
            company.maxSeats = maxSeats
        } else {
        }
        
        if let seatedEmployees = dto.seatedEmployees {
            let seatedIds = seatedEmployees.compactMap { $0.stringValue }
            company.seatedEmployeeIds = seatedIds.joined(separator: ",")
        } else {
        }
        
        if let seatGraceStartDate = dto.seatGraceStartDate {
            company.seatGraceStartDate = seatGraceStartDate
        } else {
        }
        
        // Note: subscriptionIdsJson not available in current DTO
        
        if let trialStartDate = dto.trialStartDate {
            company.trialStartDate = trialStartDate
        } else {
        }
        
        if let trialEndDate = dto.trialEndDate {
            company.trialEndDate = trialEndDate
        } else {
        }
        
        if let hasPrioritySupport = dto.hasPrioritySupport {
            company.hasPrioritySupport = hasPrioritySupport
        } else {
        }
        
        if let dataSetupPurchased = dto.dataSetupPurchased {
            company.dataSetupPurchased = dataSetupPurchased
        } else {
        }
        
        if let dataSetupCompleted = dto.dataSetupCompleted {
            company.dataSetupCompleted = dataSetupCompleted
        } else {
        }
        
        if let dataSetupScheduledDate = dto.dataSetupScheduledDate {
            company.dataSetupScheduledDate = dataSetupScheduledDate
        } else {
        }
        
        if let stripeCustomerId = dto.stripeCustomerId {
            company.stripeCustomerId = stripeCustomerId
        } else {
        }
        
        // Handle admin role update
        if let currentUser = currentUser,
           let adminRefs = dto.admin {
            // Check if current user's ID is in the admin list
            let adminIds = adminRefs.compactMap { $0.stringValue }

            print("[DATA_CONTROLLER] Checking admin status for user: \(currentUser.id)")
            print("[DATA_CONTROLLER] Company admin IDs: \(adminIds)")

            if adminIds.contains(currentUser.id) {
                print("[DATA_CONTROLLER] ✅ User IS admin - updating role from \(currentUser.role) to .admin")
                // Update current user's role to admin
                currentUser.role = .admin
                // Save the context immediately to ensure role update is persisted
                try? modelContext?.save()

                // CRITICAL: Force UI update by triggering objectWillChange
                self.objectWillChange.send()
                print("[DATA_CONTROLLER] Admin role updated and UI notified")
            } else {
                print("[DATA_CONTROLLER] ⚠️ User is NOT admin")
            }
        } else {
            print("[DATA_CONTROLLER] Cannot check admin status - missing currentUser or admin list")
        }
        
        // Handle admin list
        if let adminRefs = dto.admin {
            let adminIds = adminRefs.compactMap { $0.stringValue }
            company.setAdminIds(adminIds)
        }
        
        // Handle company details
        if let industryValue = dto.industry, !industryValue.isEmpty {
            company.setIndustries([industryValue])
        }
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
                    
                    // Always try to refresh user data if we're online to ensure we have the latest
                    if isConnected {
                        do {
                            let userDTO = try await apiService.fetchUser(id: memberId)
                            
                            // Check if user is still part of the company
                            if userDTO.company == nil || (userDTO.company != nil && userDTO.company != existingUser.companyId) {
                                // User is no longer part of the company - remove them
                                
                                // Remove from all projects
                                for assignedProject in existingUser.assignedProjects {
                                    assignedProject.teamMembers.removeAll { $0.id == memberId }
                                }
                                
                                // Delete the user
                                context.delete(existingUser)
                                continue // Skip to next team member
                            }
                            
                            // Update all user fields to ensure we have the latest data
                            existingUser.firstName = userDTO.nameFirst ?? existingUser.firstName
                            existingUser.lastName = userDTO.nameLast ?? existingUser.lastName
                            
                            // Update phone number
                            if let phoneNumber = userDTO.phone {
                                existingUser.phone = phoneNumber
                            }
                            
                            // Update email
                            if let emailAuth = userDTO.authentication?.email?.email {
                                existingUser.email = emailAuth
                            } else if let email = userDTO.email {
                                existingUser.email = email
                            }
                            
                            // Update profile image URL
                            if let avatarUrl = userDTO.avatar {
                                existingUser.profileImageURL = avatarUrl
                            }
                            
                            // Update last synced time
                            existingUser.lastSyncedAt = Date()
                            
                            // Save the context
                            try context.save()
                        } catch {
                        }
                    }
                    
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
                        
                        // Check if user belongs to a company
                        if userDTO.company == nil {
                            continue // Skip this user
                        }
                        
                        // Create new user
                        let newUser = userDTO.toModel()

                        // Create bidirectional relationship (with duplicate check)
                        if !newUser.assignedProjects.contains(where: { $0.id == project.id }) {
                            newUser.assignedProjects.append(project)
                        }
                        if !project.teamMembers.contains(where: { $0.id == newUser.id }) {
                            project.teamMembers.append(newUser)
                        }
                        
                        // Insert into database
                        context.insert(newUser)
                    } catch {
                        // Check if this is a 404 error (user deleted from system)
                        if let apiError = error as? APIError, case .httpError(let statusCode) = apiError, statusCode == 404 {
                            
                            // Delete any existing local user with this ID
                            let existingUserPredicate = #Predicate<User> { $0.id == memberId }
                            let existingUserDescriptor = FetchDescriptor<User>(predicate: existingUserPredicate)
                            if let existingUsers = try? context.fetch(existingUserDescriptor) {
                                for userToDelete in existingUsers {
                                    context.delete(userToDelete)
                                }
                            }
                            
                            // Add to sync manager's non-existent cache if available
                            if let syncManager = self.syncManager {
                                syncManager.addNonExistentUserId(memberId)
                            }
                            
                            continue
                        }
                        
                        
                        // Only create placeholder for non-404 errors (network issues, etc)
                        let placeholderUser = User(
                            id: memberId,
                            firstName: "Team Member",
                            lastName: "#\(memberId.suffix(4))",
                            role: .fieldCrew,
                            companyId: project.companyId
                        )

                        // Create bidirectional relationship (with duplicate check)
                        if !placeholderUser.assignedProjects.contains(where: { $0.id == project.id }) {
                            placeholderUser.assignedProjects.append(project)
                        }
                        if !project.teamMembers.contains(where: { $0.id == placeholderUser.id }) {
                            project.teamMembers.append(placeholderUser)
                        }
                        
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

                    // Create bidirectional relationship (with duplicate check)
                    if !placeholderUser.assignedProjects.contains(where: { $0.id == project.id }) {
                        placeholderUser.assignedProjects.append(project)
                    }
                    if !project.teamMembers.contains(where: { $0.id == placeholderUser.id }) {
                        project.teamMembers.append(placeholderUser)
                    }

                    // Insert into database
                    context.insert(placeholderUser)
                }
            } catch {
            }
        }
        
        // Save changes
        do {
            try context.save()
        } catch {
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
            
            
            // Get all projects (will sort in-memory since startDate is computed)
            let descriptor = FetchDescriptor<Project>()
            let allProjects = try modelContext.fetch(descriptor)
            
            
            // First filter by company - this is most important
            var filteredProjects = allProjects.filter { project in
                return project.companyId == companyId
            }
            
            
            // Then filter by date if needed - check if project is active on this date
            if let date = date {
                filteredProjects = filteredProjects.filter { project in
                    // Use the project's isActiveOn method to check if it's scheduled for this date
                    return project.isActiveOn(date: date)
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
    
    /// Force refresh projects from Bubble backend
    func refreshProjectsFromBackend() async {
        guard isConnected, isAuthenticated else {
            return
        }

        guard let syncManager = syncManager else {
            return
        }

        guard let companyId = currentUser?.companyId else {
            return
        }

        print("[MANUAL_SYNC] 🔄 Starting comprehensive manual sync...")

        do {
            try await syncManager.manualFullSync(companyId: companyId)
            print("[MANUAL_SYNC] ✅ Manual sync completed")
        } catch {
            print("[MANUAL_SYNC] ❌ Manual sync failed: \(error)")
        }
    }
    
    // MARK: - CalendarEvent Methods

    /// Get active calendar events that overlap with a date range (optimized for scheduler)
    /// This method is much more efficient than calling getCalendarEvents(for:) in a loop
    func getCalendarEvents(in dateRange: ClosedRange<Date>) -> [CalendarEvent] {
        guard let context = modelContext else {
            return []
        }

        do {
            // Fetch all events once (much faster than multiple queries)
            let allEvents = try context.fetch(FetchDescriptor<CalendarEvent>())

            // Filter events that overlap with the date range
            let filteredEvents = allEvents.filter { event in
                // Check if event overlaps with the range
                guard let eventStart = event.startDate else { return false }
                let eventEnd = event.endDate ?? eventStart

                // Event overlaps if:
                // - Event starts before range ends AND
                // - Event ends after range starts
                return eventStart <= dateRange.upperBound && eventEnd >= dateRange.lowerBound
            }

            return filteredEvents.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            print("[CALENDAR] ❌ Failed to fetch events in range: \(error)")
            return []
        }
    }

    /// Get calendar events for a specific date (simplified version for scheduler)
    func getCalendarEvents(for date: Date) -> [CalendarEvent] {
        guard let context = modelContext else {
            return []
        }

        let descriptor = FetchDescriptor<CalendarEvent>()

        do {
            let allEvents = try context.fetch(descriptor)

            // Filter by date
            let filteredEvents = allEvents.filter { event in
                // Check if event is active on this date
                let spannedDates = event.spannedDates
                return spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
            }

            return filteredEvents.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            return []
        }
    }

    /// Get calendar events for a specific date for the current user
    func getCalendarEventsForCurrentUser(for date: Date) -> [CalendarEvent] {
        guard let user = currentUser else { 
            return [] 
        }
        guard let context = modelContext else { 
            return [] 
        }
        
        
        let descriptor = FetchDescriptor<CalendarEvent>()
        
        do {
            let allEvents = try context.fetch(descriptor)
            
            /*
            // Search for any Railings events specifically
            let railingsEvents = allEvents.filter { $0.title.lowercased().contains("railings") }
            if !railingsEvents.isEmpty {
                for (index, event) in railingsEvents.enumerated() {
                    if let project = event.project {
                    }
                }
            }
            */
            
            /*
            // Debug first few events for general context
            for (index, event) in allEvents.prefix(5).enumerated() {
            }
            */
            
            // Filter by date and user access
            var passedDateFilter = 0
            var passedShouldDisplayFilter = 0
            var passedUserAccessFilter = 0
            
            let filteredEvents = allEvents.filter { event in
                // Check if event is active on this date
                let spannedDates = event.spannedDates
                let isActiveOnDate = spannedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
                
                if !isActiveOnDate {
                    return false
                }
                passedDateFilter += 1
                passedShouldDisplayFilter += 1
                
                // For Admin and Office Crew, show all company events
                if user.role == .admin || user.role == .officeCrew {
                    let matchesCompany = event.companyId == user.companyId
                    if !matchesCompany {
                        return false
                    } else {
                        passedUserAccessFilter += 1
                        return true
                    }
                } else {
                    // For Field Crew, only show events they're assigned to
                    let eventTeamMemberIds = event.getTeamMemberIds()
                    let isAssignedViaIds = eventTeamMemberIds.contains(user.id)
                    let isAssignedViaObjects = event.teamMembers.contains(where: { $0.id == user.id })
                    let isAssigned = isAssignedViaIds || isAssignedViaObjects
                    
                    if !isAssigned {
                        // Also check task assignment if this is a task event
                        if let task = event.task {
                            let taskTeamMemberIds = task.getTeamMemberIds()
                            let isAssignedToTask = taskTeamMemberIds.contains(user.id) || task.teamMembers.contains(where: { $0.id == user.id })
                            
                            if isAssignedToTask {
                                passedUserAccessFilter += 1
                                return true
                            }
                        }
                        return false
                    } else {
                        passedUserAccessFilter += 1
                        return true
                    }
                }
            }
            
            // Commented out verbose logging to prevent console spam during calendar rendering
            
            // for event in filteredEvents {
            // }
            
            return filteredEvents.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            return []
        }
    }

    func getAllCalendarEvents(from startDate: Date) -> [CalendarEvent] {
        guard let user = currentUser else {
            return []
        }
        guard let context = modelContext else {
            return []
        }

        let descriptor = FetchDescriptor<CalendarEvent>()

        do {
            let allEvents = try context.fetch(descriptor)

            let filteredEvents = allEvents.filter { event in
                // Filter by startDate instead of endDate to include events without end dates
                guard let eventStartDate = event.startDate else { return false }
                if eventStartDate < startDate {
                    return false
                }

                if user.role == .admin || user.role == .officeCrew {
                    return event.companyId == user.companyId
                } else {
                    let eventTeamMemberIds = event.getTeamMemberIds()
                    let isAssignedViaIds = eventTeamMemberIds.contains(user.id)
                    let isAssignedViaObjects = event.teamMembers.contains(where: { $0.id == user.id })
                    let isAssigned = isAssignedViaIds || isAssignedViaObjects

                    if !isAssigned {
                        if let task = event.task {
                            let taskTeamMemberIds = task.getTeamMemberIds()
                            let isAssignedToTask = taskTeamMemberIds.contains(user.id) || task.teamMembers.contains(where: { $0.id == user.id })
                            return isAssignedToTask
                        }
                        if let project = event.project {
                            let projectTeamMemberIds = project.getTeamMemberIds()
                            let isAssignedToProject = projectTeamMemberIds.contains(user.id) || project.teamMembers.contains(where: { $0.id == user.id })
                            return isAssignedToProject
                        }
                        return false
                    }

                    return true
                }
            }

            return filteredEvents.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
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
        
        // Fetch all projects (sorting by computed startDate must be done in-memory)
        let descriptor = FetchDescriptor<Project>()

        return try context.fetch(descriptor)
    }
    
    func getAllProjects() -> [Project] {
        guard let context = modelContext else {
            return []
        }
        
        do {
            // Fetch all projects (sorting by computed startDate must be done in-memory)
            let descriptor = FetchDescriptor<Project>()

            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }
    
    // MARK: - Client Management
    
    func getClient(id: String) -> Client? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { client in
                    client.id == id
                }
            )
            return try context.fetch(descriptor).first
        } catch {
            return nil
        }
    }
    
    func saveClient(_ client: Client) {
        guard let context = modelContext else { return }
        
        context.insert(client)
        do {
            try context.save()
        } catch {
        }
    }
    
    func getAllClients(for companyId: String) -> [Client] {
        guard let context = modelContext else { return [] }
        
        do {
            let descriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { client in
                    client.companyId == companyId
                }
            )
            return try context.fetch(descriptor)
        } catch {
            print("[DataController] Error fetching clients: \(error)")
            return []
        }
    }
    
    // MARK: - TaskType Management

    func getAllTaskTypes(for companyId: String) -> [TaskType] {
        guard let context = modelContext else { return [] }

        do {
            let descriptor = FetchDescriptor<TaskType>(
                predicate: #Predicate<TaskType> { taskType in
                    taskType.companyId == companyId
                }
            )
            return try context.fetch(descriptor)
        } catch {
            print("[DataController] Error fetching task types: \(error)")
            return []
        }
    }

    // MARK: - Task Status Options Management

    func getAllTaskStatusOptions(for companyId: String) -> [TaskStatusOption] {
        guard let context = modelContext else { return [] }

        do {
            let descriptor = FetchDescriptor<TaskStatusOption>(
                predicate: #Predicate<TaskStatusOption> { option in
                    option.companyId == companyId
                },
                sortBy: [SortDescriptor(\.index)]
            )
            return try context.fetch(descriptor)
        } catch {
            print("[DataController] Error fetching task status options: \(error)")
            return []
        }
    }

    @MainActor
    func syncTaskStatusOptions(for companyId: String) async {
        guard let context = modelContext else { return }

        do {
            let dtos = try await apiService.fetchTaskStatusOptions(companyId: companyId)

            for dto in dtos {
                let descriptor = FetchDescriptor<TaskStatusOption>(
                    predicate: #Predicate<TaskStatusOption> { $0.id == dto._id }
                )
                let existing = try context.fetch(descriptor)

                if let option = existing.first {
                    option.display = dto.Display
                    option.color = dto.color
                    option.index = Int(dto.index)
                    option.lastSyncedAt = Date()
                } else {
                    let newOption = TaskStatusOption(
                        id: dto._id,
                        display: dto.Display,
                        color: dto.color,
                        index: Int(dto.index),
                        companyId: companyId
                    )
                    context.insert(newOption)
                }
            }

            try context.save()
            print("[DataController] ✅ Synced \(dtos.count) task status options")
        } catch {
            print("[DataController] ❌ Error syncing task status options: \(error)")
        }
    }
    
    func getCurrentUserCompany() -> Company? {
        guard let user = currentUser else {
            print("[SUBSCRIPTION] getCurrentUserCompany: No current user")
            return nil
        }
        
        guard let companyId = user.companyId else {
            print("[SUBSCRIPTION] getCurrentUserCompany: User has no companyId")
            return nil
        }
        
        guard let context = modelContext else {
            print("[SUBSCRIPTION] getCurrentUserCompany: No model context")
            return nil
        }
        
        do {
            let descriptor = FetchDescriptor<Company>(
                predicate: #Predicate<Company> { $0.id == companyId }
            )
            let companies = try context.fetch(descriptor)
            if companies.isEmpty {
                print("[SUBSCRIPTION] getCurrentUserCompany: No company found with ID: \(companyId)")
            }
            return companies.first
        } catch {
            print("[SUBSCRIPTION] getCurrentUserCompany: Error fetching company: \(error)")
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
            // Get current user to check their role
            guard let user = currentUser else { return [] }
            
            // Get all projects
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            
            // Filter projects based on user role
            let filteredProjects: [Project]
            
            if user.role == .fieldCrew {
                // Field crew only see projects they're assigned to
                filteredProjects = allProjects.filter { project in
                    project.getTeamMemberIds().contains(userId) || 
                    project.teamMembers.contains(where: { $0.id == userId })
                }
            } else {
                // Office crew and admins see ALL projects for their company
                if let companyId = user.companyId {
                    filteredProjects = allProjects.filter { project in
                        project.companyId == companyId
                    }
                } else {
                    // If no company ID, fall back to showing user's projects
                    filteredProjects = allProjects.filter { project in
                        project.getTeamMemberIds().contains(userId) || 
                        project.teamMembers.contains(where: { $0.id == userId })
                    }
                }
            }
            
            // If we have real projects, return them
            if !filteredProjects.isEmpty {
                // Sort by start date, most recent first
                return filteredProjects.sorted { 
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
            return []
        }
    }
    
    private func createSampleProject(id: String, title: String, status: Status, 
                                  startDate: Date?, endDate: Date?) -> Project {
        let project = Project(id: id, title: title, status: status)
        project.startDate = startDate
        project.endDate = endDate
        // Client name will be set via Client relationship in production
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
            return false
        }
    }

    // MARK: - Data Deletion Methods

    /// Soft delete a project by setting deletedAt timestamp
    /// - Parameter project: The project to soft delete
    /// - Throws: API or database errors
    @MainActor
    func deleteProject(_ project: Project) async throws {
        guard let modelContext = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        let projectTitle = project.title
        let deletionDate = Date()

        print("[DELETE_PROJECT] 🗑️ Soft deleting project '\(projectTitle)' (setting deletedAt)")

        // SOFT DELETE: Set deletedAt timestamp instead of physical deletion
        project.deletedAt = deletionDate
        project.needsSync = true

        // Cascade soft delete to all tasks
        for task in project.tasks where task.deletedAt == nil {
            task.deletedAt = deletionDate
            task.needsSync = true
        }

        // Save changes locally
        try modelContext.save()
        print("[DELETE_PROJECT] ✅ Project '\(projectTitle)' soft deleted locally")

        // Trigger background sync to push changes to Bubble
        syncManager?.triggerBackgroundSync()
    }

    /// Delete a task and its calendar event from both Bubble API and local storage
    /// - Parameters:
    ///   - task: The task to delete
    ///   - updateProject: Whether to update parent project dates (default: true)
    /// - Throws: API or database errors
    @MainActor
    func deleteTask(_ task: ProjectTask, updateProject: Bool = true) async throws {
        guard let modelContext = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        let taskId = task.id
        let calendarEventId = task.calendarEvent?.id
        let project = task.project

        // STEP 1: Delete calendar event from Bubble if it exists
        if let eventId = calendarEventId {
            try await apiService.deleteCalendarEvent(id: eventId)
        }

        // STEP 2: Delete task from Bubble
        try await apiService.deleteTask(id: taskId)

        // STEP 3: Delete from local SwiftData
        modelContext.delete(task)
        try modelContext.save()

        // STEP 4: Update project dates (automatically computed from remaining tasks)
        if updateProject, let project = project {
            try modelContext.save()

            // Sync updated computed dates to Bubble
            try await apiService.updateProjectDates(
                projectId: project.id,
                startDate: project.computedStartDate,
                endDate: project.computedEndDate
            )
        }
    }

    /// Delete a client from both Bubble API and local storage
    /// - Parameter client: The client to delete
    /// - Throws: API or database errors
    /// - Note: Caller is responsible for handling associated projects (reassignment or deletion)
    @MainActor
    func deleteClient(_ client: Client) async throws {
        guard let modelContext = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        // STEP 1: Delete client from Bubble
        try await apiService.deleteClient(id: client.id)

        // STEP 2: Delete client from local SwiftData
        modelContext.delete(client)
        try modelContext.save()
    }

    /// Reschedule a project to new dates
    /// - Parameters:
    ///   - project: The project to reschedule
    ///   - startDate: New start date
    ///   - endDate: New end date
    ///   - calendarEvent: The project's calendar event (optional, will be found if not provided)
    /// - Throws: API or database errors
    @MainActor
    func rescheduleProject(_ project: Project, startDate: Date, endDate: Date, calendarEvent: CalendarEvent? = nil) async throws {
        guard let modelContext = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        print("[RESCHEDULE_PROJECT] 📅 Rescheduling project: \(project.title)")
        print("[RESCHEDULE_PROJECT] Old dates: \(project.startDate?.description ?? "nil") - \(project.endDate?.description ?? "nil")")
        print("[RESCHEDULE_PROJECT] New dates: \(startDate.description) - \(endDate.description)")

        // STEP 1: Update calendar event if provided
        // Note: primaryCalendarEvent removed in task-only scheduling migration
        // All calendar events are task-based now
        if let event = calendarEvent {
            event.startDate = startDate
            event.endDate = endDate
            event.needsSync = true
            print("[RESCHEDULE_PROJECT] ✅ Calendar event updated locally")
        } else {
            print("[RESCHEDULE_PROJECT] ⚠️ No calendar event provided")
        }

        // STEP 2: Update project dates
        project.startDate = startDate
        project.endDate = endDate
        project.needsSync = true

        // STEP 3: Save locally
        try modelContext.save()
        print("[RESCHEDULE_PROJECT] ✅ Changes saved locally")

        // STEP 4: Update dates in Bubble
        try await apiService.updateProjectDates(
            projectId: project.id,
            startDate: startDate,
            endDate: endDate
        )
        print("[RESCHEDULE_PROJECT] ✅ Project dates updated in Bubble")

        // STEP 5: Update calendar event in Bubble if it exists
        if let event = calendarEvent {
            let formatter = ISO8601DateFormatter()
            let startDateString = formatter.string(from: startDate)
            let endDateString = formatter.string(from: endDate)

            print("[RESCHEDULE_PROJECT] 📅 Updating calendar event dates:")
            print("[RESCHEDULE_PROJECT]   - Start: \(startDate) → \(startDateString)")
            print("[RESCHEDULE_PROJECT]   - End: \(endDate) → \(endDateString)")

            try await apiService.updateCalendarEvent(
                id: event.id,
                updates: [
                    "startDate": startDateString,
                    "endDate": endDateString
                ]
            )
            print("[RESCHEDULE_PROJECT] ✅ Calendar event updated in Bubble")
        }
    }

    // We're removing the ability to update profile images for now
    // Instead we'll rely on the API to provide profile images
    
    /// Gets a project by ID without triggering sync (internal use)
    private func getProjectWithoutSync(id: String) -> Project? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == id }
            )
            let projects = try context.fetch(descriptor)
            return projects.first
        } catch {
            print("[DataController] Error fetching project \(id): \(error)")
            return nil
        }
    }
    
    /// Gets the count of all projects for the current user's company
    func getProjectCount() async -> Int {
        guard let context = modelContext,
              let companyId = currentUser?.companyId else {
            return 0
        }

        do {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.companyId == companyId && $0.deletedAt == nil }
            )
            let projects = try context.fetch(descriptor)
            return projects.count
        } catch {
            print("[DataController] Error fetching project count: \(error)")
            return 0
        }
    }

    /// Gets a project by ID
    func getProject(id: String) -> Project? {
        guard let context = modelContext else {
            return nil
        }

        // Always fetch fresh from context to avoid invalidated models
        do {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == id }
            )
            let projects = try context.fetch(descriptor)

            if let project = projects.first {
                // Don't pass the model to a background task - use the ID instead
                let projectId = project.id
                Task { @MainActor in
                    // Fetch fresh project in the task to avoid invalidation
                    if let freshProject = self.getProjectWithoutSync(id: projectId) {
                        await self.syncProjectTeamMembers(freshProject)
                    }
                }
                return project
            }
            return nil
        } catch {
            print("[DataController] Error fetching project \(id): \(error)")
            return nil
        }
    }
    
    func getCalendarEvent(id: String) -> CalendarEvent? {
        guard let context = modelContext else { return nil }
        
        // Always fetch fresh from context to avoid invalidated models
        do {
            let descriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate<CalendarEvent> { $0.id == id }
            )
            let events = try context.fetch(descriptor)
            
            if let event = events.first {
                return event
            }
            return nil
        } catch {
            print("[DataController] Error fetching calendar event \(id): \(error)")
            return nil
        }
    }
    
    // MARK: - Diagnostic Functions
    
    /// Diagnostic function to search for specific project and analyze calendar event issues
    func diagnoseRailingsVinylProject() {
        
        guard let context = modelContext else {
            return
        }
        
        do {
            // Search for projects with "Railings" in the title
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            let railingsProjects = allProjects.filter { $0.title.lowercased().contains("railings") }
            
            
            for (index, project) in railingsProjects.enumerated() {
                
                // Check for tasks
                let tasks = project.tasks
                
                for (taskIndex, task) in tasks.enumerated() {
                    if let calendarEvent = task.calendarEvent {
                    }
                }
                
                // Search for associated calendar events
                let projectId = project.id
                let calendarEventDescriptor = FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate<CalendarEvent> { $0.projectId == projectId }
                )
                let projectCalendarEvents = try context.fetch(calendarEventDescriptor)
                
                for (eventIndex, event) in projectCalendarEvents.enumerated() {
                    
                    // Check spanned dates for Aug 17 and Aug 19
                    let spannedDates = event.spannedDates
                    let calendar = Calendar.current
                    
                    let aug17_2025 = calendar.date(from: DateComponents(year: 2025, month: 8, day: 17))!
                    let aug19_2025 = calendar.date(from: DateComponents(year: 2025, month: 8, day: 19))!
                    
                    let coversAug17 = spannedDates.contains { calendar.isDate($0, inSameDayAs: aug17_2025) }
                    let coversAug19 = spannedDates.contains { calendar.isDate($0, inSameDayAs: aug19_2025) }
                    
                }
            }
            
            // Also search for tasks with "Railings" in project title
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
            let railingsTasks = allTasks.filter { task in
                if let project = task.project {
                    return project.title.lowercased().contains("railings")
                }
                return false
            }
            
            
            for (index, task) in railingsTasks.enumerated() {
                if let calendarEvent = task.calendarEvent {
                }
            }
            
            // Check for calendar events on specific dates
            let calendar = Calendar.current
            let aug17_2025 = calendar.date(from: DateComponents(year: 2025, month: 8, day: 17))!
            let aug19_2025 = calendar.date(from: DateComponents(year: 2025, month: 8, day: 19))!
            
            for date in [aug17_2025, aug19_2025] {
                let eventsForDate = getCalendarEventsForCurrentUser(for: date)
                
                for event in eventsForDate {
                    if event.title.lowercased().contains("railings") {
                    }
                }
            }
            
        } catch {
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
            return nil
        }
    }
    
    /// Gets all employees for a company
    func getAllCompanyEmployees(companyId: String) -> [User]? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.companyId == companyId },
                sortBy: [SortDescriptor(\.firstName), SortDescriptor(\.lastName)]
            )
            let users = try context.fetch(descriptor)
            return users
        } catch {
            print("[DataController] Failed to fetch company employees: \(error)")
            return nil
        }
    }
    
    // MARK: - OPS Contacts Management
    
    /// Fetch OPS Contacts option set from Bubble
    @MainActor
    private func fetchOpsContacts() async {
        do {
            
            // Fetch from Bubble API
            let endpoint = "obj/opscontacts"  // Option sets are usually at obj/[option_set_name]
            let response: OpsContactsResponse = try await apiService.executeRequest(
                endpoint: endpoint,
                method: "GET"
            )
            
            guard let context = modelContext else {
                return
            }
            
            // Clear existing OPS Contacts
            let descriptor = FetchDescriptor<OpsContact>()
            let existingContacts = try context.fetch(descriptor)
            for contact in existingContacts {
                context.delete(contact)
            }
            
            // Save new contacts
            for dto in response.response.results {
                let contact = dto.toOpsContact()
                context.insert(contact)
            }
            
            try context.save()
            
        } catch {
            // Non-critical error - don't block login
        }
    }
    
    /// Get an OPS Contact by role
    func getOpsContact(for role: OpsContactRole) -> OpsContact? {
        guard let context = modelContext else { return nil }
        
        let roleString = role.rawValue
        
        do {
            let descriptor = FetchDescriptor<OpsContact>(
                predicate: #Predicate<OpsContact> { contact in
                    contact.role == roleString || contact.display == roleString
                }
            )
            let contacts = try context.fetch(descriptor)
            return contacts.first
        } catch {
            return nil
        }
    }
    
    /// Get the priority support contact if user has priority support
    func getPrioritySupportContact() -> OpsContact? {
        guard let company = getCurrentUserCompany(),
              company.hasPrioritySupport else {
            return nil
        }
        return getOpsContact(for: .prioritySupport)
    }
    
    /// Get general support contact
    func getGeneralSupportContact() -> OpsContact? {
        return getOpsContact(for: .generalSupport)
    }

    // MARK: - Sync Management

    /// Check for pending syncs and update published properties
    @MainActor
    func checkPendingSyncs() async {
        guard let context = modelContext else {
            hasPendingSyncs = false
            pendingSyncCount = 0
            stopPendingSyncRetryTimer()
            return
        }

        var count = 0

        // Count pending projects
        do {
            let projectDescriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.needsSync == true }
            )
            count += try context.fetchCount(projectDescriptor)
        } catch {
            print("[SYNC] ⚠️ Failed to count pending projects: \(error)")
        }

        // Count pending tasks
        do {
            let taskDescriptor = FetchDescriptor<ProjectTask>(
                predicate: #Predicate<ProjectTask> { $0.needsSync == true }
            )
            count += try context.fetchCount(taskDescriptor)
        } catch {
            print("[SYNC] ⚠️ Failed to count pending tasks: \(error)")
        }

        // Count pending calendar events
        do {
            let eventDescriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate<CalendarEvent> { $0.needsSync == true }
            )
            count += try context.fetchCount(eventDescriptor)
        } catch {
            print("[SYNC] ⚠️ Failed to count pending events: \(error)")
        }

        // Count pending users
        do {
            let userDescriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.needsSync == true }
            )
            count += try context.fetchCount(userDescriptor)
        } catch {
            print("[SYNC] ⚠️ Failed to count pending users: \(error)")
        }

        pendingSyncCount = count
        hasPendingSyncs = count > 0

        if count > 0 {
            print("[SYNC] 📊 Found \(count) items pending sync")
            // Start retry timer if we have pending syncs
            startPendingSyncRetryTimer()
        } else {
            // Stop retry timer if no pending syncs
            stopPendingSyncRetryTimer()
        }
    }

    /// Start the periodic retry timer for pending syncs
    @MainActor
    private func startPendingSyncRetryTimer() {
        // Don't create multiple timers
        guard pendingSyncRetryTimer == nil else { return }

        print("[SYNC] ⏱️ Starting periodic sync retry timer (every \(Int(syncRetryInterval/60)) minutes)")

        pendingSyncRetryTimer = Timer.scheduledTimer(withTimeInterval: syncRetryInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                if self.hasPendingSyncs && self.isConnected && self.isAuthenticated {
                    print("[SYNC] ⏱️ Retry timer triggered - attempting to sync \(self.pendingSyncCount) pending items")
                    self.syncManager?.triggerBackgroundSync()
                } else if !self.hasPendingSyncs {
                    // Stop timer if no pending syncs
                    self.stopPendingSyncRetryTimer()
                }
            }
        }
    }

    /// Stop the periodic retry timer
    @MainActor
    private func stopPendingSyncRetryTimer() {
        if pendingSyncRetryTimer != nil {
            print("[SYNC] ⏱️ Stopping periodic sync retry timer")
            pendingSyncRetryTimer?.invalidate()
            pendingSyncRetryTimer = nil
        }
    }

    deinit {
        pendingSyncRetryTimer?.invalidate()
    }

    /// Trigger an immediate sync attempt if connected
    @MainActor
    func triggerImmediateSyncIfConnected() {
        Task {
            await checkPendingSyncs()
        }

        guard isConnected, isAuthenticated else {
            print("[SYNC] ⚠️ Cannot sync - not connected or not authenticated")
            print("[SYNC] 📊 Items will sync when connection is restored")
            return
        }

        print("[SYNC] 🚀 Item added to queue - triggering immediate sync attempt...")
        syncManager?.triggerBackgroundSync()
    }

    /// Mark an item for sync and immediately attempt to sync if connected
    /// This is a helper function to ensure consistent behavior across the app
    @MainActor
    func markForSyncAndAttemptImmediate<T: PersistentModel>(_ item: T) where T: AnyObject {
        // Note: The item should already have needsSync = true before calling this
        // This function just triggers the sync attempt

        Task {
            await checkPendingSyncs()
        }

        // Immediately attempt sync if connected
        if isConnected && isAuthenticated {
            print("[SYNC] 🚀 Item marked for sync - attempting immediate sync...")
            syncManager?.triggerBackgroundSync()
        } else {
            print("[SYNC] ⚠️ Item marked for sync - will sync when connection is restored")
        }
    }

    // MARK: - Task Status Updates

    // MARK: - Generic Sync Wrapper

    /// Generic wrapper for any operation that needs triple-layer sync
    /// This centralizes the immediate sync logic for ALL operations, not just task status
    /// Uses triple-layer sync approach:
    ///   1. Immediate sync if connected (this function)
    ///   2. Event-driven on network change
    ///   3. Periodic 3-minute retry timer
    /// - Parameters:
    ///   - item: The item being updated (must have needsSync and lastSyncedAt properties)
    ///   - operationName: Name for logging (e.g., "UPDATE_TASK_STATUS", "UPDATE_PROJECT", etc.)
    ///   - itemDescription: Brief description of the item (e.g., "task abc123 to Completed")
    ///   - localUpdate: Closure that performs the local database update
    ///   - syncToAPI: Closure that syncs to Bubble API (called only if connected)
    @MainActor
    func performSyncedOperation<T>(
        item: T,
        operationName: String,
        itemDescription: String,
        localUpdate: () throws -> Void,
        syncToAPI: () async throws -> Void
    ) async throws where T: AnyObject {
        print("[\(operationName)] 🔵 \(itemDescription)")
        print("[\(operationName)] 📊 Current state - Connected: \(isConnected), Authenticated: \(isAuthenticated)")

        // Perform local update FIRST - user sees immediate feedback
        try localUpdate()
        try? modelContext?.save()
        print("[\(operationName)] ✅ Updated locally and marked for sync")

        // Update pending sync count
        await checkPendingSyncs()

        // LAYER 1: Immediate sync attempt with 5-second retry window
        if isConnected && isAuthenticated {
            let maxRetryDuration: TimeInterval = 5.0  // Try for 5 seconds total
            let retryInterval: UInt64 = 1_000_000_000 // 1 second between retries
            let startTime = Date()
            var lastError: Error?
            var attemptCount = 0

            while Date().timeIntervalSince(startTime) < maxRetryDuration {
                attemptCount += 1
                do {
                    print("[\(operationName)] 🚀 [LAYER 1] Sync attempt \(attemptCount)...")
                    try await syncToAPI()

                    // syncToAPI closure is responsible for marking item as synced
                    try? modelContext?.save()
                    print("[\(operationName)] ✅ [LAYER 1] Sync successful on attempt \(attemptCount)")

                    await checkPendingSyncs()
                    return  // Success - exit function
                } catch {
                    lastError = error
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("[\(operationName)] ⚠️ [LAYER 1] Attempt \(attemptCount) failed after \(String(format: "%.1f", elapsed))s: \(error.localizedDescription)")

                    // If we still have time, wait before retrying
                    if Date().timeIntervalSince(startTime) + 1.0 < maxRetryDuration {
                        try? await Task.sleep(nanoseconds: retryInterval)
                    }
                }
            }

            // After 5 seconds of retrying, fall back to background sync
            print("[\(operationName)] ⏱️ [LAYER 1] 5-second retry window exhausted after \(attemptCount) attempts")
            print("[\(operationName)] 🔄 [LAYER 2] Queueing for background sync")
            print("[\(operationName)] 📴 Last error: \(lastError?.localizedDescription ?? "unknown")")

            // Trigger background sync to handle this later
            syncManager?.triggerBackgroundSync()

            // DON'T throw - the operation succeeded locally and will sync in background
            // This ensures the user isn't blocked by network issues
        } else {
            if !isConnected {
                print("[\(operationName)] 📴 [LAYER 1] SKIPPED - No connection")
            } else if !isAuthenticated {
                print("[\(operationName)] 🔒 [LAYER 1] SKIPPED - Not authenticated")
            }
            print("[\(operationName)] 🔄 [LAYER 2] Will sync when connection is restored")
            print("[\(operationName)] 📊 Total pending syncs: \(pendingSyncCount)")

            // Trigger background sync
            syncManager?.triggerBackgroundSync()
        }
    }

    /// Update a task's status - SINGLE SOURCE OF TRUTH for task status updates
    /// This function ensures we only update the task's status field and NEVER manipulate project.tasks
    /// Also handles automatic project status updates based on task status changes:
    /// - If project is "accepted" and task is set to "inProgress" → project becomes "inProgress"
    /// - If project is "completed" and task changes from "completed" to "inProgress" or "booked" → project becomes "inProgress"
    /// - Parameters:
    ///   - task: The task to update
    ///   - newStatus: The new status to set
    @MainActor
    func updateTaskStatus(task: ProjectTask, to newStatus: TaskStatus) async throws {
        let oldStatus = task.status
        let project = task.project

        try await performSyncedOperation(
            item: task,
            operationName: "UPDATE_TASK_STATUS",
            itemDescription: "Updating task \(task.id) to status: \(newStatus.rawValue)",
            localUpdate: {
                task.status = newStatus
                task.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateTaskStatus(id: task.id, status: newStatus.rawValue)
                task.needsSync = false
                task.lastSyncedAt = Date()
            }
        )

        // Track task status change for analytics
        AnalyticsManager.shared.trackTaskStatusChanged(
            oldStatus: oldStatus.rawValue,
            newStatus: newStatus.rawValue
        )

        // Track task completion as high-value event
        if newStatus == .completed {
            AnalyticsManager.shared.trackTaskCompleted(taskType: task.taskType?.display)

            // Send task completion notification to all project team members
            if let project = project, OneSignalService.shared.isConfigured {
                let projectTeamMemberIds = project.teamMembers.map { $0.id }
                if !projectTeamMemberIds.isEmpty {
                    let taskName = task.displayTitle
                    let projectName = project.title
                    let completedByName = currentUser?.fullName

                    Task {
                        do {
                            try await OneSignalService.shared.notifyTaskCompletion(
                                userIds: projectTeamMemberIds,
                                taskName: taskName,
                                projectName: projectName,
                                taskId: task.id,
                                projectId: project.id,
                                completedByName: completedByName
                            )
                        } catch {
                            print("[TASK_STATUS] ⚠️ Failed to send task completion notification: \(error)")
                        }
                    }
                    print("[TASK_STATUS] 📬 Task completion notification queued for \(projectTeamMemberIds.count) project team members")
                }
            }
        }

        // Check if we need to update project status based on task status change
        if let project = project {
            await updateProjectStatusBasedOnTaskChange(
                project: project,
                taskOldStatus: oldStatus,
                taskNewStatus: newStatus
            )
        }
    }

    /// Updates project status based on task status changes
    /// - If project is "accepted" and a task is set to "inProgress" → project becomes "inProgress"
    /// - If project is "completed" and a task changes from "completed" to "inProgress" or "booked" → project becomes "inProgress"
    @MainActor
    private func updateProjectStatusBasedOnTaskChange(
        project: Project,
        taskOldStatus: TaskStatus,
        taskNewStatus: TaskStatus
    ) async {
        var shouldUpdateToInProgress = false

        // Case 1: Project is "accepted" and task is set to "active"
        if project.status == .accepted && taskNewStatus == .active {
            shouldUpdateToInProgress = true
            print("[PROJECT_STATUS] Project '\(project.title)' is accepted and task set to active - updating project to inProgress")
        }

        // Case 2: Project is "completed" and task changed from "completed" to "active"
        if project.status == .completed &&
           taskOldStatus == .completed &&
           taskNewStatus == .active {
            shouldUpdateToInProgress = true
            print("[PROJECT_STATUS] Project '\(project.title)' is completed but task changed to \(taskNewStatus.rawValue) - updating project to inProgress")
        }

        // Case 3: Project is "rfq" or "estimated" and task is set to "active"
        if (project.status == .rfq || project.status == .estimated) && taskNewStatus == .active {
            shouldUpdateToInProgress = true
            print("[PROJECT_STATUS] Project '\(project.title)' is \(project.status.rawValue) and task set to active - updating project to inProgress")
        }

        if shouldUpdateToInProgress {
            do {
                try await updateProjectStatus(project: project, to: .inProgress)
                print("[PROJECT_STATUS] ✅ Project '\(project.title)' status updated to inProgress")
            } catch {
                print("[PROJECT_STATUS] ❌ Failed to update project status: \(error)")
            }
        }
    }

    /// Updates project status when a NEW task is added
    /// - If project is "completed" or "closed" and a non-completed/non-cancelled task is added → project becomes "inProgress"
    /// - If project is "rfq" or "estimated" and task is "active" → project becomes "inProgress"
    @MainActor
    func updateProjectStatusForNewTask(project: Project, taskStatus: TaskStatus) async {
        var shouldUpdateToInProgress = false

        // Case 1: Project is "completed" or "closed" and new task is not completed/cancelled
        if (project.status == .completed || project.status == .closed) &&
           (taskStatus != .completed && taskStatus != .cancelled) {
            shouldUpdateToInProgress = true
            print("[PROJECT_STATUS] Project '\(project.title)' is \(project.status.rawValue) but new task added with status \(taskStatus.rawValue) - updating project to inProgress")
        }

        // Case 2: Project is "rfq" or "estimated" and new task is "active"
        if (project.status == .rfq || project.status == .estimated) && taskStatus == .active {
            shouldUpdateToInProgress = true
            print("[PROJECT_STATUS] Project '\(project.title)' is \(project.status.rawValue) and new task is active - updating project to inProgress")
        }

        if shouldUpdateToInProgress {
            do {
                try await updateProjectStatus(project: project, to: .inProgress)
                print("[PROJECT_STATUS] ✅ Project '\(project.title)' status updated to inProgress")
            } catch {
                print("[PROJECT_STATUS] ❌ Failed to update project status: \(error)")
            }
        }
    }

    /// Update a project's status - SINGLE SOURCE OF TRUTH for project status updates
    /// - Parameters:
    ///   - project: The project to update
    ///   - newStatus: The new status to set
    @MainActor
    func updateProjectStatus(project: Project, to newStatus: Status) async throws {
        // Capture previous status to detect completion
        let previousStatus = project.status

        try await performSyncedOperation(
            item: project,
            operationName: "UPDATE_PROJECT_STATUS",
            itemDescription: "Updating project \(project.id) to status: \(newStatus.rawValue)",
            localUpdate: {
                project.status = newStatus
                project.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateProjectStatus(id: project.id, status: newStatus.rawValue)
                project.needsSync = false
                project.lastSyncedAt = Date()
            }
        )

        // Track project status change for analytics
        AnalyticsManager.shared.trackProjectStatusChanged(
            oldStatus: previousStatus.rawValue,
            newStatus: newStatus.rawValue
        )

        // Send push notification if project was just marked as completed
        if newStatus == .completed && previousStatus != .completed {
            let teamMemberIds = project.getTeamMemberIds()
            if !teamMemberIds.isEmpty, OneSignalService.shared.isConfigured {
                Task {
                    do {
                        try await OneSignalService.shared.notifyProjectCompletion(
                            userIds: teamMemberIds,
                            projectName: project.title,
                            projectId: project.id
                        )
                    } catch {
                        print("[NOTIFICATIONS] Failed to send project completion notification: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Calendar Event Operations

    /// Update calendar event dates - SINGLE SOURCE OF TRUTH for calendar event updates
    @MainActor
    func updateCalendarEvent(event: CalendarEvent, startDate: Date, endDate: Date) async throws {
        // Store task/project references before async operation
        let task = event.task
        let project = task?.project

        // Capture previous dates to detect actual changes
        let previousStartDate = event.startDate
        let previousEndDate = event.endDate

        try await performSyncedOperation(
            item: event,
            operationName: "UPDATE_CALENDAR_EVENT",
            itemDescription: "Updating calendar event \(event.id)",
            localUpdate: {
                event.startDate = startDate
                event.endDate = endDate
                let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                event.duration = daysDiff + 1
                event.needsSync = true
            },
            syncToAPI: {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]

                let updates: [String: Any] = [
                    BubbleFields.CalendarEvent.startDate: formatter.string(from: startDate),
                    BubbleFields.CalendarEvent.endDate: formatter.string(from: endDate),
                    BubbleFields.CalendarEvent.duration: event.duration
                ]

                try await self.apiService.updateCalendarEvent(id: event.id, updates: updates)
                event.needsSync = false
                event.lastSyncedAt = Date()
            }
        )

        // Send schedule change notification if dates actually changed
        let datesChanged = previousStartDate != startDate || previousEndDate != endDate
        if datesChanged, let task = task, let project = project, OneSignalService.shared.isConfigured {
            let teamMemberIds = task.getTeamMemberIds()
            if !teamMemberIds.isEmpty {
                Task {
                    do {
                        try await OneSignalService.shared.notifyScheduleChange(
                            userIds: teamMemberIds,
                            taskName: task.displayTitle,
                            projectName: project.title,
                            taskId: task.id,
                            projectId: project.id
                        )
                    } catch {
                        print("[NOTIFICATIONS] Failed to send schedule change notification: \(error)")
                    }
                }
            }
        }

        // Recalculate task indices if this event is linked to a task
        // This runs regardless of whether calendar sync succeeded
        if let project = project {
            do {
                try await recalculateTaskIndices(for: project)
            } catch {
                print("[UPDATE_CALENDAR_EVENT] ⚠️ Failed to recalculate task indices: \(error)")
            }
        }

        // Notify calendar views to refresh
        await MainActor.run {
            calendarEventsDidChange.toggle()
        }
    }

    // MARK: - Task Index Operations

    /// Recalculate and update taskIndex for all tasks in a project
    /// Tasks are ordered by startDate (earliest = 0), with unscheduled tasks at the end
    @MainActor
    func recalculateTaskIndices(for project: Project) async throws {
        print("[TASK_INDEX] 🔢 Recalculating task indices for project: \(project.title)")

        let allTasks = project.tasks

        // Separate scheduled and unscheduled tasks
        var scheduledTasks: [(task: ProjectTask, startDate: Date)] = []
        var unscheduledTasks: [ProjectTask] = []

        for task in allTasks {
            if let calendarEvent = task.calendarEvent,
               let startDate = calendarEvent.startDate {
                scheduledTasks.append((task: task, startDate: startDate))
            } else {
                unscheduledTasks.append(task)
            }
        }

        // Sort scheduled tasks by startDate (earliest first)
        scheduledTasks.sort { $0.startDate < $1.startDate }

        // Assign indices: scheduled tasks first (0, 1, 2...), then unscheduled
        var currentIndex = 0
        var tasksToSync: [(task: ProjectTask, index: Int)] = []

        // Update scheduled tasks
        for (task, _) in scheduledTasks {
            if task.taskIndex != currentIndex {
                print("[TASK_INDEX]   - Task '\(task.displayTitle)': \(task.taskIndex ?? -1) → \(currentIndex)")
                task.taskIndex = currentIndex
                task.needsSync = true
                tasksToSync.append((task: task, index: currentIndex))
            }
            currentIndex += 1
        }

        // Update unscheduled tasks
        for task in unscheduledTasks {
            if task.taskIndex != currentIndex {
                print("[TASK_INDEX]   - Task '\(task.displayTitle)' (unscheduled): \(task.taskIndex ?? -1) → \(currentIndex)")
                task.taskIndex = currentIndex
                task.needsSync = true
                tasksToSync.append((task: task, index: currentIndex))
            }
            currentIndex += 1
        }

        print("[TASK_INDEX] ✅ Updated \(allTasks.count) task indices")

        // Save changes locally
        try modelContext?.save()

        // Sync taskIndex to Bubble for all changed tasks
        if !tasksToSync.isEmpty {
            print("[TASK_INDEX] 🔄 Syncing \(tasksToSync.count) task indices to Bubble...")
            for (task, index) in tasksToSync {
                do {
                    let updates: [String: Any] = [BubbleFields.Task.taskIndex: index]
                    try await apiService.updateTask(id: task.id, updates: updates)
                    task.needsSync = false
                    task.lastSyncedAt = Date()
                    print("[TASK_INDEX]   ✅ Synced taskIndex=\(index) for task '\(task.displayTitle)'")
                } catch {
                    print("[TASK_INDEX]   ⚠️ Failed to sync taskIndex for task '\(task.displayTitle)': \(error)")
                    // Keep needsSync = true for background sync to retry
                }
            }
            try modelContext?.save()
            print("[TASK_INDEX] ✅ Bubble sync complete")
        }
    }

    // MARK: - Team Member Operations

    /// Update task team members - SINGLE SOURCE OF TRUTH
    /// This is the ONLY method that should be used to update task team members.
    /// It handles:
    /// 1. Updating task.teamMemberIdsString
    /// 2. Updating task.teamMembers relationship array
    /// 3. Updating task's calendar event team members (both string and relationship)
    /// 4. Syncing task team members to Bubble API
    /// 5. Syncing calendar event team members to Bubble API
    /// 6. Updating project team members to reflect changes
    /// 7. Sending push notifications to newly assigned members
    @MainActor
    func updateTaskTeamMembers(task: ProjectTask, memberIds: [String]) async throws {
        print("[UPDATE_TASK_TEAM] 🔄 Starting comprehensive task team update...")
        print("[UPDATE_TASK_TEAM] Task ID: \(task.id)")
        print("[UPDATE_TASK_TEAM] New member IDs: \(memberIds)")

        // Capture previous team members before update to detect new assignments
        let previousMemberIds = Set(task.getTeamMemberIds())
        let newMemberIds = Set(memberIds)
        let addedMemberIds = newMemberIds.subtracting(previousMemberIds)

        print("[UPDATE_TASK_TEAM] Previous members: \(previousMemberIds.count), New members: \(newMemberIds.count), Added: \(addedMemberIds.count)")

        // Fetch User objects for the team member IDs
        let teamMemberUsers = fetchUsersById(Array(newMemberIds))
        print("[UPDATE_TASK_TEAM] Fetched \(teamMemberUsers.count) User objects from database")

        try await performSyncedOperation(
            item: task,
            operationName: "UPDATE_TASK_TEAM",
            itemDescription: "Updating task \(task.id) team members",
            localUpdate: {
                // Update task team member IDs string
                task.setTeamMemberIds(memberIds)
                // Update task team members relationship array
                task.teamMembers = teamMemberUsers
                task.needsSync = true
                print("[UPDATE_TASK_TEAM] ✅ Task local state updated (IDs string + relationship)")
            },
            syncToAPI: {
                try await self.apiService.updateTaskTeamMembers(id: task.id, teamMemberIds: memberIds)
                task.needsSync = false
                task.lastSyncedAt = Date()
                print("[UPDATE_TASK_TEAM] ✅ Task team synced to Bubble API")
            }
        )

        // Update calendar event team members if task has one
        if let calendarEvent = task.calendarEvent {
            print("[UPDATE_TASK_TEAM] 🔄 Updating associated calendar event team members...")
            try await updateCalendarEventTeamMembersComprehensive(
                event: calendarEvent,
                memberIds: memberIds,
                memberUsers: teamMemberUsers
            )
            print("[UPDATE_TASK_TEAM] ✅ Calendar event team members updated")
        } else {
            print("[UPDATE_TASK_TEAM] ℹ️ Task has no calendar event to update")
        }

        // Send push notifications to newly added team members
        if !addedMemberIds.isEmpty, OneSignalService.shared.isConfigured {
            let taskName = task.displayTitle
            let projectName = task.project?.title ?? "Project"

            for userId in addedMemberIds {
                Task {
                    do {
                        try await OneSignalService.shared.notifyTaskAssignment(
                            userId: userId,
                            taskName: taskName,
                            projectName: projectName,
                            taskId: task.id,
                            projectId: task.project?.id ?? ""
                        )
                    } catch {
                        print("[NOTIFICATIONS] Failed to send task assignment notification: \(error)")
                    }
                }
            }
        }

        // After updating task team members, sync project team members
        // Project team members should be the union of all task team members
        if let project = task.project {
            await syncProjectTeamMembersFromTasks(project)
        }

        print("[UPDATE_TASK_TEAM] ✅ Comprehensive task team update complete")
    }

    /// Fetch User objects by their IDs from the local database
    @MainActor
    private func fetchUsersById(_ userIds: [String]) -> [User] {
        guard let context = modelContext, !userIds.isEmpty else { return [] }

        do {
            let predicate = #Predicate<User> { user in
                userIds.contains(user.id)
            }
            let descriptor = FetchDescriptor<User>(predicate: predicate)
            let users = try context.fetch(descriptor)
            return users
        } catch {
            print("[FETCH_USERS] ❌ Error fetching users by ID: \(error)")
            return []
        }
    }

    /// Update calendar event team members comprehensively (both string and relationship)
    @MainActor
    private func updateCalendarEventTeamMembersComprehensive(
        event: CalendarEvent,
        memberIds: [String],
        memberUsers: [User]
    ) async throws {
        try await performSyncedOperation(
            item: event,
            operationName: "UPDATE_EVENT_TEAM",
            itemDescription: "Updating calendar event \(event.id) team members",
            localUpdate: {
                // Update calendar event team member IDs string
                event.setTeamMemberIds(memberIds)
                // Update calendar event team members relationship array
                event.teamMembers = memberUsers
                event.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateCalendarEventTeamMembers(id: event.id, teamMemberIds: memberIds)
                event.needsSync = false
                event.lastSyncedAt = Date()
            }
        )
    }

    /// Syncs project team members based on all its tasks
    /// Project team should include anyone assigned to any task
    @MainActor
    private func syncProjectTeamMembersFromTasks(_ project: Project) async {
        print("[TEAM_SYNC] 🔄 Syncing project team members from tasks for project: \(project.title)")

        // Collect all unique team member IDs from all tasks
        var allTeamMemberIds = Set<String>()

        for task in project.tasks where task.deletedAt == nil {
            let taskTeamIds = task.getTeamMemberIds()
            allTeamMemberIds.formUnion(taskTeamIds)
        }

        let projectTeamIds = Set(project.getTeamMemberIds())
        let finalTeamIds = Array(allTeamMemberIds)

        // Only update if the team members have changed
        if projectTeamIds != allTeamMemberIds {
            print("[TEAM_SYNC] 📝 Project team members changed:")
            print("[TEAM_SYNC]   - Before: \(projectTeamIds.count) members")
            print("[TEAM_SYNC]   - After: \(finalTeamIds.count) members")

            do {
                try await updateProjectTeamMembers(project: project, memberIds: finalTeamIds)
                print("[TEAM_SYNC] ✅ Project team members updated successfully")
            } catch {
                print("[TEAM_SYNC] ❌ Failed to update project team members: \(error)")
            }
        } else {
            print("[TEAM_SYNC] ℹ️ Project team members unchanged, no update needed")
        }
    }

    /// Update project team members - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateProjectTeamMembers(project: Project, memberIds: [String]) async throws {
        try await performSyncedOperation(
            item: project,
            operationName: "UPDATE_PROJECT_TEAM",
            itemDescription: "Updating project \(project.id) team members",
            localUpdate: {
                project.setTeamMemberIds(memberIds)
                project.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateProjectTeamMembers(projectId: project.id, teamMemberIds: memberIds)
                project.needsSync = false
                project.lastSyncedAt = Date()
            }
        )
    }

    /// Update calendar event team members - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateCalendarEventTeamMembers(event: CalendarEvent, memberIds: [String]) async throws {
        try await performSyncedOperation(
            item: event,
            operationName: "UPDATE_EVENT_TEAM",
            itemDescription: "Updating calendar event \(event.id) team members",
            localUpdate: {
                event.setTeamMemberIds(memberIds)
                event.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateCalendarEventTeamMembers(id: event.id, teamMemberIds: memberIds)
                event.needsSync = false
                event.lastSyncedAt = Date()
            }
        )
    }

    // MARK: - Client Operations

    /// Update client - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateClient(client: Client) async throws {
        try await performSyncedOperation(
            item: client,
            operationName: "UPDATE_CLIENT",
            itemDescription: "Updating client \(client.id)",
            localUpdate: {
                client.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateClient(
                    id: client.id,
                    name: client.name,
                    email: client.email,
                    phone: client.phoneNumber,
                    address: client.address
                )
                client.needsSync = false
                client.lastSyncedAt = Date()
            }
        )
    }

    // MARK: - Project Details Operations

    /// Update project notes - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateProjectNotes(project: Project, notes: String) async throws {
        try await performSyncedOperation(
            item: project,
            operationName: "UPDATE_PROJECT_NOTES",
            itemDescription: "Updating project \(project.id) notes",
            localUpdate: {
                project.notes = notes
                project.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateProjectNotes(id: project.id, notes: notes)
                project.needsSync = false
                project.lastSyncedAt = Date()
            }
        )
    }

    /// Update project dates - SINGLE SOURCE OF TRUTH
    /// Supports both setting dates (when non-nil) and clearing dates (when nil)
    @MainActor
    func updateProjectDates(project: Project, startDate: Date?, endDate: Date?, clearDates: Bool = false) async throws {
        try await performSyncedOperation(
            item: project,
            operationName: "UPDATE_PROJECT_DATES",
            itemDescription: startDate == nil ? "Clearing project \(project.id) dates" : "Updating project \(project.id) dates",
            localUpdate: {
                project.startDate = startDate
                project.endDate = endDate
                project.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateProjectDates(
                    projectId: project.id,
                    startDate: startDate,
                    endDate: endDate,
                    clearDates: clearDates || (startDate == nil && endDate == nil)
                )
                project.needsSync = false
                project.lastSyncedAt = Date()
            }
        )
    }

    /// Update project address - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateProjectAddress(project: Project, address: String) async throws {
        try await performSyncedOperation(
            item: project,
            operationName: "UPDATE_PROJECT_ADDRESS",
            itemDescription: "Updating project \(project.id) address",
            localUpdate: {
                project.address = address
                project.needsSync = true
            },
            syncToAPI: {
                try await self.apiService.updateProject(id: project.id, updates: ["address": address])
                project.needsSync = false
                project.lastSyncedAt = Date()
            }
        )
    }

    // MARK: - Task Operations

    /// Create task - SINGLE SOURCE OF TRUTH
    @MainActor
    func createTask(task: ProjectTask) async throws {
        try await performSyncedOperation(
            item: task,
            operationName: "CREATE_TASK",
            itemDescription: "Creating task for project \(task.projectId)",
            localUpdate: {
                self.modelContext?.insert(task)
                task.needsSync = true
            },
            syncToAPI: {
                let dto = TaskDTO.from(task)
                _ = try await self.apiService.createTask(dto)
                task.needsSync = false
                task.lastSyncedAt = Date()
            }
        )
    }

    /// Update task - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateTask(task: ProjectTask) async throws {
        try await performSyncedOperation(
            item: task,
            operationName: "UPDATE_TASK",
            itemDescription: "Updating task \(task.id)",
            localUpdate: {
                task.needsSync = true
            },
            syncToAPI: {
                // Convert task properties to update dictionary
                var updates: [String: Any] = [:]
                if let notes = task.taskNotes {
                    updates[BubbleFields.Task.taskNotes] = notes
                }
                updates[BubbleFields.Task.teamMembers] = task.getTeamMemberIds()
                updates[BubbleFields.Task.status] = task.status.rawValue

                try await self.apiService.updateTask(id: task.id, updates: updates)
                task.needsSync = false
                task.lastSyncedAt = Date()
            }
        )
    }

    // MARK: - Profile Image Upload

    /// Upload a profile image for a user
    @MainActor
    func uploadUserProfileImage(_ image: UIImage, for user: User) async throws -> String {
        print("[PROFILE_IMAGE] Starting upload for user: \(user.id)")

        guard let companyId = user.companyId else {
            print("[PROFILE_IMAGE] ❌ User has no company")
            throw ImageUploadError.uploadFailed
        }

        // 1. Compress and store locally immediately for instant UI update
        let targetSize = CGSize(width: min(image.size.width, 800), height: min(image.size.height, 800))
        let resizedImage = image.resized(to: targetSize)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            print("[PROFILE_IMAGE] ❌ Failed to compress image")
            throw ImageUploadError.compressionFailed
        }

        print("[PROFILE_IMAGE] Image compressed to \(imageData.count) bytes")

        // Store locally for instant UI
        user.profileImageData = imageData
        try? modelContext?.save()

        // 2. Delete old image from S3 if exists
        if let oldURL = user.profileImageURL, !oldURL.isEmpty {
            print("[PROFILE_IMAGE] Deleting old image from S3")
            do {
                try await S3UploadService.shared.deleteImageFromS3(
                    url: oldURL,
                    companyId: companyId,
                    projectId: user.id  // Using userId as the path segment
                )
                print("[PROFILE_IMAGE] ✅ Old image deleted from S3")
            } catch {
                print("[PROFILE_IMAGE] ⚠️ Failed to delete old image: \(error)")
                // Continue with upload even if delete fails
            }
        }

        // 3. Upload new image to S3
        do {
            let s3URL = try await S3UploadService.shared.uploadProfileImage(
                image,
                userId: user.id,
                companyId: companyId
            )

            print("[PROFILE_IMAGE] ✅ Uploaded to S3: \(s3URL)")

            // 3. Update local model with S3 URL
            user.profileImageURL = s3URL
            try? modelContext?.save()

            // 4. Update Bubble with S3 URL
            try await apiService.updateUser(userId: user.id, fields: [
                BubbleFields.User.avatar: s3URL
            ])

            print("[PROFILE_IMAGE] ✅ Updated Bubble with S3 URL")
            return s3URL

        } catch {
            print("[PROFILE_IMAGE] ⚠️ S3 upload failed: \(error), keeping local copy")
            // Keep the local image data, will retry on next sync
            throw ImageUploadError.uploadFailed
        }
    }

    /// Delete a user's profile image
    @MainActor
    func deleteUserProfileImage(for user: User) async throws {
        print("[PROFILE_IMAGE] Deleting profile image for user: \(user.id)")

        // Clear local data
        user.profileImageURL = nil
        user.profileImageData = nil
        try? modelContext?.save()

        // Clear from Bubble
        do {
            try await apiService.updateUser(userId: user.id, fields: [
                BubbleFields.User.avatar: ""
            ])
            print("[PROFILE_IMAGE] ✅ Profile image deleted from Bubble")
        } catch {
            print("[PROFILE_IMAGE] ⚠️ Failed to delete from Bubble: \(error)")
            // Local deletion succeeded, Bubble update will retry on next sync
        }

        print("[PROFILE_IMAGE] ✅ Profile image deleted")
    }

    /// Upload a logo for a company
    @MainActor
    func uploadCompanyLogo(_ image: UIImage, for company: Company) async throws -> String {
        print("[COMPANY_LOGO] Starting upload for company: \(company.id)")

        // 1. Compress and store locally immediately for instant UI update
        let targetSize = CGSize(width: min(image.size.width, 1000), height: min(image.size.height, 1000))
        let resizedImage = image.resized(to: targetSize)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.85) else {
            print("[COMPANY_LOGO] ❌ Failed to compress image")
            throw ImageUploadError.compressionFailed
        }

        print("[COMPANY_LOGO] Image compressed to \(imageData.count) bytes")

        // Store locally for instant UI
        company.logoData = imageData
        try? modelContext?.save()

        // 2. Delete old logo from S3 if exists
        if let oldURL = company.logoURL, !oldURL.isEmpty {
            print("[COMPANY_LOGO] Deleting old logo from S3")
            do {
                try await S3UploadService.shared.deleteImageFromS3(
                    url: oldURL,
                    companyId: company.id,
                    projectId: company.id  // Not used for S3 URLs, but required for signature
                )
                print("[COMPANY_LOGO] ✅ Old logo deleted from S3")
            } catch {
                print("[COMPANY_LOGO] ⚠️ Failed to delete old logo: \(error)")
                // Continue with upload even if delete fails
            }
        }

        // 3. Upload new logo to S3
        do {
            let s3URL = try await S3UploadService.shared.uploadCompanyLogo(
                image,
                companyId: company.id
            )

            print("[COMPANY_LOGO] ✅ Uploaded to S3: \(s3URL)")

            // 3. Update local model with S3 URL
            company.logoURL = s3URL
            try? modelContext?.save()

            // 4. Update Bubble with S3 URL
            try await apiService.updateCompanyFields(companyId: company.id, fields: [
                BubbleFields.Company.logo: s3URL
            ])

            print("[COMPANY_LOGO] ✅ Updated Bubble with S3 URL")
            return s3URL

        } catch {
            print("[COMPANY_LOGO] ⚠️ S3 upload failed: \(error), keeping local copy")
            // Keep the local image data, will retry on next sync
            throw ImageUploadError.uploadFailed
        }
    }

    /// Delete a company's logo
    @MainActor
    func deleteCompanyLogo(for company: Company) async throws {
        print("[COMPANY_LOGO] Deleting logo for company: \(company.id)")

        // Clear local data
        company.logoURL = nil
        company.logoData = nil
        try? modelContext?.save()

        // Clear from Bubble
        do {
            try await apiService.updateCompanyFields(companyId: company.id, fields: [
                BubbleFields.Company.logo: ""
            ])
            print("[COMPANY_LOGO] ✅ Logo deleted from Bubble")
        } catch {
            print("[COMPANY_LOGO] ⚠️ Failed to delete from Bubble: \(error)")
            // Local deletion succeeded, Bubble update will retry on next sync
        }

        print("[COMPANY_LOGO] ✅ Company logo deleted")
    }

    // MARK: - Company Default Project Color

    /// Update the company's default project color in both local database and Bubble API
    func updateCompanyDefaultProjectColor(companyId: String, color: String) async throws {
        print("[COMPANY_COLOR] Updating default project color to: \(color)")

        // Update in Bubble API
        do {
            try await apiService.updateCompanyFields(companyId: companyId, fields: [
                BubbleFields.Company.defaultProjectColor: color
            ])
            print("[COMPANY_COLOR] ✅ Default project color updated in Bubble")
        } catch {
            print("[COMPANY_COLOR] ⚠️ Failed to update in Bubble: \(error)")
            throw error
        }

        print("[COMPANY_COLOR] ✅ Default project color updated successfully")
    }

    // MARK: - Unassigned Employee Roles Check

    /// Check if there are company users without an assigned employeeType
    /// Returns array of UnassignedUser objects for users needing role assignment
    /// Only returns results for admin/office crew users
    @MainActor
    func checkForUnassignedEmployeeRoles() async -> [UnassignedUser] {
        // Only check for admin or office crew
        guard let user = currentUser,
              user.role == .admin || user.role == .officeCrew else {
            print("[UNASSIGNED_ROLES] Skipping check - user is not admin/office crew")
            return []
        }

        // Check if user dismissed recently (give them 24 hours before showing again)
        if let dismissedAt = UserDefaults.standard.object(forKey: "unassigned_roles_dismissed_at") as? Date {
            if Date().timeIntervalSince(dismissedAt) < 24 * 60 * 60 {
                print("[UNASSIGNED_ROLES] Skipping - dismissed recently")
                return []
            }
        }

        // Get company ID
        guard let companyId = user.companyId, !companyId.isEmpty else {
            print("[UNASSIGNED_ROLES] Skipping - no company ID")
            return []
        }

        do {
            print("[UNASSIGNED_ROLES] Fetching company users for company: \(companyId)")
            let companyUsers = try await apiService.fetchCompanyUsers(companyId: companyId)

            // Filter for users with nil employeeType (excluding current user)
            let unassignedDTOs = companyUsers.filter { dto in
                dto.employeeType == nil && dto.id != user.id
            }

            print("[UNASSIGNED_ROLES] Found \(unassignedDTOs.count) users without employeeType")

            // Convert to UnassignedUser objects
            let unassignedUsers = unassignedDTOs.map { dto in
                UnassignedUser(
                    id: dto.id,
                    firstName: dto.nameFirst ?? "",
                    lastName: dto.nameLast ?? "",
                    email: dto.email ?? dto.authentication?.email?.email
                )
            }

            return unassignedUsers

        } catch {
            print("[UNASSIGNED_ROLES] Error fetching company users: \(error)")
            return []
        }
    }
}

// MARK: - Image Upload Errors

enum ImageUploadError: LocalizedError {
    case compressionFailed
    case invalidURL
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "Failed to compress image"
        case .invalidURL: return "Invalid upload URL"
        case .uploadFailed: return "Upload failed"
        }
    }
}
