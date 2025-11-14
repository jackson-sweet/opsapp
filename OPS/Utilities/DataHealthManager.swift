//
//  DataHealthManager.swift
//  OPS
//
//  Centralized manager for validating data integrity and handling recovery scenarios
//

import Foundation
import SwiftData

/// Represents the current health state of the app's data
enum DataHealthState: Equatable {
    case healthy
    case missingUserId
    case missingUserData
    case missingCompanyId
    case missingCompanyData
    case syncManagerNotInitialized
    case modelContextNotAvailable

    var isHealthy: Bool {
        return self == .healthy
    }
}

/// Recovery action to take when data is unhealthy
enum DataRecoveryAction {
    case logout
    case returnToOnboarding(step: OnboardingStep)
    case fetchUserFromAPI
    case fetchCompanyFromAPI
    case reinitializeSyncManager
    case none
}

@MainActor
class DataHealthManager: ObservableObject {
    private let dataController: DataController
    private let authManager: AuthManager

    @Published var lastHealthCheck: Date?
    @Published var currentHealthState: DataHealthState = .healthy

    init(dataController: DataController, authManager: AuthManager) {
        self.dataController = dataController
        self.authManager = authManager
    }

    // MARK: - Health Checks

    /// Performs a comprehensive health check on all critical data
    /// Returns the current health state and recommended recovery action
    func performHealthCheck() async -> (state: DataHealthState, action: DataRecoveryAction) {
        print("[DATA_HEALTH] 🏥 Performing comprehensive health check...")

        // 1. Check for user ID
        guard let userId = UserDefaults.standard.string(forKey: "user_id"), !userId.isEmpty else {
            print("[DATA_HEALTH] ❌ No user ID found")
            currentHealthState = .missingUserId
            return (.missingUserId, .logout)
        }

        print("[DATA_HEALTH] ✅ User ID exists: \(userId)")

        // 2. Check for currentUser in DataController
        if dataController.currentUser == nil {
            print("[DATA_HEALTH] ⚠️ User ID exists but currentUser is nil - attempting to fetch from SwiftData")

            // Try to load user from SwiftData
            if let loadedUser = await loadUserFromSwiftData(userId: userId) {
                dataController.currentUser = loadedUser
                print("[DATA_HEALTH] ✅ Successfully loaded user from SwiftData")
            } else {
                print("[DATA_HEALTH] ❌ User not found in SwiftData - need to fetch from API")
                currentHealthState = .missingUserData
                return (.missingUserData, .fetchUserFromAPI)
            }
        }

        guard let user = dataController.currentUser else {
            currentHealthState = .missingUserData
            return (.missingUserData, .fetchUserFromAPI)
        }

        print("[DATA_HEALTH] ✅ Current user exists: \(user.fullName)")

        // 3. Check for company ID
        if user.companyId == nil || user.companyId?.isEmpty == true {
            print("[DATA_HEALTH] ⚠️ User has no company ID")

            // Fetch user from API to see if they have a company in Bubble
            if let apiUser = await fetchUserFromAPI(userId: userId) {
                if let apiCompanyId = apiUser.companyId, !apiCompanyId.isEmpty {
                    // User has company in Bubble but not locally - update local
                    user.companyId = apiCompanyId
                    try? dataController.modelContext?.save()
                    print("[DATA_HEALTH] ✅ Updated user with company ID from API: \(apiCompanyId)")
                } else {
                    // User has no company in Bubble either - send to company join
                    print("[DATA_HEALTH] ❌ User has no company in Bubble - return to onboarding")
                    currentHealthState = .missingCompanyId
                    return (.missingCompanyId, .returnToOnboarding(step: .companyCode))
                }
            } else {
                print("[DATA_HEALTH] ❌ Failed to fetch user from API - logout")
                currentHealthState = .missingUserData
                return (.missingUserData, .logout)
            }
        }

        guard let companyId = user.companyId, !companyId.isEmpty else {
            print("[DATA_HEALTH] ❌ Company ID still missing after checks")
            currentHealthState = .missingCompanyId
            return (.missingCompanyId, .returnToOnboarding(step: .companyCode))
        }

        print("[DATA_HEALTH] ✅ Company ID exists: \(companyId)")

        // 4. Check for company data in SwiftData
        if dataController.getCurrentUserCompany() == nil {
            print("[DATA_HEALTH] ⚠️ Company ID exists but company not found in SwiftData")
            currentHealthState = .missingCompanyData
            return (.missingCompanyData, .fetchCompanyFromAPI)
        }

        print("[DATA_HEALTH] ✅ Company data exists")

        // 5. Check SyncManager initialization
        guard dataController.syncManager != nil else {
            print("[DATA_HEALTH] ⚠️ SyncManager is nil")
            currentHealthState = .syncManagerNotInitialized
            return (.syncManagerNotInitialized, .reinitializeSyncManager)
        }

        print("[DATA_HEALTH] ✅ SyncManager initialized")

        // 6. Check ModelContext
        guard dataController.modelContext != nil else {
            print("[DATA_HEALTH] ❌ ModelContext is nil")
            currentHealthState = .modelContextNotAvailable
            return (.modelContextNotAvailable, .logout)
        }

        print("[DATA_HEALTH] ✅ ModelContext available")

        // All checks passed
        print("[DATA_HEALTH] ✅ All health checks passed - data is healthy")
        currentHealthState = .healthy
        lastHealthCheck = Date()
        return (.healthy, .none)
    }

    // MARK: - Recovery Actions

    /// Executes the appropriate recovery action for the current unhealthy state
    func executeRecoveryAction(_ action: DataRecoveryAction) async {
        print("[DATA_HEALTH] 🔧 Executing recovery action: \(action)")

        switch action {
        case .logout:
            await performLogout()

        case .returnToOnboarding(let step):
            await returnToOnboarding(step: step)

        case .fetchUserFromAPI:
            await fetchAndStoreUserData()

        case .fetchCompanyFromAPI:
            await fetchAndStoreCompanyData()

        case .reinitializeSyncManager:
            await reinitializeSyncManager()

        case .none:
            print("[DATA_HEALTH] ℹ️ No recovery action needed")
        }
    }

    // MARK: - Private Helper Methods

    private func loadUserFromSwiftData(userId: String) async -> User? {
        print("[DATA_HEALTH] 🔍 Attempting to load user from SwiftData: \(userId)")

        guard let modelContext = dataController.modelContext else {
            print("[DATA_HEALTH] ❌ ModelContext is nil, cannot load user")
            return nil
        }

        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { $0.id == userId }
        )

        do {
            let users = try modelContext.fetch(descriptor)
            if let user = users.first {
                print("[DATA_HEALTH] ✅ Found user in SwiftData: \(user.fullName)")
                return user
            } else {
                print("[DATA_HEALTH] ⚠️ User not found in SwiftData")
                return nil
            }
        } catch {
            print("[DATA_HEALTH] ❌ Error fetching user from SwiftData: \(error)")
            return nil
        }
    }

    private func fetchUserFromAPI(userId: String) async -> User? {
        // Note: APIService doesn't have a direct getUser method
        // This would need to be implemented or we fetch via sync
        print("[DATA_HEALTH] ⚠️ fetchUserFromAPI not yet implemented")
        return nil
    }

    private func fetchAndStoreUserData() async {
        // Note: This should trigger a user sync via syncManager
        print("[DATA_HEALTH] 🔄 User data fetch would be triggered here")
        // TODO: Implement user-specific sync if needed
    }

    private func fetchAndStoreCompanyData() async {
        guard let syncManager = dataController.syncManager else {
            print("[DATA_HEALTH] ❌ Cannot fetch company - syncManager is nil")
            return
        }

        do {
            print("[DATA_HEALTH] 🔄 Fetching company data from API...")
            try await syncManager.syncCompany()
            print("[DATA_HEALTH] ✅ Company data fetched and stored")
        } catch {
            print("[DATA_HEALTH] ❌ Failed to fetch company data: \(error)")
        }
    }

    private func reinitializeSyncManager() async {
        print("[DATA_HEALTH] 🔄 Reinitializing SyncManager...")

        guard let modelContext = dataController.modelContext else {
            print("[DATA_HEALTH] ❌ Cannot reinitialize SyncManager - modelContext is nil")
            return
        }

        // Call setModelContext again to trigger sync manager initialization
        print("[DATA_HEALTH] 📞 Calling setModelContext to reinitialize SyncManager")
        await dataController.setModelContext(modelContext)

        // Wait a moment for initialization to complete
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Verify it worked
        if dataController.syncManager != nil {
            print("[DATA_HEALTH] ✅ SyncManager successfully reinitialized")
        } else {
            print("[DATA_HEALTH] ❌ SyncManager still nil after reinitialization attempt")
        }
    }

    private func performLogout() async {
        print("[DATA_HEALTH] 🚪 Performing logout...")
        // Clear all user data
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "company_id")
        UserDefaults.standard.set(false, forKey: "is_authenticated")
        UserDefaults.standard.set(false, forKey: "onboarding_completed")

        // Clear current user
        dataController.currentUser = nil

        print("[DATA_HEALTH] ✅ Logout completed - user will be redirected to login")
    }

    private func returnToOnboarding(step: OnboardingStep) async {
        print("[DATA_HEALTH] 🔄 Returning to onboarding step: \(step)")
        // Clear onboarding completion flag
        UserDefaults.standard.set(false, forKey: "onboarding_completed")
        // The app's routing logic should detect this and show onboarding
    }

    // MARK: - Convenience Methods

    /// Quick check if we have the bare minimum data to function
    func hasMinimumRequiredData() -> Bool {
        print("[DATA_HEALTH] 🔎 Checking for minimum required data...")

        guard let userId = UserDefaults.standard.string(forKey: "user_id"), !userId.isEmpty else {
            print("[DATA_HEALTH] ❌ Minimum data check failed: No user ID")
            return false
        }

        guard dataController.currentUser != nil else {
            print("[DATA_HEALTH] ❌ Minimum data check failed: No current user")
            return false
        }

        guard dataController.modelContext != nil else {
            print("[DATA_HEALTH] ❌ Minimum data check failed: No model context")
            return false
        }

        print("[DATA_HEALTH] ✅ Minimum required data present")
        return true
    }

    /// Checks if sync operations can be performed
    func canPerformSync() -> Bool {
        print("[DATA_HEALTH] 🔎 Checking if sync operations can be performed...")

        guard hasMinimumRequiredData() else {
            print("[DATA_HEALTH] ❌ Cannot perform sync: Minimum data requirements not met")
            return false
        }

        guard dataController.syncManager != nil else {
            print("[DATA_HEALTH] ❌ Cannot perform sync: SyncManager is nil")
            return false
        }

        guard dataController.currentUser?.companyId != nil else {
            print("[DATA_HEALTH] ❌ Cannot perform sync: User has no company ID")
            return false
        }

        print("[DATA_HEALTH] ✅ Sync operations can be performed")
        return true
    }
}
