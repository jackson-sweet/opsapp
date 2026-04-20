//
//  OPSApp.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI
import SwiftData
import UserNotifications
import MapboxMaps
import CoreSpotlight

@main
struct OPSApp: App {
    // Register AppDelegate for handling remote notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        MapboxConfig.configure()
        AnalyticsService.shared.start()
    }
    
    // Observe scene phase for app lifecycle events
    @Environment(\.scenePhase) private var scenePhase

    // Setup shared instances for app-wide use
    @StateObject private var dataController = DataController()
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var variantManager = OnboardingVariantManager.shared
    @StateObject private var permissionStore = PermissionStore.shared

    // Create the model container for SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Core data models
            User.self,
            Project.self,
            Company.self,
            TeamMember.self,
            Client.self,
            SubClient.self,
            ProjectTask.self,
            TaskType.self,
            TaskStatusOption.self,
            SyncOperation.self,
            OpsContact.self,
            // Supabase-backed models
            Opportunity.self,
            Activity.self,
            FollowUp.self,
            StageTransition.self,
            Estimate.self,
            EstimateLineItem.self,
            Invoice.self,
            InvoiceLineItem.self,
            Payment.self,
            Product.self,
            SiteVisit.self,
            ProjectNote.self,
            PhotoAnnotation.self,
            CalendarUserEvent.self,
            // Offline-first sync models
            TimeEntry.self,
            SignatureCapture.self,
            FormSubmission.self,
            LocalPhoto.self,
            // Inventory models
            InventoryItem.self,
            InventorySnapshot.self,
            InventorySnapshotItem.self,
            InventoryTag.self,
            InventoryUnit.self,
            // Wizard system
            WizardState.self,
            // Deck builder
            DeckDesign.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // In production app, we would handle this more gracefully
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataController)
                .environmentObject(notificationManager)
                .environmentObject(subscriptionManager)
                .environmentObject(variantManager)
                .environmentObject(permissionStore)
                .onAppear {
                    // Check if this is a fresh install
                    if !UserDefaults.standard.bool(forKey: "has_launched_before") {

                        // Clear all authentication data on fresh install
                        clearAllAuthenticationData()

                        // Mark that we've launched before
                        UserDefaults.standard.set(true, forKey: "has_launched_before")
                    }

                    // Track app launch count (for features gated on 2nd+ launch)
                    let currentCount = UserDefaults.standard.integer(forKey: "appLaunchCount")
                    UserDefaults.standard.set(currentCount + 1, forKey: "appLaunchCount")

                    // Fetch A/B/C test variant for new users
                    Task {
                        await variantManager.fetchVariant()
                    }

                    // Set the model context in the data controller
                    let context = sharedModelContainer.mainContext
                    dataController.setModelContext(context)

                    // Register background sync tasks (syncEngine may not be initialized yet
                    // since setModelContext kicks off async init — guard against nil)
                    dataController.syncEngine?.registerBackgroundTasks()

                    // Wire permission store and load cached permissions
                    dataController.permissionStore = permissionStore
                    permissionStore.loadCachedPermissions()

                    // Bug G9 — hydrate mention-based project access index from
                    // cached ProjectNote rows so Search / Spotlight / deep links
                    // work offline immediately on cold launch.
                    if let userId = UserDefaults.standard.string(forKey: "currentUserId"),
                       !userId.isEmpty {
                        MentionAccessIndex.shared.rebuild(context: context, userId: userId)
                    }

                    // Initialize SubscriptionManager with DataController
                    subscriptionManager.setDataController(dataController)
                    
                    // Check notification authorization status and request if not yet determined
                    notificationManager.getAuthorizationStatus()
                    if dataController.isAuthenticated {
                        notificationManager.requestPermission()
                    }

                    // Perform data health check before syncing
                    Task {
                        await performAppLaunchChecks()
                    }
                    
                    // Migrate images from UserDefaults to file system
                    Task {
                        // Run migration in background
                        ImageFileManager.shared.migrateAllImages()
                        
                        // One-time fix: Clear remote image cache to fix duplicate image issue
                        if !UserDefaults.standard.bool(forKey: "remote_cache_cleared_v2") {
                            ImageFileManager.shared.clearRemoteImageCache()
                            ImageCache.shared.clear() // Also clear memory cache
                            UserDefaults.standard.set(true, forKey: "remote_cache_cleared_v2")
                        }
                        
                        // Clean up any sample projects (one-time cleanup)
                        if !UserDefaults.standard.bool(forKey: "sample_projects_cleaned") {
                            await dataController.removeSampleProjects()
                            UserDefaults.standard.set(true, forKey: "sample_projects_cleaned")
                        }
                        
                        // Schedule notifications for future projects
                        if let modelContext = dataController.modelContext {
                            await notificationManager.scheduleNotificationsForAllProjects(using: modelContext)
                        }


                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // App going to background - reset PIN authentication for next launch
                    dataController.simplePINManager.resetAuthentication()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Only run active checks on RETURN to foreground (not initial launch)
                    guard scenePhase == .background || scenePhase == .inactive else { return }
                    Task {
                        await performActiveChecks()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ConnectivityManager.connectivityChangedNotification)) { notification in
                    // Refresh permissions when connectivity is restored
                    if let state = notification.userInfo?["state"] as? ConnectionState,
                       state.status != .offline,
                       permissionStore.isCacheStale(),
                       let userId = dataController.currentUser?.id {
                        Task {
                            await permissionStore.fetchPermissions(userId: userId)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didRegisterForRemoteNotificationsWithDeviceTokenNotification)) { notification in
                    // Handle the device token when registered
                    if let deviceToken = notification.userInfo?["deviceToken"] as? Data {
                        notificationManager.handleDeviceTokenRegistration(deviceToken: deviceToken)
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    switch newPhase {
                    case .active:
                        // Re-link OneSignal on every foreground return to ensure
                        // the device is registered for push notifications.
                        // OneSignal.login() is idempotent — safe to call repeatedly.
                        if dataController.isAuthenticated {
                            NotificationManager.shared.linkUserToOneSignal()
                        }

                        // Only trigger sync on RETURN to foreground (not initial launch,
                        // which is handled by performAppLaunchSync)
                        if oldPhase == .background {
                            Task {
                                await dataController.syncEngine?.triggerSync()
                                // Restart realtime if authenticated
                                if dataController.isAuthenticated,
                                   let companyId = dataController.currentUser?.companyId,
                                   !companyId.isEmpty {
                                    let userId = dataController.currentUser?.id
                                    await dataController.syncEngine?.startRealtime(companyId: companyId, userId: userId)
                                }
                            }
                        }
                    case .background:
                        // Schedule background sync tasks
                        dataController.syncEngine?.scheduleBackgroundSync()
                        // Stop realtime after delay
                        Task {
                            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                            await dataController.syncEngine?.stopRealtime()
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
                .onChange(of: dataController.isAuthenticated) { _, isAuth in
                    // Request notification permission once user is authenticated
                    // (onAppear fires before auth completes, so this catches the transition)
                    if isAuth {
                        notificationManager.requestPermission()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ConnectivityManager.connectivityChangedNotification)) { _ in
                    // Trigger sync on connectivity change via new engine
                    if let connectivity = dataController.connectivity,
                       connectivity.shouldAttemptSync,
                       dataController.isAuthenticated {
                        Task {
                            await dataController.syncEngine?.triggerSync()
                        }
                    }
                }
                // MARK: - Universal Links
                // Apple-validated https://app.opsapp.co/* links open the app directly
                // (via Associated Domains entitlement + AASA file on OPS-Web). Route
                // project deep links through the existing OpenProjectDetails handler
                // so the auth/sync/fetch path is shared with push notifications.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    handleUniversalLink(url)
                }
                // Spotlight tap continuation — iPhone universal search result tapped
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    _ = SpotlightTapRouter.handle(activity)
                }
                // HTTPS universal links that weren't intercepted by AppDelegate.
                // Skip ops:// scheme URLs — AppDelegate.application(_:open:) handles
                // those and posts the deep-link notification directly. Without this
                // guard, every ops:// tap would double-route and attempt to present
                // the destination sheet twice.
                .onOpenURL { url in
                    guard url.scheme != "ops" else { return }
                    handleUniversalLink(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Deep Link Routing

    /// Parses an incoming Universal Link / custom-scheme URL and dispatches it
    /// to the appropriate in-app handler. Currently handles:
    ///   - https://app.opsapp.co/projects/{id}  → OpenProjectDetails notification
    ///   - https://app.opsapp.co/open[?from=*]  → OpenAppFromWeb notification
    ///
    /// Posts the same notifications that push notification deep links use so
    /// MainTabView's existing routing code handles sync + presentation.
    private func handleUniversalLink(_ url: URL) {
        print("[DEEP_LINK] Received: \(url.absoluteString)")

        // Accept either the production host or any future alias.
        let host = url.host?.lowercased()
        let isOPSHost = host == "app.opsapp.co"
        let isCustomScheme = url.scheme == "ops"
        guard isOPSHost || isCustomScheme else {
            print("[DEEP_LINK] Ignoring URL with unrecognized host/scheme: \(url.absoluteString)")
            return
        }

        // Path components: first is "/" for https URLs, so drop empty segments.
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // /open[/...] — web-to-app return bridge from /auth/action handler page
        if let first = segments.first, first == "open" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let from = components?.queryItems?
                .first(where: { $0.name == "from" })?
                .value ?? ""
            print("[DEEP_LINK] Routing to /open (from: \(from))")
            NotificationCenter.default.post(
                name: Notification.Name("OpenAppFromWeb"),
                object: nil,
                userInfo: ["from": from]
            )
            return
        }

        // /{entity}/{id}
        guard segments.count >= 2 else {
            print("[DEEP_LINK] No route matched for: \(url.absoluteString)")
            return
        }

        let entity = segments[0]
        let id = segments[1]
        guard !id.isEmpty else { return }

        switch entity {
        case "projects":
            print("[DEEP_LINK] Routing to project: \(id)")
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": id]
            )
        case "clients":
            print("[DEEP_LINK] Routing to client: \(id)")
            NotificationCenter.default.post(
                name: Notification.Name("OpenClientDetails"),
                object: nil,
                userInfo: ["clientId": id]
            )
        case "invoices":
            print("[DEEP_LINK] Routing to invoice: \(id)")
            NotificationCenter.default.post(
                name: Notification.Name("OpenInvoiceDetails"),
                object: nil,
                userInfo: ["invoiceId": id]
            )
        case "estimates":
            print("[DEEP_LINK] Routing to estimate: \(id)")
            NotificationCenter.default.post(
                name: Notification.Name("OpenEstimateDetails"),
                object: nil,
                userInfo: ["estimateId": id]
            )
        case "tasks":
            print("[DEEP_LINK] Routing to task: \(id)")
            NotificationCenter.default.post(
                name: Notification.Name("OpenTaskDetails"),
                object: nil,
                userInfo: ["taskId": id]
            )
        default:
            print("[DEEP_LINK] Unknown entity '\(entity)' in: \(url.absoluteString)")
        }
    }

    /// Performs health check when app becomes active
    @MainActor
    private func performActiveChecks() async {
        print("[APP_ACTIVE] 🏥 App became active - running subscription check...")

        // Refresh permissions if stale
        if permissionStore.isCacheStale(),
           let userId = dataController.currentUser?.id {
            await permissionStore.fetchPermissions(userId: userId)
        }

        // CRITICAL: Always run subscription check regardless of data health
        // Subscription check has its own guards and handles missing data gracefully
        // Gating this behind health check allowed expired subscriptions to bypass validation
        await subscriptionManager.checkSubscriptionStatus()
    }

    /// Performs data health checks and initiates sync operations if data is healthy
    @MainActor
    private func performAppLaunchChecks() async {
        print("[APP_LAUNCH] 🏥 Performing data health check before app launch sync...")

        // Create health manager
        let healthManager = DataHealthManager(
            dataController: dataController,
            authManager: AuthManager()
        )

        // Check if we're authenticated (have a user_id)
        guard let userId = UserDefaults.standard.string(forKey: "user_id"), !userId.isEmpty else {
            print("[APP_LAUNCH] ⚠️ No user ID - user not authenticated, skipping sync")
            return
        }

        print("[APP_LAUNCH] ✅ User authenticated with ID: \(userId)")

        // If we don't have currentUser loaded yet, try to load from SwiftData or trigger sync to fetch
        if dataController.currentUser == nil {
            print("[APP_LAUNCH] ⚠️ currentUser is nil - attempting to load from SwiftData...")

            // Try to load user from SwiftData
            if let modelContext = dataController.modelContext {
                let descriptor = FetchDescriptor<User>(
                    predicate: #Predicate<User> { $0.id == userId }
                )

                do {
                    let users = try modelContext.fetch(descriptor)
                    if let user = users.first {
                        dataController.currentUser = user
                        print("[APP_LAUNCH] ✅ Loaded currentUser from SwiftData: \(user.fullName)")
                    } else {
                        print("[APP_LAUNCH] ⚠️ User not found in SwiftData - sync will fetch from API")
                    }
                } catch {
                    print("[APP_LAUNCH] ❌ Error loading user from SwiftData: \(error)")
                }
            }
        }

        // Perform full health check
        let (healthState, recoveryAction) = await healthManager.performHealthCheck()

        if !healthState.isHealthy {
            print("[APP_LAUNCH] ❌ Data health check failed: \(healthState)")
            print("[APP_LAUNCH] 🔧 Executing recovery action: \(recoveryAction)")

            // Execute recovery action
            await healthManager.executeRecoveryAction(recoveryAction)

            // If recovery action was to fetch data, continue to full sync
            // For logout/return to onboarding, we should stop here
            switch recoveryAction {
            case .fetchUserFromAPI, .fetchCompanyFromAPI, .reinitializeSyncEngine:
                print("[APP_LAUNCH] ✅ Recovery action completed - continuing to full sync")
                // Fall through to run the sync
            case .logout, .returnToOnboarding:
                print("[APP_LAUNCH] ⚠️ Recovery action requires user intervention - skipping sync")
                return
            case .none:
                break
            }
        } else {
            print("[APP_LAUNCH] ✅ Data health check passed")
        }

        print("[APP_LAUNCH] 🔄 Proceeding with full sync and subscription check")

        // Data is healthy (or was repaired), proceed with normal app launch operations
        dataController.performAppLaunchSync()

        // Check subscription status
        Task {
            await subscriptionManager.checkSubscriptionStatus()
        }
    }


}


// Function to clear all authentication data on fresh install
private func clearAllAuthenticationData() {
    
    // Clear Keychain data
    let keychainManager = KeychainManager()
    keychainManager.deleteToken()
    keychainManager.deleteTokenExpiration()
    keychainManager.deleteUserId()
    keychainManager.deleteUsername()
    keychainManager.deletePassword()
    keychainManager.deletePermissions()

    // Clear all authentication-related UserDefaults
    let authKeys = [
        "is_authenticated",
        "onboarding_completed", 
        "resume_onboarding",
        "last_onboarding_step_v2",
        "user_id",
        "currentUserId",
        "user_email",
        "user_password",
        "user_first_name",
        "user_last_name",
        "user_phone_number",
        "company_code",
        "company_id",
        "Company Name",
        "has_joined_company",
        "currentUserCompanyId",
        "selected_user_type",
        "user_type",  // This was missing!
        "user_type_raw",  // Also add this for completeness
        "apple_user_identifier",  // And this
        "appPIN",
        "hasPINEnabled",
        "location_permission_granted",
        "notifications_permission_granted",
        "onboarding_variant",
        "pending_demo_data_migration",
        "appLaunchCount",
        "hasCompletedCompanySetup"
    ]
    
    for key in authKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // Force synchronize to ensure changes are saved
    UserDefaults.standard.synchronize()
    
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
