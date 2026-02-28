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
import Supabase

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
    @Published var scheduledTasksDidChange = false // Toggle to refresh calendar views
    private var hasCompletedInitialConnectionCheck = false // Track if we've done initial setup

    // Global app state for external views to access
    var appState: AppState?
    
    // MARK: - Dependencies
    let authManager: AuthManager
    private let keychainManager: KeychainManager
    private let connectivityMonitor: ConnectivityMonitor
    var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // Periodic sync retry timer
    private var pendingSyncRetryTimer: Timer?
    private let syncRetryInterval: TimeInterval = 180 // 3 minutes

    // MARK: - Public Access
    var syncManager: SupabaseSyncManager!
    var imageSyncManager: ImageSyncManager!

    /// Convenience accessor for inventory operations via Supabase
    var inventoryRepository: InventoryRepository? {
        guard let companyId = currentUser?.companyId, !companyId.isEmpty else { return nil }
        return InventoryRepository(companyId: companyId)
    }
    @Published var simplePINManager = SimplePINManager()
    
    // MARK: - Initialization
    init() {
        // Create dependencies in a predictable order
        self.keychainManager = KeychainManager()
        self.authManager = AuthManager()
        self.connectivityMonitor = ConnectivityMonitor()

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

        // Initialize the Supabase sync manager
        self.syncManager = SupabaseSyncManager(
            modelContext: modelContext,
            connectivityMonitor: connectivityMonitor
        )

        // Initialize the image sync manager
        self.imageSyncManager = ImageSyncManager(
            modelContext: modelContext,
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

    /// Returns true if the string is a valid UUID format (Supabase uses UUIDs for all IDs)
    private func isValidUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }

    @MainActor
    private func checkExistingAuth() async {

        // MIGRATION: Detect legacy-format IDs and force re-login through Supabase Auth.
        // Legacy IDs look like "1748465773440x642579687246238300", Supabase uses UUIDs.
        // If we detect non-UUID IDs, clear stored credentials so the user re-authenticates
        // via Supabase Auth, which will store proper UUID-format IDs.
        let storedUserId = UserDefaults.standard.string(forKey: "user_id")
        let storedCompanyId = UserDefaults.standard.string(forKey: "company_id")

        let userIdNeedsMigration = storedUserId != nil && !isValidUUID(storedUserId!)
        let companyIdNeedsMigration = storedCompanyId != nil && !isValidUUID(storedCompanyId!)

        if userIdNeedsMigration || companyIdNeedsMigration {
            print("[AUTH_MIGRATION] Detected legacy-format IDs in UserDefaults — forcing re-login")
            if let uid = storedUserId { print("[AUTH_MIGRATION]   user_id: \(uid)") }
            if let cid = storedCompanyId { print("[AUTH_MIGRATION]   company_id: \(cid)") }

            // Clear all stored IDs so the user goes through Supabase Auth login
            clearAuthentication()
            return
        }

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
        
        // Fall back to Supabase session restoration
        do {
            let session = try await SupabaseService.shared.client.auth.session
            let supabaseUserId = session.user.id.uuidString.lowercased()
            let email = session.user.email ?? ""

            // Load user identifiers from Supabase users table
            try? await authManager.loadUserFromSupabase(userId: supabaseUserId, email: email)
            let userId = authManager.getUserId() ?? supabaseUserId

            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId")

            // Try to find user in local SwiftData
            if let context = modelContext {
                let descriptor = FetchDescriptor<User>(
                    predicate: #Predicate<User> { $0.id == userId }
                )
                let users = try context.fetch(descriptor)

                if let user = users.first {
                    self.currentUser = user

                    NotificationManager.shared.linkUserToOneSignal()
                    Task { await OneSignalService.shared.configure() }

                    if user.hasCompletedAppOnboarding {
                        self.isAuthenticated = true
                        UserDefaults.standard.set(true, forKey: "onboarding_completed")
                    }

                    if let companyId = user.companyId {
                        UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                        UserDefaults.standard.set(companyId, forKey: "company_id")
                    }

                    initializeSyncManager()
                    return
                }
            }

            // No local user — try to fetch from API if connected
            if isConnected {
                try await fetchUserFromAPI(userId: userId)
            } else {
                let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
                self.isAuthenticated = onboardingCompleted
            }
        } catch {
            // No valid Supabase session — clear auth
            clearAuthentication()
        }
        
    }
    
    @discardableResult
    @MainActor
    func login(username: String, password: String) async -> Bool {
        
        do {
            // Sign in via Supabase Auth (handles session, stores userId + companyId)
            try await authManager.loginWithEmail(username, password: password)
            
            
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
            // Authenticate with Supabase using Apple identity token
            try await SupabaseService.shared.signInWithApple(identityToken: appleResult.identityToken)

            // Get session info from Supabase
            let session = try await SupabaseService.shared.client.auth.session
            let supabaseUserId = session.user.id.uuidString.lowercased()
            let email = session.user.email ?? appleResult.email ?? ""

            // Store Apple user identifier for future logins
            UserDefaults.standard.set(appleResult.userIdentifier, forKey: "apple_user_identifier")

            // Look up existing user in Supabase users table by email
            try await authManager.loadUserFromSupabase(userId: supabaseUserId, email: email)

            // Use the user ID from users table (may differ from auth UUID for migrated users)
            let userId = authManager.getUserId() ?? supabaseUserId

            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId")

            // Try to fetch full user data - may fail for brand new users
            do {
                try await fetchUserFromAPI(userId: userId)
            } catch {
                print("[AUTH] User not found in users table — likely a new user, will need onboarding")
            }

            // Check onboarding status
            if let user = currentUser {
                let hasCompany = !(user.companyId ?? "").isEmpty
                let hasCompletedAppOnboarding = user.hasCompletedAppOnboarding
                let hasUserType = user.userType != nil

                // Determine if onboarding is needed (indicates new user)
                let needsOnboarding = !hasCompany || !hasCompletedAppOnboarding || !hasUserType

                // Store user type if available
                if let userTypeString = user.userType?.rawValue {
                    if userTypeString.lowercased() == "company" {
                        UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
                    } else if userTypeString.lowercased() == "employee" {
                        UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
                    }
                    UserDefaults.standard.set(userTypeString, forKey: "user_type_raw")
                }

                // Track analytics (Apple sign-in)
                if needsOnboarding {
                    AnalyticsManager.shared.trackSignUp(userType: user.userType, method: .apple)
                } else {
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .apple)
                }
                AnalyticsManager.shared.setUserType(user.userType)
                AnalyticsManager.shared.setUserId(userId)

                UserDefaults.standard.set(!needsOnboarding, forKey: "onboarding_completed")

                if !needsOnboarding {
                    self.isAuthenticated = true
                }

                return true
            }

            // No user found — new user, needs onboarding
            UserDefaults.standard.set(false, forKey: "onboarding_completed")
            return true
        } catch {
            print("[AUTH] Apple login failed: \(error)")
            return false
        }
    }

    /// Google login
    @MainActor
    func loginWithGoogle(googleUser: GIDGoogleUser) async -> Bool {
        guard let idToken = googleUser.idToken?.tokenString,
              let email = googleUser.profile?.email else {
            return false
        }

        do {
            // Authenticate with Supabase using Google ID token
            try await SupabaseService.shared.signInWithGoogle(idToken: idToken)

            // Get session info from Supabase
            let session = try await SupabaseService.shared.client.auth.session
            let supabaseUserId = session.user.id.uuidString.lowercased()

            // Look up existing user in Supabase users table by email
            try await authManager.loadUserFromSupabase(userId: supabaseUserId, email: email)

            // Use the user ID from users table (may differ from auth UUID for migrated users)
            let userId = authManager.getUserId() ?? supabaseUserId

            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId")

            // Try to fetch full user data - may fail for brand new users
            do {
                try await fetchUserFromAPI(userId: userId)
            } catch {
                print("[AUTH] User not found in users table — likely a new user, will need onboarding")
            }

            // Check onboarding status
            if let user = currentUser {
                let hasCompany = !(user.companyId ?? "").isEmpty
                let hasCompletedAppOnboarding = user.hasCompletedAppOnboarding

                // Determine if onboarding is needed (indicates new user)
                let needsOnboarding = !hasCompany || !hasCompletedAppOnboarding

                // Store user type if available
                if let userTypeString = user.userType?.rawValue {
                    if userTypeString.lowercased() == "company" {
                        UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
                    } else if userTypeString.lowercased() == "employee" {
                        UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
                    }
                    UserDefaults.standard.set(userTypeString, forKey: "user_type_raw")
                }

                // Track analytics (Google sign-in)
                if needsOnboarding {
                    AnalyticsManager.shared.trackSignUp(userType: user.userType, method: .google)
                } else {
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .google)
                }
                AnalyticsManager.shared.setUserType(user.userType)
                AnalyticsManager.shared.setUserId(userId)

                UserDefaults.standard.set(!needsOnboarding, forKey: "onboarding_completed")

                if !needsOnboarding {
                    self.isAuthenticated = true
                }

                return true
            }

            // No user found — new user, needs onboarding
            UserDefaults.standard.set(false, forKey: "onboarding_completed")
            return true
        } catch {
            print("[AUTH] Google login failed: \(error)")
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
        
        // syncManager handles fetch, convert, and upsert
        initializeSyncManager()
        guard let fetchedUser = try await syncManager?.fetchUser(id: userId) else {
            // If syncManager couldn't fetch, try local
            if let existingUser = existingUsers.first {
                self.currentUser = existingUser
            } else {
                throw NSError(domain: "DataController", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user"])
            }
            return
        }

        let user = fetchedUser

        // Update app state with the current user
        self.currentUser = user

        // Store user type in UserDefaults for onboarding flow
        if let userType = user.userType {
            // Map user type strings to our UserType enum
            if userType == .company {
                UserDefaults.standard.set(UserType.company.rawValue, forKey: "selected_user_type")
            } else if userType == .employee {
                UserDefaults.standard.set(UserType.employee.rawValue, forKey: "selected_user_type")
            }
            // Also store the raw value as a backup
            UserDefaults.standard.set(userType.rawValue, forKey: "user_type_raw")
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

        // Sign out from Supabase
        Task { await SupabaseService.shared.signOut() }
        
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
            
            // 1. Delete ProjectTasks (they reference projects)
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
                // syncManager handles fetch, convert, and upsert
                let company = try await syncManager.fetchCompany(id: companyId)

                await MainActor.run {
                    if let company = company {
                        try? context.save()

                        // If team members haven't been synced, or it's been more than a day, sync team members
                        if !company.teamMembersSynced ||
                           company.lastSyncedAt == nil ||
                           Date().timeIntervalSince(company.lastSyncedAt!) > 86400 {

                            // Launch a task to fetch team members
                            Task {
                                await self.syncManager?.syncCompanyTeamMembers(company)
                            }
                        } else {
                        }
                    }
                }
            } else {
            }
        } catch {
            throw error
        }
    }
    
    // Note: updateCompany(from: CompanyDTO) removed - syncManager.fetchCompany handles upsert directly
    
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
                    // User exists - refresh if online
                    if isConnected {
                        do {
                            // syncManager.fetchUser handles fetch, convert, and upsert
                            if let refreshedUser = try await syncManager?.fetchUser(id: memberId) {
                                // Check if user is still part of the company
                                if refreshedUser.companyId == nil || refreshedUser.companyId != existingUser.companyId {
                                    // User is no longer part of the company - remove them
                                    for assignedProject in existingUser.assignedProjects {
                                        assignedProject.teamMembers.removeAll { $0.id == memberId }
                                    }
                                    context.delete(existingUser)
                                    continue
                                }
                            }
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
                    // User doesn't exist locally but we're online - fetch via syncManager
                    do {
                        if let newUser = try await syncManager?.fetchUser(id: memberId) {
                            // Check if user belongs to a company
                            if newUser.companyId == nil {
                                continue // Skip this user
                            }

                            // Create bidirectional relationship (with duplicate check)
                            if !newUser.assignedProjects.contains(where: { $0.id == project.id }) {
                                newUser.assignedProjects.append(project)
                            }
                            if !project.teamMembers.contains(where: { $0.id == newUser.id }) {
                                project.teamMembers.append(newUser)
                            }
                        } else {
                            // User not found - add to non-existent cache
                            syncManager?.addNonExistentUserId(memberId)
                            continue
                        }
                    } catch {
                        // Create placeholder for network errors
                        let placeholderUser = User(
                            id: memberId,
                            firstName: "Team Member",
                            lastName: "#\(memberId.suffix(4))",
                            role: .fieldCrew,
                            companyId: project.companyId
                        )

                        if !placeholderUser.assignedProjects.contains(where: { $0.id == project.id }) {
                            placeholderUser.assignedProjects.append(project)
                        }
                        if !project.teamMembers.contains(where: { $0.id == placeholderUser.id }) {
                            project.teamMembers.append(placeholderUser)
                        }
                        context.insert(placeholderUser)
                    }
                } else {
                    // Offline and user doesn't exist - create placeholder
                    let placeholderUser = User(
                        id: memberId,
                        firstName: "Team Member",
                        lastName: "#\(memberId.suffix(4))",
                        role: .fieldCrew,
                        companyId: project.companyId
                    )

                    if !placeholderUser.assignedProjects.contains(where: { $0.id == project.id }) {
                        placeholderUser.assignedProjects.append(project)
                    }
                    if !project.teamMembers.contains(where: { $0.id == placeholderUser.id }) {
                        project.teamMembers.append(placeholderUser)
                    }
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
    
    /// Force refresh projects from backend
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
    
    // MARK: - Scheduled Task Methods

    /// Get scheduled tasks that overlap with a date range (optimized for scheduler)
    /// This method is much more efficient than calling getScheduledTasks(for:) in a loop
    func getScheduledTasks(in dateRange: ClosedRange<Date>) -> [ProjectTask] {
        guard let context = modelContext else {
            return []
        }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())

            let filteredTasks = allTasks.filter { task in
                guard task.deletedAt == nil else { return false }
                guard let taskStart = task.startDate else { return false }
                let taskEnd = task.endDate ?? taskStart

                // Task overlaps if it starts before range ends AND ends after range starts
                return taskStart <= dateRange.upperBound && taskEnd >= dateRange.lowerBound
            }

            return filteredTasks.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            print("[SCHEDULE] ❌ Failed to fetch tasks in range: \(error)")
            return []
        }
    }

    /// Get scheduled tasks for a specific date
    func getScheduledTasks(for date: Date) -> [ProjectTask] {
        guard let context = modelContext else {
            return []
        }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())

            let filteredTasks = allTasks.filter { task in
                guard task.deletedAt == nil else { return false }
                guard let taskStart = task.startDate else { return false }
                let taskEnd = task.endDate ?? taskStart
                let calendar = Calendar.current

                // Check if date falls within task's start-to-end range
                return calendar.compare(taskStart, to: date, toGranularity: .day) != .orderedDescending
                    && calendar.compare(taskEnd, to: date, toGranularity: .day) != .orderedAscending
            }

            return filteredTasks.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            return []
        }
    }

    /// Get scheduled tasks for a specific date for the current user
    func getScheduledTasksForCurrentUser(for date: Date) -> [ProjectTask] {
        guard let user = currentUser else { return [] }
        guard let context = modelContext else { return [] }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())

            let filteredTasks = allTasks.filter { task in
                guard task.deletedAt == nil else { return false }
                guard let taskStart = task.startDate else { return false }
                let taskEnd = task.endDate ?? taskStart
                let calendar = Calendar.current

                // Check if date falls within task's start-to-end range
                let isActiveOnDate = calendar.compare(taskStart, to: date, toGranularity: .day) != .orderedDescending
                    && calendar.compare(taskEnd, to: date, toGranularity: .day) != .orderedAscending

                if !isActiveOnDate {
                    return false
                }

                // For Admin and Office Crew, show all company tasks
                if user.role == .admin || user.role == .officeCrew {
                    return task.companyId == user.companyId
                } else {
                    // For Field Crew, only show tasks they're assigned to
                    let taskTeamMemberIds = task.getTeamMemberIds()
                    let isAssigned = taskTeamMemberIds.contains(user.id)
                        || task.teamMembers.contains(where: { $0.id == user.id })

                    if !isAssigned {
                        // Also check project assignment
                        if let project = task.project {
                            let projectTeamMemberIds = project.getTeamMemberIds()
                            return projectTeamMemberIds.contains(user.id)
                                || project.teamMembers.contains(where: { $0.id == user.id })
                        }
                        return false
                    }
                    return true
                }
            }

            return filteredTasks.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            return []
        }
    }

    /// Get all scheduled tasks from a given start date, filtered by current user access
    func getAllScheduledTasks(from startDate: Date) -> [ProjectTask] {
        guard let user = currentUser else { return [] }
        guard let context = modelContext else { return [] }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())

            let filteredTasks = allTasks.filter { task in
                guard let taskStartDate = task.startDate else { return false }
                if taskStartDate < startDate { return false }

                if user.role == .admin || user.role == .officeCrew {
                    return task.companyId == user.companyId
                } else {
                    let taskTeamMemberIds = task.getTeamMemberIds()
                    let isAssigned = taskTeamMemberIds.contains(user.id)
                        || task.teamMembers.contains(where: { $0.id == user.id })

                    if !isAssigned {
                        if let project = task.project {
                            let projectTeamMemberIds = project.getTeamMemberIds()
                            return projectTeamMemberIds.contains(user.id)
                                || project.teamMembers.contains(where: { $0.id == user.id })
                        }
                        return false
                    }
                    return true
                }
            }

            return filteredTasks.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
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
        
        // Online and needing refresh: sync projects then read from local
        do {
            try await syncManager?.syncProjects()

            if let localProject = try context.fetch(descriptor).first {
                await syncProjectTeamMembers(localProject)
                return localProject
            }

            throw NSError(domain: "DataController", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Project not found after sync"])
        } catch {
            // On sync error, fall back to local if available
            if let localProject = try context.fetch(descriptor).first {
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
        
        // Trigger a sync to get fresh data, then use local SwiftData
        do {
            try await syncManager?.syncProjects()
        } catch {
            // Non-fatal - we still have local data
        }

        // Re-fetch from local after sync
        let refreshedProjects = getProjects(for: today, assignedTo: user ?? currentUser)

        // Sync team member relationships for each project
        for project in refreshedProjects {
            await syncProjectTeamMembers(project)
        }

        return refreshedProjects
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
        // Task status options now come from the TaskStatus enum, not from the API
        // This method is a no-op but kept for compatibility
        print("[DataController] Task status options are now derived from TaskStatus enum")
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
        guard isConnected, isAuthenticated else {
            if !isConnected {
                throw NSError(domain: "DataController", code: 100,
                             userInfo: [NSLocalizedDescriptionKey: "No internet connection"])
            }
            throw NSError(domain: "DataController", code: 101,
                         userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        // syncManager handles fetch, convert, and upsert
        let _ = try await syncManager.fetchCompany(id: id)
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
            
            return companies.first
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
    
    /// Request a password reset email via Supabase Auth
    /// - Parameter email: The user's email address
    /// - Returns: Tuple with success flag and optional error message
    func requestPasswordReset(email: String) async -> (Bool, String?) {
        do {
            try await authManager.resetPassword(email: email)
            return (true, nil)
        } catch {
            return (false, "Failed to request password reset. Please try again.")
        }
    }
    
    /// Delete the current user's account
    /// - Parameter userId: The ID of the user to delete
    /// - Returns: Success boolean
    @MainActor
    func deleteUserAccount(userId: String) async -> Bool {
        do {
            // Call the sync manager to delete the user account
            try await syncManager.deleteUser(userId: userId)

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

        // Trigger background sync to push changes to server
        syncManager?.triggerBackgroundSync()
    }

    /// Delete a task from both Supabase and local storage
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
        let project = task.project

        // STEP 1: Delete task from Supabase
        try await syncManager.deleteTask(taskId: taskId)

        // STEP 3: Delete from local SwiftData
        modelContext.delete(task)
        try modelContext.save()

        // STEP 4: Update project dates (automatically computed from remaining tasks)
        if updateProject, let project = project {
            try modelContext.save()

            // Sync updated computed dates to Supabase
            try await syncManager.updateProjectDates(
                projectId: project.id,
                startDate: project.computedStartDate,
                endDate: project.computedEndDate
            )
        }
    }

    /// Delete a client from both server and local storage
    /// - Parameter client: The client to delete
    /// - Throws: API or database errors
    /// - Note: Caller is responsible for handling associated projects (reassignment or deletion)
    @MainActor
    func deleteClient(_ client: Client) async throws {
        guard let modelContext = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        // STEP 1: Delete client from Supabase
        try await syncManager.deleteClient(clientId: client.id)

        // STEP 2: Delete client from local SwiftData
        modelContext.delete(client)
        try modelContext.save()
    }

    /// Reschedule a project to new dates
    /// - Parameters:
    ///   - project: The project to reschedule
    ///   - startDate: New start date
    ///   - endDate: New end date
    /// - Throws: API or database errors
    @MainActor
    func rescheduleProject(_ project: Project, startDate: Date, endDate: Date) async throws {
        guard let modelContext = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        print("[RESCHEDULE_PROJECT] 📅 Rescheduling project: \(project.title)")
        print("[RESCHEDULE_PROJECT] Old dates: \(project.startDate?.description ?? "nil") - \(project.endDate?.description ?? "nil")")
        print("[RESCHEDULE_PROJECT] New dates: \(startDate.description) - \(endDate.description)")

        // STEP 1: Update project dates
        project.startDate = startDate
        project.endDate = endDate
        project.needsSync = true

        // STEP 2: Save locally
        try modelContext.save()
        print("[RESCHEDULE_PROJECT] ✅ Changes saved locally")

        // STEP 3: Update dates in Supabase
        try await syncManager.updateProjectDates(
            projectId: project.id,
            startDate: startDate,
            endDate: endDate
        )
        print("[RESCHEDULE_PROJECT] ✅ Project dates updated in Supabase")
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
    
    /// Gets a user by ID
    func getTask(id: String) -> ProjectTask? {
        guard let context = modelContext else { return nil }

        do {
            let descriptor = FetchDescriptor<ProjectTask>(
                predicate: #Predicate<ProjectTask> { $0.id == id }
            )
            let tasks = try context.fetch(descriptor)
            return tasks.first
        } catch {
            return nil
        }
    }

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
    
    /// Fetch OPS Contacts
    /// TODO: Implement OPS Contacts fetch from Supabase when the table is set up
    @MainActor
    private func fetchOpsContacts() async {
        // OpsContacts fetched from Supabase
        // This is a non-critical feature - contacts will be populated when Supabase table is ready
        print("[OPS_CONTACTS] Skipping fetch - Supabase migration pending")
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
    ///   - syncToAPI: Closure that syncs to server (called only if connected)
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
                try await self.syncManager.updateTaskStatus(taskId: task.id, status: newStatus)
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
            if let project = project {
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
            print("[PROJECT_STATUS] Project '\(project.title)' is accepted and task set to \(taskNewStatus.rawValue) - updating project to inProgress")
        }

        // Case 2: Project is "completed" and task changed from "completed" to non-terminal
        if project.status == .completed &&
           taskOldStatus == .completed &&
           taskNewStatus == .active {
            shouldUpdateToInProgress = true
            print("[PROJECT_STATUS] Project '\(project.title)' is completed but task changed to \(taskNewStatus.rawValue) - updating project to inProgress")
        }

        // Case 3: Project is "rfq" or "estimated" and task is set to "active"
        if (project.status == .rfq || project.status == .estimated) && taskNewStatus == .active {
            shouldUpdateToInProgress = true
            print("[PROJECT_STATUS] Project '\(project.title)' is \(project.status.rawValue) and task set to \(taskNewStatus.rawValue) - updating project to inProgress")
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
            print("[PROJECT_STATUS] Project '\(project.title)' is \(project.status.rawValue) and new task is \(taskStatus.rawValue) - updating project to inProgress")
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
                try await self.syncManager.updateProjectStatus(projectId: project.id, status: newStatus)
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
            if !teamMemberIds.isEmpty {
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

    // MARK: - Task Schedule Operations

    /// Update task schedule dates - SINGLE SOURCE OF TRUTH for task scheduling updates
    @MainActor
    func updateTaskSchedule(task: ProjectTask, startDate: Date, endDate: Date) async throws {
        let project = task.project

        // Capture previous dates to detect actual changes
        let previousStartDate = task.startDate
        let previousEndDate = task.endDate

        try await performSyncedOperation(
            item: task,
            operationName: "UPDATE_TASK_SCHEDULE",
            itemDescription: "Updating task \(task.id) schedule",
            localUpdate: {
                task.startDate = startDate
                task.endDate = endDate
                let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                task.duration = daysDiff + 1
                task.needsSync = true
            },
            syncToAPI: {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]

                let fields: [String: AnyJSON] = [
                    "start_date": .string(formatter.string(from: startDate)),
                    "end_date": .string(formatter.string(from: endDate)),
                    "duration": .integer(task.duration)
                ]

                try await self.syncManager.updateTaskFields(taskId: task.id, fields: fields)
                task.needsSync = false
                task.lastSyncedAt = Date()
            }
        )

        // Send schedule change notification if dates actually changed
        let datesChanged = previousStartDate != startDate || previousEndDate != endDate
        if datesChanged, let project = project {
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

        // Recalculate task indices
        if let project = project {
            do {
                try await recalculateTaskIndices(for: project)
            } catch {
                print("[UPDATE_TASK_SCHEDULE] ⚠️ Failed to recalculate task indices: \(error)")
            }
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
            if let startDate = task.startDate {
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

        // Sync taskIndex to Supabase for all changed tasks
        if !tasksToSync.isEmpty {
            print("[TASK_INDEX] 🔄 Syncing \(tasksToSync.count) task indices to Supabase...")
            for (task, index) in tasksToSync {
                do {
                    let fields: [String: AnyJSON] = ["task_index": .integer(index)]
                    try await syncManager.updateTaskFields(taskId: task.id, fields: fields)
                    task.needsSync = false
                    task.lastSyncedAt = Date()
                    print("[TASK_INDEX]   ✅ Synced taskIndex=\(index) for task '\(task.displayTitle)'")
                } catch {
                    print("[TASK_INDEX]   ⚠️ Failed to sync taskIndex for task '\(task.displayTitle)': \(error)")
                    // Keep needsSync = true for background sync to retry
                }
            }
            try modelContext?.save()
            print("[TASK_INDEX] ✅ Supabase sync complete")
        }
    }

    // MARK: - Team Member Operations

    /// Update task team members - SINGLE SOURCE OF TRUTH
    /// This is the ONLY method that should be used to update task team members.
    /// It handles:
    /// 1. Updating task.teamMemberIdsString
    /// 2. Updating task.teamMembers relationship array
    /// 3. Syncing task team members to Supabase
    /// 4. Updating project team members to reflect changes
    /// 5. Sending push notifications to newly assigned members
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
                try await self.syncManager.updateTaskTeamMembers(taskId: task.id, memberIds: memberIds)
                task.needsSync = false
                task.lastSyncedAt = Date()
                print("[UPDATE_TASK_TEAM] ✅ Task team synced to Supabase")
            }
        )

        // Send push notifications to newly added team members
        if !addedMemberIds.isEmpty {
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
                try await self.syncManager.updateProjectTeamMembers(projectId: project.id, memberIds: memberIds)
                project.needsSync = false
                project.lastSyncedAt = Date()
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
                try await self.syncManager.updateClient(
                    clientId: client.id,
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
                try await self.syncManager.updateProjectNotes(projectId: project.id, notes: notes)
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
                try await self.syncManager.updateProjectDates(
                    projectId: project.id,
                    startDate: startDate,
                    endDate: endDate
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
                try await self.syncManager.updateProjectAddress(projectId: project.id, address: address)
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
                // TODO: Convert ProjectTask to SupabaseProjectTaskDTO for creation
                // For now, trigger background sync which will pick up the needsSync flag
                self.syncManager?.triggerBackgroundSync()
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
                var fields: [String: AnyJSON] = [:]
                if let notes = task.taskNotes {
                    fields["task_notes"] = .string(notes)
                }
                fields["status"] = .string(task.status.rawValue)

                try await self.syncManager.updateTaskFields(taskId: task.id, fields: fields)

                // Also update team members separately
                try await self.syncManager.updateTaskTeamMembers(taskId: task.id, memberIds: task.getTeamMemberIds())

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

            // 4. Update Supabase with S3 URL
            try await syncManager.updateUserFields(userId: user.id, fields: [
                "profile_image_url": .string(s3URL)
            ])

            print("[PROFILE_IMAGE] ✅ Updated Supabase with S3 URL")
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

        // Clear from Supabase
        do {
            try await syncManager.updateUserFields(userId: user.id, fields: [
                "profile_image_url": .string("")
            ])
            print("[PROFILE_IMAGE] ✅ Profile image deleted from Supabase")
        } catch {
            print("[PROFILE_IMAGE] ⚠️ Failed to delete from Supabase: \(error)")
            // Local deletion succeeded, Supabase update will retry on next sync
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

            // 4. Update Supabase with S3 URL
            try await syncManager.updateCompanyFields(companyId: company.id, fields: [
                "logo_url": s3URL
            ])

            print("[COMPANY_LOGO] ✅ Updated Supabase with S3 URL")
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

        // Clear from Supabase
        do {
            try await syncManager.updateCompanyFields(companyId: company.id, fields: [
                "logo_url": ""
            ])
            print("[COMPANY_LOGO] ✅ Logo deleted from Supabase")
        } catch {
            print("[COMPANY_LOGO] ⚠️ Failed to delete from Supabase: \(error)")
            // Local deletion succeeded, Supabase update will retry on next sync
        }

        print("[COMPANY_LOGO] ✅ Company logo deleted")
    }

    // MARK: - Company Default Project Color

    /// Update the company's default project color in both local database and server
    func updateCompanyDefaultProjectColor(companyId: String, color: String) async throws {
        print("[COMPANY_COLOR] Updating default project color to: \(color)")

        // Update in Supabase
        do {
            try await syncManager.updateCompanyFields(companyId: companyId, fields: [
                "default_project_color": color
            ])
            print("[COMPANY_COLOR] ✅ Default project color updated in Supabase")
        } catch {
            print("[COMPANY_COLOR] ⚠️ Failed to update in Supabase: \(error)")
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
            print("[UNASSIGNED_ROLES] Syncing company users for company: \(companyId)")
            // Sync users from Supabase first
            try await syncManager.syncUsers()

            // Read from local SwiftData
            guard let context = modelContext else { return [] }

            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.companyId == companyId }
            )
            let companyUsers = try context.fetch(descriptor)

            // Filter for users with default role (no assigned employee type) excluding current user
            let unassignedLocalUsers = companyUsers.filter { localUser in
                localUser.role == .fieldCrew && localUser.id != user.id
            }

            print("[UNASSIGNED_ROLES] Found \(unassignedLocalUsers.count) users without assigned role")

            // Convert to UnassignedUser objects
            let unassignedUsers = unassignedLocalUsers.map { localUser in
                UnassignedUser(
                    id: localUser.id,
                    firstName: localUser.firstName,
                    lastName: localUser.lastName,
                    email: localUser.email
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
