//
//  AppConfiguration.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation

/// Central place for app configuration
/// IMPORTANT: You'll need to fill in your specific values here
struct AppConfiguration {
    
    // MARK: - Bubble API Configuration
    
    /// Base URL for your Bubble.io app
    /// FILL THIS IN: Replace with your actual Bubble app URL
    static let bubbleBaseURL = URL(string: "https://your-bubble-app.bubbleapps.io")!
    
    /// Authentication Configuration
    struct Auth {
        /// Service name for keychain items - should be unique to your app
        /// Recommended: use your bundle identifier
        static let keychainService = "com.yourcompany.ops"
        
        /// Token expiration time in seconds
        /// Adjust based on your Bubble authentication settings
        static let tokenExpirationSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
    }
    
    // MARK: - Sync Configuration
    
    struct Sync {
        /// How often to sync when app is in foreground (in seconds)
        static let backgroundSyncInterval: TimeInterval = 15 * 60 // 15 minutes
        
        /// Maximum number of items to sync in one batch
        static let maxBatchSize = 50
        
        /// How far back to fetch historical jobs (in days)
        static let jobHistoryDays = 30
    }
    
    // MARK: - Map Configuration
    
    struct Map {
        /// Default zoom level for map
        static let defaultZoomLevel = 14.0
        
        /// Job marker colors
        static let upcomingMarkerColor = "blue"
        static let inProgressMarkerColor = "orange"
        static let completedMarkerColor = "green"
        static let cancelledMarkerColor = "red"
    }
    
    // MARK: - User Experience
    
    struct UX {
        /// Define the minimum time between status updates in seconds
        /// Prevents multiple rapid taps from causing issues
        static let statusUpdateCooldown: TimeInterval = 2.0
    }
}