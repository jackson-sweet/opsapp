//
//  OnboardingManager.swift
//  OPS
//
//  New onboarding manager for the simplified v3 flow.
//  Replaces the old OnboardingManager as part of the new onboarding system.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
class OnboardingManager: ObservableObject {

    // MARK: - Published State

    @Published var state: OnboardingState
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var navigationDirection: NavigationDirection = .forward

    enum NavigationDirection {
        case forward
        case backward
    }

    // MARK: - Dependencies

    private let dataController: DataController
    private let onboardingService: OnboardingService
    private let apiService: APIService

    // MARK: - Callbacks

    var onComplete: (() -> Void)?

    // MARK: - Initialization

    init(dataController: DataController) {
        self.dataController = dataController
        self.onboardingService = OnboardingService()
        self.apiService = APIService(authManager: dataController.authManager)

        // Load saved state or create initial
        if let savedState = OnboardingState.load() {
            self.state = savedState
            print("[ONBOARDING_MANAGER] Loaded saved state: \(savedState.currentScreen)")

            // If resuming with an existing userId, ensure local user and sync manager are initialized
            if let userId = savedState.userData.userId, !userId.isEmpty {
                print("[ONBOARDING_MANAGER] Resuming with userId: \(userId), will restore local state")
                Task { @MainActor in
                    await self.restoreLocalUserState(userId: userId)
                }
            }
        } else {
            self.state = OnboardingState.initial
            print("[ONBOARDING_MANAGER] Created initial state")
        }
    }

    /// Restore local user state when resuming mid-onboarding
    /// Ensures the local User exists and sync manager is initialized
    private func restoreLocalUserState(userId: String) async {
        print("[ONBOARDING_MANAGER] Restoring local user state for userId: \(userId)")

        guard let modelContext = dataController.modelContext else {
            print("[ONBOARDING_MANAGER] ⚠️ No modelContext available for restore!")
            return
        }

        // Check if user exists locally
        let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == userId })
        if let existingUser = try? modelContext.fetch(descriptor).first {
            print("[ONBOARDING_MANAGER] ✅ Found existing local user")
            dataController.currentUser = existingUser
        } else {
            // User doesn't exist locally - create from saved state
            print("[ONBOARDING_MANAGER] Creating local user from saved state...")
            let userType = state.flow?.userType ?? .employee
            let newUser = User(
                id: userId,
                firstName: state.userData.firstName,
                lastName: state.userData.lastName,
                role: userType == .company ? .admin : .fieldCrew,
                companyId: state.companyData.companyId ?? ""
            )
            newUser.email = state.userData.email
            newUser.userType = userType
            newUser.isActive = true

            modelContext.insert(newUser)
            do {
                try modelContext.save()
                print("[ONBOARDING_MANAGER] ✅ Created local user from saved state")
                dataController.currentUser = newUser
            } catch {
                print("[ONBOARDING_MANAGER] ❌ Failed to create local user: \(error)")
            }
        }

        // Ensure currentUserId is set in UserDefaults
        if UserDefaults.standard.string(forKey: "currentUserId") != userId {
            UserDefaults.standard.set(userId, forKey: "currentUserId")
            print("[ONBOARDING_MANAGER] Set currentUserId in UserDefaults")
        }

        // Initialize sync manager if needed
        if dataController.syncManager == nil {
            print("[ONBOARDING_MANAGER] Initializing SyncManager for resumed session...")
            dataController.initializeSyncManager()
        }

        print("[ONBOARDING_MANAGER] ✅ Local state restored - currentUser: \(dataController.currentUser?.id ?? "nil"), syncManager: \(dataController.syncManager != nil)")
    }

    // MARK: - Static Methods (for app integration)

    /// Clear any saved onboarding state
    static func clearState() {
        OnboardingState.clear()
        print("[ONBOARDING_MANAGER] State cleared")
    }

    /// Check if onboarding should be shown and return a manager if so
    @MainActor
    static func shouldShowOnboarding(dataController: DataController) -> (Bool, OnboardingManager?) {
        // Check if user is authenticated
        guard dataController.isAuthenticated else {
            // Not logged in - show welcome screen
            let manager = OnboardingManager(dataController: dataController)
            return (true, manager)
        }

        // Check if currentUser exists
        guard let user = dataController.currentUser else {
            let manager = OnboardingManager(dataController: dataController)
            return (true, manager)
        }

        // CRITICAL: Check if user has already completed onboarding
        if user.hasCompletedAppOnboarding {
            // Clear any stale saved state
            OnboardingState.clear()
            print("[ONBOARDING_MANAGER] User has completed onboarding, skipping")
            return (false, nil)
        }

        // Check if user has userType set
        let hasUserType = user.userType != nil

        // Check if user has company
        let hasCompany = user.companyId != nil && !user.companyId!.isEmpty

        // Check for saved state that needs to be resumed
        if let savedState = OnboardingState.load() {
            let manager = OnboardingManager(dataController: dataController)
            manager.state = savedState
            return (true, manager)
        }

        // If missing userType, need to complete onboarding
        if !hasUserType {
            let manager = OnboardingManager(dataController: dataController)
            manager.goToScreen(.userTypeSelection)
            return (true, manager)
        }

        // All conditions met - no onboarding needed
        return (false, nil)
    }

    // MARK: - Navigation

    /// Navigate to a specific screen (forward direction by default)
    func goToScreen(_ screen: OnboardingScreen, direction: NavigationDirection = .forward) {
        print("[ONBOARDING_MANAGER] Navigating to: \(screen) (direction: \(direction))")
        navigationDirection = direction
        state.currentScreen = screen
        state.save()
    }

    /// Go back to previous screen (if applicable)
    func goBack() {
        switch state.currentScreen {
        case .welcome:
            // Can't go back from welcome
            break

        case .login, .signup:
            goToScreen(.welcome, direction: .backward)

        case .userTypeSelection:
            // Back to welcome (logout scenario)
            goToScreen(.welcome, direction: .backward)

        case .credentials:
            goToScreen(.signup, direction: .backward)

        case .profile:
            goToScreen(.credentials, direction: .backward)

        case .companySetup:
            goToScreen(.profile, direction: .backward)

        case .companyDetails:
            goToScreen(.companySetup, direction: .backward)

        case .companyCode:
            // Can't go back from success screen
            break

        case .profileCompany:
            if state.profileCompanyPhase == .form {
                goToScreen(.credentials, direction: .backward)
            }
            // Can't go back during processing or success

        case .codeEntry:
            goToScreen(.profile, direction: .backward)

        case .profileJoin:
            if state.profileJoinPhase == .form {
                goToScreen(.profile, direction: .backward)
            }
            // Can't go back during joining

        case .ready:
            // Can't go back from ready
            break
        }
    }

    /// Navigate forward based on current flow
    func goForward() {
        switch state.currentScreen {
        case .welcome:
            goToScreen(.signup)

        case .login:
            // After login, resume based on user data
            resume()

        case .signup:
            goToScreen(.credentials)

        case .userTypeSelection:
            // After selecting type, go to profile then appropriate next screen
            goToScreen(.profile)

        case .credentials:
            // After auth, go to profile screen
            goToScreen(.profile)

        case .profile:
            // After profile, go to company setup or join based on flow
            if state.flow == .companyCreator {
                goToScreen(.companySetup)
            } else {
                goToScreen(.profileJoin)
            }

        case .companySetup:
            goToScreen(.companyDetails)

        case .companyDetails:
            goToScreen(.companyCode)

        case .companyCode:
            goToScreen(.ready)

        case .profileCompany:
            goToScreen(.ready)

        case .codeEntry:
            goToScreen(.ready)

        case .profileJoin:
            goToScreen(.ready)

        case .ready:
            completeOnboarding()
        }
    }

    // MARK: - Flow Selection

    /// Set the onboarding flow (company creator or employee)
    func selectFlow(_ flow: OnboardingFlow) {
        print("[ONBOARDING_MANAGER] Flow selected: \(flow)")
        state.flow = flow
        state.save()
    }

    // MARK: - Resume Logic

    /// Determine the resume screen based on user data from Bubble
    /// Call this after authentication to figure out where to resume
    func determineResumeScreen() -> OnboardingScreen {
        guard let user = dataController.currentUser else {
            print("[ONBOARDING_MANAGER] No current user, starting from welcome")
            return .welcome
        }

        print("[ONBOARDING_MANAGER] Determining resume screen for user: \(user.fullName)")
        print("[ONBOARDING_MANAGER] - hasCompletedAppOnboarding: \(user.hasCompletedAppOnboarding)")
        print("[ONBOARDING_MANAGER] - userType: \(user.userType?.rawValue ?? "nil")")
        print("[ONBOARDING_MANAGER] - firstName: '\(user.firstName)'")
        print("[ONBOARDING_MANAGER] - lastName: '\(user.lastName)'")
        print("[ONBOARDING_MANAGER] - companyId: '\(user.companyId ?? "nil")'")

        // Step 1: Already completed?
        if user.hasCompletedAppOnboarding {
            print("[ONBOARDING_MANAGER] User already completed onboarding")
            return .ready // Will trigger completion
        }

        // Step 2: No user type?
        guard let userType = user.userType else {
            print("[ONBOARDING_MANAGER] No userType, showing selection")
            return .userTypeSelection
        }

        // Set the flow based on userType
        state.flow = OnboardingFlow(from: userType)

        // Pre-fill user data from database
        prefillUserData(from: user)

        // Step 3: Profile incomplete? (check name BEFORE company per requirements)
        let hasName = !user.firstName.isEmpty && !user.lastName.isEmpty
        if !hasName {
            print("[ONBOARDING_MANAGER] Name incomplete, showing profile screen")
            return userType == .company ? .profileCompany : .profileJoin
        }

        // Step 4: No company?
        let hasCompany = !(user.companyId ?? "").isEmpty
        if !hasCompany {
            print("[ONBOARDING_MANAGER] No company, showing profile screen")
            return userType == .company ? .profileCompany : .profileJoin
        }

        // Pre-fill company data if exists
        prefillCompanyData()

        // All data exists
        print("[ONBOARDING_MANAGER] All data exists, showing ready screen")
        return .ready
    }

    /// Resume onboarding from the appropriate screen
    func resume() {
        let screen = determineResumeScreen()
        goToScreen(screen)
    }

    // MARK: - Pre-fill Logic

    /// Pre-fill user data from the current user
    private func prefillUserData(from user: User) {
        if !user.firstName.isEmpty {
            state.userData.firstName = user.firstName
        }
        if !user.lastName.isEmpty {
            state.userData.lastName = user.lastName
        }
        if let phone = user.phone, !phone.isEmpty {
            state.userData.phone = phone
        }
        state.userData.email = user.email ?? ""
        state.userData.userId = user.id
        state.userData.avatarURL = user.profileImageURL

        // Check if user already has a company
        state.hasExistingCompany = !(user.companyId ?? "").isEmpty

        print("[ONBOARDING_MANAGER] Pre-filled user data from database")
    }

    /// Pre-fill company data from the current company
    private func prefillCompanyData() {
        // Try to get company from context
        guard let companyId = dataController.currentUser?.companyId,
              !companyId.isEmpty else { return }

        // Fetch company from context
        if let modelContext = dataController.modelContext {
            let targetId = companyId
            let descriptor = FetchDescriptor<Company>(predicate: #Predicate<Company> { company in
                company.id == targetId
            })
            if let company = try? modelContext.fetch(descriptor).first {
                state.companyData.companyId = company.id
                state.companyData.name = company.name
                state.companyData.companyCode = company.externalId // externalId is the code
                state.companyData.email = company.email ?? ""
                state.companyData.phone = company.phone ?? ""
                state.companyData.address = company.address ?? ""
                state.companyData.logoURL = company.logoURL

                // Industry is stored as a string
                if !company.industryString.isEmpty {
                    state.companyData.industry = company.industryString
                }
                state.companyData.size = company.companySize ?? ""
                state.companyData.age = company.companyAge ?? ""

                print("[ONBOARDING_MANAGER] Pre-filled company data from database")
            }
        }
    }

    // MARK: - API Actions

    /// Create account with email/password
    func createAccount(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let flow = state.flow else {
            throw OnboardingManagerError.noFlowSelected
        }

        print("[ONBOARDING_MANAGER] Creating account for: \(email)")

        do {
            // Sign up using OnboardingService
            let response = try await onboardingService.signUpUser(
                email: email,
                password: password,
                userType: flow.userType
            )

            guard response.wasSuccessful, let userId = response.extractedUserId else {
                let message = response.error_message ?? "Account creation failed"
                throw OnboardingManagerError.serverError(message)
            }

            // Store credentials - CRITICAL: Set both user_id AND currentUserId
            state.userData.email = email
            state.userData.userId = userId
            UserDefaults.standard.set(email, forKey: "user_email")
            UserDefaults.standard.set(password, forKey: "user_password")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId") // Required for CentralizedSyncManager
            UserDefaults.standard.set(flow.userType.rawValue, forKey: "selected_user_type")

            state.isAuthenticated = true
            state.save()

            print("[ONBOARDING_MANAGER] Account created successfully: \(userId)")

            // CRITICAL: Create local User object in SwiftData
            await createLocalUser(userId: userId, email: email, userType: flow.userType)
            print("[ONBOARDING_MANAGER] Local user created and DataController initialized")

            // PATCH userType to Bubble (required by spec)
            try await patchUserType(userId: userId, userType: flow.userType)

        } catch let error as SignUpError {
            throw OnboardingManagerError.serverError(error.localizedDescription)
        }
    }

    /// Handle social auth callback
    func handleSocialAuth(userId: String, email: String, firstName: String?, lastName: String?) async throws {
        print("[ONBOARDING_MANAGER] Handling social auth for: \(email)")

        state.userData.userId = userId
        state.userData.email = email
        if let firstName = firstName, !firstName.isEmpty {
            state.userData.firstName = firstName
        }
        if let lastName = lastName, !lastName.isEmpty {
            state.userData.lastName = lastName
        }

        state.isAuthenticated = true

        // Store for later - CRITICAL: Set both user_id AND currentUserId
        UserDefaults.standard.set(userId, forKey: "user_id")
        UserDefaults.standard.set(userId, forKey: "currentUserId") // Required for CentralizedSyncManager
        UserDefaults.standard.set(email, forKey: "user_email")

        // PATCH userType if we have a flow selected
        if let flow = state.flow {
            UserDefaults.standard.set(flow.userType.rawValue, forKey: "selected_user_type")
            try await patchUserType(userId: userId, userType: flow.userType)

            // CRITICAL: Create local User object in SwiftData
            await createLocalUser(userId: userId, email: email, userType: flow.userType)
            print("[ONBOARDING_MANAGER] Local user created for social auth")
        }

        state.save()
    }

    /// PATCH userType to Bubble
    private func patchUserType(userId: String, userType: UserType) async throws {
        print("[ONBOARDING_MANAGER] PATCHing userType '\(userType.rawValue)' for user \(userId)")

        let fields: [String: Any] = ["userType": userType.rawValue]
        try await apiService.updateUser(userId: userId, fields: fields)

        print("[ONBOARDING_MANAGER] userType PATCHed successfully")
    }

    /// Update user's userType selection (for UserTypeSelection screen)
    func updateUserType(_ userType: UserType) async throws {
        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        state.flow = OnboardingFlow(from: userType)
        try await patchUserType(userId: userId, userType: userType)
        state.save()
    }

    /// Create a new company (Company Creator flow)
    func createCompany() async throws -> String {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        print("[ONBOARDING_MANAGER] ========== CREATE COMPANY START ==========")
        print("[ONBOARDING_MANAGER] Creating company: \(state.companyData.name)")
        print("[ONBOARDING_MANAGER] userId: \(userId)")

        state.profileCompanyPhase = .processing

        do {
            // First update user profile
            try await updateUserProfile()

            // Create company via OnboardingService
            let response = try await onboardingService.updateCompany(
                companyId: state.companyData.companyId, // nil for new, ID for update
                name: state.companyData.name,
                email: state.companyData.email,
                phone: state.companyData.phone.isEmpty ? nil : state.companyData.phone,
                industry: state.companyData.industry,
                size: state.companyData.size,
                age: state.companyData.age,
                address: state.companyData.address,
                userId: userId,
                firstName: state.userData.firstName,
                lastName: state.userData.lastName,
                userPhone: state.userData.phone
            )

            guard response.wasSuccessful,
                  let company = response.extractedCompany,
                  let companyId = company.extractedId else {
                throw OnboardingManagerError.serverError("Company creation failed")
            }

            // Store company data
            state.companyData.companyId = companyId
            state.companyData.companyCode = company.extractedCode ?? companyId
            print("[ONBOARDING_MANAGER] Company created in Bubble:")
            print("[ONBOARDING_MANAGER]   - companyId: \(companyId)")
            print("[ONBOARDING_MANAGER]   - companyCode: \(state.companyData.companyCode ?? "unknown")")

            state.profileCompanyPhase = .success
            state.hasExistingCompany = true
            state.save()

            // CRITICAL: Update local user's companyId before syncing company
            // syncCompany() relies on currentUser?.companyId to fetch company data
            if let currentUser = dataController.currentUser {
                print("[ONBOARDING_MANAGER] DataController.currentUser exists:")
                print("[ONBOARDING_MANAGER]   - id: \(currentUser.id)")
                print("[ONBOARDING_MANAGER]   - companyId BEFORE: \(currentUser.companyId ?? "nil")")
                currentUser.companyId = companyId
                print("[ONBOARDING_MANAGER] ✅ Updated local user companyId to: \(companyId)")
                print("[ONBOARDING_MANAGER]   - companyId AFTER: \(currentUser.companyId ?? "nil")")
            } else {
                print("[ONBOARDING_MANAGER] ⚠️ DataController.currentUser is NIL! Cannot set companyId!")
            }

            // Trigger sync to load company data
            if let syncManager = dataController.syncManager {
                print("[ONBOARDING_MANAGER] Triggering company sync...")
                try? await syncManager.syncCompany()
                print("[ONBOARDING_MANAGER] Company sync triggered")
            } else {
                print("[ONBOARDING_MANAGER] ⚠️ SyncManager is NIL!")
            }

            print("[ONBOARDING_MANAGER] ========== CREATE COMPANY END ==========")
            print("[ONBOARDING_MANAGER] Company created: \(companyId), code: \(state.companyData.companyCode ?? "unknown")")

            return state.companyData.companyCode ?? companyId

        } catch {
            state.profileCompanyPhase = .form
            throw error
        }
    }

    /// Join an existing company (Employee flow)
    func joinCompany(code: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        print("[ONBOARDING_MANAGER] Joining company with code: \(code)")

        state.profileJoinPhase = .joining

        do {
            // First update user profile
            try await updateUserProfile()

            // Store user data in UserDefaults for join_company API
            UserDefaults.standard.set(state.userData.firstName, forKey: "user_first_name")
            UserDefaults.standard.set(state.userData.lastName, forKey: "user_last_name")
            UserDefaults.standard.set(state.userData.phone, forKey: "user_phone_number")

            // Join company via OnboardingService
            let companyId = try await onboardingService.joinCompany(
                code: code,
                userId: userId,
                dataController: dataController
            )

            state.companyData.companyId = companyId
            state.companyData.companyCode = code
            state.hasExistingCompany = true
            state.save()

            // CRITICAL: Update local user's companyId before syncing company
            if let currentUser = dataController.currentUser {
                currentUser.companyId = companyId
                print("[ONBOARDING_MANAGER] Updated local user companyId to: \(companyId)")
            }

            // Trigger sync to load company data
            if let syncManager = dataController.syncManager {
                try? await syncManager.syncCompany()
                print("[ONBOARDING_MANAGER] Company sync triggered after join")
            }

            print("[ONBOARDING_MANAGER] Joined company: \(companyId)")

        } catch {
            state.profileJoinPhase = .form
            if let signUpError = error as? SignUpError {
                if case .companyJoinFailed = signUpError {
                    throw OnboardingManagerError.invalidCompanyCode
                }
                throw OnboardingManagerError.serverError(signUpError.localizedDescription)
            }
            throw error
        }
    }

    /// Update user profile to Bubble
    private func updateUserProfile() async throws {
        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        print("[ONBOARDING_MANAGER] Updating user profile for: \(userId)")

        var fields: [String: Any] = [
            "nameFirst": state.userData.firstName,
            "nameLast": state.userData.lastName
        ]

        if !state.userData.phone.isEmpty {
            fields["phone"] = state.userData.phone
        }

        try await apiService.updateUser(userId: userId, fields: fields)

        print("[ONBOARDING_MANAGER] User profile updated")
    }

    /// Create a local User object in SwiftData and initialize DataController
    /// This is CRITICAL for sync to work during onboarding
    private func createLocalUser(userId: String, email: String, userType: UserType) async {
        print("[ONBOARDING_MANAGER] Creating local user in SwiftData...")

        guard let modelContext = dataController.modelContext else {
            print("[ONBOARDING_MANAGER] ⚠️ No modelContext available!")
            return
        }

        // Check if user already exists
        let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == userId })
        if let existingUser = try? modelContext.fetch(descriptor).first {
            print("[ONBOARDING_MANAGER] User already exists locally, updating DataController")
            await MainActor.run {
                dataController.currentUser = existingUser
                // NOTE: Do NOT set isAuthenticated = true here!
                // That would trigger navigation to main app before onboarding completes
            }
        } else {
            // Create new user - companyId will be set later when company is created/joined
            let newUser = User(
                id: userId,
                firstName: state.userData.firstName,
                lastName: state.userData.lastName,
                role: userType == .company ? .admin : .fieldCrew,
                companyId: "" // Will be set when company is created or joined
            )
            newUser.email = email
            newUser.userType = userType
            newUser.isActive = true

            modelContext.insert(newUser)

            do {
                try modelContext.save()
                print("[ONBOARDING_MANAGER] ✅ Local user saved to SwiftData")

                await MainActor.run {
                    dataController.currentUser = newUser
                    // NOTE: Do NOT set isAuthenticated = true here!
                    // That would trigger navigation to main app before onboarding completes
                }
            } catch {
                print("[ONBOARDING_MANAGER] ❌ Failed to save local user: \(error)")
            }
        }

        // Initialize sync manager if not already done
        await MainActor.run {
            if dataController.syncManager == nil {
                print("[ONBOARDING_MANAGER] Initializing SyncManager...")
                dataController.initializeSyncManager()
            }
            print("[ONBOARDING_MANAGER] ✅ DataController.currentUser: \(dataController.currentUser?.id ?? "nil")")
            print("[ONBOARDING_MANAGER] ✅ DataController.syncManager: \(dataController.syncManager != nil ? "initialized" : "nil")")
        }
    }

    // MARK: - Completion

    /// Complete onboarding and transition to main app
    func completeOnboarding() {
        print("[ONBOARDING_MANAGER] ========== COMPLETE ONBOARDING START ==========")
        print("[ONBOARDING_MANAGER] Completing onboarding")

        // Debug current state
        print("[ONBOARDING_MANAGER] State data:")
        print("[ONBOARDING_MANAGER]   - userId: \(state.userData.userId ?? "nil")")
        print("[ONBOARDING_MANAGER]   - companyId: \(state.companyData.companyId ?? "nil")")
        print("[ONBOARDING_MANAGER]   - companyCode: \(state.companyData.companyCode ?? "nil")")

        // Store credentials so app can load user data on next launch
        storeCredentials()

        Task {
            // Mark as completed on server
            await markOnboardingComplete()

            await MainActor.run {
                // Clear state
                OnboardingState.markCompleted()
                print("[ONBOARDING_MANAGER] ✅ Onboarding state marked as completed")

                // Verify UserDefaults
                let udUserId = UserDefaults.standard.string(forKey: "currentUserId")
                let udCompanyId = UserDefaults.standard.string(forKey: "company_id")
                print("[ONBOARDING_MANAGER] Final UserDefaults check:")
                print("[ONBOARDING_MANAGER]   - currentUserId: \(udUserId ?? "nil")")
                print("[ONBOARDING_MANAGER]   - company_id: \(udCompanyId ?? "nil")")

                print("[ONBOARDING_MANAGER] ========== COMPLETE ONBOARDING END ==========")
                print("[ONBOARDING_MANAGER] Calling onComplete callback...")

                // Notify completion - app will reload and DataHealthManager will handle sync
                onComplete?()
            }
        }
    }

    /// Store user credentials for app to use after onboarding
    private func storeCredentials() {
        print("[ONBOARDING_MANAGER] Storing credentials...")

        guard let userId = state.userData.userId else {
            print("[ONBOARDING_MANAGER] ⚠️ No user ID to store!")
            return
        }

        let companyId = state.companyData.companyId ?? ""

        print("[ONBOARDING_MANAGER] Storing credentials:")
        print("[ONBOARDING_MANAGER]   - userId: \(userId)")
        print("[ONBOARDING_MANAGER]   - companyId: \(companyId.isEmpty ? "EMPTY!" : companyId)")

        UserDefaults.standard.set(userId, forKey: "user_id")
        UserDefaults.standard.set(userId, forKey: "currentUserId")
        UserDefaults.standard.set(companyId, forKey: "company_id")
        UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
        UserDefaults.standard.set(true, forKey: "is_authenticated")
        UserDefaults.standard.set(true, forKey: "onboarding_completed")

        print("[ONBOARDING_MANAGER] ✅ Credentials stored to UserDefaults")
    }

    /// PATCH hasCompletedAppOnboarding to Bubble
    private func markOnboardingComplete() async {
        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            print("[ONBOARDING_MANAGER] No user ID for completion patch")
            return
        }

        do {
            let fields: [String: Any] = ["hasCompletedAppOnboarding": true]
            try await apiService.updateUser(userId: userId, fields: fields)
            print("[ONBOARDING_MANAGER] hasCompletedAppOnboarding PATCHed to true")
        } catch {
            print("[ONBOARDING_MANAGER] Failed to patch completion: \(error)")
            // Non-fatal, continue anyway
        }
    }

    // MARK: - Error Handling

    /// Show an error message
    func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    /// Clear error state
    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - State Reset

    /// Reset onboarding state (for testing or "start over")
    func reset() {
        state = OnboardingState.initial
        OnboardingState.clear()
        errorMessage = nil
        showError = false
        isLoading = false
    }

    /// Sign out during onboarding - clears all state and returns to welcome
    func signOut() {
        print("[ONBOARDING_MANAGER] Signing out during onboarding...")

        // Clear onboarding state
        OnboardingState.clear()

        // Clear user credentials
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "user_email")
        UserDefaults.standard.removeObject(forKey: "user_password")
        UserDefaults.standard.removeObject(forKey: "selected_user_type")
        UserDefaults.standard.removeObject(forKey: "company_id")
        UserDefaults.standard.removeObject(forKey: "currentUserCompanyId")
        UserDefaults.standard.set(false, forKey: "is_authenticated")

        // Reset local state
        state = OnboardingState.initial
        errorMessage = nil
        showError = false
        isLoading = false

        // Clear DataController user
        dataController.currentUser = nil

        print("[ONBOARDING_MANAGER] Sign out complete, returning to welcome")
    }

    /// Switch flow (e.g., from employee to company creator via help sheet)
    func switchFlow(to newFlow: OnboardingFlow) async {
        print("[ONBOARDING_MANAGER] Switching flow to: \(newFlow)")

        state.flow = newFlow
        state.resetForNewFlow()

        // Update userType on server if authenticated
        if let userId = state.userData.userId ?? dataController.currentUser?.id {
            try? await patchUserType(userId: userId, userType: newFlow.userType)
        }

        // Navigate to appropriate profile screen
        if newFlow == .companyCreator {
            goToScreen(.profileCompany)
        } else {
            goToScreen(.profileJoin)
        }
    }
}

// MARK: - Onboarding Manager Errors

enum OnboardingManagerError: LocalizedError {
    case noFlowSelected
    case noUserId
    case invalidCompanyCode
    case serverError(String)
    case networkError

    var errorDescription: String? {
        switch self {
        case .noFlowSelected:
            return "Please select how you'll use OPS"
        case .noUserId:
            return "User ID not found. Please try again."
        case .invalidCompanyCode:
            return "Company code not found. Check the code and try again."
        case .serverError(let message):
            return message
        case .networkError:
            return "No internet connection. Check your connection and try again."
        }
    }
}
