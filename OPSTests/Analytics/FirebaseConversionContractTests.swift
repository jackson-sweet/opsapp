import XCTest
@testable import OPS

final class FirebaseConversionContractTests: XCTestCase {

    func test_firebaseEmitsExactlyTheFiveDeliberateConversionEvents() {
        var names: [String] = []
        let manager = AnalyticsManager(
            eventLogger: { name, _ in names.append(name) },
            userPropertySetter: { _, _ in },
            userIDSetter: { _ in }
        )

        manager.trackSignUp(userType: .company, method: .apple)
        manager.trackBeginTrial(userType: .company, trialDays: 30)
        manager.trackCompleteOnboarding(userType: .company, hasCompany: true)
        manager.trackCreateFirstProject(userType: .company)
        manager.trackPurchase(
            planName: "OPS Pro",
            price: 99,
            currency: "CAD",
            userType: .company
        )
        manager.setUserType(.company)
        manager.setUserId("private-user-id")
        manager.setSubscriptionStatus(true)

        XCTAssertEqual(names, [
            "sign_up",
            "begin_trial",
            "complete_onboarding",
            "create_first_project",
            "purchase"
        ])
        XCTAssertEqual(Set(names), AnalyticsManager.firebaseConversionEventNames)
    }
}
