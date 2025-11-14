//
//  OPSApp.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct OPSApp: App {
    // Register AppDelegate for handling remote notifications
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Setup shared instances for app-wide use
    @StateObject private var dataController = DataController()
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    // Create the model container for SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Project.self,
            Company.self,
            TeamMember.self,
            Client.self,
            SubClient.self,
            ProjectTask.self,
            TaskType.self,
            TaskStatusOption.self,
            CalendarEvent.self,
            OpsContact.self
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
                .onAppear {
                    // Check if this is a fresh install
                    if !UserDefaults.standard.bool(forKey: "has_launched_before") {
                        
                        // Clear all authentication data on fresh install
                        clearAllAuthenticationData()
                        
                        // Mark that we've launched before
                        UserDefaults.standard.set(true, forKey: "has_launched_before")
                    }
                    
                    // Set the model context in the data controller
                    let context = sharedModelContainer.mainContext
                    dataController.setModelContext(context)
                    
                    // Initialize SubscriptionManager with DataController
                    subscriptionManager.setDataController(dataController)
                    
                    // Check notification authorization status
                    notificationManager.getAuthorizationStatus()

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
                    // App became active - check subscription status if data is healthy
                    Task {
                        await performActiveChecks()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didRegisterForRemoteNotificationsWithDeviceTokenNotification)) { notification in
                    // Handle the device token when registered
                    if let deviceToken = notification.userInfo?["deviceToken"] as? Data {
                        notificationManager.handleDeviceTokenRegistration(deviceToken: deviceToken)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Performs health check when app becomes active
    @MainActor
    private func performActiveChecks() async {
        print("[APP_ACTIVE] 🏥 App became active - checking data health...")

        let healthManager = DataHealthManager(
            dataController: dataController,
            authManager: AuthManager()
        )

        // Quick check - just verify minimum data exists
        let hasMinimumData = healthManager.hasMinimumRequiredData()

        if !hasMinimumData {
            print("[APP_ACTIVE] ⚠️ Minimum data requirements not met - skipping subscription check")
            return
        }

        // Minimum data exists, check subscription
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
            case .fetchUserFromAPI, .fetchCompanyFromAPI, .reinitializeSyncManager:
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
        "notifications_permission_granted"
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
