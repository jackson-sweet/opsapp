//
//  OnboardingIdentityRecoveryTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

@MainActor
final class OnboardingIdentityRecoveryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearOnboardingDefaults()
    }

    override func tearDown() {
        clearOnboardingDefaults()
        super.tearDown()
    }

    func testSocialSyncFailureDoesNotPersistFirebaseUIDAsCurrentUser() async throws {
        let firebaseUID = "firebase-social-uid"
        UserDefaults.standard.set(firebaseUID, forKey: "user_id")
        UserDefaults.standard.set(firebaseUID, forKey: "currentUserId")

        let manager = OnboardingManager(
            dataController: DataController(),
            onboardingService: FailingOnboardingService(syncError: OnboardingServiceError.serverError("sync down"))
        )
        manager.state.flow = .companyCreator

        do {
            try await manager.handleSocialAuth(
                userId: firebaseUID,
                email: "operator@ops.test",
                firstName: "Jackson",
                lastName: "Sweet"
            )
            XCTFail("Expected social auth to fail closed when syncUser fails")
        } catch {
            XCTAssertNil(manager.state.userData.userId)
            XCTAssertEqual(manager.state.userData.email, "operator@ops.test")
            XCTAssertEqual(manager.state.authSyncStatus, .syncFailed)
            XCTAssertTrue(manager.state.isAuthenticated)
            XCTAssertNil(UserDefaults.standard.string(forKey: "user_id"))
            XCTAssertNil(UserDefaults.standard.string(forKey: "currentUserId"))
            XCTAssertEqual(ABTestFlowStep.loadSaved(), .signup)
        }
    }
}

