//
//  OnboardingResumeTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class OnboardingResumeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearOnboardingDefaults()
    }

    override func tearDown() {
        clearOnboardingDefaults()
        super.tearDown()
    }

    func testResumeCompanyCreatorPostAuthPreCompanyLandsAtCompanyName() {
        var state = OnboardingState.initial
        state.flow = .companyCreator
        state.isAuthenticated = true
        state.resumeBoundary = .postAuthPreCompany

        let step = OnboardingABTestCoordinator.resumeStep(
            savedStep: .signup,
            hasAuth: true,
            state: state
        )

        XCTAssertEqual(step, .companyName)
    }

    func testResumeEmployeePostCodeFallsBackToCodeEntryWhenTransientConfirmationIsLost() {
        var state = OnboardingState.initial
        state.flow = .employee
        state.isAuthenticated = true
        state.resumeBoundary = .employeePostCode
        state.companyData.companyCode = "OPS123"

        let step = OnboardingABTestCoordinator.resumeStep(
            savedStep: .employeeConfirmation,
            hasAuth: true,
            state: state
        )

        XCTAssertEqual(step, .employeeCodeEntry)
    }

    func testResumeEmployeePostJoinPreProfileLandsAtProfile() {
        var state = OnboardingState.initial
        state.flow = .employee
        state.isAuthenticated = true
        state.hasExistingCompany = true
        state.companyData.companyId = "company-id"
        state.resumeBoundary = .employeePostJoinPreProfile

        let step = OnboardingABTestCoordinator.resumeStep(
            savedStep: .employeeConfirmation,
            hasAuth: true,
            state: state
        )

        XCTAssertEqual(step, .employeeProfile)
    }

    func testResumeCompletionBeforeServerAckRetriesCompletionScreen() {
        var state = OnboardingState.initial
        state.flow = .companyCreator
        state.isAuthenticated = true
        state.resumeBoundary = .completionPendingServerACK

        let step = OnboardingABTestCoordinator.resumeStep(
            savedStep: .complete,
            hasAuth: true,
            state: state
        )

        XCTAssertEqual(step, .complete)
    }
}

