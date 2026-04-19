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
import Network
import CoreLocation
import GoogleSignIn
import Supabase
import FirebaseAuth
import FirebaseCrashlytics

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
    @Published var connectionType: NWInterface.InterfaceType? = nil
    @Published var lastSyncTime: Date?

    // Sync status tracking
    @Published var hasPendingSyncs = false
    @Published var pendingSyncCount = 0
    @Published var showSyncRestoredAlert = false
    @Published var isPerformingInitialSync = false // Track post-login initial sync
    @Published var syncStatusMessage = "" // Console-style sync status messages
    @Published var scheduledTasksDidChange = false // Toggle to refresh calendar views
    private var hasCompletedInitialConnectionCheck = false // Track if we've done initial setup
    private var lastSyncRestoredAlertTime: Date? // Cooldown to prevent repeated banners

    // Global app state for external views to access
    var appState: AppState?

    /// Permission store reference — set from OPSApp on launch
    var permissionStore: PermissionStore?
    
    // MARK: - Dependencies
    let authManager: AuthManager
    private let keychainManager: KeychainManager
    var modelContext: ModelContext?

    /// Background SwiftData actor — owns all sync/cleanup/background writes.
    /// Created once in setModelContext. Gated behind FeatureFlags.useDataActor.
    private(set) var dataActor: DataActor?

    /// Bridges DataActor.didSave → main context @Query refresh.
    /// Created alongside dataActor; published for views to observe.
    @Published private(set) var refreshBridge: MainContextRefreshBridge?

    private var cancellables = Set<AnyCancellable>()

    // Cancellable data wipe scheduled during logout — cancelled if re-login starts
    private var pendingDataWipeWork: DispatchWorkItem?

    // MARK: - Public Access
    var imageSyncManager: ImageSyncManager!

    // Cache of non-existent user IDs to prevent repeated fetch attempts
    private var nonExistentUserIds: Set<String> = []

    /// New sync engine (offline-first) — initialized in setModelContext,
    /// configured in initializeSyncManager. Safe to call methods before
    /// configure (they guard on modelContext and return early).
    private(set) var syncEngine: SyncEngine!
    private(set) var connectivity: ConnectivityManager!

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

        // Migrate any images from UserDefaults to FileManager
        // This prevents the "attempting to store >= 4194304 bytes" error
        ImageFileManager.shared.migrateAllImages()

        // Check for existing authentication - plain Task for async work
        Task {
            await checkExistingAuth()
        }
    }
    
    // MARK: - Setup

    /// Called from setModelContext once ConnectivityManager is created.
    @MainActor
    func setupConnectivityMonitoring() {
        guard let connectivity = connectivity else { return }

        // Mirror initial state
        isConnected = connectivity.isConnected
        connectionType = connectivity.state.type

        print("[SYNC] 📱 Initial connection state: \(isConnected ? "Connected" : "Disconnected")")

        // Check for pending syncs on startup
        Task { @MainActor in
            await checkPendingSyncs()

            // If we have pending syncs AND we're connected, trigger immediate sync
            // (no alert — this is initial load, not a reconnection)
            if hasPendingSyncs && isConnected && isAuthenticated {
                print("[SYNC] 🚀 App startup with \(pendingSyncCount) pending items - triggering sync")
                await syncEngine.triggerSync()
            }

            // Mark that we've completed initial setup
            hasCompletedInitialConnectionCheck = true
        }

        // Handle connection changes from ConnectivityManager
        connectivity.onStateChanged = { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasDisconnected = !self.isConnected
                self.isConnected = newState.status != .offline
                self.connectionType = newState.type

                print("[SYNC] 🔌 Network state changed: \(self.isConnected ? "Connected" : "Disconnected")")

                if newState.status != .offline, self.isAuthenticated {
                    // Check if we have pending syncs before triggering sync
                    await self.checkPendingSyncs()

                    // ONLY show alert if:
                    // 1. We've completed initial setup (not first load)
                    // 2. We were actually disconnected before
                    // 3. We have pending syncs
                    // 4. At least 60s since last alert (prevent rapid flashing)
                    let cooldownElapsed = self.lastSyncRestoredAlertTime == nil ||
                        Date().timeIntervalSince(self.lastSyncRestoredAlertTime!) > 60
                    if self.hasCompletedInitialConnectionCheck && wasDisconnected && self.hasPendingSyncs && cooldownElapsed {
                        print("[SYNC] 🔄 Connection restored with \(self.pendingSyncCount) pending items - showing alert")
                        self.showSyncRestoredAlert = true
                        self.lastSyncRestoredAlertTime = Date()
                    } else {
                        print("[SYNC] 🔄 Connection active - triggering background sync (no alert)")
                    }

                    // Trigger sync via SyncEngine
                    await self.syncEngine.triggerSync()
                }
            }
        }
    }
    
    @MainActor
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context

        // Create sync engine and connectivity eagerly so they're never nil.
        // configure() is called later in initializeSyncManager() once auth is verified.
        if self.syncEngine == nil {
            self.syncEngine = SyncEngine()
        }
        if self.connectivity == nil {
            self.connectivity = ConnectivityManager()
            // Wire up connectivity state changes now that the manager exists
            setupConnectivityMonitoring()
        }

        // Create the DataActor + refresh bridge SYNCHRONOUSLY (flag-gated).
        //
        // Must happen before any other code path can race to sync. Specifically:
        //   - DataController.fetchUserFromAPI calls initializeSyncManager at
        //     line 843 during auth check — configure() must see a non-nil
        //     self.dataActor.
        //   - ConnectivityManager.onStateChanged callbacks can trigger a sync
        //     immediately upon connectivity restore; SyncEngine.dataActor
        //     must be bound before that happens.
        //
        // The @ModelActor-synthesized init runs synchronously; only configure()
        // is async. Actor methods are FIFO-serialized, so scheduling configure()
        // first guarantees it runs before any queued cleanup/sync method.
        if FeatureFlags.useDataActor && self.dataActor == nil {
            let actor = DataActor(modelContainer: context.container)

            let bridge = MainContextRefreshBridge(
                mainContext: context,
                listeningTo: .dataActorDidSave
            )

            self.dataActor = actor
            self.refreshBridge = bridge

            // Bind the actor to SyncEngine synchronously so the first sync
            // trigger (network reconnect, auth completion) sees the actor path.
            self.syncEngine.setDataActor(actor)

            // configure() sets autosave off and installs the didSave → main
            // rebroadcast observer. Runs async on the actor's executor; any
            // subsequent actor method queues behind it.
            Task { await actor.configure() }

            print("[DATA_CONTROLLER] DataActor created — actor path is active for this session")
        }

        // Cleanup + initializeSyncManager remain in a Task because cleanup is
        // async and we don't want to block setModelContext's caller.
        Task { @MainActor in
            if FeatureFlags.useDataActor, let actor = self.dataActor {
                await actor.cleanupDuplicateUsers()
                await actor.cleanupDuplicateProjects()
                await actor.cleanupDuplicateTasks()
                await actor.cleanupDuplicateClients()
                await actor.cleanupDuplicateTaskTypes()
            } else {
                await cleanupDuplicateUsers()
                await cleanupDuplicateProjects()
                await cleanupDuplicateTasks()
                await cleanupDuplicateClients()
                await cleanupDuplicateTaskTypes()
            }

            if isAuthenticated || currentUser != nil {
                initializeSyncManager()
            }
        }
    }
    
    @MainActor
    func initializeSyncManager() {
        guard let modelContext = modelContext else {
            print("[DATA_CONTROLLER] ⚠️ Cannot initialize sync system - no modelContext")
            return
        }

        // Skip if already configured (syncEngine.isSyncing is observable after configure)
        guard imageSyncManager == nil else {
            print("[DATA_CONTROLLER] Sync system already initialized")
            return
        }

        print("[DATA_CONTROLLER] Initializing sync system...")

        // Initialize the image sync manager
        self.imageSyncManager = ImageSyncManager(
            modelContext: modelContext,
            connectivity: connectivity
        )

        // Configure the sync engine (already created eagerly). Pass dataActor when
        // the feature flag is on and the actor has been created in setModelContext;
        // SyncEngine routes fullSync/pullDelta/pushPending/etc. through the actor.
        syncEngine.configure(
            modelContext: modelContext,
            connectivity: connectivity,
            dataActor: self.dataActor
        )
        syncEngine.registerBackgroundTasks()

        // Immediately check for pending images after initialization
        if isConnected {
            Task {
                await imageSyncManager?.syncPendingImages()
            }
        }

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
        print("[APP_LAUNCH_SYNC] - syncEngine: available")

        Task {
            // Always trigger full sync on app launch if authenticated
            if isConnected && isAuthenticated {
                print("[APP_LAUNCH_SYNC] ✅ Triggering FULL SYNC via SyncEngine")
                await syncEngine.fullSync()
                print("[APP_LAUNCH_SYNC] ✅ Full sync completed")

                // Then process pending photo uploads
                await syncEngine.processPhotoUploads()
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

                        // Fetch permissions (will use cache if offline)
                        Task {
                            await self.permissionStore?.fetchPermissions(userId: user.id)
                        }

                        // Link user to OneSignal for push notifications
                        NotificationManager.shared.linkUserToOneSignal()

                        // Configure OneSignal service for sending notifications
                        Task {
                            await OneSignalService.shared.configure()
                        }

                        // Fetch and cache notification preferences from Supabase
                        NotificationManager.shared.refreshCachedPreferences()

                        // Initialize sync system and reconfigure with confirmed companyId
                        initializeSyncManager()
                        syncEngine.reconfigureForCompany()
                        return
                    }
                } catch {
                }
            }

            // Even without a user object, maintain authentication
            return
        }
        
        // Fall back to Firebase session restoration
        FirebaseAuthService.shared.restoreSession()

        guard FirebaseAuthService.shared.isAuthenticated,
              let email = FirebaseAuthService.shared.currentUserEmail else {
            // No valid Firebase session — clear auth
            clearAuthentication()
            return
        }

        do {
            // Load user identifiers from Supabase users table via email
            let firebaseUID = FirebaseAuthService.shared.firebaseUID ?? ""
            try? await authManager.loadUserFromSupabase(userId: firebaseUID, email: email)
            let userId = authManager.getUserId() ?? firebaseUID

            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId")

            // Backfill firebase_uid in users table
            Task { await authManager.backfillFirebaseUID(usersTableId: userId) }

            // Try to find user in local SwiftData
            if let context = modelContext {
                let descriptor = FetchDescriptor<User>(
                    predicate: #Predicate<User> { $0.id == userId }
                )
                let users = try context.fetch(descriptor)

                if let user = users.first {
                    self.currentUser = user

                    // Fetch permissions (will use cache if offline)
                    Task {
                        await self.permissionStore?.fetchPermissions(userId: user.id)
                    }

                    NotificationManager.shared.linkUserToOneSignal()
                    Task { await OneSignalService.shared.configure() }
                    NotificationManager.shared.refreshCachedPreferences()

                    let localHasCompany = !(user.companyId ?? "").isEmpty
                    if user.hasCompletedAppOnboarding || localHasCompany {
                        self.isAuthenticated = true
                        UserDefaults.standard.set(true, forKey: "onboarding_completed")
                    }

                    if let companyId = user.companyId {
                        UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                        UserDefaults.standard.set(companyId, forKey: "company_id")

                        // Cache identity fields for analytics
                        let companyDescriptor = FetchDescriptor<Company>(
                            predicate: #Predicate<Company> { $0.id == companyId }
                        )
                        if let company = try? context.fetch(companyDescriptor).first {
                            UserDefaults.standard.set(company.subscriptionPlan, forKey: "subscription_plan")
                        }
                    }
                    UserDefaults.standard.set(user.role.rawValue, forKey: "user_role")

                    initializeSyncManager()
                    syncEngine.reconfigureForCompany()
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
            // Failed to load user data — clear auth
            clearAuthentication()
        }
        
    }
    
    @discardableResult
    @MainActor
    func login(username: String, password: String) async -> (Bool, String?) {
        // Cancel any pending data wipe from a prior logout
        cancelPendingDataWipe()

        do {
            // Sign in via Firebase Auth (handles session, stores userId + companyId)
            try await authManager.loginWithEmail(username, password: password)

            if let userId = authManager.getUserId() {
                // Set the authentication flags immediately
                UserDefaults.standard.set(true, forKey: "is_authenticated")
                UserDefaults.standard.set(userId, forKey: "user_id")
                UserDefaults.standard.set(userId, forKey: "currentUserId")

                // Backfill firebase_uid in users table
                Task { await authManager.backfillFirebaseUID(usersTableId: userId) }

                // Fetch user data
                try await fetchUserFromAPI(userId: userId)

                // Check if user has completed onboarding from server data
                if let user = currentUser {
                    UserDefaults.standard.set(user.hasCompletedAppOnboarding, forKey: "onboarding_completed")

                    // Track login conversion for Google Ads
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .email)
                    AnalyticsService.shared.track(eventType: .lifecycle, eventName: "login", properties: ["method": "email"])
                    AnalyticsManager.shared.setUserType(user.userType)
                    AnalyticsManager.shared.setUserId(userId)
                }

                return (true, nil)
            } else {
                return (false, "No account found for this email. Please check your email or sign up.")
            }
        } catch let error as FirebaseAuthService.FirebaseAuthServiceError {
            return (false, error.errorDescription)
        } catch {
            return (false, "Incorrect email or password. Please try again.")
        }
    }
    
    /// Apple login
    @MainActor
    func loginWithApple(appleResult: AppleSignInManager.AppleSignInResult) async -> Bool {
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log("[AUTH] loginWithApple: start")

        // Cancel any pending data wipe from a prior logout
        cancelPendingDataWipe()

        // Track whether we've begun writing persisted auth state so an
        // exception mid-flight can be rolled back cleanly. Without this,
        // a partial auth state would survive to the next launch and cause
        // subsequent login attempts to crash while trying to load a user
        // that doesn't exist yet.
        var didWriteAuthFlags = false

        do {
            // Authenticate with Firebase using Apple identity token
            crashlytics.log("[AUTH] loginWithApple: FirebaseAuth.signInWithApple")
            try await FirebaseAuthService.shared.signInWithApple(identityToken: appleResult.identityToken)

            let firebaseUID = FirebaseAuthService.shared.firebaseUID ?? ""
            let email = FirebaseAuthService.shared.currentUserEmail ?? appleResult.email ?? ""
            crashlytics.log("[AUTH] loginWithApple: firebase OK — uid='\(firebaseUID)' emailPresent=\(!email.isEmpty)")
            crashlytics.setUserID(firebaseUID)

            // Store Apple user identifier for future logins
            UserDefaults.standard.set(appleResult.userIdentifier, forKey: "apple_user_identifier")

            // Look up existing user in Supabase users table by email
            crashlytics.log("[AUTH] loginWithApple: loadUserFromSupabase")
            try await authManager.loadUserFromSupabase(userId: firebaseUID, email: email)

            // Use the user ID from users table (may differ from Firebase UID for migrated users)
            let userId = authManager.getUserId() ?? firebaseUID
            crashlytics.log("[AUTH] loginWithApple: resolved userId='\(userId)'")

            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId")
            didWriteAuthFlags = true

            // Backfill firebase_uid in users table
            Task { await authManager.backfillFirebaseUID(usersTableId: userId) }

            // Try to fetch full user data - may fail for brand new users
            do {
                crashlytics.log("[AUTH] loginWithApple: fetchUserFromAPI")
                try await fetchUserFromAPI(userId: userId)
                crashlytics.log("[AUTH] loginWithApple: fetchUserFromAPI OK")
            } catch {
                crashlytics.log("[AUTH] loginWithApple: fetchUserFromAPI threw — \(error.localizedDescription)")
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
                    AnalyticsService.shared.track(eventType: .lifecycle, eventName: "sign_up", properties: ["method": "apple"])
                } else {
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .apple)
                    AnalyticsService.shared.track(eventType: .lifecycle, eventName: "login", properties: ["method": "apple"])
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
            // Roll back any partial auth state so a failed attempt can't
            // leave the app in a zombie "authenticated but no user" state
            // that crashes subsequent launches when checkExistingAuth runs.
            if didWriteAuthFlags {
                UserDefaults.standard.removeObject(forKey: "is_authenticated")
                UserDefaults.standard.removeObject(forKey: "user_id")
                UserDefaults.standard.removeObject(forKey: "currentUserId")
                UserDefaults.standard.removeObject(forKey: "apple_user_identifier")
                print("[AUTH] Rolled back partial Apple login state")
            }
            // Sign the Firebase user out so a retry starts fresh instead
            // of reusing a half-migrated session.
            FirebaseAuthService.shared.signOut()
            return false
        }
    }

    /// Google login
    @MainActor
    func loginWithGoogle(googleUser: GIDGoogleUser) async -> Bool {
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log("[AUTH] loginWithGoogle: start")

        guard let idToken = googleUser.idToken?.tokenString,
              let accessToken = googleUser.accessToken.tokenString as String?,
              let email = googleUser.profile?.email else {
            crashlytics.log("[AUTH] loginWithGoogle: missing googleUser fields — aborting")
            return false
        }

        // Cancel any pending data wipe from a prior logout — prevents race condition
        // where the wipe fires mid-login and destroys freshly-loaded user data
        cancelPendingDataWipe()

        do {
            // Authenticate with Firebase using Google credentials
            crashlytics.log("[AUTH] loginWithGoogle: FirebaseAuth.signInWithGoogle")
            try await FirebaseAuthService.shared.signInWithGoogle(idToken: idToken, accessToken: accessToken)

            let firebaseUID = FirebaseAuthService.shared.firebaseUID ?? ""
            crashlytics.log("[AUTH] loginWithGoogle: firebase OK — uid='\(firebaseUID)'")
            crashlytics.setUserID(firebaseUID)

            // Look up existing user in Supabase users table by email
            crashlytics.log("[AUTH] loginWithGoogle: loadUserFromSupabase")
            try await authManager.loadUserFromSupabase(userId: firebaseUID, email: email)

            // Use the user ID from users table (may differ from Firebase UID for migrated users).
            // getUserId() returns nil if loadUserFromSupabase didn't find the user.
            let supabaseUserId = authManager.getUserId()
            let userId = supabaseUserId ?? firebaseUID
            let userExistsInSupabase = supabaseUserId != nil

            // Set authentication flags
            UserDefaults.standard.set(true, forKey: "is_authenticated")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId")

            // Backfill firebase_uid in users table
            Task { await authManager.backfillFirebaseUID(usersTableId: userId) }

            // Try to fetch full user data - may fail for brand new users
            do {
                crashlytics.log("[AUTH] loginWithGoogle: fetchUserFromAPI")
                try await fetchUserFromAPI(userId: userId)
                crashlytics.log("[AUTH] loginWithGoogle: fetchUserFromAPI OK")
            } catch {
                crashlytics.log("[AUTH] loginWithGoogle: fetchUserFromAPI threw — \(error.localizedDescription)")
                print("[AUTH] fetchUserFromAPI failed: \(error)")
                if userExistsInSupabase {
                    print("[AUTH] ⚠️ User exists in Supabase but fetch failed — treating as returning user")
                } else {
                    print("[AUTH] User not found in users table — likely a new user, will need onboarding")
                }
            }

            // Check onboarding status
            if let user = currentUser {
                let hasCompany = !(user.companyId ?? "").isEmpty
                let hasCompletedAppOnboarding = user.hasCompletedAppOnboarding

                // A user with a company has definitively completed onboarding,
                // even if onboarding_completed JSONB is empty (pre-migration users).
                let needsOnboarding = !hasCompany

                print("[AUTH] 🔍 Onboarding check: hasCompany=\(hasCompany) (companyId='\(user.companyId ?? "nil")'), hasCompletedAppOnboarding=\(hasCompletedAppOnboarding), needsOnboarding=\(needsOnboarding)")

                // Backfill: if user has a company but onboarding_completed["ios"] is false,
                // patch Supabase so future logins don't hit this path
                if hasCompany && !hasCompletedAppOnboarding {
                    print("[AUTH] 📝 Backfilling onboarding_completed for pre-migration user")
                    user.hasCompletedAppOnboarding = true
                    Task { await self.backfillOnboardingCompleted(userId: user.id) }
                }

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
                    AnalyticsService.shared.track(eventType: .lifecycle, eventName: "sign_up", properties: ["method": "google"])
                } else {
                    AnalyticsManager.shared.trackLogin(userType: user.userType, method: .google)
                    AnalyticsService.shared.track(eventType: .lifecycle, eventName: "login", properties: ["method": "google"])
                }
                AnalyticsManager.shared.setUserType(user.userType)
                AnalyticsManager.shared.setUserId(userId)

                UserDefaults.standard.set(!needsOnboarding, forKey: "onboarding_completed")

                if !needsOnboarding {
                    self.isAuthenticated = true
                }

                return true
            } else if userExistsInSupabase {
                // User exists in Supabase but fetchUserFromAPI failed to populate currentUser.
                // Treat as returning user to avoid incorrectly routing to onboarding.
                print("[AUTH] ⚠️ User exists in Supabase but currentUser is nil — setting authenticated")
                UserDefaults.standard.set(true, forKey: "onboarding_completed")
                self.isAuthenticated = true
                // Re-attempt fetch in background so data loads
                Task {
                    try? await self.fetchUserFromAPI(userId: userId)
                }
                return true
            }

            // No user found — new user, needs onboarding
            print("[AUTH] No user found in Supabase — new user, needs onboarding")
            UserDefaults.standard.set(false, forKey: "onboarding_completed")
            return true
        } catch {
            print("[AUTH] Google login failed: \(error)")
            return false
        }
    }

    /// Backfill onboarding_completed JSONB with {"ios": true} for pre-migration users
    /// who completed onboarding before this column was introduced.
    @MainActor
    private func backfillOnboardingCompleted(userId: String) async {
        do {
            let userRepo = UserRepository(companyId: "")
            let currentDTO = try await userRepo.fetchOne(userId)
            var merged = currentDTO.onboardingCompleted ?? [:]
            merged["ios"] = true

            var mergedJSON: [String: AnyJSON] = [:]
            for (key, value) in merged {
                mergedJSON[key] = .bool(value)
            }

            try await userRepo.updateFields(userId: userId, fields: [
                "onboarding_completed": .object(mergedJSON)
            ])
            print("[AUTH] ✅ Backfilled onboarding_completed with ios:true → \(merged)")
        } catch {
            // Non-fatal — will retry on next login
            print("[AUTH] ⚠️ Failed to backfill onboarding_completed: \(error)")
        }
    }

    @MainActor
    private func fetchUserFromAPI(userId: String) async throws {
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log("[AUTH] fetchUserFromAPI: start userId='\(userId)'")

        guard let context = modelContext else {
            crashlytics.log("[AUTH] fetchUserFromAPI: modelContext nil")
            throw NSError(domain: "DataController", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        // First, check if this user already exists in the database
        let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == userId })
        let existingUsers = try context.fetch(descriptor)
        crashlytics.log("[AUTH] fetchUserFromAPI: local users=\(existingUsers.count)")

        // Fetch user from API via repository and upsert locally
        crashlytics.log("[AUTH] fetchUserFromAPI: initializeSyncManager #1")
        initializeSyncManager()
        crashlytics.log("[AUTH] fetchUserFromAPI: fetchAndUpsertUser")
        guard let fetchedUser = try await fetchAndUpsertUser(id: userId) else {
            // If fetch failed, try local
            if let existingUser = existingUsers.first {
                self.currentUser = existingUser
                // Fetch permissions (will use cache if offline)
                Task {
                    await self.permissionStore?.fetchPermissions(userId: existingUser.id)
                }
            } else {
                throw NSError(domain: "DataController", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user"])
            }
            return
        }

        let user = fetchedUser
        print("[AUTH] 🔍 fetchUserFromAPI: user.id=\(user.id), companyId='\(user.companyId ?? "nil")', hasCompletedAppOnboarding=\(user.hasCompletedAppOnboarding)")

        // Update app state with the current user
        self.currentUser = user

        // Fetch permissions from Supabase
        await self.permissionStore?.fetchPermissions(userId: user.id)

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
        crashlytics.log("[AUTH] fetchUserFromAPI: linkUserToOneSignal")
        NotificationManager.shared.linkUserToOneSignal()

        // Configure OneSignal service for sending notifications
        Task {
            await OneSignalService.shared.configure()
        }

        // Initialize sync managers (may already be initialized from line 751)
        crashlytics.log("[AUTH] fetchUserFromAPI: initializeSyncManager #2")
        initializeSyncManager()

        // Reconfigure all sync processors with the now-confirmed companyId.
        // This is critical: if initializeSyncManager() ran before companyId was
        // in UserDefaults, the InboundProcessor repositories will have been built
        // with companyId="" and would fetch 0 rows.
        crashlytics.log("[AUTH] fetchUserFromAPI: syncEngine.reconfigureForCompany")
        syncEngine.reconfigureForCompany()

        // Capture the authentication decision up-front but DO NOT flip
        // isAuthenticated yet. Flipping it here — mid-chain, while the
        // method is still running fetchCompanyData and fullSync below —
        // triggers a SwiftUI cascade that tears down the onboarding
        // coordinator and spins up MainTabView/HomeView *while* the
        // InboundProcessor is still writing to the same SwiftData
        // context. HomeView.onAppear then calls loadTodaysProjects and
        // reads the context concurrently with the sync pipeline's
        // writes, which SwiftData is not thread-safe against. The flip
        // is deferred to the very end of this method, after the full
        // sync completes and SwiftData is stable.
        //
        // The check preserves the original semantics: "has completed
        // app onboarding OR has a company" — having a company is
        // definitive proof of completed onboarding for pre-migration
        // users whose onboarding_completed JSONB was never populated.
        await MainActor.run {
            isPerformingInitialSync = true
        }
        let hasCompany = !(user.companyId ?? "").isEmpty
        let shouldFlipAuthentication = user.hasCompletedAppOnboarding || hasCompany

        // Fetch company data if needed
        if isConnected, let companyId = user.companyId, !companyId.isEmpty {
            do {
                crashlytics.log("[AUTH] fetchUserFromAPI: fetchCompanyData companyId='\(companyId)'")
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
                    await syncEngine.fullSync()
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

                // Kick off Spotlight initial backfill (no-op if already complete).
                // Runs async so it doesn't block the login flow.
                if let ctx = self.modelContext {
                    Task { @MainActor in
                        await SpotlightBackfillCoordinator.shared.runIfNeeded(context: ctx)
                    }
                }
            } catch {
                // Continue even if company data fetch fails - don't block authentication
                // But still try to sync what we can
                print("[LOGIN] ⚠️ Company fetch failed, attempting sync anyway...")
                await MainActor.run {
                    syncStatusMessage = "SYNCING PROJECTS..."
                }
                do {
                    await syncEngine.fullSync()
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

                if let ctx = self.modelContext {
                    Task { @MainActor in
                        await SpotlightBackfillCoordinator.shared.runIfNeeded(context: ctx)
                    }
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

        // Deferred authentication flip: now that every branch above has
        // finished loading data AND cleared isPerformingInitialSync,
        // SwiftData is stable and safe to read. Flipping isAuthenticated
        // here triggers ContentView's onChange handler to tear down the
        // onboarding coordinator and render MainTabView — at which point
        // HomeView's loadTodaysProjects can safely read the context
        // without racing the InboundProcessor's writes.
        if shouldFlipAuthentication {
            crashlytics.log("[AUTH] fetchUserFromAPI: flipping isAuthenticated (post-sync)")
            await MainActor.run {
                self.isAuthenticated = true
            }
        }
    }

    @MainActor
    func logout() {
        print("[LOGOUT] Starting logout process...")

        // Halt the sync engine's timer and observers FIRST — before flipping
        // isAuthenticated, before wiping data, and before SwiftUI starts
        // tearing down the view hierarchy. Without this step, the retry
        // timer could fire mid-wipe and crash accessing invalidated SwiftData
        // models, and connectivity/permission observers could re-arm sync
        // activity while deletions are in flight.
        syncEngine.stopForLogoutSync()
        // Fire-and-forget the realtime teardown; it doesn't block logout.
        Task { @MainActor [weak self] in
            await self?.syncEngine.stopForLogoutAsync()
        }

        // Flip auth state so ContentView tears down PINGatedView before
        // any downstream state mutations. Prevents a one-frame render of
        // MainTabView when the lockout screen is dismissed by resetForLogout()
        // while ContentView still sees isAuthenticated = true.
        self.isAuthenticated = false

        // Unlink user from OneSignal
        NotificationManager.shared.unlinkUserFromOneSignal()

        // Clear OneSignal service configuration
        OneSignalService.shared.clearConfiguration()

        // Reset subscription manager state to prevent lockout screen from showing after logout
        SubscriptionManager.shared.resetForLogout()

        // Clear permissions
        permissionStore?.clearPermissions()

        // Clear on-disk client avatar cache
        ClientAvatarCache.shared.clearAll()

        // Capture the current user id BEFORE clearAuthentication() wipes it,
        // so SpotlightIndexManager.clearAll can remove the user-scoped backfill
        // flag. Without this, the async Task below would read a nil currentUserId
        // and clear the legacy unscoped key instead, leaking the user-scoped flag.
        let spotlightUserId = UserDefaults.standard.string(forKey: "currentUserId")

        // Clear Spotlight index
        Task { await SpotlightIndexManager.shared.clearAll(forUserId: spotlightUserId) }

        // First, clear the current user reference to prevent views from accessing it
        self.currentUser = nil

        // Post notification to reset app state and dismiss views
        NotificationCenter.default.post(name: NSNotification.Name("LogoutInitiated"), object: nil)

        // Clear keychain, UserDefaults, and remaining auth tokens
        clearAuthentication()

        // Sign out from Firebase and Google synchronously — we're already on MainActor.
        // Must happen synchronously to prevent race: if done via async Task, the signout
        // could execute AFTER the user starts a new login, invalidating the fresh session.
        FirebaseAuthService.shared.signOut()
        GoogleSignInManager.shared.signOut()
        // Clear keychain credentials (authManager keychain ops are synchronous)
        authManager.clearCredentials()

        // Clear PIN settings
        simplePINManager.removePIN()

        // Clear onboarding state to prevent stale flow data on next login
        OnboardingState.clear()
        UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.completed)

        // Schedule data wipe with a cancellable work item.
        // If the user re-logs in before this fires, loginWithGoogle/loginWithEmail
        // will cancel it to prevent wiping freshly-loaded data.
        cancelPendingDataWipe()
        let wipeWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Double-check: if user re-authenticated while waiting, skip the wipe
            guard !self.isAuthenticated else {
                print("[LOGOUT] Skipping data wipe — user re-authenticated")
                return
            }

            print("[LOGOUT] Performing complete data wipe...")
            self.performCompleteDataWipe()
            print("[LOGOUT] Data wipe complete")
        }
        pendingDataWipeWork = wipeWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: wipeWork)
    }

    /// Cancel any pending data wipe from a prior logout.
    /// Called at the start of login flows to prevent race conditions.
    @MainActor
    private func cancelPendingDataWipe() {
        if let work = pendingDataWipeWork {
            work.cancel()
            pendingDataWipeWork = nil
            print("[AUTH] Cancelled pending data wipe from prior logout")
        }
    }
    
    /// Completely wipes all data from the SwiftData store
    @MainActor
    private func performCompleteDataWipe() {
        guard let context = modelContext else {
            print("[LOGOUT] No model context available for data wipe")
            return
        }

        // Belt-and-suspenders: re-halt the sync engine in case logout() ran
        // before stopForLogoutSync landed, or something rearmed it.
        syncEngine.stopForLogoutSync()

        print("[LOGOUT] Deleting all SwiftData models...")

        // Use iterative fetch+delete everywhere instead of the
        // `context.delete(model:)` bulk API. The bulk API posts a single
        // change notification that still-mounted @Query views react to on
        // the same run loop — and because it also fires SwiftData's cascade
        // delete paths under the hood, it has historically crashed during
        // logout when a view reaches into an invalidated model's relationship.
        // Iterative deletion plus a final save gives us one controlled
        // notification point and lets us handle each entity class in an
        // order that respects our inverse relationships.
        autoreleasepool {
            // Phase 1: leaf entities (no inbound relationships from other
            // entities we care about during logout). Deleting these first
            // makes Phase 2 cascade semantics predictable.
            deleteAll(FetchDescriptor<WizardState>(), label: "WizardState", in: context)
            deleteAll(FetchDescriptor<SyncOperation>(), label: "SyncOperation", in: context)
            deleteAll(FetchDescriptor<LocalPhoto>(), label: "LocalPhoto", in: context)
            deleteAll(FetchDescriptor<PhotoAnnotation>(), label: "PhotoAnnotation", in: context)
            deleteAll(FetchDescriptor<SignatureCapture>(), label: "SignatureCapture", in: context)
            deleteAll(FetchDescriptor<FormSubmission>(), label: "FormSubmission", in: context)
            deleteAll(FetchDescriptor<TimeEntry>(), label: "TimeEntry", in: context)
            deleteAll(FetchDescriptor<Activity>(), label: "Activity", in: context)
            deleteAll(FetchDescriptor<FollowUp>(), label: "FollowUp", in: context)
            deleteAll(FetchDescriptor<StageTransition>(), label: "StageTransition", in: context)
            deleteAll(FetchDescriptor<SiteVisit>(), label: "SiteVisit", in: context)
            deleteAll(FetchDescriptor<CalendarUserEvent>(), label: "CalendarUserEvent", in: context)
            deleteAll(FetchDescriptor<ProjectNote>(), label: "ProjectNote", in: context)
            deleteAll(FetchDescriptor<EstimateLineItem>(), label: "EstimateLineItem", in: context)
            deleteAll(FetchDescriptor<InvoiceLineItem>(), label: "InvoiceLineItem", in: context)
            deleteAll(FetchDescriptor<Estimate>(), label: "Estimate", in: context)
            deleteAll(FetchDescriptor<Invoice>(), label: "Invoice", in: context)
            deleteAll(FetchDescriptor<Payment>(), label: "Payment", in: context)
            deleteAll(FetchDescriptor<InventorySnapshotItem>(), label: "InventorySnapshotItem", in: context)
            deleteAll(FetchDescriptor<InventorySnapshot>(), label: "InventorySnapshot", in: context)
            deleteAll(FetchDescriptor<InventoryItem>(), label: "InventoryItem", in: context)
            deleteAll(FetchDescriptor<InventoryTag>(), label: "InventoryTag", in: context)
            deleteAll(FetchDescriptor<InventoryUnit>(), label: "InventoryUnit", in: context)
            deleteAll(FetchDescriptor<Opportunity>(), label: "Opportunity", in: context)
            deleteAll(FetchDescriptor<Product>(), label: "Product", in: context)
            deleteAll(FetchDescriptor<OpsContact>(), label: "OpsContact", in: context)
            deleteAll(FetchDescriptor<TaskStatusOption>(), label: "TaskStatusOption", in: context)
            deleteAll(FetchDescriptor<SubClient>(), label: "SubClient", in: context)

            // Phase 2: core entities in dependency order. We clear inverse
            // relationships BEFORE calling delete so SwiftData's cascade
            // rules don't try to re-delete already-deleted children.
            if let tasks = try? context.fetch(FetchDescriptor<ProjectTask>()) {
                for task in tasks {
                    task.project = nil
                    task.taskType = nil
                    task.teamMembers.removeAll()
                    context.delete(task)
                }
                print("[LOGOUT] Deleted \(tasks.count) tasks")
            }

            if let taskTypes = try? context.fetch(FetchDescriptor<TaskType>()) {
                for taskType in taskTypes {
                    taskType.tasks.removeAll()
                    context.delete(taskType)
                }
                print("[LOGOUT] Deleted \(taskTypes.count) task types")
            }

            if let projects = try? context.fetch(FetchDescriptor<Project>()) {
                for project in projects {
                    project.teamMembers.removeAll()
                    project.tasks.removeAll()
                    project.client = nil
                    context.delete(project)
                }
                print("[LOGOUT] Deleted \(projects.count) projects")
            }

            if let clients = try? context.fetch(FetchDescriptor<Client>()) {
                for client in clients {
                    client.projects.removeAll()
                    client.subClients.removeAll()
                    context.delete(client)
                }
                print("[LOGOUT] Deleted \(clients.count) clients")
            }

            if let teamMembers = try? context.fetch(FetchDescriptor<TeamMember>()) {
                for member in teamMembers {
                    member.company = nil
                    context.delete(member)
                }
                print("[LOGOUT] Deleted \(teamMembers.count) team members")
            }

            if let users = try? context.fetch(FetchDescriptor<User>()) {
                for user in users {
                    user.assignedProjects.removeAll()
                    context.delete(user)
                }
                print("[LOGOUT] Deleted \(users.count) users")
            }

            if let companies = try? context.fetch(FetchDescriptor<Company>()) {
                for company in companies {
                    company.teamMembers.removeAll()
                    context.delete(company)
                }
                print("[LOGOUT] Deleted \(companies.count) companies")
            }
        }

        // Save all deletions
        do {
            try context.save()
            print("[LOGOUT] All data deleted and saved")
        } catch {
            print("[LOGOUT] Error saving after data wipe: \(error)")
        }

        // Clear sync timestamps so next login does a full sync, not a delta
        syncEngine.clearAllTimestamps()

        // Clear any cached data
        clearAllCaches()
    }

    /// Fetch all instances of a model and delete them individually.
    /// Isolated helper so performCompleteDataWipe reads like a list of
    /// entity types rather than repeated try? / fetch / for-loop blocks.
    private func deleteAll<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>,
        label: String,
        in context: ModelContext
    ) {
        guard let rows = try? context.fetch(descriptor) else {
            print("[LOGOUT] Fetch failed for \(label) — skipping")
            return
        }
        guard !rows.isEmpty else { return }
        for row in rows {
            context.delete(row)
        }
        print("[LOGOUT] Deleted \(rows.count) \(label)")
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
        UserDefaults.standard.removeObject(forKey: "subscription_plan")
        UserDefaults.standard.removeObject(forKey: "user_role")
        
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

    // MARK: - Project / Task / Client Duplicate Cleanup
    //
    // The core SwiftData models (Project, ProjectTask, Client) do not have
    // @Attribute(.unique) on `id`, so historical sync paths could insert
    // multiple rows with the same id. Duplicates render as blank cells in
    // ForEach views (SwiftUI collapses duplicate IDs). These cleanup functions
    // run on every modelContext init and are idempotent.

    /// Picks the "freshest" duplicate to keep based on local-edit state and sync recency.
    /// Returns the index of the winner in the input array.
    ///
    /// Pinned to @MainActor because the closures read properties from SwiftData
    /// models bound to the main-queue context. Off-main property access on
    /// main-queue-bound models corrupts context state (the same crash class
    /// this helper supports cleaning up).
    @MainActor
    private func pickFreshestIndex<T>(
        _ duplicates: [T],
        needsSync: (T) -> Bool,
        lastSyncedAt: (T) -> Date?
    ) -> Int {
        var winnerIdx = 0
        for i in 1..<duplicates.count {
            let cur = duplicates[i]
            let win = duplicates[winnerIdx]

            // Local edits (needsSync == true) win — never discard unsynced user changes
            let curNeedsSync = needsSync(cur)
            let winNeedsSync = needsSync(win)
            if curNeedsSync != winNeedsSync {
                if curNeedsSync { winnerIdx = i }
                continue
            }

            // Otherwise prefer the most recently synced row
            let curSync = lastSyncedAt(cur) ?? .distantPast
            let winSync = lastSyncedAt(win) ?? .distantPast
            if curSync > winSync { winnerIdx = i }
        }
        return winnerIdx
    }

    @MainActor
    func cleanupDuplicateProjects() async {
        guard let context = modelContext else { return }

        do {
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            let grouped = Dictionary(grouping: allProjects, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }

            guard !duplicateGroups.isEmpty else { return }

            print("[Cleanup] Found \(duplicateGroups.count) project IDs with duplicates")
            var totalDeleted = 0

            for (id, copies) in duplicateGroups {
                let winnerIdx = pickFreshestIndex(
                    copies,
                    needsSync: { $0.needsSync },
                    lastSyncedAt: { $0.lastSyncedAt }
                )
                let keep = copies[winnerIdx]
                let dupsToDelete = copies.enumerated()
                    .filter { $0.offset != winnerIdx }
                    .map { $0.element }

                // Snapshot all tasks across duplicates BEFORE mutating relationships.
                // Setting task.project = keep triggers SwiftData's inverse mechanism,
                // which removes the task from dup.tasks — mutating during iteration
                // corrupts the context.
                //
                // Also update the string FK (task.projectId). The relationship and
                // the string field are maintained separately by application code;
                // if we only touch the relationship, the string still points at
                // the deleted row and sync DTOs leak the stale id.
                let orphanedTasks = dupsToDelete.flatMap { Array($0.tasks) }
                for task in orphanedTasks {
                    task.project = keep
                    task.projectId = keep.id
                }

                // Same snapshot pattern for team members.
                // Project.teamMembers has User.assignedProjects as its inverse.
                let existingMemberIds = Set(keep.teamMembers.map { $0.id })
                let orphanedMembers = dupsToDelete.flatMap { Array($0.teamMembers) }
                for member in orphanedMembers where !existingMemberIds.contains(member.id) {
                    keep.teamMembers.append(member)
                }

                // Now safe to delete duplicates — their tasks array is empty,
                // so the cascade delete rule has nothing to remove.
                for dup in dupsToDelete {
                    context.delete(dup)
                    totalDeleted += 1
                }

                print("[Cleanup] Deduped project \(id): kept lastSyncedAt=\(String(describing: keep.lastSyncedAt)), deleted \(copies.count - 1)")
            }

            try context.save()
            print("[Cleanup] Removed \(totalDeleted) duplicate Project rows total")
        } catch {
            print("[Cleanup] Failed to dedupe projects: \(error)")
        }
    }

    @MainActor
    func cleanupDuplicateTasks() async {
        guard let context = modelContext else { return }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
            let grouped = Dictionary(grouping: allTasks, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }

            guard !duplicateGroups.isEmpty else { return }

            print("[Cleanup] Found \(duplicateGroups.count) task IDs with duplicates")
            var totalDeleted = 0

            for (id, copies) in duplicateGroups {
                let winnerIdx = pickFreshestIndex(
                    copies,
                    needsSync: { $0.needsSync },
                    lastSyncedAt: { $0.lastSyncedAt }
                )
                let dupsToDelete = copies.enumerated()
                    .filter { $0.offset != winnerIdx }
                    .map { $0.element }

                for dup in dupsToDelete {
                    context.delete(dup)
                    totalDeleted += 1
                }

                print("[Cleanup] Deduped task \(id): deleted \(copies.count - 1)")
            }

            try context.save()
            print("[Cleanup] Removed \(totalDeleted) duplicate ProjectTask rows total")
        } catch {
            print("[Cleanup] Failed to dedupe tasks: \(error)")
        }
    }

    @MainActor
    func cleanupDuplicateClients() async {
        guard let context = modelContext else { return }

        do {
            let allClients = try context.fetch(FetchDescriptor<Client>())
            let grouped = Dictionary(grouping: allClients, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }

            guard !duplicateGroups.isEmpty else { return }

            print("[Cleanup] Found \(duplicateGroups.count) client IDs with duplicates")
            var totalDeleted = 0

            for (id, copies) in duplicateGroups {
                let winnerIdx = pickFreshestIndex(
                    copies,
                    needsSync: { $0.needsSync },
                    lastSyncedAt: { $0.lastSyncedAt }
                )
                let keep = copies[winnerIdx]
                let dupsToDelete = copies.enumerated()
                    .filter { $0.offset != winnerIdx }
                    .map { $0.element }

                // Snapshot referenced projects from each duplicate's `projects` inverse
                // BEFORE mutating relationships. Setting project.client = keep triggers
                // the inverse which would mutate dup.projects mid-iteration.
                //
                // Also update the string FK (project.clientId) to keep it in sync
                // with the relationship — sync DTOs read the string field.
                let orphanedProjects = dupsToDelete.flatMap { Array($0.projects) }
                for project in orphanedProjects {
                    project.client = keep
                    project.clientId = keep.id
                }

                for dup in dupsToDelete {
                    context.delete(dup)
                    totalDeleted += 1
                }

                print("[Cleanup] Deduped client \(id): deleted \(copies.count - 1)")
            }

            try context.save()
            print("[Cleanup] Removed \(totalDeleted) duplicate Client rows total")
        } catch {
            print("[Cleanup] Failed to dedupe clients: \(error)")
        }
    }

    /// Deduplicates local TaskType rows. Without `@Attribute(.unique)` on
    /// `TaskType.id`, SwiftData can hold multiple rows with the same id. When
    /// a task resolves `task.taskType`, it picks one of them — possibly a
    /// stale duplicate with missing data — and the UI renders as if the task
    /// has no type. Server-side is fine; only local state is broken.
    ///
    /// This runs on every launch (alongside the other cleanups) and is
    /// idempotent: it only touches duplicate groups and ignores clean data.
    @MainActor
    func cleanupDuplicateTaskTypes() async {
        guard let context = modelContext else { return }

        do {
            let allTaskTypes = try context.fetch(FetchDescriptor<TaskType>())
            let grouped = Dictionary(grouping: allTaskTypes, by: { $0.id })
            let duplicateGroups = grouped.filter { $0.value.count > 1 }

            guard !duplicateGroups.isEmpty else { return }

            print("[Cleanup] Found \(duplicateGroups.count) task type IDs with duplicates")
            var totalDeleted = 0

            for (id, copies) in duplicateGroups {
                let winnerIdx = pickFreshestIndex(
                    copies,
                    needsSync: { $0.needsSync },
                    lastSyncedAt: { $0.lastSyncedAt }
                )
                let keep = copies[winnerIdx]
                let dupsToDelete = copies.enumerated()
                    .filter { $0.offset != winnerIdx }
                    .map { $0.element }

                // Snapshot all tasks across duplicates BEFORE mutating relationships.
                // TaskType.tasks is the inverse of ProjectTask.taskType, so setting
                // task.taskType = keep removes the task from dup.tasks via the
                // inverse — mutating during iteration corrupts the context (same
                // bug pattern we hit on Project cleanup).
                //
                // Also update task.taskTypeId string so it matches the relationship.
                let orphanedTasks = dupsToDelete.flatMap { Array($0.tasks) }
                for task in orphanedTasks {
                    task.taskType = keep
                    task.taskTypeId = keep.id
                }

                for dup in dupsToDelete {
                    context.delete(dup)
                    totalDeleted += 1
                }

                print("[Cleanup] Deduped task type \(id) (\(keep.display)): deleted \(copies.count - 1)")
            }

            try context.save()
            print("[Cleanup] Removed \(totalDeleted) duplicate TaskType rows total")
        } catch {
            print("[Cleanup] Failed to dedupe task types: \(error)")
        }
    }

    // MARK: - Data Operations
    
    /// Fetch company data from API - optimized for reliability
    @MainActor
    private func fetchCompanyData(companyId: String) async throws {
        guard let context = modelContext else {
            return
        }

        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == companyId }
        )

        let companies = try context.fetch(descriptor)

        if companies.isEmpty || (companies.first?.needsSync == true) {
            // Pull just the company row directly. triggerCompanySync() delegates
            // to syncEngine.triggerSync() which runs a delta sync, and delta
            // sync does NOT include the company entity — so the row wouldn't
            // actually land in SwiftData until the subsequent full sync,
            // creating a window where getCurrentUserCompany() returns nil and
            // downstream features (subscription checks, views, etc.) fire with
            // stale/empty state.
            await syncEngine.syncCompanyNow()

            // Re-fetch the company after sync
            let updatedCompanies = try context.fetch(descriptor)
            if let company = updatedCompanies.first {
                // If team members haven't been synced, or it's been more than a day, sync team members
                if !company.teamMembersSynced ||
                   company.lastSyncedAt == nil ||
                   Date().timeIntervalSince(company.lastSyncedAt!) > 86400 {
                    await triggerTeamMembersSync(companyId: companyId)
                }
            }
        }
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
                    // User exists - refresh if online
                    if isConnected {
                        do {
                            if let refreshedUser = try await fetchAndUpsertUser(id: memberId) {
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
                    // User doesn't exist locally but we're online - fetch via repository
                    do {
                        if let newUser = try await fetchAndUpsertUser(id: memberId) {
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
                            addNonExistentUserId(memberId)
                            continue
                        }
                    } catch {
                        // Create placeholder for network errors
                        let placeholderUser = User(
                            id: memberId,
                            firstName: "Team Member",
                            lastName: "#\(memberId.suffix(4))",
                            role: .crew,
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
                        role: .crew,
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
            if let user = user, !PermissionStore.shared.hasFullAccess("projects.view") {
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
        if PermissionStore.shared.hasFullAccess("projects.view") {
            return getProjects(for: date, assignedTo: nil)
        } else {
            // For Field Crew, pass the user to filter by assignment
            return getProjects(for: date, assignedTo: user)
        }
    }
    
    /// Force refresh projects from backend
    @MainActor
    func refreshProjectsFromBackend() async {
        guard isConnected, isAuthenticated else {
            return
        }

        print("[MANUAL_SYNC] 🔄 Starting comprehensive manual sync via SyncEngine...")
        await syncEngine.fullSync()
        print("[MANUAL_SYNC] ✅ Manual sync completed")
    }
    
    // MARK: - All Tasks

    /// Get all non-deleted tasks in the local store
    func getAllTasks() -> [ProjectTask] {
        guard let context = modelContext else { return [] }
        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
            return allTasks.filter { $0.deletedAt == nil }
        } catch {
            print("[DataController] Failed to fetch all tasks: \(error)")
            return []
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
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)

            let filteredTasks = allTasks.filter { task in
                guard task.deletedAt == nil else { return false }
                guard let taskStart = task.startDate else { return false }
                let taskEnd = task.endDate ?? taskStart

                // Normalize to start-of-day to avoid time-component mismatches
                let taskStartDay = calendar.startOfDay(for: taskStart)
                let taskEndDay = calendar.startOfDay(for: taskEnd)
                let isActiveOnDate = taskStartDay <= dayStart && taskEndDay >= dayStart

                if !isActiveOnDate {
                    return false
                }

                // For users with full task access, show all company tasks
                if PermissionStore.shared.hasFullAccess("tasks.view") {
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

    /// Get ALL scheduled tasks for a date (company-wide, no user filter)
    func getScheduledTasksForCompany(for date: Date) -> [ProjectTask] {
        guard let user = currentUser else { return [] }
        guard let context = modelContext else { return [] }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)

            let filteredTasks = allTasks.filter { task in
                guard task.deletedAt == nil else { return false }
                guard task.companyId == user.companyId else { return false }
                guard let taskStart = task.startDate else { return false }
                let taskEnd = task.endDate ?? taskStart

                // Normalize to start-of-day to avoid time-component mismatches
                let taskStartDay = calendar.startOfDay(for: taskStart)
                let taskEndDay = calendar.startOfDay(for: taskEnd)
                return taskStartDay <= dayStart && taskEndDay >= dayStart
            }

            return filteredTasks.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            return []
        }
    }

    /// Get scheduled tasks for a specific team member on a date
    func getScheduledTasksForMember(for date: Date, memberId: String) -> [ProjectTask] {
        guard let user = currentUser else { return [] }
        guard let context = modelContext else { return [] }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)

            let filteredTasks = allTasks.filter { task in
                guard task.deletedAt == nil else { return false }
                guard task.companyId == user.companyId else { return false }
                guard let taskStart = task.startDate else { return false }
                let taskEnd = task.endDate ?? taskStart

                // Normalize to start-of-day to avoid time-component mismatches
                let taskStartDay = calendar.startOfDay(for: taskStart)
                let taskEndDay = calendar.startOfDay(for: taskEnd)
                let isActiveOnDate = taskStartDay <= dayStart && taskEndDay >= dayStart

                if !isActiveOnDate { return false }

                // Check if member is assigned to this task or its project
                let taskTeamMemberIds = task.getTeamMemberIds()
                let isAssigned = taskTeamMemberIds.contains(memberId)
                    || task.teamMembers.contains(where: { $0.id == memberId })

                if isAssigned { return true }

                // Also check project assignment
                if let project = task.project {
                    let projectTeamMemberIds = project.getTeamMemberIds()
                    return projectTeamMemberIds.contains(memberId)
                        || project.teamMembers.contains(where: { $0.id == memberId })
                }
                return false
            }

            return filteredTasks.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
        } catch {
            return []
        }
    }

    /// Get all scheduled tasks from a date forward where any of the given member IDs are assigned.
    /// Unlike getScheduledTasksForMember(for:memberId:), this checks a date range (not single date)
    /// and accepts multiple member IDs.
    func getScheduledTasksForMembers(memberIds: Set<String>, from startDate: Date) -> [ProjectTask] {
        guard !memberIds.isEmpty else { return [] }
        guard let context = modelContext else { return [] }

        do {
            let allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: startDate)

            return allTasks.filter { task in
                guard task.deletedAt == nil else { return false }
                guard let taskStart = task.startDate else { return false }
                let taskEnd = task.endDate ?? taskStart

                // Task must end on or after our start date
                let taskEndDay = calendar.startOfDay(for: taskEnd)
                guard taskEndDay >= startDay else { return false }

                // Check if any requested member is assigned to this task
                let taskMemberIds = Set(task.getTeamMemberIds())
                return !taskMemberIds.isDisjoint(with: memberIds)
            }.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
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

                if PermissionStore.shared.hasFullAccess("tasks.view") {
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

    @MainActor
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
        
        // Online and needing refresh: sync via SyncEngine then read from local
        do {
            await syncEngine.triggerSync()

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
    
    
    
    @MainActor
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
        await syncEngine.triggerSync()

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
            await syncEngine.triggerSync()
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

        // Use SyncEngine fullSync to refresh all data including company
        await syncEngine.fullSync()
    }
    
    func appDidBecomeActive() {
        if isConnected && isAuthenticated {
            forceSync()
            Task { await syncEngine.triggerSync() }
        }
    }

    func appDidEnterBackground() {
        Task { @MainActor in
            syncEngine.scheduleBackgroundSync()
        }
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
                predicate: #Predicate<User> {
                    $0.companyId == companyId &&
                    $0.deletedAt == nil
                }
            )
            let users = try context.fetch(descriptor).filter { $0.isActive != false }

            if !users.isEmpty {
                return users
            } else if isRunningInPreview {
                // Return sample team members ONLY for SwiftUI previews
                let sampleUsers: [User] = [
                    createSampleUser(id: "1", firstName: "John", lastName: "Doe", role: .crew, companyId: companyId),
                    createSampleUser(id: "2", firstName: "Jane", lastName: "Smith", role: .office, companyId: companyId),
                    createSampleUser(id: "3", firstName: "Michael", lastName: "Johnson", role: .crew, companyId: companyId)
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
    /// Converts from User query since the Company.teamMembers relationship is not populated by sync.
    func getCompanyTeamMembers(companyId: String) -> [TeamMember] {
        let users = getTeamMembers(companyId: companyId)
        if !users.isEmpty {
            return users.map { TeamMember.fromUser($0) }
        }

        // If no users found, trigger a sync if connected
        if isConnected {
            Task {
                await syncEngine.triggerSync()
            }
        }

        return []
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
            
            if !PermissionStore.shared.hasFullAccess("projects.view") {
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

            // Record sync operation for outbound push
            var fields: [String: Any] = [
                "first_name": firstName,
                "last_name": lastName,
                "email": email,
                "phone": phone
            ]
            if let homeAddress = homeAddress {
                fields["home_address"] = homeAddress
            }
            let userId = user.id
            let capturedFields = fields
            await MainActor.run {
                syncEngine.recordOperation(
                    entityType: .user,
                    entityId: userId,
                    operationType: "update",
                    changedFields: capturedFields,
                    priority: 0
                )
            }

            return true
        } catch {
            return false
        }
    }

    /// Request a password reset email via the OPS web API.
    /// The API generates a Firebase reset link and sends a branded email via SendGrid.
    /// - Parameter email: The user's email address
    /// - Returns: Tuple with success flag and optional error message
    func requestPasswordReset(email: String) async -> (Bool, String?) {
        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/auth/reset-password")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[PASSWORD_RESET] Server error: \(errorBody)")
                return (false, "Failed to send reset email. Please try again.")
            }

            return (true, nil)
        } catch {
            print("[PASSWORD_RESET] Network error: \(error)")
            return (false, "Network error. Please check your connection and try again.")
        }
    }
    
    /// Delete the current user's account
    /// - Parameter userId: The ID of the user to delete
    /// - Returns: Tuple of (success, errorMessage)
    @MainActor
    func deleteUserAccount(userId: String) async -> (Bool, String?) {
        do {
            // 1. Soft-delete the user row in Supabase DIRECTLY (not via sync queue).
            //    This must happen BEFORE Firebase deletion because the Supabase client
            //    needs the Firebase JWT (via accessToken callback) to authenticate.
            //    Using the sync queue would fail because logout() clears auth state
            //    before the queued operation can execute.
            do {
                try await SupabaseService.shared.client
                    .from("users")
                    .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
                    .eq("id", value: userId)
                    .execute()
                print("[DELETE_ACCOUNT] User soft-deleted in Supabase")
            } catch {
                print("[DELETE_ACCOUNT] Supabase soft-delete failed: \(error.localizedDescription)")
                // Continue — we still want to delete the Firebase account
            }

            // 2. Remove user from company's seated_employee_ids (best-effort)
            if let companyId = currentUser?.companyId, !companyId.isEmpty {
                do {
                    try await SupabaseService.shared.client
                        .rpc("remove_seated_employee", params: [
                            "p_company_id": companyId,
                            "p_user_id": userId
                        ])
                        .execute()
                    print("[DELETE_ACCOUNT] Removed from seated_employee_ids")
                } catch {
                    print("[DELETE_ACCOUNT] Failed to remove from seated employees (non-fatal): \(error.localizedDescription)")
                }
            }

            // 3. Delete the Firebase Auth account (requires active session)
            do {
                try await FirebaseAuthService.shared.deleteAccount()
                print("[DELETE_ACCOUNT] Firebase Auth account deleted")
            } catch {
                let nsError = error as NSError
                let authErrorCode = AuthErrorCode(rawValue: nsError.code)
                if authErrorCode == .requiresRecentLogin {
                    print("[DELETE_ACCOUNT] Firebase requires re-authentication")
                    return (false, "Please sign out and sign back in, then try deleting your account again.")
                }
                // If Firebase deletion fails, the user row is already soft-deleted in Supabase.
                // The Firebase account will be orphaned but won't map to an active user.
                print("[DELETE_ACCOUNT] Firebase deletion failed (user already soft-deleted in Supabase): \(error.localizedDescription)")
            }

            // 4. Also soft-delete locally so it's consistent
            if let context = modelContext {
                let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
                if let localUser = try? context.fetch(descriptor).first {
                    localUser.deletedAt = Date()
                    try? context.save()
                }
            }

            // 5. Clean up local data and log out
            logout()

            return (true, nil)
        } catch {
            print("[DELETE_ACCOUNT] Failed: \(error.localizedDescription)")
            return (false, "Failed to delete account. Please try again.")
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        print("[DELETE_PROJECT] 🗑️ Soft deleting project '\(projectTitle)' (setting deletedAt)")

        // SOFT DELETE: Set deletedAt timestamp instead of physical deletion
        project.deletedAt = deletionDate
        project.needsSync = true

        // Cascade soft delete to all tasks
        for task in project.tasks where task.deletedAt == nil {
            task.deletedAt = deletionDate
            task.needsSync = true

            // Record delete for each cascaded task
            syncEngine.recordOperation(
                entityType: .projectTask,
                entityId: task.id,
                operationType: "delete",
                changedFields: ["deleted_at": formatter.string(from: deletionDate)]
            )
        }

        // Save changes locally
        try modelContext.save()
        print("[DELETE_PROJECT] ✅ Project '\(projectTitle)' soft deleted locally")

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "delete",
            changedFields: ["deleted_at": formatter.string(from: deletionDate)]
        )
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

        // Record delete for async sync before removing locally
        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: taskId,
            operationType: "delete",
            changedFields: ["id": taskId]
        )

        // Delete from local SwiftData
        modelContext.delete(task)
        try modelContext.save()

        // Update project dates (automatically computed from remaining tasks)
        if updateProject, let project = project {
            try modelContext.save()

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            var dateFields: [String: Any] = [:]
            if let startDate = project.computedStartDate {
                dateFields["start_date"] = formatter.string(from: startDate)
            }
            if let endDate = project.computedEndDate {
                dateFields["end_date"] = formatter.string(from: endDate)
            }

            if !dateFields.isEmpty {
                syncEngine.recordOperation(
                    entityType: .project,
                    entityId: project.id,
                    operationType: "update",
                    changedFields: dateFields
                )
            }
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

        let clientId = client.id

        // Record delete for async sync
        syncEngine.recordOperation(
            entityType: .client,
            entityId: clientId,
            operationType: "delete",
            changedFields: ["id": clientId]
        )

        // Delete client from local SwiftData
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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        print("[RESCHEDULE_PROJECT] 📅 Rescheduling project: \(project.title)")
        print("[RESCHEDULE_PROJECT] Old dates: \(project.startDate?.description ?? "nil") - \(project.endDate?.description ?? "nil")")
        print("[RESCHEDULE_PROJECT] New dates: \(startDate.description) - \(endDate.description)")

        // Apply locally
        project.startDate = startDate
        project.endDate = endDate
        project.needsSync = true

        try modelContext.save()
        print("[RESCHEDULE_PROJECT] ✅ Changes saved locally")

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "update",
            changedFields: [
                "start_date": formatter.string(from: startDate),
                "end_date": formatter.string(from: endDate)
            ]
        )
        print("[RESCHEDULE_PROJECT] ✅ Project reschedule recorded for sync")
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
    @MainActor
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
        let count = syncEngine.pendingOperationCount
        pendingSyncCount = count
        hasPendingSyncs = count > 0
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
        Task { await syncEngine.triggerSync() }
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
            Task { await syncEngine.triggerSync() }
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
    /// - Note: Deprecated — use syncEngine.recordOperation() instead.
    @available(*, deprecated, message: "Use syncEngine.recordOperation() instead of performSyncedOperation")
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

            // Trigger sync via SyncEngine to handle this later
            Task { await syncEngine.triggerSync() }

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

            // Trigger sync via SyncEngine
            Task { await syncEngine.triggerSync() }
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

        // Apply locally
        task.status = newStatus
        task.needsSync = true
        try? modelContext?.save()

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: task.id,
            operationType: "update",
            changedFields: ["status": newStatus.rawValue]
        )

        // Track task status change for analytics
        AnalyticsManager.shared.trackTaskStatusChanged(
            oldStatus: oldStatus.rawValue,
            newStatus: newStatus.rawValue
        )
        AnalyticsService.shared.track(
            eventType: .action,
            eventName: "task_status_changed",
            properties: [
                "old_status": oldStatus.rawValue,
                "new_status": newStatus.rawValue
            ]
        )

        // Track task completion as high-value event
        if newStatus == .completed {
            AnalyticsManager.shared.trackTaskCompleted(taskType: task.taskType?.display)
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "task_completed",
                properties: ["task_type": task.taskType?.display ?? "unknown"]
            )

            // Send task completion notification to all project team members
            if let project = project {
                let projectTeamMemberIds = project.teamMembers.map { $0.id }
                if !projectTeamMemberIds.isEmpty {
                    let taskName = task.displayTitle
                    let projectName = project.title
                    let completedByName = currentUser?.fullName ?? "A team member"
                    let capturedTaskId = task.id
                    let capturedProjectId = project.id
                    let capturedCompanyId = currentUser?.companyId

                    Task {
                        // Create in-app notifications
                        if let companyId = capturedCompanyId {
                            let notifRepo = NotificationRepository()
                            let currentId = UserDefaults.standard.string(forKey: "currentUserId")
                            for memberId in projectTeamMemberIds where memberId != currentId {
                                let dto = NotificationRepository.CreateNotificationDTO(
                                    userId: memberId,
                                    companyId: companyId,
                                    type: "task_completion",
                                    title: "Task Completed",
                                    body: "\(completedByName) completed \"\(taskName)\" on \(projectName)",
                                    projectId: capturedProjectId,
                                    noteId: nil,
                                    expenseId: nil,
                                    batchId: nil,
                                    deepLinkType: "projectDetails"
                                )
                                try? await notifRepo.createNotification(dto)
                            }
                        }
                        // Send push
                        do {
                            try await OneSignalService.shared.notifyTaskCompletion(
                                userIds: projectTeamMemberIds,
                                taskName: taskName,
                                projectName: projectName,
                                taskId: capturedTaskId,
                                projectId: capturedProjectId,
                                completedByName: completedByName
                            )
                        } catch {
                            print("[TASK_STATUS] ⚠️ Failed to send task completion notification: \(error)")
                        }
                    }
                    print("[TASK_STATUS] 📬 Task completion notification queued for \(projectTeamMemberIds.count) project team members")
                }
            }

            // Send dependency completion notifications
            Task {
                await sendDependencyCompletionNotifications(for: task)
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

        // Apply locally
        project.status = newStatus

        // Track completion timestamp
        if newStatus == .completed {
            project.completedAt = Date()
        } else if previousStatus == .completed && newStatus != .completed {
            project.completedAt = nil
        }

        project.needsSync = true
        try? modelContext?.save()

        // Record for async sync — include completedAt when marking complete
        var changedFields: [String: Any] = ["status": newStatus.rawValue]
        if newStatus == .completed {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            changedFields["completed_at"] = formatter.string(from: project.completedAt ?? Date())
        } else if previousStatus == .completed && newStatus != .completed {
            changedFields["completed_at"] = NSNull()
        }

        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "update",
            changedFields: changedFields
        )

        // Track project status change for analytics
        AnalyticsManager.shared.trackProjectStatusChanged(
            oldStatus: previousStatus.rawValue,
            newStatus: newStatus.rawValue
        )
        AnalyticsService.shared.track(
            eventType: .action,
            eventName: "project_status_changed",
            properties: [
                "old_status": previousStatus.rawValue,
                "new_status": newStatus.rawValue
            ]
        )

        // Send push + in-app notification if project was just marked as completed
        if newStatus == .completed && previousStatus != .completed {
            let teamMemberIds = project.getTeamMemberIds()
            if !teamMemberIds.isEmpty {
                let capturedProjectId = project.id
                let capturedProjectName = project.title
                let capturedCompanyId = currentUser?.companyId
                Task {
                    // Create in-app notifications
                    if let companyId = capturedCompanyId {
                        let notifRepo = NotificationRepository()
                        let currentId = UserDefaults.standard.string(forKey: "currentUserId")
                        for memberId in teamMemberIds where memberId != currentId {
                            let dto = NotificationRepository.CreateNotificationDTO(
                                userId: memberId,
                                companyId: companyId,
                                type: "project_completion",
                                title: "Project Completed",
                                body: "\"\(capturedProjectName)\" has been marked as completed",
                                projectId: capturedProjectId,
                                noteId: nil,
                                expenseId: nil,
                                batchId: nil,
                                deepLinkType: "projectDetails"
                            )
                            try? await notifRepo.createNotification(dto)
                        }
                    }
                    // Send push
                    do {
                        try await OneSignalService.shared.notifyProjectCompletion(
                            userIds: teamMemberIds,
                            projectName: capturedProjectName,
                            projectId: capturedProjectId
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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Apply locally
        task.startDate = startDate
        task.endDate = endDate
        let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        task.duration = daysDiff + 1
        task.needsSync = true
        try? modelContext?.save()

        // Notify calendar views to refresh immediately
        DispatchQueue.main.async { [weak self] in
            self?.scheduledTasksDidChange.toggle()
        }

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: task.id,
            operationType: "update",
            changedFields: [
                "start_date": formatter.string(from: startDate),
                "end_date": formatter.string(from: endDate),
                "duration": task.duration
            ]
        )

        // Send schedule change notification if dates actually changed
        let datesChanged = previousStartDate != startDate || previousEndDate != endDate
        if datesChanged, let project = project {
            let teamMemberIds = task.getTeamMemberIds()
            if !teamMemberIds.isEmpty {
                let capturedTaskName = task.displayTitle
                let capturedProjectName = project.title
                let capturedTaskId = task.id
                let capturedProjectId = project.id
                let capturedCompanyId = currentUser?.companyId
                Task {
                    // Create in-app notifications
                    if let companyId = capturedCompanyId {
                        let notifRepo = NotificationRepository()
                        let currentId = UserDefaults.standard.string(forKey: "currentUserId")
                        for memberId in teamMemberIds where memberId != currentId {
                            let dto = NotificationRepository.CreateNotificationDTO(
                                userId: memberId,
                                companyId: companyId,
                                type: "schedule_change",
                                title: "Schedule Update",
                                body: "\"\(capturedTaskName)\" on \(capturedProjectName) has been rescheduled",
                                projectId: capturedProjectId,
                                noteId: nil,
                                expenseId: nil,
                                batchId: nil,
                                deepLinkType: "taskDetails"
                            )
                            try? await notifRepo.createNotification(dto)
                        }
                    }
                    // Send push
                    do {
                        try await OneSignalService.shared.notifyScheduleChange(
                            userIds: teamMemberIds,
                            taskName: capturedTaskName,
                            projectName: capturedProjectName,
                            taskId: capturedTaskId,
                            projectId: capturedProjectId
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

    // MARK: - Push & Cascade Scheduling

    /// Get all active tasks for a project (excludes soft-deleted)
    func getTasksForProject(_ projectId: String) -> [ProjectTask] {
        guard let ctx = modelContext else { return [] }
        let predicate = #Predicate<ProjectTask> { task in
            task.projectId == projectId && task.deletedAt == nil
        }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate, sortBy: [SortDescriptor(\.displayOrder)])
        return (try? ctx.fetch(descriptor)) ?? []
    }

    /// Push a single task by N days (no cascade).
    @MainActor
    func pushTask(_ task: ProjectTask, byDays days: Int, skipWeekends: Bool? = nil) async throws {
        let skip = skipWeekends ?? (getCurrentCompany()?.skipWeekendsInAutoSchedule ?? false)
        let result = SchedulingEngine.pushByDays(task: task, days: days, skipWeekends: skip)
        try await updateTaskSchedule(task: task, startDate: result.newStart, endDate: result.newEnd)
    }

    /// Push a task by N days and cascade to all dependent tasks.
    /// Returns the cascade result so UI can show preview / enable undo.
    @MainActor
    @discardableResult
    func pushTaskWithCascade(_ task: ProjectTask, byDays days: Int) async throws -> SchedulingEngine.CascadeResult {
        let skip = getCurrentCompany()?.skipWeekendsInAutoSchedule ?? false
        let calendar = Calendar.current

        guard let start = task.startDate else {
            throw SchedulingError.noStartDate
        }

        var newStart = calendar.date(byAdding: .day, value: days, to: start)!
        if skip { newStart = SchedulingEngine.pushByDays(task: task, days: days, skipWeekends: true).newStart }
        let newEnd = calendar.date(byAdding: .day, value: max(task.duration - 1, 0), to: newStart)!

        let projectTasks = getTasksForProject(task.projectId)

        let cascade = SchedulingEngine.calculateCascade(
            pushedTaskId: task.id,
            newStartDate: newStart,
            newEndDate: newEnd,
            allProjectTasks: projectTasks,
            skipWeekends: skip
        )

        // Apply the pushed task's new dates
        try await updateTaskSchedule(task: task, startDate: newStart, endDate: newEnd)

        // Apply cascade changes
        for change in cascade.changes {
            if let affectedTask = projectTasks.first(where: { $0.id == change.id }) {
                try await updateTaskSchedule(task: affectedTask, startDate: change.newStartDate, endDate: change.newEndDate)
            }
        }

        return cascade
    }

    /// Undo a cascade by restoring previous dates.
    @MainActor
    func undoCascade(_ cascade: SchedulingEngine.CascadeResult, originalTaskId: String, originalStart: Date, originalEnd: Date) async throws {
        guard let ctx = modelContext else { return }
        // Find the project from the original task
        let predicate = #Predicate<ProjectTask> { $0.id == originalTaskId }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
        guard let originalTask = try ctx.fetch(descriptor).first else { return }

        // Restore original task
        try await updateTaskSchedule(task: originalTask, startDate: originalStart, endDate: originalEnd)

        // Restore cascaded tasks
        let projectTasks = getTasksForProject(originalTask.projectId)
        for change in cascade.changes {
            if let task = projectTasks.first(where: { $0.id == change.id }),
               let oldStart = change.oldStartDate,
               let oldEnd = change.oldEndDate {
                try await updateTaskSchedule(task: task, startDate: oldStart, endDate: oldEnd)
            }
        }
    }

    /// Auto-schedule all unscheduled tasks in a project.
    @MainActor
    func autoScheduleProject(_ project: Project, anchorDate: Date) async throws -> SchedulingEngine.AutoScheduleResult {
        let skip = getCurrentCompany()?.skipWeekendsInAutoSchedule ?? false
        let allTasks = getTasksForProject(project.id)
        let unscheduled = allTasks.filter { $0.startDate == nil || $0.endDate == nil }

        let result = SchedulingEngine.autoSchedule(
            unscheduledTasks: unscheduled,
            allProjectTasks: allTasks,
            anchorDate: anchorDate,
            skipWeekends: skip
        )

        for placement in result.placements {
            if let task = unscheduled.first(where: { $0.id == placement.id }) {
                try await updateTaskSchedule(task: task, startDate: placement.startDate, endDate: placement.endDate)
            }
        }

        return result
    }

    /// Get the current company for the logged-in user.
    private func getCurrentCompany() -> Company? {
        guard let ctx = modelContext, let companyId = currentUser?.companyId else { return nil }
        let predicate = #Predicate<Company> { $0.id == companyId }
        let descriptor = FetchDescriptor<Company>(predicate: predicate)
        return try? ctx.fetch(descriptor).first
    }

    /// Send notifications to dependent task teams when a task is completed
    @MainActor
    private func sendDependencyCompletionNotifications(for completedTask: ProjectTask) async {
        let projectTasks = getTasksForProject(completedTask.projectId)

        for dependentTask in projectTasks {
            guard dependentTask.effectiveDependencies.contains(where: { $0.dependsOnTaskTypeId == completedTask.taskTypeId }) else { continue }

            let recipientIds = dependentTask.teamMemberIdsString
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }

            guard !recipientIds.isEmpty else { continue }

            let projectTitle = dependentTask.project?.title ?? "Project"

            // Create in-app notifications
            if let companyId = currentUser?.companyId {
                let notifRepo = NotificationRepository()
                let currentId = UserDefaults.standard.string(forKey: "currentUserId")
                for memberId in recipientIds where memberId != currentId {
                    let dto = NotificationRepository.CreateNotificationDTO(
                        userId: memberId,
                        companyId: companyId,
                        type: "dependency_completed",
                        title: "Ready to start",
                        body: "\(dependentTask.displayTitle) on \(projectTitle) — \(completedTask.displayTitle) is complete",
                        projectId: dependentTask.projectId,
                        noteId: nil,
                        expenseId: nil,
                        batchId: nil,
                        deepLinkType: "taskDetails"
                    )
                    try? await notifRepo.createNotification(dto)
                }
            }
            // Send push
            do {
                try await OneSignalService.shared.notifyDependencyCompleted(
                    completedTaskTitle: completedTask.displayTitle,
                    dependentTaskTitle: dependentTask.displayTitle,
                    projectTitle: projectTitle,
                    recipientUserIds: recipientIds,
                    projectId: dependentTask.projectId,
                    dependentTaskId: dependentTask.id
                )
                print("[TASK_STATUS] 📬 Dependency notification sent for \(dependentTask.displayTitle)")
            } catch {
                print("[TASK_STATUS] ⚠️ Failed to send dependency notification: \(error)")
            }
        }
    }

    enum SchedulingError: Error, LocalizedError {
        case noStartDate

        var errorDescription: String? {
            switch self {
            case .noStartDate: return "Task has no start date to push from"
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
                task.displayOrder = currentIndex
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
                task.displayOrder = currentIndex
                task.needsSync = true
                tasksToSync.append((task: task, index: currentIndex))
            }
            currentIndex += 1
        }

        print("[TASK_INDEX] ✅ Updated \(allTasks.count) task indices")

        // Save changes locally
        try modelContext?.save()

        // Record task index updates for async sync (use display_order — the actual Supabase column)
        if !tasksToSync.isEmpty {
            print("[TASK_INDEX] 🔄 Recording \(tasksToSync.count) task index updates for sync...")
            for (task, index) in tasksToSync {
                syncEngine.recordOperation(
                    entityType: .projectTask,
                    entityId: task.id,
                    operationType: "update",
                    changedFields: ["display_order": index]
                )
                print("[TASK_INDEX]   ✅ Recorded displayOrder=\(index) for task '\(task.displayTitle)'")
            }
            print("[TASK_INDEX] ✅ Task index updates recorded for sync")
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

        // Apply locally
        task.setTeamMemberIds(memberIds)
        task.teamMembers = teamMemberUsers
        task.needsSync = true
        try? modelContext?.save()
        print("[UPDATE_TASK_TEAM] ✅ Task local state updated (IDs string + relationship)")

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: task.id,
            operationType: "update",
            changedFields: ["team_member_ids": memberIds]
        )

        // Send push + in-app notifications to newly added team members
        if !addedMemberIds.isEmpty {
            let taskName = task.displayTitle
            let projectName = task.project?.title ?? "Project"
            let capturedTaskId = task.id
            let capturedProjectId = task.project?.id ?? ""
            let capturedCompanyId = currentUser?.companyId

            for userId in addedMemberIds {
                Task {
                    // Create in-app notification
                    if let companyId = capturedCompanyId {
                        let dto = NotificationRepository.CreateNotificationDTO(
                            userId: userId,
                            companyId: companyId,
                            type: "task_assignment",
                            title: "New Task Assignment",
                            body: "You've been assigned to \"\(taskName)\" on \(projectName)",
                            projectId: capturedProjectId,
                            noteId: nil,
                            expenseId: nil,
                            batchId: nil,
                            deepLinkType: "taskDetails"
                        )
                        try? await NotificationRepository().createNotification(dto)
                    }
                    // Send push
                    do {
                        try await OneSignalService.shared.notifyTaskAssignment(
                            userId: userId,
                            taskName: taskName,
                            projectName: projectName,
                            taskId: capturedTaskId,
                            projectId: capturedProjectId
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
        // Apply locally
        project.setTeamMemberIds(memberIds)
        project.needsSync = true
        try? modelContext?.save()

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "update",
            changedFields: ["team_member_ids": memberIds]
        )
    }

    // MARK: - Client Operations

    /// Update client - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateClient(client: Client) async throws {
        // Apply locally
        client.needsSync = true
        try? modelContext?.save()

        // Record for async sync
        var changedFields: [String: Any] = [
            "name": client.name
        ]
        if let email = client.email { changedFields["email"] = email }
        if let phone = client.phoneNumber { changedFields["phone_number"] = phone }
        if let address = client.address { changedFields["address"] = address }

        syncEngine.recordOperation(
            entityType: .client,
            entityId: client.id,
            operationType: "update",
            changedFields: changedFields
        )
    }

    // MARK: - ProjectNote Operations

    /// Create a project note locally and record for sync - SINGLE SOURCE OF TRUTH
    @MainActor
    func createProjectNote(note: ProjectNote) {
        note.needsSync = true
        modelContext?.insert(note)
        try? modelContext?.save()

        var changedFields: [String: Any] = [
            "id": note.id,
            "project_id": note.projectId,
            "company_id": note.companyId,
            "author_id": note.authorId,
            "content": note.content
        ]
        if let photoURL = note.photoURL { changedFields["photo_url"] = photoURL }
        if !note.attachments.isEmpty { changedFields["attachments"] = note.attachments }
        if !note.mentionedUserIds.isEmpty { changedFields["mentioned_user_ids"] = note.mentionedUserIds }

        syncEngine.recordOperation(
            entityType: .projectNote,
            entityId: note.id,
            operationType: "create",
            changedFields: changedFields
        )
    }

    /// Update a project note's content locally and record for sync - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateProjectNoteContent(note: ProjectNote, content: String) {
        note.content = content
        note.updatedAt = Date()
        note.needsSync = true
        try? modelContext?.save()

        syncEngine.recordOperation(
            entityType: .projectNote,
            entityId: note.id,
            operationType: "update",
            changedFields: ["content": content]
        )
    }

    /// Soft-delete a project note locally and record for sync - SINGLE SOURCE OF TRUTH
    @MainActor
    func deleteProjectNote(note: ProjectNote) {
        note.deletedAt = Date()
        note.needsSync = true
        try? modelContext?.save()

        syncEngine.recordOperation(
            entityType: .projectNote,
            entityId: note.id,
            operationType: "delete",
            changedFields: ["deleted_at": ISO8601DateFormatter().string(from: note.deletedAt!)]
        )
    }

    // MARK: - Project Details Operations

    /// Update project notes - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateProjectNotes(project: Project, notes: String) async throws {
        // Apply locally
        project.notes = notes
        project.needsSync = true
        try? modelContext?.save()

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "update",
            changedFields: ["notes": notes]
        )
    }

    /// Update project dates - SINGLE SOURCE OF TRUTH
    /// Supports both setting dates (when non-nil) and clearing dates (when nil)
    @MainActor
    func updateProjectDates(project: Project, startDate: Date?, endDate: Date?, clearDates: Bool = false) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Apply locally
        project.startDate = startDate
        project.endDate = endDate
        project.needsSync = true
        try? modelContext?.save()

        // Record for async sync
        var changedFields: [String: Any] = [:]
        if let startDate = startDate {
            changedFields["start_date"] = formatter.string(from: startDate)
        } else {
            changedFields["start_date"] = NSNull()
        }
        if let endDate = endDate {
            changedFields["end_date"] = formatter.string(from: endDate)
        } else {
            changedFields["end_date"] = NSNull()
        }

        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "update",
            changedFields: changedFields
        )
    }

    /// Update project address - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateProjectAddress(project: Project, address: String) async throws {
        // Apply address locally
        project.address = address
        project.needsSync = true

        var changedFields: [String: Any] = ["address": address]

        // Geocode the address to update lat/long for map display
        if !address.isEmpty {
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(address)
                if let location = placemarks.first?.location {
                    project.latitude = location.coordinate.latitude
                    project.longitude = location.coordinate.longitude
                    changedFields["latitude"] = location.coordinate.latitude
                    changedFields["longitude"] = location.coordinate.longitude
                    print("[DataController] ✅ Geocoded address to \(location.coordinate.latitude), \(location.coordinate.longitude)")
                }
            } catch {
                print("[DataController] ⚠️ Geocoding failed for address: \(error.localizedDescription)")
                // Continue without coordinates — address still saves
            }
        } else {
            // Clear coordinates when address is cleared
            project.latitude = nil
            project.longitude = nil
            changedFields["latitude"] = NSNull()
            changedFields["longitude"] = NSNull()
        }

        try? modelContext?.save()

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "update",
            changedFields: changedFields
        )
    }

    // MARK: - Task Operations

    /// Create task - SINGLE SOURCE OF TRUTH
    @MainActor
    func createTask(task: ProjectTask) async throws {
        // Apply locally
        modelContext?.insert(task)
        task.needsSync = true
        try? modelContext?.save()

        // Record for async sync
        var changedFields: [String: Any] = [
            "id": task.id,
            "project_id": task.projectId,
            "status": task.status.rawValue
        ]
        if let notes = task.taskNotes { changedFields["task_notes"] = notes }
        if !task.taskTypeId.isEmpty { changedFields["task_type_id"] = task.taskTypeId }

        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: task.id,
            operationType: "create",
            changedFields: changedFields
        )
    }

    /// Create task from DTO - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.createTask(dto:) calls. Returns the new task ID.
    @MainActor
    func createTask(dto: SupabaseProjectTaskDTO) async throws -> String {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        // Check if task already exists in context (prevents duplicate inserts)
        let taskId = dto.id
        let existingDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { $0.id == taskId }
        )
        let existing = try? context.fetch(existingDescriptor)

        if existing?.isEmpty != false {
            // Convert DTO to model and insert locally
            let task = dto.toModel()
            task.needsSync = true
            context.insert(task)

            // Link to project
            let projectDescriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == dto.projectId })
            if let project = try? context.fetch(projectDescriptor).first {
                task.project = project
            }

            try context.save()
            print("[DataController] ✅ Task created locally from DTO: \(dto.id)")
        } else {
            print("[DataController] ⚠️ Task already exists locally, skipping insert: \(dto.id)")
        }

        // Build the full payload for SyncEngine create
        var changedFields: [String: Any] = [
            "id": dto.id,
            "company_id": dto.companyId,
            "project_id": dto.projectId,
            "status": dto.status
        ]
        if let v = dto.taskTypeId { changedFields["task_type_id"] = v }
        if let v = dto.customTitle { changedFields["custom_title"] = v }
        if let v = dto.taskNotes { changedFields["task_notes"] = v }
        if let v = dto.taskColor { changedFields["task_color"] = v }
        if let v = dto.displayOrder { changedFields["display_order"] = v }
        if let v = dto.teamMemberIds { changedFields["team_member_ids"] = v }
        if let v = dto.startDate { changedFields["start_date"] = v }
        if let v = dto.endDate { changedFields["end_date"] = v }
        if let v = dto.duration { changedFields["duration"] = v }
        if let v = dto.startTime { changedFields["start_time"] = v }
        if let v = dto.endTime { changedFields["end_time"] = v }
        if let v = dto.sourceLineItemId { changedFields["source_line_item_id"] = v }
        if let v = dto.sourceEstimateId { changedFields["source_estimate_id"] = v }

        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: dto.id,
            operationType: "create",
            changedFields: changedFields
        )

        return dto.id
    }

    /// Delete task by ID - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.deleteTask(taskId:) calls.
    @MainActor
    func deleteTask(taskId: String) async throws {
        guard let context = modelContext else { return }

        // Soft delete locally
        let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })
        if let task = try? context.fetch(descriptor).first {
            task.deletedAt = Date()
            task.needsSync = true
            try? context.save()
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: taskId,
            operationType: "delete",
            changedFields: ["deleted_at": formatter.string(from: Date())]
        )

        print("[DataController] Task deleted: \(taskId)")
    }

    // MARK: - Restore Operations (Trash / Undo)

    /// Clear the soft-delete tombstone on a project and push the change.
    /// Used by Settings > Trash to let admins bring back accidentally
    /// deleted projects. Sync op uses NSNull() so PostgREST writes an
    /// actual SQL NULL instead of the string "null".
    @MainActor
    func restoreProject(_ project: Project) async throws {
        project.deletedAt = nil
        project.needsSync = true
        try? modelContext?.save()

        syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "update",
            changedFields: ["deleted_at": NSNull()]
        )
        print("[DataController] Project restored: \(project.id)")
    }

    /// Clear the soft-delete tombstone on a client and push the change.
    @MainActor
    func restoreClient(_ client: Client) async throws {
        client.deletedAt = nil
        client.needsSync = true
        try? modelContext?.save()

        syncEngine.recordOperation(
            entityType: .client,
            entityId: client.id,
            operationType: "update",
            changedFields: ["deleted_at": NSNull()]
        )
        print("[DataController] Client restored: \(client.id)")
    }

    /// Clear the soft-delete tombstone on a task and push the change.
    @MainActor
    func restoreTask(_ task: ProjectTask) async throws {
        task.deletedAt = nil
        task.needsSync = true
        try? modelContext?.save()

        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: task.id,
            operationType: "update",
            changedFields: ["deleted_at": NSNull()]
        )
        print("[DataController] Task restored: \(task.id)")
    }

    /// Update task - SINGLE SOURCE OF TRUTH
    @MainActor
    func updateTask(task: ProjectTask) async throws {
        // Apply locally
        task.needsSync = true
        try? modelContext?.save()

        // Record for async sync
        var changedFields: [String: Any] = [
            "status": task.status.rawValue
        ]
        if let notes = task.taskNotes {
            changedFields["task_notes"] = notes
        }
        let teamMemberIds = task.getTeamMemberIds()
        if !teamMemberIds.isEmpty {
            changedFields["team_member_ids"] = teamMemberIds
        }

        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: task.id,
            operationType: "update",
            changedFields: changedFields
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

            // 4. Record for async sync
            syncEngine.recordOperation(
                entityType: .user,
                entityId: user.id,
                operationType: "update",
                changedFields: ["profile_image_url": s3URL]
            )

            print("[PROFILE_IMAGE] ✅ Recorded profile image URL update for sync")
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

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .user,
            entityId: user.id,
            operationType: "update",
            changedFields: ["profile_image_url": ""]
        )

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

            // 4. Record for async sync
            syncEngine.recordOperation(
                entityType: .company,
                entityId: company.id,
                operationType: "update",
                changedFields: ["logo_url": s3URL]
            )

            print("[COMPANY_LOGO] ✅ Recorded logo URL update for sync")
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

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .company,
            entityId: company.id,
            operationType: "update",
            changedFields: ["logo_url": ""]
        )

        print("[COMPANY_LOGO] ✅ Company logo deleted")
    }

    // MARK: - Company Default Project Color

    /// Update the company's default project color in both local database and server
    @MainActor
    func updateCompanyDefaultProjectColor(companyId: String, color: String) async throws {
        print("[COMPANY_COLOR] Updating default project color to: \(color)")

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .company,
            entityId: companyId,
            operationType: "update",
            changedFields: ["default_project_color": color]
        )

        print("[COMPANY_COLOR] ✅ Default project color update recorded for sync")
    }

    // MARK: - Unassigned Employee Roles Check

    /// Check if there are company users without an assigned employeeType
    /// Returns array of UnassignedUser objects for users needing role assignment
    /// Only returns results for admin/office crew users
    @MainActor
    func checkForUnassignedEmployeeRoles() async -> [UnassignedUser] {
        // Only check for admin or office crew
        guard let user = currentUser,
              PermissionStore.shared.can("team.manage") else {
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
            // Sync users via SyncEngine
            await triggerUsersSync()

            // Read from local SwiftData
            guard let context = modelContext else { return [] }

            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.companyId == companyId }
            )
            let companyUsers = try context.fetch(descriptor)

            // Filter for users with no assigned role — only .unassigned counts
            // Crew is a valid intentional role, not an unassigned state
            let unassignedLocalUsers = companyUsers.filter { localUser in
                localUser.role == .unassigned && localUser.id != user.id
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

    // MARK: - User Field Updates (SyncEngine Migration)

    /// Update user with generic AnyJSON fields - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.updateUserFields() calls throughout the app.
    /// The AnyJSON fields are converted to [String: Any] for SyncEngine recording.
    @MainActor
    func updateUserFields(userId: String, fields: [String: AnyJSON]) async throws {
        guard let context = modelContext else { return }

        // Apply locally — map known AnyJSON fields to local model properties
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
        if let user = try? context.fetch(descriptor).first {
            applyUserFieldsLocally(user: user, fields: fields)
            user.needsSync = true
            try? context.save()
        }

        // Convert AnyJSON fields to [String: Any] for SyncEngine
        let changedFields = anyJSONToDict(fields)

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .user,
            entityId: userId,
            operationType: "update",
            changedFields: changedFields
        )
    }

    /// Apply AnyJSON field values to a local User model
    private func applyUserFieldsLocally(user: User, fields: [String: AnyJSON]) {
        for (key, value) in fields {
            switch key {
            case "first_name":
                if case .string(let v) = value { user.firstName = v }
            case "last_name":
                if case .string(let v) = value { user.lastName = v }
            case "phone":
                if case .string(let v) = value { user.phone = v }
            case "email":
                if case .string(let v) = value { user.email = v }
            case "home_address":
                if case .string(let v) = value { user.homeAddress = v }
            case "role":
                if case .string(let v) = value { user.role = UserRole(rawValue: v) ?? user.role }
            case "user_color":
                if case .string(let v) = value { user.userColor = v }
            case "is_active":
                if case .bool(let v) = value { user.isActive = v }
            case "has_completed_tutorial":
                if case .bool(let v) = value { user.hasCompletedAppTutorial = v }
            case "profile_image_url":
                if case .string(let v) = value { user.profileImageURL = v }
            case "emergency_contact_name":
                if case .string(let v) = value { user.emergencyContactName = v }
            case "emergency_contact_phone":
                if case .string(let v) = value { user.emergencyContactPhone = v }
            case "emergency_contact_relationship":
                if case .string(let v) = value { user.emergencyContactRelationship = v }
            default:
                // Unknown fields are still sent to the server via SyncEngine
                break
            }
        }
    }

    // MARK: - Company Field Updates (SyncEngine Migration)

    /// Update company with generic string fields - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.updateCompanyFields() calls.
    @MainActor
    func updateCompanyFields(companyId: String, fields: [String: String]) async throws {
        guard let context = modelContext else { return }

        // Apply locally
        let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyId })
        if let company = try? context.fetch(descriptor).first {
            for (key, value) in fields {
                switch key {
                case "name": company.name = value
                case "phone": company.phone = value
                case "email": company.email = value
                case "address": company.address = value
                case "website": company.website = value
                case "description": company.companyDescription = value
                case "default_project_color": company.defaultProjectColor = value
                default: break
                }
            }
            company.needsSync = true
            try? context.save()
        }

        // Convert to [String: Any] for SyncEngine
        let changedFields: [String: Any] = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value as Any) })

        syncEngine.recordOperation(
            entityType: .company,
            entityId: companyId,
            operationType: "update",
            changedFields: changedFields
        )
    }

    /// Update company seated employees - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.updateCompanySeatedEmployees() calls.
    @MainActor
    func updateCompanySeatedEmployees(companyId: String, userIds: [String]) async throws {
        guard let context = modelContext else { return }

        // Apply locally
        let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyId })
        if let company = try? context.fetch(descriptor).first {
            company.seatedEmployeeIds = userIds.joined(separator: ",")
            company.needsSync = true
            try? context.save()
        }

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .company,
            entityId: companyId,
            operationType: "update",
            changedFields: ["seated_employee_ids": userIds]
        )

        // Refresh subscription status so the UI reflects the new seat assignments immediately
        await SubscriptionManager.shared.checkSubscriptionStatus()
    }

    // MARK: - Generic Project Field Updates (SyncEngine Migration)

    /// Update project with generic AnyJSON fields - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.updateProjectFields() calls.
    /// For known fields, it applies optimistic local updates.
    @MainActor
    func updateProjectFields(projectId: String, fields: [String: AnyJSON]) async throws {
        guard let context = modelContext else { return }

        // Apply locally for known fields
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        if let project = try? context.fetch(descriptor).first {
            applyProjectFieldsLocally(project: project, fields: fields)
            project.needsSync = true
            try? context.save()
        }

        // Convert AnyJSON to [String: Any]
        let changedFields = anyJSONToDict(fields)

        syncEngine.recordOperation(
            entityType: .project,
            entityId: projectId,
            operationType: "update",
            changedFields: changedFields
        )
    }

    /// Apply AnyJSON field values to a local Project model
    private func applyProjectFieldsLocally(project: Project, fields: [String: AnyJSON]) {
        for (key, value) in fields {
            switch key {
            case "title":
                if case .string(let v) = value { project.title = v }
            case "status":
                if case .string(let v) = value { project.status = Status(rawValue: v) ?? project.status }
            case "address":
                if case .string(let v) = value { project.address = v }
            case "notes":
                if case .string(let v) = value { project.notes = v }
            case "description":
                if case .string(let v) = value { project.projectDescription = v }
            case "client_id":
                if case .string(let v) = value { project.clientId = v }
            default:
                break
            }
        }
    }

    // MARK: - Generic Task Field Updates (SyncEngine Migration)

    /// Update task with generic AnyJSON fields - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.updateTaskFields() calls.
    @MainActor
    func updateTaskFields(taskId: String, fields: [String: AnyJSON]) async throws {
        guard let context = modelContext else { return }

        // Apply locally for known fields
        let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == taskId })
        if let task = try? context.fetch(descriptor).first {
            applyTaskFieldsLocally(task: task, fields: fields)
            task.needsSync = true
            try? context.save()
        }

        // Convert AnyJSON to [String: Any]
        let changedFields = anyJSONToDict(fields)

        syncEngine.recordOperation(
            entityType: .projectTask,
            entityId: taskId,
            operationType: "update",
            changedFields: changedFields
        )
    }

    /// Apply AnyJSON field values to a local ProjectTask model
    private func applyTaskFieldsLocally(task: ProjectTask, fields: [String: AnyJSON]) {
        for (key, value) in fields {
            switch key {
            case "status":
                if case .string(let v) = value { task.status = TaskStatus(rawValue: v) ?? task.status }
            case "task_notes":
                if case .string(let v) = value { task.taskNotes = v }
            case "custom_title":
                if case .string(let v) = value { task.customTitle = v }
            case "task_color":
                if case .string(let v) = value { task.taskColor = v }
            case "team_member_ids":
                if case .string(let v) = value { task.teamMemberIdsString = v }
            case "display_order":
                if case .integer(let v) = value { task.displayOrder = v }
            default:
                break
            }
        }
    }

    // MARK: - Create Operations (SyncEngine Migration)

    /// Create a new project - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.createProject(dto:) calls.
    /// Returns the new project ID.
    @MainActor
    func createProject(dto: SupabaseProjectDTO) async throws -> String {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Check if project already exists in context (prevents duplicate inserts)
        let projectId = dto.id
        let existingDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == projectId }
        )
        let existing = try? context.fetch(existingDescriptor)

        if existing?.isEmpty != false {
            // Create local model from DTO
            let project = Project(id: dto.id, title: dto.title, status: Status(rawValue: dto.status) ?? .rfq)
            project.companyId = dto.companyId
            project.clientId = dto.clientId
            project.opportunityId = dto.opportunityId
            project.address = dto.address
            project.latitude = dto.latitude
            project.longitude = dto.longitude
            project.notes = dto.notes
            project.projectDescription = dto.description
            project.allDay = dto.allDay ?? true
            project.duration = dto.duration ?? 1
            if let startStr = dto.startDate { project.startDate = formatter.date(from: startStr) }
            if let endStr = dto.endDate { project.endDate = formatter.date(from: endStr) }
            if let memberIds = dto.teamMemberIds { project.setTeamMemberIds(memberIds) }
            if let images = dto.projectImages { project.projectImagesString = images.joined(separator: ",") }
            project.needsSync = true

            // Insert locally
            context.insert(project)
            try context.save()

            print("[DataController] ✅ Project created locally: \(dto.id)")
        } else {
            print("[DataController] ⚠️ Project already exists locally, skipping insert: \(dto.id)")
        }

        // Build the full payload for SyncEngine create
        var changedFields: [String: Any] = [
            "id": dto.id,
            "company_id": dto.companyId,
            "title": dto.title,
            "status": dto.status
        ]
        if let v = dto.clientId { changedFields["client_id"] = v }
        if let v = dto.opportunityId { changedFields["opportunity_id"] = v }
        if let v = dto.address { changedFields["address"] = v }
        if let v = dto.latitude { changedFields["latitude"] = v }
        if let v = dto.longitude { changedFields["longitude"] = v }
        if let v = dto.notes { changedFields["notes"] = v }
        if let v = dto.description { changedFields["description"] = v }
        if let v = dto.startDate { changedFields["start_date"] = v }
        if let v = dto.endDate { changedFields["end_date"] = v }
        if let v = dto.duration { changedFields["duration"] = v }
        if let v = dto.allDay { changedFields["all_day"] = v }
        if let v = dto.teamMemberIds { changedFields["team_member_ids"] = v }
        if let v = dto.projectImages { changedFields["project_images"] = v }

        syncEngine.recordOperation(
            entityType: .project,
            entityId: dto.id,
            operationType: "create",
            changedFields: changedFields
        )

        return dto.id
    }

    /// Create a new client - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.createClient(dto:) calls.
    /// Returns the new client ID.
    @MainActor
    func createClient(dto: SupabaseClientDTO) async throws -> String {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        // Check if client already exists in context (prevents duplicate inserts)
        let clientId = dto.id
        let existingDescriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { $0.id == clientId }
        )
        let existing = try? context.fetch(existingDescriptor)

        if existing?.isEmpty != false {
            // Create local model
            let client = Client(id: dto.id, name: dto.name, email: dto.email, phoneNumber: dto.phoneNumber, address: dto.address, companyId: dto.companyId, notes: dto.notes)
            client.latitude = dto.latitude
            client.longitude = dto.longitude
            client.profileImageURL = dto.profileImageUrl
            client.needsSync = true

            // Insert locally
            context.insert(client)
            try context.save()

            print("[DataController] ✅ Client created locally: \(dto.id)")
        } else {
            print("[DataController] ⚠️ Client already exists locally, skipping insert: \(dto.id)")
        }

        // Build payload for SyncEngine create
        var changedFields: [String: Any] = [
            "id": dto.id,
            "company_id": dto.companyId,
            "name": dto.name
        ]
        if let v = dto.email { changedFields["email"] = v }
        if let v = dto.phoneNumber { changedFields["phone_number"] = v }
        if let v = dto.address { changedFields["address"] = v }
        if let v = dto.latitude { changedFields["latitude"] = v }
        if let v = dto.longitude { changedFields["longitude"] = v }
        if let v = dto.notes { changedFields["notes"] = v }
        if let v = dto.profileImageUrl { changedFields["profile_image_url"] = v }

        syncEngine.recordOperation(
            entityType: .client,
            entityId: dto.id,
            operationType: "create",
            changedFields: changedFields
        )

        return dto.id
    }

    /// Create a new task type - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.createTaskType(dto:) calls.
    /// Returns the new task type ID.
    @MainActor
    func createTaskType(dto: SupabaseTaskTypeDTO) async throws -> String {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        // Check if task type already exists in context (prevents duplicate inserts)
        let taskTypeId = dto.id
        let existingDescriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { $0.id == taskTypeId }
        )
        let existing = try? context.fetch(existingDescriptor)

        if existing?.isEmpty != false {
            // Create local model
            let taskType = TaskType(
                id: dto.id,
                display: dto.display,
                color: dto.color,
                companyId: dto.companyId,
                isDefault: dto.isDefault ?? false,
                icon: dto.icon
            )
            taskType.displayOrder = dto.displayOrder ?? 0
            if let deps = dto.dependencies,
               let jsonData = try? JSONEncoder().encode(deps),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                taskType.dependenciesJSON = jsonStr
            }
            taskType.needsSync = true

            // Insert locally
            context.insert(taskType)
            try context.save()

            print("[DataController] ✅ Task type created locally: \(dto.id)")
        } else {
            print("[DataController] ⚠️ Task type already exists locally, skipping insert: \(dto.id)")
        }

        // Build payload for SyncEngine create
        var changedFields: [String: Any] = [
            "id": dto.id,
            "company_id": dto.companyId,
            "display": dto.display,
            "color": dto.color
        ]
        if let v = dto.icon { changedFields["icon"] = v }
        if let v = dto.isDefault { changedFields["is_default"] = v }
        if let v = dto.displayOrder { changedFields["display_order"] = v }
        if let v = dto.defaultTeamMemberIds { changedFields["default_team_member_ids"] = v }
        if let deps = dto.dependencies,
           let jsonData = try? JSONEncoder().encode(deps),
           let jsonArr = try? JSONSerialization.jsonObject(with: jsonData) {
            changedFields["dependencies"] = jsonArr
        }

        syncEngine.recordOperation(
            entityType: .taskType,
            entityId: dto.id,
            operationType: "create",
            changedFields: changedFields
        )

        return dto.id
    }

    /// Delete a task type - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.deleteTaskType(taskTypeId:) calls.
    @MainActor
    func deleteTaskType(taskTypeId: String) async throws {
        guard let context = modelContext else { return }

        let deletionDate = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Soft delete locally and cascade to associated tasks
        let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == taskTypeId })
        if let taskType = try? context.fetch(descriptor).first {
            // Cascade soft delete to all tasks that belong to this task type
            for task in taskType.tasks where task.deletedAt == nil {
                task.deletedAt = deletionDate
                task.needsSync = true

                syncEngine.recordOperation(
                    entityType: .projectTask,
                    entityId: task.id,
                    operationType: "delete",
                    changedFields: ["deleted_at": formatter.string(from: deletionDate)]
                )
            }

            taskType.deletedAt = deletionDate
            taskType.needsSync = true
            try? context.save()
        }

        // Record for async sync
        syncEngine.recordOperation(
            entityType: .taskType,
            entityId: taskTypeId,
            operationType: "delete",
            changedFields: ["deleted_at": formatter.string(from: deletionDate)]
        )

        print("[DataController] ✅ Task type deleted: \(taskTypeId)")
    }

    // MARK: - SubClient Operations (SyncEngine Migration)

    /// Create a new sub-client - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.createSubClient() calls.
    @MainActor
    func createSubClient(clientId: String, name: String, title: String?, email: String?, phone: String?, address: String?, companyId: String) async throws -> SubClient {
        guard let context = modelContext else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model context not available"])
        }

        // Generate ID locally
        let subClientId = UUID().uuidString

        // Create local model
        let subClient = SubClient(id: subClientId, name: name)
        subClient.title = title
        subClient.email = email
        subClient.phoneNumber = phone
        subClient.address = address
        subClient.needsSync = true

        // Link to parent client
        let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        if let parentClient = try? context.fetch(clientDescriptor).first {
            subClient.client = parentClient
        }

        context.insert(subClient)
        try context.save()

        print("[DataController] ✅ Sub-client created locally: \(subClientId)")

        // Build payload for SyncEngine create
        var changedFields: [String: Any] = [
            "id": subClientId,
            "client_id": clientId,
            "company_id": companyId,
            "name": name
        ]
        if let v = title, !v.isEmpty { changedFields["title"] = v }
        if let v = email, !v.isEmpty { changedFields["email"] = v }
        if let v = phone, !v.isEmpty { changedFields["phone_number"] = v }
        if let v = address, !v.isEmpty { changedFields["address"] = v }

        syncEngine.recordOperation(
            entityType: .subClient,
            entityId: subClientId,
            operationType: "create",
            changedFields: changedFields
        )

        return subClient
    }

    /// Edit an existing sub-client - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.editSubClient() calls.
    @MainActor
    func editSubClient(subClientId: String, name: String, title: String?, email: String?, phone: String?, address: String?) async throws {
        guard let context = modelContext else { return }

        // Update locally
        let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == subClientId })
        guard let subClient = try? context.fetch(descriptor).first else {
            throw NSError(domain: "DataController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sub-client not found"])
        }

        subClient.name = name
        subClient.title = title
        subClient.email = email
        subClient.phoneNumber = phone
        subClient.address = address
        subClient.updatedAt = Date()
        subClient.needsSync = true
        try? context.save()

        // Build changed fields
        var changedFields: [String: Any] = ["name": name]
        if let v = title { changedFields["title"] = v }
        if let v = email { changedFields["email"] = v }
        if let v = phone { changedFields["phone_number"] = v }
        if let v = address { changedFields["address"] = v }

        syncEngine.recordOperation(
            entityType: .subClient,
            entityId: subClientId,
            operationType: "update",
            changedFields: changedFields
        )

        print("[DataController] ✅ Sub-client updated: \(subClientId)")
    }

    /// Delete a sub-client - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.deleteSubClient() calls.
    @MainActor
    func deleteSubClient(subClientId: String) async throws {
        guard let context = modelContext else { return }

        // Soft delete locally
        let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == subClientId })
        if let subClient = try? context.fetch(descriptor).first {
            subClient.deletedAt = Date()
            subClient.needsSync = true
            try? context.save()
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        syncEngine.recordOperation(
            entityType: .subClient,
            entityId: subClientId,
            operationType: "delete",
            changedFields: ["deleted_at": formatter.string(from: Date())]
        )

        print("[DataController] ✅ Sub-client deleted: \(subClientId)")
    }

    // MARK: - Client Contact Update (SyncEngine Migration)

    /// Update client contact information - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.updateClientContact() calls.
    @MainActor
    func updateClientContact(clientId: String, name: String, email: String?, phone: String?, address: String?) async throws {
        guard let context = modelContext else { return }

        // Apply locally
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        if let client = try? context.fetch(descriptor).first {
            client.name = name
            client.email = email
            client.phoneNumber = phone
            client.address = address
            client.needsSync = true
            try? context.save()
        }

        // Build changed fields
        var changedFields: [String: Any] = ["name": name]
        if let v = email { changedFields["email"] = v }
        if let v = phone { changedFields["phone_number"] = v }
        if let v = address { changedFields["address"] = v }

        syncEngine.recordOperation(
            entityType: .client,
            entityId: clientId,
            operationType: "update",
            changedFields: changedFields
        )
    }

    // MARK: - User Delete (SyncEngine Migration)

    /// Delete a user (soft delete) - SINGLE SOURCE OF TRUTH
    /// This replaces syncManager.deleteUser() calls.
    @MainActor
    func deleteUser(userId: String) async throws {
        guard let context = modelContext else { return }

        // Soft delete locally
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userId })
        if let user = try? context.fetch(descriptor).first {
            user.deletedAt = Date()
            user.needsSync = true
            try? context.save()
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        syncEngine.recordOperation(
            entityType: .user,
            entityId: userId,
            operationType: "delete",
            changedFields: ["deleted_at": formatter.string(from: Date())]
        )

        print("[DataController] ✅ User deleted: \(userId)")
    }

    // MARK: - Single-User Fetch (replaces syncManager.fetchUser)

    /// Fetch a single user from Supabase by ID, upsert into SwiftData, and return the local model.
    /// Returns nil if the fetch fails or the repository cannot be constructed.
    @MainActor
    func fetchAndUpsertUser(id: String) async throws -> User? {
        guard let companyId = currentUser?.companyId ?? UserDefaults.standard.string(forKey: "company_id"),
              !companyId.isEmpty else {
            print("[DATA_CONTROLLER] Cannot fetch user — no companyId")
            return nil
        }
        guard let context = modelContext else {
            print("[DATA_CONTROLLER] Cannot fetch user — no modelContext")
            return nil
        }

        let repo = UserRepository(companyId: companyId)
        let dto = try await repo.fetchOne(id)
        let model = dto.toModel()
        model.lastSyncedAt = Date()
        model.needsSync = false

        // Upsert: update existing or insert new
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.firstName = model.firstName
            existing.lastName = model.lastName
            if let email = model.email { existing.email = email }
            existing.phone = model.phone
            existing.homeAddress = model.homeAddress
            existing.profileImageURL = model.profileImageURL
            existing.userColor = model.userColor
            existing.role = model.role
            existing.userType = model.userType
            existing.hasCompletedAppOnboarding = model.hasCompletedAppOnboarding
            existing.hasCompletedAppTutorial = model.hasCompletedAppTutorial
            existing.devPermission = model.devPermission
            existing.latitude = model.latitude
            existing.longitude = model.longitude
            existing.locationName = model.locationName
            existing.isActive = model.isActive
            existing.deletedAt = model.deletedAt
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            context.insert(model)
        }
        try context.save()

        return try context.fetch(descriptor).first
    }

    /// Add a user ID to the non-existent users cache
    func addNonExistentUserId(_ userId: String) {
        nonExistentUserIds.insert(userId)
    }

    /// Check if a user ID is in the non-existent users cache
    func isNonExistentUser(_ userId: String) -> Bool {
        nonExistentUserIds.contains(userId)
    }

    // MARK: - Permission Scope Data Purge

    /// Purges locally-cached data the user no longer has permission to see
    /// after a scope contraction (e.g., "all" -> "assigned").
    /// Also cancels any pending SyncOperations for purged entities.
    @MainActor
    func purgeNonPermittedData() async {
        guard let context = modelContext else {
            print("[DataController] purgeNonPermittedData — no modelContext")
            return
        }
        guard let userId = currentUser?.id else {
            print("[DataController] purgeNonPermittedData — no currentUser")
            return
        }

        let projectScope = PermissionStore.shared.scope(for: "projects.view") ?? "all"
        let taskScope = PermissionStore.shared.scope(for: "tasks.view") ?? "all"

        var purgedProjects = 0
        var purgedTasks = 0
        var purgedClients = 0

        // Purge projects the user can no longer see
        if projectScope == "assigned" || projectScope == "own" {
            let allProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            for project in allProjects {
                var shouldPurge = false
                if projectScope == "assigned" {
                    let teamIds = project.getTeamMemberIds()
                    shouldPurge = !teamIds.contains(userId)
                } else if projectScope == "own" {
                    // Without a createdBy property, fall back to team membership check
                    let teamIds = project.getTeamMemberIds()
                    shouldPurge = !teamIds.contains(userId)
                }

                if shouldPurge {
                    let projectId = project.id

                    // Delete associated ProjectNote records
                    let notePredicate = #Predicate<ProjectNote> { $0.projectId == projectId }
                    if let notes = try? context.fetch(FetchDescriptor(predicate: notePredicate)) {
                        for note in notes { context.delete(note) }
                    }

                    // Delete associated LocalPhoto records
                    let photoPredicate = #Predicate<LocalPhoto> {
                        $0.entityType == "project" && $0.entityId == projectId
                    }
                    if let photos = try? context.fetch(FetchDescriptor(predicate: photoPredicate)) {
                        for photo in photos { context.delete(photo) }
                    }

                    // Delete associated PhotoAnnotation records
                    let annotationPredicate = #Predicate<PhotoAnnotation> { $0.projectId == projectId }
                    if let annotations = try? context.fetch(FetchDescriptor(predicate: annotationPredicate)) {
                        for annotation in annotations { context.delete(annotation) }
                    }

                    // Cancel pending SyncOperations for this project
                    let predicate = #Predicate<SyncOperation> {
                        $0.entityId == projectId && $0.status == "pending"
                    }
                    if let ops = try? context.fetch(FetchDescriptor(predicate: predicate)) {
                        for op in ops { context.delete(op) }
                    }
                    context.delete(project)
                    purgedProjects += 1
                }
            }
        }

        // Purge tasks the user can no longer see
        if taskScope == "assigned" || taskScope == "own" {
            let allTasks = (try? context.fetch(FetchDescriptor<ProjectTask>())) ?? []
            for task in allTasks {
                var shouldPurge = false
                if taskScope == "assigned" {
                    let teamIds = task.getTeamMemberIds()
                    shouldPurge = !teamIds.contains(userId)
                } else if taskScope == "own" {
                    let teamIds = task.getTeamMemberIds()
                    shouldPurge = !teamIds.contains(userId)
                }

                if shouldPurge {
                    // Cancel pending SyncOperations for this task
                    let taskId = task.id
                    let predicate = #Predicate<SyncOperation> {
                        $0.entityId == taskId && $0.status == "pending"
                    }
                    if let ops = try? context.fetch(FetchDescriptor(predicate: predicate)) {
                        for op in ops { context.delete(op) }
                    }
                    context.delete(task)
                    purgedTasks += 1
                }
            }
        }

        // Purge clients the user can no longer see.
        // Client has no createdBy field, so both "assigned" and "own" scopes use the same
        // logic: purge any client that has no locally-remaining (non-deleted) projects.
        // This runs after the project purge so that already-purged projects are gone.
        let clientScope = PermissionStore.shared.scope(for: "clients.view") ?? "all"
        if clientScope == "assigned" || clientScope == "own" {
            let allClients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
            for client in allClients {
                // A client is permitted as long as at least one of its projects survived the purge
                let hasPermittedProject = client.projects.contains { $0.deletedAt == nil }
                if !hasPermittedProject {
                    let clientId = client.id
                    let predicate = #Predicate<SyncOperation> {
                        $0.entityId == clientId && $0.status == "pending"
                    }
                    if let ops = try? context.fetch(FetchDescriptor(predicate: predicate)) {
                        for op in ops { context.delete(op) }
                    }
                    context.delete(client)
                    purgedClients += 1
                }
            }
        }

        if purgedProjects > 0 || purgedTasks > 0 || purgedClients > 0 {
            try? context.save()
            print("[DataController] purgeNonPermittedData — purged \(purgedProjects) projects, \(purgedTasks) tasks, \(purgedClients) clients")
        } else {
            print("[DataController] purgeNonPermittedData — nothing to purge")
        }
    }

    // MARK: - Inbound Sync Triggers (SyncEngine Migration)

    /// Trigger a full sync via SyncEngine - replaces syncManager.syncAll()
    @MainActor
    func triggerFullSync() async {
        await syncEngine.fullSync()
    }

    /// Trigger a background sync via SyncEngine - replaces syncManager.triggerBackgroundSync()
    @MainActor
    func triggerBackgroundSync() {
        Task {
            await syncEngine.triggerSync()
        }
    }

    /// Trigger a company data refresh via SyncEngine - replaces syncManager.syncCompany()
    @MainActor
    func triggerCompanySync() async {
        await syncEngine.triggerSync()
    }

    /// Trigger a users sync via SyncEngine - replaces syncManager.syncUsers()
    @MainActor
    func triggerUsersSync() async {
        await syncEngine.triggerSync()
    }

    /// Trigger team members sync - replaces syncManager.syncCompanyTeamMembers()
    @MainActor
    func triggerTeamMembersSync(companyId: String) async {
        await syncEngine.triggerSync()
    }

    /// Trigger task types sync - replaces syncManager.syncCompanyTaskTypes()
    @MainActor
    func triggerTaskTypesSync(companyId: String) async {
        await syncEngine.triggerSync()
    }

    /// Trigger tasks sync - replaces syncManager.syncTasks()
    @MainActor
    func triggerTasksSync() async {
        await syncEngine.triggerSync()
    }

    /// Trigger onboarding sync - replaces syncManager.performOnboardingSync()
    @MainActor
    func performOnboardingSync() async {
        // Re-configure SyncEngine in case companyId just changed during onboarding
        syncEngine.reconfigureForCompany()
        await syncEngine.fullSync()
    }

    /// Trigger manual full sync - replaces syncManager.manualFullSync()
    @MainActor
    func triggerManualFullSync() async {
        await syncEngine.fullSync()
    }

    /// Trigger project tasks sync - replaces syncManager.syncProjectTasks(projectId:)
    @MainActor
    func triggerProjectTasksSync(projectId: String) async {
        await syncEngine.triggerSync()
    }

    /// Refresh a single client's data - replaces syncManager.refreshSingleClient(clientId:)
    @MainActor
    func refreshSingleClient(clientId: String) async throws {
        await syncEngine.triggerSync()
    }

    // MARK: - AnyJSON Conversion Helper

    /// Convert [String: AnyJSON] to [String: Any] for SyncEngine payload serialization
    private func anyJSONToDict(_ fields: [String: AnyJSON]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in fields {
            switch value {
            case .string(let v): result[key] = v
            case .integer(let v): result[key] = v
            case .double(let v): result[key] = v
            case .bool(let v): result[key] = v
            case .null: result[key] = NSNull()
            case .array(let arr):
                result[key] = arr.map { anyJSONToAny($0) }
            case .object(let obj):
                var dict: [String: Any] = [:]
                for (k, v) in obj { dict[k] = anyJSONToAny(v) }
                result[key] = dict
            @unknown default:
                result[key] = "\(value)"
            }
        }
        return result
    }

    /// Convert a single AnyJSON value to Any
    private func anyJSONToAny(_ value: AnyJSON) -> Any {
        switch value {
        case .string(let v): return v
        case .integer(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        case .array(let arr): return arr.map { anyJSONToAny($0) }
        case .object(let obj):
            var dict: [String: Any] = [:]
            for (k, v) in obj { dict[k] = anyJSONToAny(v) }
            return dict
        @unknown default: return "\(value)"
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

// MARK: - ScheduleDataProvider Conformance

extension DataController: ScheduleDataProvider {
    func tasksForProject(_ projectId: String) -> [any SchedulableTask] {
        getTasksForProject(projectId)
    }

    func allScheduledTasksForMembers(_ memberIds: Set<String>, from date: Date) -> [any SchedulableTask] {
        getScheduledTasksForMembers(memberIds: memberIds, from: date)
    }

    func coordinatesForProject(_ projectId: String) -> (lat: Double, lng: Double)? {
        guard let context = modelContext else { return nil }
        guard let project = (try? context.fetch(FetchDescriptor<Project>()))?.first(where: { $0.id == projectId }) else { return nil }
        guard let lat = project.latitude, let lng = project.longitude,
              !(lat == 0 && lng == 0) else { return nil }
        return (lat, lng)
    }

    func priorityDateForProject(_ projectId: String) -> Date? {
        guard let context = modelContext else { return nil }

        // 1. Try won date from StageTransition
        if let allTransitions = try? context.fetch(FetchDescriptor<StageTransition>()),
           let opportunities = try? context.fetch(FetchDescriptor<Opportunity>()) {
            if let opp = opportunities.first(where: { $0.projectId == projectId }) {
                if let wonTransition = allTransitions.first(where: { $0.opportunityId == opp.id && $0.toStage == .won }) {
                    return wonTransition.createdAt
                }
            }
        }

        // 2. Fallback: estimate approved date
        if let allEstimates = try? context.fetch(FetchDescriptor<Estimate>()) {
            let approved = allEstimates
                .filter { $0.projectId == projectId && $0.status == .approved }
                .sorted { $0.updatedAt < $1.updatedAt }
            if let estimate = approved.first {
                return estimate.updatedAt
            }
        }

        // 3. Fallback: project start date
        if let allProjects = try? context.fetch(FetchDescriptor<Project>()),
           let project = allProjects.first(where: { $0.id == projectId }) {
            return project.startDate
        }

        return nil
    }
}

// MARK: - AutoScheduleManager Convenience

extension DataController {
    /// Build a ScheduleRequest with current company constraints
    func buildScheduleConstraints() -> ScheduleConstraints {
        ScheduleConstraints.from(company: getCurrentCompany())
    }

    /// Auto-schedule a single task using the centralized manager
    func autoScheduleSingleTask(
        _ task: any SchedulableTask,
        teamMemberIds: Set<String>,
        anchorDate: Date = Date()
    ) -> SchedulePlan {
        let constraints = buildScheduleConstraints()
        let request = ScheduleRequest(
            mode: .single(task: task, teamMemberIds: teamMemberIds),
            anchorDate: anchorDate,
            constraints: constraints
        )
        return AutoScheduleManager.schedule(request: request, provider: self)
    }

    /// Auto-schedule all unscheduled tasks in a project
    func autoScheduleProjectV2(_ projectId: String, anchorDate: Date = Date()) -> SchedulePlan {
        let constraints = buildScheduleConstraints()
        let request = ScheduleRequest(
            mode: .projectBatch(projectId: projectId),
            anchorDate: anchorDate,
            constraints: constraints
        )
        return AutoScheduleManager.schedule(request: request, provider: self)
    }

    /// Auto-schedule across multiple projects
    func autoScheduleProjects(_ projectIds: [String], anchorDate: Date = Date()) -> SchedulePlan {
        let constraints = buildScheduleConstraints()
        let request = ScheduleRequest(
            mode: .multiProjectBatch(projectIds: projectIds),
            anchorDate: anchorDate,
            constraints: constraints
        )
        return AutoScheduleManager.schedule(request: request, provider: self)
    }
}
