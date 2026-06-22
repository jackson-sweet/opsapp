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
        #if DEBUG
        if CatalogSetupQARuntime.isEnabled() {
            return
        }
        #endif
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

    // Create the model container for SwiftData.
    // Schema is driven by the LATEST VersionedSchema (currently `OPSSchemaV9`)
    // and the container runs `OPSMigrationPlan` on launch so stores written by
    // earlier builds (e.g. pre-`WizardState.id`, pre-catalog, pre-reminders)
    // are migrated in place. **When you add a new VersionedSchema (V7, V8, …),
    // bump this reference to the new latest** — leaving it stale produces the
    // "Duplicate version checksums across stages detected" runtime crash
    // because the migration plan validates from-version/to-version pairs that
    // overshoot the declared schema. Equivalently: adding a new persistent
    // property to a live `@Model` that's referenced by any historical
    // VersionedSchema (e.g. anything in `OPSSchemaCommon.unchangedModels`)
    // shifts every schema's hash by the same delta — the relative distinctness
    // between schemas survives only if every adjacent pair (Vn, Vn+1) already
    // declared a real model-list difference. Mint a new schema version when
    // the only thing differentiating it is the property add, OR ensure your
    // schema bump also introduces a new @Model (which is what V6 does via
    // `v6ForecastModels`).
    //
    // Error 134504 ("unknown model version") means the on-disk store was created
    // before this app introduced versioned schemas. SwiftData can't map it to any
    // schema in the migration plan, so it refuses to open it. We delete the store
    // and start fresh — Supabase sync will re-hydrate all data on next launch.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: OPSSchemaV9.self)

        let isHostedXCTest = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isHostedXCTest,
            allowsSave: true
        )

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(
                for: schema,
                migrationPlan: OPSMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        }

        do {
            return try makeContainer()
        } catch {
            // Pre-versioning stores have no version fingerprint; SwiftData
            // surfaces this as SwiftDataError (not the underlying CoreData
            // 134504). Wipe the store and retry — Supabase sync re-hydrates.
            print("[SWIFTDATA] Container failed (\(error)) — deleting store and retrying")
            destroyDefaultStore()
            do {
                return try makeContainer()
            } catch {
                fatalError("Failed to create model container after store reset: \(error.localizedDescription)")
            }
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if CatalogSetupQARuntime.isEnabled() {
            CatalogSetupQALocalHost()
                .environmentObject(dataController)
                .environmentObject(notificationManager)
                .environmentObject(subscriptionManager)
                .environmentObject(variantManager)
                .environmentObject(permissionStore)
                .preferredColorScheme(.dark)
        } else {
            productionRootView
        }
        #else
        productionRootView
        #endif
    }

    private var productionRootView: some View {
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

                    // HIGH-5 (spec §6.3 R10): one-time sweep of legacy onboarding
                    // state — most importantly any plaintext `user_password` left by
                    // pre-rebuild installs, which fresh-install/logout never cleared
                    // for an already-logged-in user.
                    sweepLegacyOnboardingKeysOnce()

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

                    // Bridge the model container to non-View singletons
                    // (CalendarMirrorService reaches SwiftData through this).
                    ModelContainerHolder.shared = sharedModelContainer

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

                    // Bug 68123654 — kick a launch-time reconcile so the iPhone
                    // Calendar mirror catches up with any changes that happened
                    // while the app was closed. No-op when feature is disabled.
                    Task { @MainActor in
                        await CalendarMirrorService.shared.reconcileAll()
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

                        // Refresh the share-extension session bridge and drain any
                        // photos captured via the share sheet while we were away.
                        // Runs on every foreground (including cold launch to active)
                        // when signed in.
                        if dataController.isAuthenticated {
                            Task { @MainActor in
                                await dataController.refreshShareSessionBridge()
                                ShareUploadCoordinator.shared.activate()
                                await ShareUploadCoordinator.shared.drainInbox()
                            }
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
                // We only route https:// here — ops:// flows through AppDelegate's
                // application(_:open:options:) and any third-party schemes
                // (Google OAuth callback, etc.) must be left alone. Matching on
                // scheme is the correct outer guard; the inner host check in
                // handleUniversalLink is a second layer of defense.
                .onOpenURL { url in
                    guard url.scheme == "https" else { return }
                    handleUniversalLink(url)
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
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "deep_link_malformed",
                properties: [
                    "scheme": url.scheme ?? "",
                    "path": url.path,
                    "reason": "insufficient_path_segments"
                ]
            )
            return
        }

        let entity = segments[0]
        let id = segments[1]
        guard !id.isEmpty else {
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "deep_link_malformed",
                properties: [
                    "entity": entity,
                    "scheme": url.scheme ?? "",
                    "reason": "empty_id"
                ]
            )
            return
        }

        switch entity {
        case "projects", "clients", "invoices", "estimates", "tasks", "leads", "opportunities":
            print("[DEEP_LINK] Routing to \(entity): \(id)")
            DeepLinkCoordinator.shared.receive(entity: entity, id: id, scheme: url.scheme ?? "")
        default:
            print("[DEEP_LINK] Unknown entity '\(entity)' in: \(url.absoluteString)")
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "deep_link_malformed",
                properties: [
                    "entity": entity,
                    "id": id,
                    "scheme": url.scheme ?? "",
                    "reason": "unknown_entity"
                ]
            )
        }
    }

    /// Performs health check when app becomes active
    @MainActor
    private func performActiveChecks() async {
        print("[APP_ACTIVE] 🏥 App became active - running subscription check...")

        // Always refresh permissions on app foreground — the fetch is cheap
        // and the stale-cache TTL gate (8 hrs default) was causing a real
        // bug where flag/permission changes wouldn't reach the device until
        // the user logged out + back in or the cache aged past the threshold.
        // Connectivity-restored handler keeps the gate (fires too frequently
        // to drop), but foreground-active is a once-per-resume signal.
        if let userId = dataController.currentUser?.id {
            await permissionStore.fetchPermissions(userId: userId)
        }

        // CRITICAL: Always run subscription check regardless of data health
        // Subscription check has its own guards and handles missing data gracefully
        // Gating this behind health check allowed expired subscriptions to bypass validation
        await subscriptionManager.checkSubscriptionStatus()

        // Advance any "accepted" projects whose tasks have start dates in the
        // past. This catches the common case where a job was accepted days ago,
        // tasks were scheduled, but the app was never opened on the actual
        // work day to trigger the real-time task-status hook.
        await dataController.advanceAcceptedProjectsWithPastTasks()
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


// Removes the default SwiftData SQLite store and its WAL/SHM sidecars.
// Called when the store has no version fingerprint and can't be migrated.
private func destroyDefaultStore() {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    for name in ["default.store", "default.store-wal", "default.store-shm"] {
        let url = appSupport.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
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
        "onboarding_state_v2",
        "onboarding_state_v3",
        "onboarding_state_v4",
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

    // Purge any in-memory deep link that might have been captured before
    // the fresh-install wipe runs, so a resumed user doesn't inherit a
    // link that was tapped under a prior identity.
    Task { @MainActor in
        DeepLinkCoordinator.shared.clear()
    }
}

// HIGH-5 (onboarding rebuild spec §6.3 R10): one-time launch sweep of legacy
// onboarding state. Runs once per device (gated by `did_sweep_legacy_onboarding_keys`)
// and, unlike `clearAllAuthenticationData`, does NOT require a fresh install or a
// logout — it reaches an already-logged-in user whose device still carries:
//   • `user_password` — a PLAINTEXT credential persisted by pre-rebuild installs.
//     It was only ever removed on logout / first-launch, so existing logged-in
//     installs kept it indefinitely. This sweep is the missing eviction.
//   • stale legacy-flow keys that the rebuilt flow (now the shipping default) no
//     longer uses.
// `onboarding_state_v4` is intentionally excluded: it is the CURRENT rebuilt-flow
// resume blob and is cleared on logout / fresh install only (HIGH-4). Blanket-
// sweeping it here would wipe an in-progress onboarding on the next launch.
// NOTE: if `FeatureFlags.useRebuiltOnboarding` is ever reverted to the legacy flow,
// this sweep will have discarded the legacy resume state (`onboarding_state_v3`,
// `resume_onboarding`, `ab_test_flow_step`). That is acceptable — the legacy flow
// simply restarts from its entry point.
private func sweepLegacyOnboardingKeysOnce() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: "did_sweep_legacy_onboarding_keys") else { return }

    let legacyKeys = [
        "user_password",                 // plaintext credential — must never persist
        "ab_test_flow_step",
        "onboarding_state_v3",
        "resume_onboarding",
        "pre_signup_tutorial_completed",
        "onboarding_variant"
    ]
    for key in legacyKeys {
        defaults.removeObject(forKey: key)
    }

    defaults.set(true, forKey: "did_sweep_legacy_onboarding_keys")
    defaults.synchronize()
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
