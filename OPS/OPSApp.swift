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
    
    // Create the model container for SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Project.self,
            Company.self,
            TeamMember.self
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
                    
                    // Check notification authorization status
                    notificationManager.getAuthorizationStatus()
                    
                    // Sync to Bubble on app launch
                    dataController.performAppLaunchSync()
                    
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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didRegisterForRemoteNotificationsWithDeviceTokenNotification)) { notification in
                    // Handle the device token when registered
                    if let deviceToken = notification.userInfo?["deviceToken"] as? Data {
                        notificationManager.handleDeviceTokenRegistration(deviceToken: deviceToken)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
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
