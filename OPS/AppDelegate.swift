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
        
        print("AppDelegate: Application did finish launching with options")
        
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
        print("AppDelegate: Successfully registered for remote notifications with device token")
        
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
        print("AppDelegate: Failed to register for remote notifications: \(error.localizedDescription)")
        
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
        print("AppDelegate: Running in simulator, skipping remote notifications registration")
        #endif
    }
}

// Add custom notification names as UIApplication extension
extension UIApplication {
    static let didRegisterForRemoteNotificationsWithDeviceTokenNotification = Notification.Name("UIApplicationDidRegisterForRemoteNotificationsWithDeviceToken")
    static let didFailToRegisterForRemoteNotificationsNotification = Notification.Name("UIApplicationDidFailToRegisterForRemoteNotifications")
}