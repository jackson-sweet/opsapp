//
//  AnalyticsManager.swift
//  OPS
//
//  Created for Google Ads conversion tracking via Firebase Analytics
//

import Foundation
import FirebaseAnalytics

/// Centralized analytics manager for tracking conversion events
/// Events flow to Google Ads via Firebase Analytics integration
final class AnalyticsManager {

    static let shared = AnalyticsManager()

    private init() {}

    // MARK: - Conversion Events

    /// Track when a new user completes sign-up
    /// - Parameters:
    ///   - userType: The type of user (employee or company/business owner)
    ///   - method: The sign-up method used (email, apple, google)
    func trackSignUp(userType: UserType?, method: SignUpMethod) {
        var parameters: [String: Any] = [
            AnalyticsParameterMethod: method.rawValue
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent(AnalyticsEventSignUp, parameters: parameters)

        print("[ANALYTICS] Tracked sign_up - method: \(method.rawValue), user_type: \(userType?.rawValue ?? "unknown")")
    }

    /// Track when a user logs in
    /// - Parameters:
    ///   - userType: The type of user (employee or company/business owner)
    ///   - method: The login method used (email, apple, google)
    func trackLogin(userType: UserType?, method: SignUpMethod) {
        var parameters: [String: Any] = [
            AnalyticsParameterMethod: method.rawValue
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent(AnalyticsEventLogin, parameters: parameters)

        print("[ANALYTICS] Tracked login - method: \(method.rawValue), user_type: \(userType?.rawValue ?? "unknown")")
    }

    /// Track app install / first open (automatic via Firebase, but can be called manually if needed)
    func trackFirstOpen() {
        // Firebase tracks first_open automatically
        // This method exists for explicit tracking if needed
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)

        print("[ANALYTICS] Tracked app_open")
    }

    // MARK: - User Properties

    /// Set the user type as a user property for segmentation
    /// - Parameter userType: The type of user
    func setUserType(_ userType: UserType?) {
        if let userType = userType {
            Analytics.setUserProperty(userType.rawValue, forName: "user_type")
            print("[ANALYTICS] Set user property user_type: \(userType.rawValue)")
        }
    }

    /// Set the user ID for analytics
    /// - Parameter userId: The user's unique ID
    func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
        if let userId = userId {
            print("[ANALYTICS] Set user ID: \(userId)")
        }
    }
}

// MARK: - Supporting Types

enum SignUpMethod: String {
    case email = "email"
    case apple = "apple"
    case google = "google"
}
