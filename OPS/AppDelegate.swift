//
//  AppDelegate.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-09.
//

import UIKit
import UserNotifications
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        
        // Register for remote notifications
        // The actual permission request happens elsewhere through the NotificationManager
        registerForRemoteNotifications()
        
        return true
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
            print("AppDelegate: Failed to register for remote notifications: \(error.localizedDescription)")
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
}

// Add custom notification names as UIApplication extension
extension UIApplication {
    static let didRegisterForRemoteNotificationsWithDeviceTokenNotification = Notification.Name("UIApplicationDidRegisterForRemoteNotificationsWithDeviceToken")
    static let didFailToRegisterForRemoteNotificationsNotification = Notification.Name("UIApplicationDidFailToRegisterForRemoteNotifications")
}