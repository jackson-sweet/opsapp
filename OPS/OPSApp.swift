//
//  OPSApp.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI
import SwiftData

@main
struct OPSApp: App {
    // Setup shared instances for app-wide use
    @StateObject private var dataController = DataController()
    
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
                .onAppear {
                    // Set the model context in the data controller
                    let context = sharedModelContainer.mainContext
                    dataController.setModelContext(context)
                    
                    // Sync to Bubble on app launch
                    dataController.performAppLaunchSync()
                    print("Synced")
                    
                    // Migrate images from UserDefaults to file system
                    Task {
                        // Run migration in background
                        ImageFileManager.shared.migrateAllImages()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}


extension String: @retroactive Identifiable {
    public var id: String { self }
}
