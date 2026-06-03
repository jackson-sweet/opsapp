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
import Supabase

@MainActor
class OnboardingManager: ObservableObject {

    // MARK: - Published State

    @Published var state: OnboardingState
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var navigationDirection: NavigationDirection = .forward

    // MARK: - Invite-Aware Onboarding (transient, not persisted)
    @Published var pendingInvites: [PendingInviteDTO] = []
    @Published var selectedInvite: PendingInviteDTO? = nil
    @Published var companyJoinDetails: CompanyJoinDetailsDTO? = nil
    @Published var confirmationSource: CompanyConfirmationSource = .manualCodeEntry
    @Published var isCheckingInvites: Bool = false

    enum NavigationDirection {
        case forward
        case backward
    }

    // MARK: - Dependencies

    private let dataController: DataController
    private let onboardingService: OnboardingServiceProtocol

    var dataControllerForTesting: DataController {
        dataController
    }

    // MARK: - Callbacks

    var onComplete: (() -> Void)?

    // MARK: - Initialization

    init(dataController: DataController, onboardingService: OnboardingServiceProtocol = OnboardingService()) {
        self.dataController = dataController
        self.onboardingService = onboardingService

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
                role: userType == .company ? .owner : .crew,
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

        // Initialize sync system if needed
        if dataController.imageSyncManager == nil {
            print("[ONBOARDING_MANAGER] Initializing sync system for resumed session...")
            dataController.initializeSyncManager()
        }

        print("[ONBOARDING_MANAGER] ✅ Local state restored - currentUser: \(dataController.currentUser?.id ?? "nil")")
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

        // Check if user has company and type. These are required identity fields,
        // but they are not completion ACKs by themselves.
        let hasCompany = user.companyId != nil && !user.companyId!.isEmpty
        let hasUserType = user.userType != nil

        // CRITICAL: Only the server onboarding_completed.ios ACK can complete
        // onboarding. A company_id can exist after a partial join and must resume.
        if user.hasCompletedAppOnboarding && hasCompany && hasUserType {
            // Clear any stale saved state
            OnboardingState.clear()
            print("[ONBOARDING_MANAGER] User has completed onboarding (hasCompletedAppOnboarding=\(user.hasCompletedAppOnboarding), hasCompany=\(hasCompany), hasUserType=\(hasUserType)), skipping")
            return (false, nil)
        }

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

        let manager = OnboardingManager(dataController: dataController)
        manager.state.userData.userId = user.id
        manager.state.companyData.companyId = user.companyId
        manager.state.flow = user.userType == .company ? .companyCreator : .employee

        if hasCompany {
            manager.state.resumeBoundary = .completionPendingServerACK
            manager.goToScreen(.ready)
        } else if user.userType == .company {
            manager.state.resumeBoundary = .postAuthPreCompany
            manager.goToScreen(.companySetup)
        } else {
            manager.goToScreen(.codeEntry)
        }

        return (true, manager)
    }

    // MARK: - Navigation

    /// Navigate to a specific screen (forward direction by default)
    func goToScreen(_ screen: OnboardingScreen, direction: NavigationDirection = .forward) {
        print("[ONBOARDING_MANAGER] Navigating to: \(screen) (direction: \(direction))")
        navigationDirection = direction
        state.currentScreen = screen
        state.save()

        // Track analytics (only for forward navigation to avoid duplicate events)
        if direction == .forward {
            trackPageView(screen: screen)
        }
    }

    // MARK: - Analytics Tracking

    /// Track page view for onboarding analytics
    private func trackPageView(screen: OnboardingScreen) {
        let (pageIndex, totalPages) = getPageIndexAndTotal(for: screen)
        let flowType = state.flow?.rawValue ?? "unknown"

    }

    /// Get page index and total pages for analytics
    /// Returns (pageIndex, totalPages) - indices are 1-based
    private func getPageIndexAndTotal(for screen: OnboardingScreen) -> (Int, Int) {
        // Define screen order for each flow
        // These are the main user-facing screens (excluding legacy/deprecated)
        let companyCreatorScreens: [OnboardingScreen] = [
            .welcome, .signup, .preSignupTutorial, .credentials, .profile,
            .companySetup, .companyDetails, .companyCode, .ready
        ]

        let employeeScreens: [OnboardingScreen] = [
            .welcome, .signup, .preSignupTutorial, .credentials,
            .codeEntry, .invitePicker, .companyConfirmation,
            .profile, .emergencyContact, .ready
        ]

        // Determine which flow's screens to use
        let screens: [OnboardingScreen]
        switch state.flow {
        case .companyCreator:
            screens = companyCreatorScreens
        case .employee:
            screens = employeeScreens
        case .none:
            // Before flow is selected, use a minimal set
            screens = [.welcome, .login, .signup]
        }

        // Find index (1-based)
        if let index = screens.firstIndex(of: screen) {
            return (index + 1, screens.count)
        }

        // Screen not in flow (e.g., login) - return reasonable defaults
        return (1, screens.count)
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

        case .preSignupTutorial:
            // Go back to signup screen (account type selection)
            goToScreen(.signup, direction: .backward)

        case .postTutorialCTA:
            // Legacy/unused
            goToScreen(.signup, direction: .backward)

        case .credentials:
            // Always go back to signup (path selection)
            goToScreen(.signup, direction: .backward)

        case .invitePicker:
            goToScreen(.credentials, direction: .backward)

        case .companyConfirmation:
            // Fallback — CompanyConfirmationScreen handles its own back via handleBack()
            goToScreen(.codeEntry, direction: .backward)

        case .profile:
            if state.flow == .employee {
                goToScreen(.credentials, direction: .backward)
            } else {
                goToScreen(.credentials, direction: .backward)
            }

        case .emergencyContact:
            goToScreen(.profile, direction: .backward)

        case .appSetup:
            // Can't go back from app setup
            break

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
            if state.flow == .employee {
                goToScreen(.credentials, direction: .backward)
            } else {
                goToScreen(.profile, direction: .backward)
            }

        case .profileJoin:
            if state.profileJoinPhase == .form {
                goToScreen(.profile, direction: .backward)
            }
            // Can't go back during joining

        case .ready:
            // Can't go back from ready
            break

        case .tutorial:
            // Can't go back from tutorial
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
            // After path selection, always show pre-signup tutorial
            // Skip button is available if they've already completed it
            goToScreen(.preSignupTutorial)

        case .preSignupTutorial:
            // Guard: if flow was lost (state restoration), redirect to signup
            guard state.flow != nil else {
                print("[ONBOARDING_MANAGER] Flow is nil at preSignupTutorial → redirecting to signup")
                goToScreen(.signup, direction: .backward)
                return
            }
            // Tutorial completed, mark flag and go straight to credentials
            state.hasCompletedPreSignupTutorial = true
            UserDefaults.standard.set(true, forKey: OnboardingStorageKeys.preSignupTutorialCompleted)
            state.save()
            goToScreen(.credentials)

        case .postTutorialCTA:
            // Legacy/unused — go to credentials
            goToScreen(.credentials)

        case .userTypeSelection:
            // After selecting type, go to profile then appropriate next screen
            goToScreen(.profile)

        case .credentials:
            if state.flow == .employee {
                // Employee flow: check for pending invites after credentials
                print("[ONBOARDING_MANAGER] Credentials → employee flow, checking pending invites...")
                print("[ONBOARDING_MANAGER] Email for invite check: '\(state.userData.email)'")
                isCheckingInvites = true
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.checkPendingInvites()
                    await MainActor.run {
                        self.isCheckingInvites = false
                        print("[ONBOARDING_MANAGER] Invite check complete. Found \(self.pendingInvites.count) invites")
                        if self.pendingInvites.count > 1 {
                            print("[ONBOARDING_MANAGER] Multiple invites → invitePicker")
                            self.goToScreen(.invitePicker)
                        } else if self.pendingInvites.count == 1 {
                            print("[ONBOARDING_MANAGER] Single invite → companyConfirmation")
                            self.selectedInvite = self.pendingInvites.first
                            self.confirmationSource = .singleInvite
                            self.goToScreen(.companyConfirmation)
                        } else {
                            print("[ONBOARDING_MANAGER] No invites → codeEntry")
                            self.goToScreen(.codeEntry)
                        }
                    }
                }
                return  // Don't fall through — async navigation handles it
            } else {
                // Company creator flow: go to profile screen
                goToScreen(.profile)
            }

        case .profile:
            // After profile, go to company setup or emergency contact based on flow
            if state.flow == .companyCreator {
                goToScreen(.companySetup)
            } else {
                goToScreen(.emergencyContact)
            }

        case .emergencyContact:
            // After emergency contact, go to ready (employee flow reordered)
            goToScreen(.ready)

        case .companySetup:
            goToScreen(.companyDetails)

        case .companyDetails:
            goToScreen(.companyCode)

        case .companyCode:
            goToScreen(.ready)

        case .profileCompany:
            goToScreen(.ready)

        case .companyConfirmation:
            goToScreen(.profile)

        case .invitePicker:
            goToScreen(.codeEntry)

        case .codeEntry:
            goToScreen(.companyConfirmation)

        case .profileJoin:
            goToScreen(.ready)

        case .ready:
            // If pre-signup tutorial was already completed, skip post-signup tutorial
            let preSignupDone = state.hasCompletedPreSignupTutorial ||
                UserDefaults.standard.bool(forKey: OnboardingStorageKeys.preSignupTutorialCompleted)

            print("[ONBOARDING_MANAGER] Ready screen - checking tutorial status:")
            print("[ONBOARDING_MANAGER]   - preSignupTutorialDone: \(preSignupDone)")

            // User reached final onboarding UX, but local completion is gated
            // until completeOnboardingAwaitingServerAck() receives server ACK.
            state.resumeBoundary = .completionPendingServerACK
            state.save()

            if preSignupDone {
                // Pre-signup tutorial was done, mark hasCompletedAppTutorial and go to app setup
                print("[ONBOARDING_MANAGER]   -> Pre-signup tutorial done, marking tutorial complete and going to app setup")
                Task {
                    await markTutorialComplete()
                    await MainActor.run {
                        goToScreen(.appSetup)
                    }
                }
            } else {
                // No pre-signup tutorial, check if post-signup tutorial needed
                let user = dataController.currentUser
                let hasCompletedTutorial = user?.hasCompletedAppTutorial ?? false

                print("[ONBOARDING_MANAGER]   - currentUser exists: \(user != nil)")
                print("[ONBOARDING_MANAGER]   - hasCompletedAppTutorial: \(hasCompletedTutorial)")

                if !hasCompletedTutorial {
                    print("[ONBOARDING_MANAGER]   -> Navigating to tutorial")
                    goToScreen(.tutorial)
                } else {
                    print("[ONBOARDING_MANAGER]   -> Skipping tutorial, going to app setup")
                    goToScreen(.appSetup)
                }
            }

        case .tutorial:
            // After tutorial, show app setup loading screen
            goToScreen(.appSetup)

        case .appSetup:
            // AppSetupScreen calls completeOnboarding() directly after its animation
            break
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

    /// Determine the resume screen based on existing user data
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

        // If resuming on an invite-related screen, transient data may be lost.
        if state.currentScreen == .invitePicker || state.currentScreen == .companyConfirmation {
            if pendingInvites.isEmpty && selectedInvite == nil && companyJoinDetails == nil {
                return .codeEntry
            }
        }

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
            // Sign up via Firebase Auth
            let authManager = dataController.authManager
            try await authManager.signUpWithEmail(email, password: password)

            // Create user row via ops-web API (service role, bypasses RLS, generates proper UUID).
            // Direct client-side upsert fails because Firebase UIDs are not valid UUIDs
            // and the users.id column is UUID type.
            let syncResponse = try await onboardingService.syncUser(email: email, firstName: nil, lastName: nil, photoURL: nil)
            let userId = syncResponse.user.id

            // Store credentials - CRITICAL: Set both user_id AND currentUserId
            state.userData.email = email
            state.userData.userId = userId
            UserDefaults.standard.set(email, forKey: "user_email")
            UserDefaults.standard.set(password, forKey: "user_password")
            UserDefaults.standard.set(userId, forKey: "user_id")
            UserDefaults.standard.set(userId, forKey: "currentUserId")
            UserDefaults.standard.set(flow.userType.rawValue, forKey: "selected_user_type")

            // Update AuthManager with the correct Supabase user ID (not Firebase UID)
            authManager.setUserId(userId)

            state.isAuthenticated = true
            state.save()

            print("[ONBOARDING_MANAGER] Account created successfully: \(userId)")

            // CRITICAL: Create local User object in SwiftData
            await createLocalUser(userId: userId, email: email, userType: flow.userType)
            print("[ONBOARDING_MANAGER] Local user created and DataController initialized")

            // PATCH userType to Supabase
            try await patchUserType(userId: userId, userType: flow.userType)

        } catch let error as OnboardingManagerError {
            throw error
        } catch {
            let msg = error.localizedDescription
            if msg.contains("already registered") || msg.contains("already been registered") {
                // Account exists — attempt to log them in with the same credentials
                print("[ONBOARDING_MANAGER] Email already registered, attempting login instead...")
                do {
                    let (loginSuccess, _) = await dataController.login(username: email, password: password)
                    if loginSuccess, let user = dataController.currentUser {
                        let hasCompany = !(user.companyId ?? "").isEmpty
                        if hasCompany {
                            // Returning user with completed setup — skip onboarding entirely
                            print("[ONBOARDING_MANAGER] Existing user logged in — skipping onboarding")
                            dataController.isAuthenticated = true
                            UserDefaults.standard.set(true, forKey: "onboarding_completed")
                            UserDefaults.standard.set(true, forKey: "is_authenticated")
                            OnboardingState.clear()
                            throw OnboardingManagerError.existingUserLoggedIn
                        } else {
                            // Existing user but hasn't finished onboarding — continue the flow
                            print("[ONBOARDING_MANAGER] Existing user logged in — continuing onboarding")
                            state.userData.email = email
                            state.userData.userId = user.id
                            state.isAuthenticated = true
                            state.save()
                        }
                    } else {
                        // Login failed — likely wrong password for the existing account
                        throw OnboardingManagerError.serverError("An account with this email already exists but the password doesn't match. Try logging in instead.")
                    }
                }
            } else {
                throw OnboardingManagerError.serverError(msg)
            }
        }
    }

    /// Handle social auth callback
    func handleSocialAuth(userId: String, email: String, firstName: String?, lastName: String?) async throws {
        print("[ONBOARDING_MANAGER] Handling social auth for: \(email)")

        // Ensure user row exists in Supabase via the web API (service role, proper UUID).
        // The userId passed in may be a Firebase UID — we need the actual Supabase UUID.
        var resolvedUserId = userId
        if !email.isEmpty {
            do {
                let syncResponse = try await onboardingService.syncUser(
                    email: email,
                    firstName: firstName,
                    lastName: lastName,
                    photoURL: nil
                )
                resolvedUserId = syncResponse.user.id
                print("[ONBOARDING_MANAGER] Social auth user synced — Supabase ID: \(resolvedUserId)")

                // Update AuthManager with the correct Supabase user ID
                dataController.authManager.setUserId(resolvedUserId)
            } catch {
                print("[ONBOARDING_MANAGER] sync-user failed for social auth; holding recoverable unsynced state: \(error.localizedDescription)")
                state.userData.userId = nil
                state.userData.email = email
                if let firstName = firstName, !firstName.isEmpty {
                    state.userData.firstName = firstName
                }
                if let lastName = lastName, !lastName.isEmpty {
                    state.userData.lastName = lastName
                }
                state.isAuthenticated = true
                state.authSyncStatus = .syncFailed
                state.resumeBoundary = .postAuthPreCompany
                if state.flow == .employee {
                    ABTestFlowStep.employeeSignup.save()
                } else {
                    ABTestFlowStep.signup.save()
                }
                state.save()
                removeFirebaseFallbackUserDefaults(firebaseUID: userId)
                showError("SYS :: USER SYNC FAILED")
                throw OnboardingManagerError.serverError("SYS :: USER SYNC FAILED. Retry sign-in.")
            }
        }

        state.userData.userId = resolvedUserId
        state.userData.email = email
        if let firstName = firstName, !firstName.isEmpty {
            state.userData.firstName = firstName
        }
        if let lastName = lastName, !lastName.isEmpty {
            state.userData.lastName = lastName
        }

        state.isAuthenticated = true
        state.authSyncStatus = .synced
        state.resumeBoundary = state.flow == .employee ? .employeePostCode : .postAuthPreCompany

        // Store for later - CRITICAL: Set both user_id AND currentUserId
        UserDefaults.standard.set(resolvedUserId, forKey: "user_id")
        UserDefaults.standard.set(resolvedUserId, forKey: "currentUserId") // Required for SyncEngine
        UserDefaults.standard.set(email, forKey: "user_email")

        // PATCH userType if we have a flow selected
        if let flow = state.flow {
            UserDefaults.standard.set(flow.userType.rawValue, forKey: "selected_user_type")
            try await patchUserType(userId: resolvedUserId, userType: flow.userType)

            // CRITICAL: Create local User object in SwiftData
            await createLocalUser(userId: resolvedUserId, email: email, userType: flow.userType)
            print("[ONBOARDING_MANAGER] Local user created for social auth")
        }

        state.save()
    }

    private func removeFirebaseFallbackUserDefaults(firebaseUID: String) {
        guard !firebaseUID.isEmpty else { return }
        if UserDefaults.standard.string(forKey: "user_id") == firebaseUID {
            UserDefaults.standard.removeObject(forKey: "user_id")
        }
        if UserDefaults.standard.string(forKey: "currentUserId") == firebaseUID {
            UserDefaults.standard.removeObject(forKey: "currentUserId")
        }
    }

    /// PATCH userType to Supabase
    private func patchUserType(userId: String, userType: UserType) async throws {
        print("[ONBOARDING_MANAGER] PATCHing userType '\(userType.rawValue)' for user \(userId)")

        let fields: [String: AnyJSON] = [
            "user_type": .string(userType.rawValue)
        ]
        try await dataController.updateUserFields(userId: userId, fields: fields)

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

            // Idempotent retry guard: if a prior attempt already created the
            // company (insert succeeded but a later step failed, or the app was
            // killed mid-flow), reuse it instead of inserting a duplicate.
            // companyData persists across relaunch via OnboardingState.save().
            let companyId: String
            let newCompanyCode: String

            if let existingCompanyId = state.companyData.companyId,
               !existingCompanyId.isEmpty {
                companyId = existingCompanyId
                newCompanyCode = state.companyData.companyCode ?? generateCompanyCode()
                print("[ONBOARDING_MANAGER] Reusing company from a prior attempt: \(companyId)")
            } else {
                // Generate a unique company code
                newCompanyCode = generateCompanyCode()
                let now = ISO8601DateFormatter().string(from: Date())
                let trialEnd = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date())!)

                // Insert company into Supabase
                let companyRepo = CompanyRepository()
                let payload = NewCompanyPayload(
                    name: state.companyData.name,
                    email: state.companyData.email.isEmpty ? nil : state.companyData.email,
                    phone: state.companyData.phone.isEmpty ? nil : state.companyData.phone,
                    address: state.companyData.address.isEmpty ? nil : state.companyData.address,
                    company_code: newCompanyCode,
                    admin_ids: [userId],
                    seated_employee_ids: [userId],
                    account_holder_id: userId,
                    industries: state.companyData.industry.isEmpty ? nil : [state.companyData.industry],
                    company_size: state.companyData.size.isEmpty ? nil : state.companyData.size,
                    company_age: state.companyData.age.isEmpty ? nil : state.companyData.age,
                    subscription_status: "trial",
                    subscription_plan: "trial",
                    trial_start_date: now,
                    trial_end_date: trialEnd,
                    max_seats: 10,
                    created_at: now,
                    updated_at: now
                )
                let createdCompany = try await companyRepo.insert(payload)
                companyId = createdCompany.id

                // Persist immediately so any failure after this point reuses the
                // company on retry instead of inserting a duplicate.
                state.companyData.companyId = companyId
                state.companyData.companyCode = newCompanyCode
                state.save()
            }

            // Update user's company_id in Supabase
            let userRepo = UserRepository(companyId: companyId)
            try await userRepo.updateFields(userId: userId, fields: [
                "company_id": .string(companyId),
                "role": .string("owner"),
                "is_company_admin": .bool(true)
            ])

            // Assign Owner role in user_roles table for permission system
            do {
                let ownerRoleRows: [[String: String]] = try await SupabaseService.shared.client
                    .from("roles")
                    .select("id")
                    .eq("name", value: "Owner")
                    .execute()
                    .value
                if let roleId = ownerRoleRows.first?["id"] {
                    try await SupabaseService.shared.client
                        .from("user_roles")
                        .upsert(["user_id": userId, "role_id": roleId])
                        .execute()
                    print("[ONBOARDING_MANAGER] ✅ Owner role assigned in user_roles")
                }
            } catch {
                print("[ONBOARDING_MANAGER] ⚠️ Failed to assign Owner role: \(error)")
            }

            // Seed default task types, inventory units, and company settings (non-fatal)
            do {
                try await SupabaseService.shared.client
                    .rpc("initialize_company_defaults", params: ["p_company_id": companyId])
                    .execute()
                print("[ONBOARDING_MANAGER] ✅ Company defaults initialized")
            } catch {
                print("[ONBOARDING_MANAGER] ⚠️ Failed to initialize defaults (will retry via web): \(error)")
            }

            // Store company data in state
            state.companyData.companyId = companyId
            state.companyData.companyCode = newCompanyCode
            print("[ONBOARDING_MANAGER] Company created in Supabase:")
            print("[ONBOARDING_MANAGER]   - companyId: \(companyId)")
            print("[ONBOARDING_MANAGER]   - companyCode: \(newCompanyCode)")

            state.profileCompanyPhase = .success
            state.hasExistingCompany = true
            state.resumeBoundary = .completionPendingServerACK
            state.save()

            // Store in UserDefaults
            UserDefaults.standard.set(companyId, forKey: "company_id")
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
            UserDefaults.standard.set(state.companyData.name, forKey: "Company Name")

            // Update local user's data before syncing company
            if let currentUser = dataController.currentUser {
                currentUser.companyId = companyId
                currentUser.firstName = state.userData.firstName
                currentUser.lastName = state.userData.lastName
                if !state.userData.phone.isEmpty {
                    currentUser.phone = state.userData.phone
                }
                currentUser.role = .owner
                try? dataController.modelContext?.save()
                print("[ONBOARDING_MANAGER] ✅ Updated local user - companyId: \(companyId), name: \(currentUser.fullName)")
            } else {
                print("[ONBOARDING_MANAGER] ⚠️ DataController.currentUser is NIL! Cannot set companyId!")
            }

            // Create Company object in SwiftData
            if let modelContext = dataController.modelContext {
                let companyObject = Company(id: companyId, name: state.companyData.name)
                companyObject.email = state.companyData.email
                companyObject.phone = state.companyData.phone
                companyObject.address = state.companyData.address
                companyObject.subscriptionStatus = "trial"
                companyObject.subscriptionPlan = "trial"
                companyObject.trialStartDate = Date()
                companyObject.trialEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
                companyObject.maxSeats = 10
                companyObject.seatedEmployeeIds = userId
                companyObject.adminIdsString = userId
                modelContext.insert(companyObject)
                try? modelContext.save()
                print("[ONBOARDING_MANAGER] ✅ Company saved to SwiftData")
            }

            // Trigger sync to load company data via DataController
            print("[ONBOARDING_MANAGER] Triggering company sync...")
            await dataController.triggerCompanySync()
            print("[ONBOARDING_MANAGER] Company sync triggered")

            print("[ONBOARDING_MANAGER] ========== CREATE COMPANY END ==========")
            print("[ONBOARDING_MANAGER] Company created: \(companyId), code: \(newCompanyCode)")

            return newCompanyCode

        } catch {
            state.profileCompanyPhase = .form
            throw error
        }
    }

    /// Join an existing company (Employee flow)
    ///
    /// Calls the `public.join_user_to_company` Supabase RPC which atomically handles:
    /// - company_id assignment on the user row
    /// - role_id assignment via user_roles (honors prescribed role from team_invitations)
    /// - users.role sync with the assigned role name
    /// - team_invitations status update to 'accepted'
    /// - seat granting (if seats are available)
    ///
    /// The RPC returns `{ error: "..." }` on failure, or `{ success: true, ... }` on success.
    /// Both paths are surfaced to the caller as user-facing error messages — no silent bounces.
    func joinCompany(code: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        guard let companyCodeProof = normalizedCompanyCodeProof(code) else {
            throw OnboardingManagerError.invalidCompanyCode
        }

        print("[ONBOARDING_MANAGER] Joining company with code: \(companyCodeProof)")

        state.profileJoinPhase = .joining

        do {
            // Look up company by code in Supabase (needed for name/phone/address metadata
            // that goes into UserDefaults and local SwiftData).
            let companyRepo = CompanyRepository()
            guard let companyDTO = try await companyRepo.fetchByCode(companyCodeProof) else {
                throw OnboardingManagerError.invalidCompanyCode
            }

            let companyId = companyDTO.id

            // Atomic RPC: writes company_id, role, invitation acceptance, and seat grant.
            // Mirrors the ops-web /api/auth/join-company path so all platforms stay in sync.
            let joinResult = try await executeJoinUserToCompanyRPC(
                userId: userId,
                companyId: companyId,
                companyCode: companyCodeProof
            )

            // RPC returns `{ seat_granted: false }` when the company is at seat capacity.
            // Treat that as a user-visible error so the join doesn't succeed silently
            // with the user still locked out.
            if joinResult.seatGranted == false && !(companyDTO.seatedEmployeeIds ?? []).contains(userId) {
                print("[ONBOARDING_MANAGER] ❌ No available seats — RPC returned seat_granted: false")
                throw OnboardingManagerError.serverError("This company's team is full. Contact your boss to add more seats.")
            }

            print("[ONBOARDING_MANAGER] ✅ RPC success — role: \(joinResult.roleName ?? "unassigned"), seat_granted: \(joinResult.seatGranted ?? false)")

            // Set employee-specific fields not handled by the RPC.
            let userRepo = UserRepository(companyId: companyId)
            try? await userRepo.updateFields(userId: userId, fields: [
                "is_company_admin": .bool(false),
                "user_type": .string("employee")
            ])

            state.companyData.companyId = companyId
            state.companyData.companyCode = companyCodeProof
            state.hasExistingCompany = true
            state.resumeBoundary = .employeePostJoinPreProfile
            state.save()

            // Store in UserDefaults
            UserDefaults.standard.set(companyId, forKey: "company_id")
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
            UserDefaults.standard.set(companyDTO.name, forKey: "Company Name")

            // Reconfigure sync engine now that company_id is set in UserDefaults
            dataController.syncEngine.reconfigureForCompany()

            // NOW update profile data — userRepo is available after repo reconfiguration
            try await updateUserProfile()

            // Upload avatar if available
            if let avatarData = state.userData.avatarData {
                await uploadAvatarDuringOnboarding(userId: userId, imageData: avatarData)
            }

            // Update local user's data before syncing company
            if let currentUser = dataController.currentUser {
                currentUser.companyId = companyId
                currentUser.firstName = state.userData.firstName
                currentUser.lastName = state.userData.lastName
                currentUser.userType = .employee
                if let roleName = joinResult.roleName,
                   let mapped = UserRole(rawValue: roleName.lowercased()) {
                    currentUser.role = mapped
                }
                if !state.userData.phone.isEmpty {
                    currentUser.phone = state.userData.phone
                }
                try? dataController.modelContext?.save()
                print("[ONBOARDING_MANAGER] Updated local user - companyId: \(companyId), name: \(currentUser.fullName)")
            }

            // Create Company object in SwiftData
            if let modelContext = dataController.modelContext {
                let compDesc = FetchDescriptor<Company>(
                    predicate: #Predicate<Company> { $0.id == companyId }
                )
                if (try? modelContext.fetch(compDesc).first) == nil {
                    let companyObject = Company(id: companyId, name: companyDTO.name)
                    companyObject.email = companyDTO.email
                    companyObject.phone = companyDTO.phone
                    companyObject.address = companyDTO.address
                    modelContext.insert(companyObject)
                    try? modelContext.save()
                }
            }

            // Trigger sync to load company data via DataController
            await dataController.triggerCompanySync()
            print("[ONBOARDING_MANAGER] Company sync triggered after join")

            // Notify company admins that a new member joined (push only — the RPC
            // does not create web-rail notifications; OneSignal push is iOS-only here).
            do {
                let notifyIds = joinResult.adminIds ?? companyDTO.adminIds ?? []
                let memberName = "\(state.userData.firstName) \(state.userData.lastName)"
                // Create in-app notifications for each admin
                let notifRepo = NotificationRepository()
                for adminId in notifyIds {
                    let dto = NotificationRepository.CreateNotificationDTO(
                        userId: adminId,
                        companyId: companyId,
                        type: "team_join",
                        title: "New Team Member",
                        body: "\(memberName) joined as Crew. Tap to set their role.",
                        projectId: nil,
                        noteId: nil,
                        expenseId: nil,
                        batchId: nil,
                        deepLinkType: "manageTeam"
                    )
                    try? await notifRepo.createNotification(dto)
                }
                // Send push
                try await OneSignalService.shared.notifyTeamJoin(
                    adminUserIds: notifyIds,
                    newMemberName: memberName,
                    newMemberUserId: userId,
                    companyId: companyId
                )
            } catch {
                print("[ONBOARDING_MANAGER] ⚠️ Failed to send team join notification: \(error)")
            }

            print("[ONBOARDING_MANAGER] Joined company: \(companyId)")

        } catch {
            state.profileJoinPhase = .form
            if let onboardingError = error as? OnboardingManagerError {
                throw onboardingError
            }
            throw OnboardingManagerError.serverError(error.localizedDescription)
        }
    }

    // MARK: - Supabase join_user_to_company RPC

    /// Lightweight wrapper over the `public.join_user_to_company` Supabase RPC.
    /// The RPC returns JSONB with either `{ error: "..." }` or `{ success: true, ... }`.
    /// Maps `error` responses to `OnboardingManagerError.serverError` so the caller's
    /// catch handler surfaces the exact server-side message to the UI.
    private struct JoinUserToCompanyResult: Decodable {
        let success: Bool?
        let error: String?
        let userId: String?
        let companyId: String?
        let roleName: String?
        let seatGranted: Bool?
        let invitationFound: Bool?
        let adminIds: [String]?
        let newMemberName: String?
        let companyName: String?

        enum CodingKeys: String, CodingKey {
            case success, error
            case userId = "user_id"
            case companyId = "company_id"
            case roleName = "role_name"
            case seatGranted = "seat_granted"
            case invitationFound = "invitation_found"
            case adminIds = "admin_ids"
            case newMemberName = "new_member_name"
            case companyName = "company_name"
        }
    }

    /// Calls `public.join_user_to_company(p_user_id, p_company_id, p_company_code)` and decodes the JSONB result.
    /// Throws `OnboardingManagerError.serverError(...)` if the RPC returns `{ error: "..." }`.
    private func executeJoinUserToCompanyRPC(userId: String, companyId: String, companyCode: String) async throws -> JoinUserToCompanyResult {
        print("[ONBOARDING_MANAGER] Calling join_user_to_company RPC (user: \(userId), company: \(companyId))")

        let responseData: Data = try await SupabaseService.shared.client
            .rpc("join_user_to_company", params: [
                "p_user_id": userId,
                "p_company_id": companyId,
                "p_company_code": companyCode
            ])
            .execute()
            .data

        let decoder = JSONDecoder()

        // PostgREST may wrap JSONB in an array, unwrap as needed.
        if let single = try? decoder.decode(JoinUserToCompanyResult.self, from: responseData) {
            if let serverError = single.error {
                print("[ONBOARDING_MANAGER] ❌ RPC returned error: \(serverError)")
                throw OnboardingManagerError.serverError(serverError)
            }
            return single
        }

        if let array = try? decoder.decode([JoinUserToCompanyResult].self, from: responseData),
           let first = array.first {
            if let serverError = first.error {
                print("[ONBOARDING_MANAGER] ❌ RPC returned error: \(serverError)")
                throw OnboardingManagerError.serverError(serverError)
            }
            return first
        }

        let raw = String(data: responseData, encoding: .utf8) ?? "nil"
        print("[ONBOARDING_MANAGER] ❌ Failed to decode RPC response: \(raw.prefix(500))")
        throw OnboardingManagerError.serverError("Could not parse join response. Please try again.")
    }

    private func normalizedCompanyCodeProof(_ code: String?) -> String? {
        let normalized = (code ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isASCII && !$0.isWhitespace }
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    /// Look up a company by crew code without joining.
    /// Returns the company DTO for confirmation screen display.
    func lookupCompanyByCode(_ code: String) async throws -> SupabaseCompanyDTO {
        // Strip whitespace, newlines, and zero-width/invisible Unicode characters
        // that can be introduced by copy-paste from messaging apps or websites
        let trimmedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isASCII && !$0.isWhitespace }
            .uppercased()

        guard !trimmedCode.isEmpty else {
            throw OnboardingManagerError.invalidCompanyCode
        }

        let companyRepo = CompanyRepository()
        guard let companyDTO = try await companyRepo.fetchByCode(trimmedCode) else {
            print("[ONBOARDING_MANAGER] Company code lookup failed for sanitized code: '\(trimmedCode)' (original: '\(code)', length: \(code.count) -> \(trimmedCode.count))")
            throw OnboardingManagerError.invalidCompanyCode
        }

        // Store code in state for later joinCompany call
        state.companyData.companyCode = trimmedCode
        state.save()

        return companyDTO
    }

    // MARK: - Invite-Aware Onboarding Methods

    /// Called after credentials step completes. Checks for pending invites by email.
    func checkPendingInvites() async {
        guard !state.userData.email.isEmpty else {
            pendingInvites = []
            return
        }
        isCheckingInvites = true
        defer { isCheckingInvites = false }

        do {
            let invites = try await CompanyRepository().checkPendingInvites(email: state.userData.email)
            pendingInvites = invites
        } catch {
            print("[ONBOARDING_MANAGER] Failed to check pending invites: \(error)")
            pendingInvites = []
        }
    }

    /// Called after manual code entry to fetch branded company data for confirmation.
    func fetchCompanyJoinDetails(code: String) async throws -> CompanyJoinDetailsDTO {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let details = try await CompanyRepository().fetchJoinDetails(code: trimmedCode) else {
            throw OnboardingManagerError.invalidCompanyCode
        }
        companyJoinDetails = details
        state.resumeBoundary = .employeePostCode
        state.save()
        return details
    }

    /// Joins company during onboarding flow. Unlike joinCompany(code:), this method:
    /// 1. Accepts companyId directly after code/invite confirmation
    /// 2. Skips updateUserProfile() (Profile screen hasn't been filled yet)
    /// 3. Marks the invitation as accepted (if invitationId provided)
    /// 4. Applies prescribed role from invitation (instead of hardcoding Crew)
    func joinCompanyFromOnboarding(companyId: String, invitationId: String? = nil, companyCode: String? = nil) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        print("[ONBOARDING_MANAGER] Joining company \(companyId) from onboarding (invitation: \(invitationId ?? "none"))")

        do {
            let companyRepo = CompanyRepository()
            // fetch(companyId:) throws if not found — no optional
            let companyDTO = try await companyRepo.fetch(companyId: companyId)
            guard let companyCodeProof = normalizedCompanyCodeProof(
                companyCode
                    ?? state.companyData.companyCode
                    ?? selectedInvite?.companyCode
                    ?? companyJoinDetails?.companyCode
                    ?? companyDTO.companyCode
            ) else {
                throw OnboardingManagerError.invalidCompanyCode
            }

            // Atomic RPC: writes company_id, role (from invitation or default), invitation
            // acceptance, and seat grant. Mirrors ops-web /api/auth/join-company.
            let joinResult = try await executeJoinUserToCompanyRPC(
                userId: userId,
                companyId: companyId,
                companyCode: companyCodeProof
            )

            // When the RPC reports seat_granted:false for a user who isn't already seated,
            // surface a clear user-visible error instead of letting the join succeed with
            // the user still locked out of the app.
            if joinResult.seatGranted == false && !(companyDTO.seatedEmployeeIds ?? []).contains(userId) {
                print("[ONBOARDING_MANAGER] ❌ No available seats — RPC returned seat_granted: false")
                throw OnboardingManagerError.serverError("This company's team is full. Contact your boss to add more seats.")
            }

            print("[ONBOARDING_MANAGER] ✅ RPC success — role: \(joinResult.roleName ?? "unassigned"), seat_granted: \(joinResult.seatGranted ?? false)")

            // Set employee-specific fields not handled by the RPC
            let userRepo = UserRepository(companyId: companyId)
            try? await userRepo.updateFields(userId: userId, fields: [
                "is_company_admin": .bool(false),
                "user_type": .string("employee")
            ])

            // Store company info in state and UserDefaults
            state.companyData.companyId = companyId
            state.companyData.companyCode = companyCodeProof
            state.hasExistingCompany = true
            state.resumeBoundary = .employeePostJoinPreProfile
            state.save()

            UserDefaults.standard.set(companyId, forKey: "company_id")
            UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
            UserDefaults.standard.set(companyDTO.name, forKey: "Company Name")

            // Reconfigure sync engine now that company_id is set in UserDefaults
            dataController.syncEngine.reconfigureForCompany()

            // DO NOT call updateUserProfile() — Profile screen hasn't been filled yet

            // Update local user's data before syncing company
            if let currentUser = dataController.currentUser {
                currentUser.companyId = companyId
                currentUser.userType = .employee
                // Set local role from RPC (which honors invitation-prescribed roles)
                if let roleName = joinResult.roleName,
                   let mapped = UserRole(rawValue: roleName.lowercased()) {
                    currentUser.role = mapped
                    print("[ONBOARDING_MANAGER] Set local user role to: \(roleName.lowercased())")
                }
                try? dataController.modelContext?.save()
                print("[ONBOARDING_MANAGER] Updated local user - companyId: \(companyId)")
            }

            // Create Company object in SwiftData
            if let modelContext = dataController.modelContext {
                let compDesc = FetchDescriptor<Company>(
                    predicate: #Predicate<Company> { $0.id == companyId }
                )
                if (try? modelContext.fetch(compDesc).first) == nil {
                    let companyObject = Company(id: companyId, name: companyDTO.name)
                    companyObject.email = companyDTO.email
                    companyObject.phone = companyDTO.phone
                    companyObject.address = companyDTO.address
                    modelContext.insert(companyObject)
                    try? modelContext.save()
                }
            }

            // Trigger sync to load company data via DataController
            await dataController.triggerCompanySync()
            print("[ONBOARDING_MANAGER] Company sync triggered after join")

            // Notify company admins that a new member joined
            do {
                let notifyIds = joinResult.adminIds ?? companyDTO.adminIds ?? []
                let memberName = "\(state.userData.firstName) \(state.userData.lastName)"
                // Create in-app notifications for each admin
                let notifRepo = NotificationRepository()
                for adminId in notifyIds {
                    let dto = NotificationRepository.CreateNotificationDTO(
                        userId: adminId,
                        companyId: companyId,
                        type: "team_join",
                        title: "New Team Member",
                        body: "\(memberName) joined as Crew. Tap to set their role.",
                        projectId: nil,
                        noteId: nil,
                        expenseId: nil,
                        batchId: nil,
                        deepLinkType: "manageTeam"
                    )
                    try? await notifRepo.createNotification(dto)
                }
                // Send push
                try await OneSignalService.shared.notifyTeamJoin(
                    adminUserIds: notifyIds,
                    newMemberName: memberName,
                    newMemberUserId: userId,
                    companyId: companyId
                )
            } catch {
                print("[ONBOARDING_MANAGER] ⚠️ Failed to send team join notification: \(error)")
            }

            print("[ONBOARDING_MANAGER] Successfully joined company \(companyId)")

        } catch {
            print("[ONBOARDING_MANAGER] Failed to join company: \(error)")
            // Preserve typed errors so callers can surface the server-side message;
            // only fall back to a generic banner if we genuinely have no detail.
            if let onboardingError = error as? OnboardingManagerError {
                errorMessage = onboardingError.errorDescription
                throw onboardingError
            }
            errorMessage = "Failed to join company. Please try again."
            throw OnboardingManagerError.serverError(error.localizedDescription)
        }
    }

    /// Update user profile to Supabase
    private func updateUserProfile() async throws {
        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        print("[ONBOARDING_MANAGER] Updating user profile for: \(userId)")
        print("[ONBOARDING_MANAGER]   firstName='\(state.userData.firstName)', lastName='\(state.userData.lastName)', phone='\(state.userData.phone)'")

        var fields: [String: AnyJSON] = [
            "first_name": .string(state.userData.firstName),
            "last_name": .string(state.userData.lastName)
        ]

        if !state.userData.phone.isEmpty {
            fields["phone"] = .string(state.userData.phone)
        }

        // Update user fields via DataController
        try await dataController.updateUserFields(userId: userId, fields: fields)
        print("[ONBOARDING_MANAGER] ✅ User profile updated via DataController")
    }

    /// Upload avatar image to Supabase Storage during onboarding
    private func uploadAvatarDuringOnboarding(userId: String, imageData: Data) async {
        do {
            let fileName = "\(userId)/profile.jpg"
            try await SupabaseService.shared.client.storage
                .from("profile-images")
                .upload(
                    path: fileName,
                    file: imageData,
                    options: .init(contentType: "image/jpeg", upsert: true)
                )

            let publicURL = try SupabaseService.shared.client.storage
                .from("profile-images")
                .getPublicURL(path: fileName)

            let userRepo = UserRepository(companyId: state.companyData.companyId ?? "")
            try await userRepo.updateProfileImageUrl(userId: userId, url: publicURL.absoluteString)

            // Update local user
            dataController.currentUser?.profileImageURL = publicURL.absoluteString
            dataController.currentUser?.profileImageData = imageData
            try? dataController.modelContext?.save()

            print("[ONBOARDING_MANAGER] ✅ Avatar uploaded: \(publicURL.absoluteString)")
        } catch {
            print("[ONBOARDING_MANAGER] ⚠️ Avatar upload failed: \(error)")
        }
    }

    /// Save employee profile fields including emergency contact to Supabase.
    /// Called from the employee onboarding profile screen.
    func saveEmployeeProfile(
        firstName: String,
        lastName: String,
        phone: String?,
        emergencyContactName: String?,
        emergencyContactPhone: String?,
        emergencyContactRelationship: String?
    ) async throws {
        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            throw OnboardingManagerError.noUserId
        }

        // Update state so joinCompany can use it
        state.userData.firstName = firstName
        state.userData.lastName = lastName
        state.userData.phone = phone ?? ""
        state.save()

        var fields: [String: AnyJSON] = [
            "first_name": .string(firstName),
            "last_name": .string(lastName)
        ]

        if let phone = phone, !phone.isEmpty {
            fields["phone"] = .string(phone)
        }
        if let name = emergencyContactName, !name.isEmpty {
            fields["emergency_contact_name"] = .string(name)
        }
        if let phone = emergencyContactPhone, !phone.isEmpty {
            fields["emergency_contact_phone"] = .string(phone)
        }
        if let rel = emergencyContactRelationship, !rel.isEmpty {
            fields["emergency_contact_relationship"] = .string(rel)
        }

        try await dataController.updateUserFields(userId: userId, fields: fields)

        // Update local SwiftData user
        if let currentUser = dataController.currentUser {
            currentUser.firstName = firstName
            currentUser.lastName = lastName
            currentUser.phone = phone
            currentUser.emergencyContactName = emergencyContactName
            currentUser.emergencyContactPhone = emergencyContactPhone
            currentUser.emergencyContactRelationship = emergencyContactRelationship
            try? dataController.modelContext?.save()
        }

        print("[ONBOARDING_MANAGER] Employee profile saved")
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
                role: userType == .company ? .owner : .unassigned,
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

        // Initialize sync system if not already done
        await MainActor.run {
            if dataController.imageSyncManager == nil {
                print("[ONBOARDING_MANAGER] Initializing sync system...")
                dataController.initializeSyncManager()
            }
            print("[ONBOARDING_MANAGER] ✅ DataController.currentUser: \(dataController.currentUser?.id ?? "nil")")
            print("[ONBOARDING_MANAGER] ✅ DataController.syncEngine: \(dataController.syncEngine != nil ? "initialized" : "nil")")
        }
    }

    // MARK: - Completion

    /// Complete onboarding and transition to main app
    func completeOnboarding() {
        Task { @MainActor in
            do {
                _ = try await completeOnboardingAwaitingServerAck()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func completeOnboardingAwaitingServerAck(callCompletion: Bool = true) async throws -> Bool {
        print("[ONBOARDING_MANAGER] ========== COMPLETE ONBOARDING START ==========")
        print("[ONBOARDING_MANAGER] Completing onboarding")

        if OnboardingState.isCompleted {
            if callCompletion {
                onComplete?()
            }
            return true
        }

        // Debug current state
        print("[ONBOARDING_MANAGER] State data:")
        print("[ONBOARDING_MANAGER]   - userId: \(state.userData.userId ?? "nil")")
        print("[ONBOARDING_MANAGER]   - companyId: \(state.companyData.companyId ?? "nil")")
        print("[ONBOARDING_MANAGER]   - companyCode: \(state.companyData.companyCode ?? "nil")")

        state.resumeBoundary = .completionPendingServerACK
        state.save()

        try await markOnboardingComplete()

        // Store credentials so app can load user data on next launch. This must
        // happen only after the server ACK above.
        storeCredentials()
        dataController.currentUser?.hasCompletedAppOnboarding = true
        OnboardingState.markCompleted()
        ABTestFlowStep.clearSaved()
        UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.preSignupTutorialCompleted)
        state.resumeBoundary = nil

        let udUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let udCompanyId = UserDefaults.standard.string(forKey: "company_id")
        print("[ONBOARDING_MANAGER] Final UserDefaults check:")
        print("[ONBOARDING_MANAGER]   - currentUserId: \(udUserId ?? "nil")")
        print("[ONBOARDING_MANAGER]   - company_id: \(udCompanyId ?? "nil")")

        print("[ONBOARDING_MANAGER] ========== COMPLETE ONBOARDING END ==========")
        if callCompletion {
            print("[ONBOARDING_MANAGER] Calling onComplete callback...")
            onComplete?()
        }
        return true
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

    /// ACK onboarding completion through the server-authoritative ops-web endpoint.
    private func markOnboardingComplete() async throws {
        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            print("[ONBOARDING_MANAGER] No user ID for completion patch")
            throw OnboardingManagerError.noUserId
        }
        try await onboardingService.markOnboardingComplete(userId: userId)
    }

    /// Mark tutorial as completed (used when pre-signup tutorial was already done)
    private func markTutorialComplete() async {
        // Update local user
        dataController.currentUser?.hasCompletedAppTutorial = true

        // Fire Firebase event for A/B test tracking
        let variant = UserDefaults.standard.string(forKey: "onboarding_variant")
        AnalyticsManager.shared.trackTutorialCompleted(variant: variant, flowType: "company_creator", isPreSignup: false)

        // Sync to Supabase
        guard let userId = state.userData.userId ?? dataController.currentUser?.id else {
            print("[ONBOARDING_MANAGER] No user ID for tutorial completion patch")
            return
        }

        do {
            let fields: [String: AnyJSON] = ["has_completed_app_tutorial": .bool(true)]
            try await dataController.updateUserFields(userId: userId, fields: fields)
            print("[ONBOARDING_MANAGER] hasCompletedAppTutorial synced to true (pre-signup tutorial)")
        } catch {
            print("[ONBOARDING_MANAGER] Failed to sync tutorial completion: \(error)")
            // Non-fatal, will be caught by ContentView fallback
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

        // Sign out from Firebase Auth and Google
        FirebaseAuthService.shared.signOut()
        GoogleSignInManager.shared.signOut()

        // Reset local state
        state = OnboardingState.initial
        errorMessage = nil
        showError = false
        isLoading = false

        // Clear invite state
        pendingInvites = []
        selectedInvite = nil
        companyJoinDetails = nil
        confirmationSource = .manualCodeEntry

        // Clear A/B test flow step
        ABTestFlowStep.clearSaved()

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
    /// Signup detected an existing account and successfully logged the user in.
    /// The caller should skip onboarding and proceed to the main app.
    case existingUserLoggedIn

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
        case .existingUserLoggedIn:
            return nil // Not an error — handled silently
        }
    }
}
