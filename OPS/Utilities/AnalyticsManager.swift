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

        print("[ANALYTICS] 📊 Tracked sign_up - method: \(method.rawValue), user_type: \(userType?.rawValue ?? "unknown")")
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

        print("[ANALYTICS] 📊 Tracked login - method: \(method.rawValue), user_type: \(userType?.rawValue ?? "unknown")")
    }

    /// Track app install / first open (automatic via Firebase, but can be called manually if needed)
    func trackFirstOpen() {
        // Firebase tracks first_open automatically
        // This method exists for explicit tracking if needed
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)

        print("[ANALYTICS] 📊 Tracked app_open")
    }

    // MARK: - Trial & Subscription Events

    /// Track when a user starts their free trial
    /// - Parameters:
    ///   - userType: The type of user
    ///   - trialDays: Number of days in the trial (default 30)
    func trackBeginTrial(userType: UserType?, trialDays: Int = 30) {
        var parameters: [String: Any] = [
            "trial_days": trialDays
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("begin_trial", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked begin_trial - user_type: \(userType?.rawValue ?? "unknown"), trial_days: \(trialDays)")
    }

    /// Track when a user subscribes (converts to paid)
    /// - Parameters:
    ///   - planName: Name of the subscription plan
    ///   - price: Price of the subscription
    ///   - currency: Currency code (default USD)
    ///   - userType: The type of user
    func trackSubscribe(planName: String, price: Double, currency: String = "USD", userType: UserType?) {
        var parameters: [String: Any] = [
            AnalyticsParameterItemName: planName,
            AnalyticsParameterPrice: price,
            AnalyticsParameterCurrency: currency
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        // Use Firebase's standard purchase event for better Google Ads integration
        Analytics.logEvent(AnalyticsEventPurchase, parameters: parameters)

        // Also log custom subscribe event for flexibility
        Analytics.logEvent("subscribe", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked subscribe - plan: \(planName), price: \(price) \(currency), user_type: \(userType?.rawValue ?? "unknown")")
    }

    // MARK: - Onboarding & Engagement Events

    /// Track when a user completes onboarding
    /// - Parameters:
    ///   - userType: The type of user
    ///   - hasCompany: Whether the user has/created a company
    func trackCompleteOnboarding(userType: UserType?, hasCompany: Bool) {
        var parameters: [String: Any] = [
            "has_company": hasCompany
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("complete_onboarding", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked complete_onboarding - user_type: \(userType?.rawValue ?? "unknown"), has_company: \(hasCompany)")
    }

    /// Track when a user creates their first project (high-intent signal)
    /// - Parameter userType: The type of user
    func trackCreateFirstProject(userType: UserType?) {
        var parameters: [String: Any] = [:]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("create_first_project", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked create_first_project - user_type: \(userType?.rawValue ?? "unknown")")
    }

    /// Track when a user creates a project (general tracking)
    /// - Parameters:
    ///   - projectCount: Total number of projects the user now has
    ///   - userType: The type of user
    func trackCreateProject(projectCount: Int, userType: UserType?) {
        var parameters: [String: Any] = [
            "project_count": projectCount
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("create_project", parameters: parameters)

        // Track first project separately for conversion optimization
        if projectCount == 1 {
            trackCreateFirstProject(userType: userType)
        }

        print("[ANALYTICS] 📊 Tracked create_project - count: \(projectCount), user_type: \(userType?.rawValue ?? "unknown")")
    }

    // MARK: - User Properties

    /// Set the user type as a user property for segmentation
    /// - Parameter userType: The type of user
    func setUserType(_ userType: UserType?) {
        if let userType = userType {
            Analytics.setUserProperty(userType.rawValue, forName: "user_type")
            print("[ANALYTICS] 📊 Set user property user_type: \(userType.rawValue)")
        }
    }

    /// Set the user ID for analytics
    /// - Parameter userId: The user's unique ID
    func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
        if let userId = userId {
            print("[ANALYTICS] 📊 Set user ID: \(userId)")
        }
    }

    /// Set subscription status as a user property
    /// - Parameter isSubscribed: Whether user has active subscription
    func setSubscriptionStatus(_ isSubscribed: Bool) {
        Analytics.setUserProperty(isSubscribed ? "subscribed" : "free", forName: "subscription_status")
        print("[ANALYTICS] 📊 Set user property subscription_status: \(isSubscribed ? "subscribed" : "free")")
    }
}

// MARK: - Supporting Types

enum SignUpMethod: String {
    case email = "email"
    case apple = "apple"
    case google = "google"
}
