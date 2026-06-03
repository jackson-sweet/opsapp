//
//  OnboardingTestSupport.swift
//  OPSTests
//

import Foundation
@testable import OPS

func clearOnboardingDefaults() {
    [
        "user_id",
        "currentUserId",
        "user_email",
        "user_password",
        "selected_user_type",
        "is_authenticated",
        "onboarding_completed",
        "company_id",
        "currentUserCompanyId",
        "ab_test_flow_step",
        OnboardingStorageKeys.stateV3,
        OnboardingStorageKeys.preSignupTutorialCompleted
    ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
}

struct FailingOnboardingService: OnboardingServiceProtocol {
    var syncError: Error?
    var completionError: Error?

    func syncUser(email: String, firstName: String?, lastName: String?, photoURL: String?) async throws -> SyncUserResponse {
        if let syncError {
            throw syncError
        }
        return SyncUserResponse(
            user: .init(
                id: "supabase-user-id",
                firstName: firstName ?? "",
                lastName: lastName ?? "",
                email: email,
                companyId: nil,
                userType: nil,
                role: nil,
                isActive: true
            ),
            company: nil
        )
    }

    func markOnboardingComplete(userId: String) async throws {
        if let completionError {
            throw completionError
        }
    }
}

