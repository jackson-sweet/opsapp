//
//  OnboardingCompletionTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

@MainActor
final class OnboardingCompletionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearOnboardingDefaults()
    }

    override func tearDown() {
        clearOnboardingDefaults()
        super.tearDown()
    }

    func testServerCompletionFailureDoesNotSetLocalCompletionOrAuthentication() async throws {
        let service = FailingOnboardingService(completionError: OnboardingServiceError.serverError("completion down"))
        let manager = OnboardingManager(dataController: DataController(), onboardingService: service)
        manager.state.userData.userId = "supabase-user-id"
        manager.state.companyData.companyId = "company-id"

        do {
            _ = try await manager.completeOnboardingAwaitingServerAck()
            XCTFail("Expected completion to fail before local onboarding is marked complete")
        } catch {
            XCTAssertFalse(UserDefaults.standard.bool(forKey: "onboarding_completed"))
            XCTAssertFalse(UserDefaults.standard.bool(forKey: "is_authenticated"))
            XCTAssertFalse(manager.dataControllerForTesting.currentUser?.hasCompletedAppOnboarding ?? false)
            XCTAssertEqual(manager.state.resumeBoundary, .completionPendingServerACK)
        }
    }

    func testCompanyIdWithoutServerCompletionStillShowsOnboarding() {
        let dataController = DataController()
        let user = User(
            id: "partial-user-id",
            firstName: "Jack",
            lastName: "Ops",
            role: .owner,
            companyId: "company-id"
        )
        user.userType = .company
        user.hasCompletedAppOnboarding = false
        dataController.currentUser = user
        dataController.isAuthenticated = true

        let (shouldShow, manager) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

        XCTAssertTrue(shouldShow)
        XCTAssertNotNil(manager)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "onboarding_completed"))
    }

    func testServerCompletedUserWithCompanyAndTypeSkipsOnboarding() {
        let dataController = DataController()
        let user = User(
            id: "complete-user-id",
            firstName: "Jack",
            lastName: "Ops",
            role: .owner,
            companyId: "company-id"
        )
        user.userType = .company
        user.hasCompletedAppOnboarding = true
        dataController.currentUser = user
        dataController.isAuthenticated = true

        let (shouldShow, manager) = OnboardingManager.shouldShowOnboarding(dataController: dataController)

        XCTAssertFalse(shouldShow)
        XCTAssertNil(manager)
    }
}
