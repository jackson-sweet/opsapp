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
    
    // MARK: - API Configuration

    /// Base URL for ops-web API routes
    static let apiBaseURL = URL(string: "https://app.opsapp.co")!

    struct API {
        static let webBaseURL = "https://app.opsapp.co"
    }

    /// Authentication Configuration
    struct Auth {
        /// Service name for keychain items - should be unique to your app
        /// Recommended: use your bundle identifier
        static let keychainService = "co.opsapp.ops.OPS"
        
        /// Token expiration time in seconds
        /// Authentication timeout settings
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
            "Empty schedule. Perfect for equipment maintenance. Preparation prevents problems.",
            "No jobs today. GOOD. Sharpen skills. Tomorrow will test you.",
            "Clear day. Tools don't maintain themselves. Get after it.",
            "Open schedule. Review safety protocols. Complacency kills.",
            "No projects. GOOD. Find ways to add value. Leaders don't wait.",
            "Empty calendar. Attack your weaknesses. Turn gaps into gains.",
            "No work scheduled. Master the fundamentals. Excellence is built in downtime.",
            "Clear day. Stay ready so you don't have to get ready.",
            "No projects today. Train harder now. Work easier later.",
            "Open schedule. Own it. Make it count. No excuses.",
            "No jobs. GOOD. Refine processes. Gain the advantage.",
            "Down time. There is no down time. Only improvement time.",
            "Empty day. Study the craft. Knowledge is power.",
            "No projects. Check your gear. Readiness is everything.",
            "Clear schedule. Build tomorrow's strength today.",
            "Open day. Review procedures. Perfect the basics.",
            "No work. GOOD. Discipline yourself when no one's watching.",
            "Empty calendar. Opportunity disguised as free time. Take it.",
            "No projects today. Leaders are forged in quiet moments."
            ]
    }
    
    // MARK: - App Info
    
    struct AppInfo {
        /// App version from Bundle
        static var version: String {
            return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        }
        
        /// Build number from Bundle
        static var build: String {
            return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        }
        
        /// Full version string for display
        static var fullVersion: String {
            return "v\(version) (\(build))"
        }
        
        /// Simple version string for display
        static var displayVersion: String {
            return "v\(version)"
        }
    }
    
    // MARK: - Debug Settings
    
    struct Debug {
        /// Whether to use sample data for UI development
        /// Set to false for production builds
        static let useSampleData = false // Using real production API calls
        
        /// Enable verbose logging
        static let verboseLogging = true
        
        /// Show debug overlays in UI
        static let showDebugOverlays = false
    }
}
