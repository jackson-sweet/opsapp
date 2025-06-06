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
    static let bubbleBaseURL = URL(string: "https://opsapp.co")!

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
        
        /// Feature flag for the consolidated onboarding flow
        static let useConsolidatedOnboardingFlow = true
        
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
    
    // MARK: - What's New Features
    
    struct WhatsNew {
        /// Feature status options
        enum FeatureStatus: String {
            case inDevelopment = "In Development"
            case comingSoon = "Coming Soon"
            case planned = "Planned"
        }
        
        /// Feature items structure
        struct FeatureItem {
            let icon: String
            let title: String
            let description: String
            let status: FeatureStatus
        }
        
        /// Feature categories structure
        struct FeatureCategory {
            let name: String
            let icon: String
            let features: [FeatureItem]
        }
        
        /// All feature categories
        static let featureCategories: [FeatureCategory] = [
            FeatureCategory(
                name: "Calendar & Scheduling",
                icon: "calendar",
                features: [
                    FeatureItem(
                        icon: "calendar.badge.plus",
                        title: "Calendar Request System",
                        description: "Long press on calendar dates to request days off or schedule changes",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "cloud.sun.rain",
                        title: "Weather Integration",
                        description: "Choose weather source in settings, mark jobs as weather dependent, get rain warnings",
                        status: .planned
                    )
                ]
            ),
            FeatureCategory(
                name: "Time & Analytics",
                icon: "clock",
                features: [
                    FeatureItem(
                        icon: "location.circle",
                        title: "Automatic Time Tracking",
                        description: "Auto-start tracking when arriving at projects, stop when leaving",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Work Analytics",
                        description: "Track days worked, hours logged, jobs completed per hour, and productivity trends",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Project Analytics",
                        description: "Track project completion times, team productivity, and trends",
                        status: .planned
                    )
                ]
            ),
            FeatureCategory(
                name: "Team & Communication",
                icon: "person.2",
                features: [
                    FeatureItem(
                        icon: "person.2",
                        title: "Team Member Notes",
                        description: "Add specific notes for each team member on a project",
                        status: .inDevelopment
                    ),
                    FeatureItem(
                        icon: "map",
                        title: "Team Member Locations",
                        description: "See where your team members are on the map with real-time updates",
                        status: .inDevelopment
                    ),
                    FeatureItem(
                        icon: "message",
                        title: "In-App Messaging",
                        description: "Message team members directly within the app with project context",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Contact Info Updates",
                        description: "Update teammate contact info with approval notifications",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "bell.badge",
                        title: "Project Note Notifications",
                        description: "Get notified when teammates update project notes",
                        status: .comingSoon
                    )
                ]
            ),
            FeatureCategory(
                name: "Business Features",
                icon: "dollarsign.circle",
                features: [
                    FeatureItem(
                        icon: "receipt",
                        title: "Expense Tracking",
                        description: "Detailed expense tracking and submission functionality",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "checkmark.shield",
                        title: "Certifications & Training",
                        description: "Track team member certifications, training records, and expiration dates",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "person.circle",
                        title: "Client Portal",
                        description: "Allow clients to log in, see their projects and create RFQs.",
                        status: .comingSoon
                    )
                ]
            ),
            FeatureCategory(
                name: "AI & Web Features",
                icon: "brain",
                features: [
                    FeatureItem(
                        icon: "doc.text.magnifyingglass",
                        title: "AI Quoting System",
                        description: "Upload price sheets and project drawings for AI-powered quotes",
                        status: .planned
                    ),
                    FeatureItem(
                        icon: "eyedropper.halffull",
                        title: "Smart UI Colors",
                        description: "Extract colors from company logo for personalized UI themes",
                        status: .planned
                    )
                ]
            ),
            FeatureCategory(
                name: "Data & Projects",
                icon: "folder",
                features: [
                    FeatureItem(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Multiple Project Visits",
                        description: "Track and schedule multiple visits to the same project with new 'visit' data type",
                        status: .comingSoon
                    ),
                    FeatureItem(
                        icon: "doc.text",
                        title: "Client Project History",
                        description: "View all projects for a specific client in one place",
                        status: .planned
                    )
                ]
            ),
            FeatureCategory(
                name: "Technology Integration",
                icon: "apps.iphone",
                features: [
                    FeatureItem(
                        icon: "car",
                        title: "Apple CarPlay",
                        description: "Access OPS safely while driving with CarPlay integration",
                        status: .inDevelopment
                    ),
                    FeatureItem(
                        icon: "applewatch.watchface",
                        title: "Apple Watch",
                        description: "Access OPS on Apple Watch to view project notes and details.",
                        status: .inDevelopment
                    )
                ]
            ),
            FeatureCategory(
                name: "Merch & Kit",
                icon: "tag",
                features: [
                    FeatureItem(
                        icon: "tshirt",
                        title: "OPS Merchandise",
                        description: "Limited edition OPS apparel.",
                        status: .comingSoon
                    )
                ]
            )
        ]
    }
}
