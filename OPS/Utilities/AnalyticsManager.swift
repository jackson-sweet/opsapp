//
//  AnalyticsManager.swift
//  OPS
//
//  Deliberate Firebase conversion events used for Google Ads optimization.
//  Detailed product behaviour belongs exclusively to AnalyticsService.
//

import Foundation
import FirebaseAnalytics

final class AnalyticsManager {

    typealias EventLogger = (String, [String: Any]?) -> Void
    typealias UserPropertySetter = (String?, String) -> Void
    typealias UserIDSetter = (String?) -> Void

    static let shared = AnalyticsManager()

    static let firebaseConversionEventNames: Set<String> = [
        "sign_up",
        "begin_trial",
        "complete_onboarding",
        "create_first_project",
        "purchase"
    ]

    private let eventLogger: EventLogger
    private let userPropertySetter: UserPropertySetter
    private let userIDSetter: UserIDSetter

    init(
        eventLogger: @escaping EventLogger = { name, parameters in
            Analytics.logEvent(name, parameters: parameters)
        },
        userPropertySetter: @escaping UserPropertySetter = { value, name in
            Analytics.setUserProperty(value, forName: name)
        },
        userIDSetter: @escaping UserIDSetter = { value in
            Analytics.setUserID(value)
        }
    ) {
        self.eventLogger = eventLogger
        self.userPropertySetter = userPropertySetter
        self.userIDSetter = userIDSetter
    }

    // MARK: - Conversion events

    func trackSignUp(userType: UserType?, method: SignUpMethod) {
        eventLogger("sign_up", parameters(
            userType: userType,
            values: [AnalyticsParameterMethod: method.rawValue]
        ))
        debugLog("sign_up")
    }

    func trackBeginTrial(userType: UserType?, trialDays: Int = 30) {
        eventLogger("begin_trial", parameters(
            userType: userType,
            values: ["trial_days": trialDays]
        ))
        debugLog("begin_trial")
    }

    func trackCompleteOnboarding(userType: UserType?, hasCompany: Bool) {
        eventLogger("complete_onboarding", parameters(
            userType: userType,
            values: ["has_company": hasCompany]
        ))
        debugLog("complete_onboarding")
    }

    func trackCreateFirstProject(userType: UserType?) {
        eventLogger("create_first_project", parameters(userType: userType))
        debugLog("create_first_project")
    }

    func trackPurchase(
        planName: String,
        price: Double,
        currency: String = "USD",
        userType: UserType?
    ) {
        eventLogger("purchase", parameters(
            userType: userType,
            values: [
                AnalyticsParameterItemName: planName,
                AnalyticsParameterPrice: price,
                AnalyticsParameterCurrency: currency
            ]
        ))
        debugLog("purchase")
    }

    // MARK: - Conversion segmentation

    func setUserType(_ userType: UserType?) {
        userPropertySetter(userType?.rawValue, "user_type")
        debugLog("user_type_updated")
    }

    func setUserId(_ userId: String?) {
        userIDSetter(userId)
        debugLog("user_id_updated")
    }

    func setSubscriptionStatus(_ isSubscribed: Bool) {
        userPropertySetter(
            isSubscribed ? "subscribed" : "free",
            "subscription_status"
        )
        debugLog("subscription_status_updated")
    }

    private func parameters(
        userType: UserType?,
        values: [String: Any] = [:]
    ) -> [String: Any] {
        var result = values
        if let userType {
            result["user_type"] = userType.rawValue
        }
        return result
    }

    private func debugLog(_ event: String) {
        #if DEBUG
        print("[ANALYTICS] Firebase conversion: \(event)")
        #endif
    }
}

enum SignUpMethod: String {
    case email
    case apple
    case google
}

enum TabName: String {
    case home
    case pipeline
    case books
    case jobBoard = "job_board"
    case inventory
    case schedule
    case settings

    var index: Int {
        switch self {
        case .home: return 0
        case .pipeline: return 1
        case .books: return 2
        case .jobBoard: return 3
        case .inventory: return 4
        case .schedule: return 5
        case .settings: return 6
        }
    }
}

enum ClientImportMethod: String {
    case manual
    case contactImport = "contact_import"
}
