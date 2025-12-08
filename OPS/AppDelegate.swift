//
//  AppDelegate.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-09.
//

import UIKit
import UserNotifications
import GoogleSignIn
import FirebaseCore
import FirebaseAnalytics
import OneSignalFramework

class AppDelegate: NSObject, UIApplicationDelegate, OSNotificationLifecycleListener, OSNotificationClickListener {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Configure Firebase (must be first)
        FirebaseApp.configure()

        // Configure Stripe SDK
        StripeConfiguration.shared.configure()

        // Configure OneSignal
        configureOneSignal()

        // Register for remote notifications
        // The actual permission request happens elsewhere through the NotificationManager
        registerForRemoteNotifications()

        // Check if app was launched from a push notification
        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            print("[PUSH] App launched from notification")
            // Delay handling to allow app to fully initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.handleRemoteNotification(userInfo: remoteNotification)
            }
        }

        return true
    }

    // MARK: - OneSignal Configuration

    private func configureOneSignal() {
        // Set log level - use .LL_VERBOSE for debugging, .LL_NONE for production
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_WARN)
        #else
        OneSignal.Debug.setLogLevel(.LL_NONE)
        #endif

        // Initialize OneSignal with your App ID
        OneSignal.initialize("0fc0a8e0-9727-49b6-9e37-5d6d919d741f", withLaunchOptions: nil)

        // Set up notification click handler
        OneSignal.Notifications.addClickListener(self)

        // Set up foreground notification handler
        OneSignal.Notifications.addForegroundLifecycleListener(self)

        print("[ONESIGNAL] Initialized successfully")
    }

    // MARK: - OSNotificationClickListener

    /// Called when a notification is tapped/clicked
    func onClick(event: OSNotificationClickEvent) {
        print("[ONESIGNAL] Notification clicked")

        // Extract custom data from the notification
        let additionalData = event.notification.additionalData
        let notificationType = additionalData?["type"] as? String
        let projectId = additionalData?["projectId"] as? String
        let taskId = additionalData?["taskId"] as? String
        let screen = additionalData?["screen"] as? String

        print("[ONESIGNAL] Type: \(notificationType ?? "unknown")")
        print("[ONESIGNAL] Project: \(projectId ?? "none"), Task: \(taskId ?? "none")")
        print("[ONESIGNAL] Screen: \(screen ?? "none")")

        // Delay routing to allow app to fully initialize if cold-launched
        // This gives time for view observers to be set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let screen = screen {
                self.routeToScreen(screen, projectId: projectId, taskId: taskId)
            } else if let type = notificationType {
                self.routeByType(type, projectId: projectId, taskId: taskId)
            } else if let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        }
    }

    // MARK: - OSNotificationLifecycleListener

    /// Called when a notification is received while app is in foreground
    func onWillDisplay(event: OSNotificationWillDisplayEvent) {
        print("[ONESIGNAL] Notification will display in foreground")

        // Check if we should show the notification based on user settings
        if NotificationManager.shared.shouldSendNotification() {
            // Allow the notification to display
            event.notification.display()
        } else {
            // Prevent display (user has DND or mute enabled)
            event.preventDefault()
            print("[ONESIGNAL] Notification suppressed by user settings")
        }
    }

    // Handle URL for Google Sign-In
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GoogleSignInManager.handle(url)
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        // Pass device token to the notification manager
        NotificationManager.shared.handleDeviceTokenRegistration(deviceToken: deviceToken)
        
        // Post notification for any observers
        NotificationCenter.default.post(
            name: UIApplication.didRegisterForRemoteNotificationsWithDeviceTokenNotification,
            object: nil,
            userInfo: ["deviceToken": deviceToken]
        )
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Only log in debug builds - this is expected when push notification entitlements aren't configured
        #if DEBUG
        if (error as NSError).code != 3000 { // 3000 = no valid aps-environment entitlement
        }
        #endif
        
        // Post notification for any observers
        NotificationCenter.default.post(
            name: UIApplication.didFailToRegisterForRemoteNotificationsNotification,
            object: nil,
            userInfo: ["error": error]
        )
    }
    
    // Register for remote notifications
    private func registerForRemoteNotifications() {
        // Only register for remote notifications on real devices (not simulator)
        // This doesn't request authorization, just registers the app with APNs
        #if !targetEnvironment(simulator)
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #else
        #endif
    }

    // MARK: - Remote Notification Handling

    /// Called when a remote notification arrives (foreground or background with content-available)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[PUSH] Received remote notification: \(userInfo)")

        // Parse and route the notification
        handleRemoteNotification(userInfo: userInfo)

        // Tell system we processed the notification
        completionHandler(.newData)
    }

    /// Parse and route remote notification to appropriate screen
    private func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        // Extract standard APNs fields
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        let title = alert?["title"] as? String
        let body = alert?["body"] as? String

        // Extract custom data from Bubble
        let notificationType = userInfo["type"] as? String
        let projectId = userInfo["projectId"] as? String
        let taskId = userInfo["taskId"] as? String
        let screen = userInfo["screen"] as? String

        print("[PUSH] Type: \(notificationType ?? "unknown")")
        print("[PUSH] Title: \(title ?? "none"), Body: \(body ?? "none")")
        print("[PUSH] Project: \(projectId ?? "none"), Task: \(taskId ?? "none")")
        print("[PUSH] Screen: \(screen ?? "none")")

        // Route based on screen or type
        if let screen = screen {
            routeToScreen(screen, projectId: projectId, taskId: taskId)
        } else if let type = notificationType {
            routeByType(type, projectId: projectId, taskId: taskId)
        } else if let projectId = projectId {
            // Default: open project details if projectId is provided
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    }

    /// Route to specific screen based on payload
    private func routeToScreen(_ screen: String, projectId: String?, taskId: String?) {
        switch screen {
        case "projectDetails":
            if let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        case "taskDetails":
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            }
        case "schedule", "calendar":
            NotificationCenter.default.post(
                name: Notification.Name("OpenSchedule"),
                object: nil,
                userInfo: [:]
            )
        case "jobBoard":
            NotificationCenter.default.post(
                name: Notification.Name("OpenJobBoard"),
                object: nil,
                userInfo: [:]
            )
        default:
            print("[PUSH] Unknown screen: \(screen)")
        }
    }

    /// Route based on notification type
    private func routeByType(_ type: String, projectId: String?, taskId: String?) {
        switch type {
        case "assignment", "update", "completion", "projectCompletion", "taskCompletion":
            if let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        case "taskAssignment", "taskUpdate", "scheduleChange":
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            } else if let projectId = projectId {
                // Fallback to project details if no taskId
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        case "advanceNotice":
            // Local advance notice - open task or project details
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            } else if let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        default:
            print("[PUSH] Unknown type: \(type)")
        }
    }
}

// Add custom notification names as UIApplication extension
extension UIApplication {
    static let didRegisterForRemoteNotificationsWithDeviceTokenNotification = Notification.Name("UIApplicationDidRegisterForRemoteNotificationsWithDeviceToken")
    static let didFailToRegisterForRemoteNotificationsNotification = Notification.Name("UIApplicationDidFailToRegisterForRemoteNotifications")
}