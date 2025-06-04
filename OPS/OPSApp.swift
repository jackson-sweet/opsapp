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
                    // Set the model context in the data controller
                    let context = sharedModelContainer.mainContext
                    dataController.setModelContext(context)
                    
                    // Check notification authorization status
                    notificationManager.getAuthorizationStatus()
                    
                    // Sync to Bubble on app launch
                    dataController.performAppLaunchSync()
                    print("Synced")
                    
                    // Migrate images from UserDefaults to file system
                    Task {
                        // Run migration in background
                        ImageFileManager.shared.migrateAllImages()
                        
                        // One-time fix: Clear remote image cache to fix duplicate image issue
                        if !UserDefaults.standard.bool(forKey: "remote_cache_cleared_v2") {
                            ImageFileManager.shared.clearRemoteImageCache()
                            ImageCache.shared.clear() // Also clear memory cache
                            UserDefaults.standard.set(true, forKey: "remote_cache_cleared_v2")
                            print("Cleared remote image cache to fix duplicate issue")
                        }
                        
                        // Clean up any sample projects (one-time cleanup)
                        if !UserDefaults.standard.bool(forKey: "sample_projects_cleaned") {
                            await dataController.removeSampleProjects()
                            UserDefaults.standard.set(true, forKey: "sample_projects_cleaned")
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


extension String: @retroactive Identifiable {
    public var id: String { self }
}
