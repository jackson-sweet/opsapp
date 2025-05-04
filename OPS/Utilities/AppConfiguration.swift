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
    static let bubbleBaseURL = URL(string: "https://opsapp.co/version-test")!

    /// Bubble API token
    static let bubbleAPIToken = "f81e9da85b7a12e996ac53e970a52299"

    /// Bubble Data API endpoint path
    static let bubbleDataAPIPath = "/api/1.1/obj"

    /// Bubble Workflow API endpoint path
    static let bubbleWorkflowAPIPath = "/api/1.1/wf"

    
    /// Authentication Configuration
    struct Auth {
        /// Service name for keychain items - should be unique to your app
        /// Recommended: use your bundle identifier
        static let keychainService = "co.opsapp.ops.OPS"
        
        /// Token expiration time in seconds
        /// Adjust based on your Bubble authentication settings
        static let tokenExpirationSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
    }
    
    // MARK: - Sync Configuration
    
    struct Sync {
        /// Whether to sync automatically on app launch
        static let syncOnLaunch = true
        
        /// How often to sync when app is in foreground (in seconds)
        static let backgroundSyncInterval: TimeInterval = 15 * 60 // 15 minutes
        
        /// Maximum number of items to sync in one batch
        static let maxBatchSize = 50
        
        /// How far back to fetch jobs (in days)
        static let jobHistoryDays = 30
            
        /// How far forward to fetch jobs (in days)
        static let jobFutureDays = 60
        
        /// Minimum time between syncs (prevents excessive network usage)
        static let minimumSyncInterval: TimeInterval = 5 * 60 // 5 minutes
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
        
        /// Collection of quotes to display when there are no projects scheduled
        static let noProjectQuotes = [
                "No projects. GOOD. Time to train, prepare, improve.",
                "Empty schedule. Time to get ahead. Maintain equipment. Prepare for tomorrow. DISCIPLINE.",
                "No jobs today. GOOD. Opportunity to train, learn, develop skills. Stay ready.",
                "Clear day. Perfect for maintenance. Tools don't sharpen themselves.",
                "No scheduled work. Good. Time to review procedures. Preparation prevents problems.",
                "Empty calendar. GOOD. Time to check gear. Be ready when others aren't.",
                "No projects today. GOOD. Train harder than yesterday. Tomorrow will test you.",
                "Open schedule. Perfect time to review safety protocols. Complacency kills.",
                "No jobs scheduled. GOOD. Get after equipment maintenance. Readiness is protection.",
                "Clear day. Execute self-improvement. Leaders are built in downtime.",
                "No projects. GOOD. Take ownership. Find ways to add value. Leaders don't wait.",
                "Empty schedule. Time to ATTACK weaknesses. Turn disadvantage into strength.",
                "No work scheduled. GOOD. Perfect opportunity to master fundamentals.",
                "Open day. GOOD. Stay ready so you don't have to get ready.",
                "No projects today. GOOD. Train harder now, work easier later.",
                "Empty calendar. Own it. Make it productive. No excuses.",
                "No jobs today. GOOD. Refine processes. Gain the advantage. Get after it.",
                "Clear day. GOOD. Review, prepare, strengthen. Extreme ownership starts now.",
                "Down day. There are no down days. Only opportunities for improvement.",
                "No work scheduled. GOOD. Preparation is where battles are won. Get after it."
            ]
    }
    
    // MARK: - Debug Settings
    
    struct Debug {
        /// Whether to use sample data for UI development
        /// Set to false for production builds
        static let useSampleData = false
        
        /// Enable verbose logging
        static let verboseLogging = false
        
        /// Show debug overlays in UI
        static let showDebugOverlays = false
    }
}
