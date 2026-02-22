//
//  OnboardingViewModel.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import Foundation
import SwiftUI
import Combine
import SwiftData
import CoreLocation
import UserNotifications
import Supabase

class OnboardingViewModel: ObservableObject {
    // Reference to DataController for database operations
    var dataController: DataController? {
        didSet {
            // When dataController is set, populate user data if available
            if let user = dataController?.currentUser {
                populateFromUser(user)
                
                // After populating, check if we need to skip to a specific step
                checkAndSkipToAppropriateStep()
            }
            
            // Also ensure user type is loaded if not already set
            if selectedUserType == nil {
                selectedUserType = Self.loadStoredUserType()
            }
        }
    }
    
    // Current step in the onboarding process
    @Published var currentStep: OnboardingStep = .welcome
    
    // User input data
    @Published var selectedUserType: UserType? {
        didSet {
            if let userType = selectedUserType {
                // Don't save to UserDefaults immediately - wait until after signup
            }
        }
    }
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var phoneNumber: String = ""
    @Published var companyCode: String = ""
    
    // Company data for business owners
    @Published var companyName: String = ""
    @Published var companyAddress: String = ""
    @Published var companyEmail: String = ""
    @Published var companyPhone: String = ""
    @Published var companyIndustry: Industry? = nil
    @Published var companySize: CompanySize? = nil
    @Published var companyAge: CompanyAge? = nil
    @Published var teamInviteEmails: [String] = []

    // Image data
    @Published var profileImage: UIImage? = nil
    @Published var companyLogo: UIImage? = nil

    // State management
    @Published var isLoading: Bool = false
    @Published var isShowingCompanyCreationLoading: Bool = false
    @Published var isCompanyCreationComplete: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLocationPermissionGranted: Bool = false
    @Published var isNotificationsPermissionGranted: Bool = false
    
    // API response data
    @Published var isSignedUp: Bool = false
    @Published var isCompanyJoined: Bool = false
    @Published var userId: String = "" // Track user ID from sign-up response
    
    // Validation states
    @Published var isEmailValid: Bool = false
    @Published var isPasswordValid: Bool = false
    @Published var isPasswordMatching: Bool = false
    @Published var isPhoneValid: Bool = false
    @Published var isCompanyEmailValid: Bool = false
    @Published var isCompanyNameValid: Bool = false
    @Published var isCompanyAddressValid: Bool = false
    @Published var isCompanyPhoneValid: Bool = false
    
    // Services
    private let onboardingService = OnboardingService()
    let locationManager = LocationManager() // Made internal so PermissionsView can access it
    private var cancellables = Set<AnyCancellable>()
    
    // Computed property to determine if we should use light theme (for employee signup)
    var shouldUseLightTheme: Bool {
        // Since selectedUserType is now initialized from stored values,
        // we can simply check it directly
        return selectedUserType == .employee
    }
    
    init() {
        // Initialize selectedUserType first
        self.selectedUserType = Self.loadStoredUserType()
        
        // Check if we're resuming onboarding
        let isResuming = UserDefaults.standard.bool(forKey: "resume_onboarding")
        
        // Check if user is already authenticated (existing user logging in)
        let isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
        let hasUserId = UserDefaults.standard.string(forKey: "user_id") != nil
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "onboarding_completed")
        
        // IMPORTANT: Don't clear data for existing users who are authenticated but haven't completed onboarding
        let shouldLoadExistingData = isResuming || (isAuthenticated && hasUserId && !hasCompletedOnboarding)
        
        // Load any existing user data (for both resuming and authenticated users)
        if shouldLoadExistingData {
            // Load email, password and user ID
            self.email = UserDefaults.standard.string(forKey: "user_email") ?? ""
            self.password = UserDefaults.standard.string(forKey: "user_password") ?? ""
            self.userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
            
            
            // Mark as signed up if we have a valid user ID OR if authenticated
            self.isSignedUp = (!self.userId.isEmpty && !self.email.isEmpty) || isAuthenticated
            
            // Load personal information if available
            self.firstName = UserDefaults.standard.string(forKey: "user_first_name") ?? ""
            self.lastName = UserDefaults.standard.string(forKey: "user_last_name") ?? ""
            self.phoneNumber = UserDefaults.standard.string(forKey: "user_phone_number") ?? ""
            self.companyCode = UserDefaults.standard.string(forKey: "company_code") ?? ""
            
            // Load company information if available
            if UserDefaults.standard.string(forKey: "company_id") != nil {
                self.isCompanyJoined = true
                self.companyName = UserDefaults.standard.string(forKey: "Company Name") ?? "Your Company"
                
                // Load additional company fields
                self.companyAddress = UserDefaults.standard.string(forKey: "company_address") ?? ""
                self.companyEmail = UserDefaults.standard.string(forKey: "company_email") ?? ""
                self.companyPhone = UserDefaults.standard.string(forKey: "company_phone") ?? ""
            }
            
            // User type is already loaded at the beginning of init, so we don't need to load it again here
            // Just log the current state
            if let userType = selectedUserType {
            } else {
            }
            
            // Load the last saved step if available
            let lastStepRaw = UserDefaults.standard.integer(forKey: "last_onboarding_step_v2")
            if lastStepRaw > 0, let savedStep = OnboardingStep(rawValue: lastStepRaw) {
                self.currentStep = savedStep
            }
            
        } else if !isAuthenticated {
            // Only clear data if this is truly a new signup (not authenticated at all)
            clearUserData()
        } else {
            // Authenticated user with completed onboarding shouldn't be here
        }
        
        // Check current permission states
        checkCurrentPermissions()
        
        setupValidations()
    }
    
    /// Clears all user data from UserDefaults to ensure we don't mix data between different users
    private func clearUserData() {
        // Reset all local properties
        DispatchQueue.main.async {
            self.email = ""
            self.password = ""
            self.confirmPassword = ""
            self.firstName = ""
            self.lastName = ""
            self.phoneNumber = ""
            self.companyCode = ""
            self.userId = ""
            self.isSignedUp = false
            self.isCompanyJoined = false
            self.selectedUserType = nil
        }
        
        // Clear data from UserDefaults (only onboarding-specific fields)
        UserDefaults.standard.removeObject(forKey: "user_email")
        UserDefaults.standard.removeObject(forKey: "user_password")
        UserDefaults.standard.removeObject(forKey: "user_first_name")
        UserDefaults.standard.removeObject(forKey: "user_last_name")
        UserDefaults.standard.removeObject(forKey: "user_phone_number")
        UserDefaults.standard.removeObject(forKey: "company_code")
        
    }
    
    // Populate data from an existing user
    func populateFromUser(_ user: User) {
        
        // First check if user has an explicit userType - this is the source of truth
        if let userType = user.userType {
            // Only override if we don't already have the correct type
            if self.selectedUserType != userType {
                self.selectedUserType = userType
            }
        }
        
        // Populate basic info
        if !user.firstName.isEmpty {
            self.firstName = user.firstName
            UserDefaults.standard.set(user.firstName, forKey: "user_first_name")
        }
        if !user.lastName.isEmpty {
            self.lastName = user.lastName
            UserDefaults.standard.set(user.lastName, forKey: "user_last_name")
        }
        if let phone = user.phone, !phone.isEmpty {
            self.phoneNumber = phone
            UserDefaults.standard.set(phone, forKey: "user_phone_number")
        }
        if let email = user.email, !email.isEmpty {
            self.email = email
            UserDefaults.standard.set(email, forKey: "user_email")
        }
        
        // Set company info
        if let companyId = user.companyId, !companyId.isEmpty {
            self.isCompanyJoined = true
            UserDefaults.standard.set(true, forKey: "has_joined_company")
            UserDefaults.standard.set(companyId, forKey: "company_id")
            
            // Get company name from UserDefaults if available
            if let savedCompanyName = UserDefaults.standard.string(forKey: "Company Name"), !savedCompanyName.isEmpty {
                self.companyName = savedCompanyName
            }
            
            // Try to load company details from DataController
            if let company = dataController?.getCompany(id: companyId) {
                populateFromCompany(company)
            }
        }
        
        // Mark as signed up
        self.isSignedUp = true
        self.userId = user.id
        UserDefaults.standard.set(user.id, forKey: "user_id")
        
    }
    
    // Populate data from an existing company
    func populateFromCompany(_ company: Company) {
        
        // Populate company basic info
        if !company.name.isEmpty {
            self.companyName = company.name
            UserDefaults.standard.set(company.name, forKey: "Company Name")
        }
        
        // Populate company address
        if let address = company.address, !address.isEmpty {
            self.companyAddress = address
            UserDefaults.standard.set(address, forKey: "company_address")
        }
        
        // Populate company contact info
        if let email = company.email, !email.isEmpty {
            self.companyEmail = email
            UserDefaults.standard.set(email, forKey: "company_email")
        }
        
        if let phone = company.phone, !phone.isEmpty {
            self.companyPhone = phone
            UserDefaults.standard.set(phone, forKey: "company_phone")
        }
        
        // Populate company details
        let industries = company.getIndustries()
        if !industries.isEmpty {
            // Map the first industry string to Industry enum if possible
            if let firstIndustry = industries.first,
               let industryEnum = Industry.allCases.first(where: { $0.displayName == firstIndustry }) {
                self.companyIndustry = industryEnum
            }
        }
        
        // Map company size from string to enum
        if let size = company.companySize,
           let sizeEnum = CompanySize.allCases.first(where: { $0.rawValue == size }) {
            self.companySize = sizeEnum
        }
        
        // Map company age from string to enum
        if let age = company.companyAge,
           let ageEnum = CompanyAge.allCases.first(where: { $0.displayName == age }) {
            self.companyAge = ageEnum
        }
    }
    
    // Check and skip to the appropriate step based on existing data
    private func checkAndSkipToAppropriateStep() {
        
        // If we're at welcome and have data, determine the right step
        if currentStep == .welcome {
            // Check what data we have to determine where to skip
            if selectedUserType == nil {
                // No user type - start from user type selection
                return
            }
            
            // Check if this is an authenticated user (e.g., from Apple Sign-In)
            let isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
            
            if !isSignedUp || userId.isEmpty {
                // User type known but not signed up - skip to account setup
                // UNLESS they're already authenticated (Apple Sign-In case)
                if isAuthenticated && !email.isEmpty {
                    // Show account created screen briefly (organizationJoin is the "Account Created" screen)
                    DispatchQueue.main.async {
                        self.currentStep = .organizationJoin
                    }
                    // Auto-advance after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        // Skip to appropriate next step based on user type
                        if self.selectedUserType == .employee {
                            self.currentStep = self.firstName.isEmpty || self.lastName.isEmpty || self.phoneNumber.isEmpty ? .userDetails : .companyCode
                        } else {
                            self.currentStep = .userDetails
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.currentStep = .accountSetup
                    }
                }
                return
            }
            
            if firstName.isEmpty || lastName.isEmpty || phoneNumber.isEmpty {
                // Signed up but missing personal info - skip to user details
                DispatchQueue.main.async {
                    self.currentStep = .userDetails
                }
                return
            }
            
            if selectedUserType == .employee && !isCompanyJoined {
                // Employee without company - skip to company code
                DispatchQueue.main.async {
                    self.currentStep = .companyCode
                }
                return
            }
            
            if selectedUserType == .company {
                // Company owners should always go through company setup steps
                // even if they have existing data (to review/confirm)
                DispatchQueue.main.async {
                    self.currentStep = .companyBasicInfo
                }
                return
            }
            
            // For employees with a company, skip to permissions
            if selectedUserType == .employee && isCompanyJoined {
                DispatchQueue.main.async {
                    self.currentStep = .permissions
                }
                return
            }
        }
    }
    
    // Check current permission states
    private func checkCurrentPermissions() {
        // Check location permission
        let locationStatus = locationManager.authorizationStatus
        let isGranted = (locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse)
        DispatchQueue.main.async {
            self.isLocationPermissionGranted = isGranted
        }
        
        // Check notification permission
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isNotificationsPermissionGranted = (settings.authorizationStatus == .authorized)
            }
        }
    }
    
    // Setup field validations
    private func setupValidations() {
        // Email validation
        $email
            .dropFirst()
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .map { email in
                let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
                let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
                return emailPredicate.evaluate(with: email)
            }
            .receive(on: RunLoop.main) // Ensure updates happen on main thread
            .assign(to: &$isEmailValid)
        
        // Password validation
        $password
            .dropFirst()
            .map { password in
                return password.count >= 8
            }
            .receive(on: RunLoop.main) // Ensure updates happen on main thread
            .assign(to: &$isPasswordValid)
        
        // Confirm password matching
        Publishers.CombineLatest($password, $confirmPassword)
            .dropFirst()
            .map { password, confirmPassword in
                return !password.isEmpty && password == confirmPassword
            }
            .receive(on: RunLoop.main) // Ensure updates happen on main thread
            .assign(to: &$isPasswordMatching)
        
        // Phone validation
        $phoneNumber
            .dropFirst()
            .map { phoneNumber in
                let digitsOnly = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                return digitsOnly.count >= 10
            }
            .receive(on: RunLoop.main) // Ensure updates happen on main thread
            .assign(to: &$isPhoneValid)
        
        // Company email validation
        $companyEmail
            .dropFirst()
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .map { email in
                let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
                let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
                return emailPredicate.evaluate(with: email)
            }
            .receive(on: RunLoop.main)
            .assign(to: &$isCompanyEmailValid)
        
        // Company name validation
        $companyName
            .dropFirst()
            .map { name in
                return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .receive(on: RunLoop.main)
            .assign(to: &$isCompanyNameValid)
        
        // Company address validation
        $companyAddress
            .dropFirst()
            .map { address in
                return !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .receive(on: RunLoop.main)
            .assign(to: &$isCompanyAddressValid)
        
        // Company phone validation
        $companyPhone
            .dropFirst()
            .map { phoneNumber in
                let digitsOnly = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                return digitsOnly.count >= 10
            }
            .receive(on: RunLoop.main)
            .assign(to: &$isCompanyPhoneValid)
    }
    
    
    // Format and validate phone number
    func formatPhoneNumber() {
        // Format phone number (remove any non-digits)
        let digitsOnly = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        phoneNumber = digitsOnly
        
        // Store phone number in UserDefaults for later use
        if isPhoneValid {
            UserDefaults.standard.set(phoneNumber, forKey: "user_phone_number")
        }
    }
    
    // Submit initial sign up (email and password only)
    func submitEmailPasswordSignUp() async throws -> Bool {
        // Validate email and password
        guard isEmailValid else {
            errorMessage = "Invalid email address"
            return false
        }
        
        guard isPasswordValid else {
            errorMessage = "Password must be at least 8 characters"
            return false
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return false
        }
        
        // Sign up via Supabase Auth
        do {
            guard let authManager = dataController?.authManager else {
                await MainActor.run { errorMessage = "App not ready. Please restart." }
                return false
            }

            try await authManager.signUpWithEmail(email, password: password)

            // signUpWithEmail stores userId in UserDefaults and keychain
            guard let userIdValue = authManager.getUserId(), !userIdValue.isEmpty else {
                await MainActor.run { errorMessage = "Account creation failed. Please try again." }
                return false
            }

            // Also create a row in the Supabase users table so other queries work
            let userRepo = UserRepository(companyId: "")
            let userDTO = SupabaseUserDTO(
                id: userIdValue,
                bubbleId: nil,
                companyId: nil,
                firstName: "",
                lastName: "",
                email: email,
                phone: nil,
                homeAddress: nil,
                profileImageUrl: nil,
                userColor: nil,
                role: nil,
                userType: (selectedUserType ?? .employee).rawValue,
                isCompanyAdmin: nil,
                hasCompletedOnboarding: false,
                hasCompletedTutorial: nil,
                devPermission: nil,
                latitude: nil,
                longitude: nil,
                locationName: nil,
                isActive: true,
                deletedAt: nil
            )
            try? await userRepo.upsert(userDTO)

            await MainActor.run {
                isSignedUp = true
                userId = userIdValue
                UserDefaults.standard.set(userIdValue, forKey: "user_id")
                UserDefaults.standard.set(userIdValue, forKey: "currentUserId")

                print("[ONBOARDING] User signed up successfully with ID: \(userIdValue)")

                // Create User object in SwiftData
                if let modelContext = dataController?.modelContext {
                    let descriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { $0.id == userIdValue }
                    )
                    let existingUsers = try? modelContext.fetch(descriptor)

                    if existingUsers?.isEmpty ?? true {
                        let userObject = User(
                            id: userIdValue,
                            firstName: "",
                            lastName: "",
                            role: .fieldCrew,
                            companyId: ""
                        )
                        userObject.email = email
                        modelContext.insert(userObject)
                        try? modelContext.save()
                        print("[ONBOARDING] ✅ User object created in SwiftData")
                    }
                }

                UserDefaults.standard.set(email, forKey: "user_email")
                UserDefaults.standard.set(password, forKey: "user_password")

                if let userType = selectedUserType {
                    UserDefaults.standard.set(userType.rawValue, forKey: "selected_user_type")
                }

                AnalyticsManager.shared.trackSignUp(userType: selectedUserType, method: .email)
                AnalyticsManager.shared.setUserType(selectedUserType)
                AnalyticsManager.shared.setUserId(userIdValue)

                UserDefaults.standard.set(false, forKey: "is_authenticated")
                UserDefaults.standard.set(false, forKey: "onboarding_completed")
                UserDefaults.standard.set(OnboardingStep.organizationJoin.rawValue, forKey: "last_onboarding_step_v2")
            }

            return isSignedUp

        } catch {
            await MainActor.run {
                isSignedUp = false
                let msg = error.localizedDescription
                if msg.contains("already registered") || msg.contains("already been registered") {
                    errorMessage = "An account with this email already exists. Please log in instead."
                } else {
                    errorMessage = "Account creation failed: \(msg)"
                }
            }
            return false
        }
    }
    
    // Join company with full user details
    func joinCompany() async -> Bool {
        // Validate fields
        guard !firstName.isEmpty else {
            await MainActor.run {
                errorMessage = "First name is required"
            }
            return false
        }
        
        guard !lastName.isEmpty else {
            await MainActor.run {
                errorMessage = "Last name is required"
            }
            return false
        }
        
        guard isPhoneValid else {
            await MainActor.run {
                errorMessage = "A valid phone number is required"
            }
            return false
        }
        
        guard !companyCode.isEmpty else {
            await MainActor.run {
                errorMessage = "Company code is required"
            }
            return false
        }
        
        // Ensure we have the user ID - this is now the critical piece
        let currentUserId = userId.isEmpty ? UserDefaults.standard.string(forKey: "user_id") ?? "" : userId
        guard !currentUserId.isEmpty else {
            await MainActor.run {
                errorMessage = "User ID is missing. Please restart the onboarding process."
            }
            return false
        }
        
        
        // Update the userId property if we loaded it from UserDefaults
        if userId.isEmpty && !currentUserId.isEmpty {
            await MainActor.run {
                self.userId = currentUserId
            }
        }
        
        // Format phone number
        let formattedPhone = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        
        do {
            // Look up company by code in Supabase
            let companyRepo = CompanyRepository()
            guard let companyDTO = try await companyRepo.fetchByCode(companyCode) else {
                await MainActor.run {
                    isCompanyJoined = false
                    errorMessage = "No company found with that code. Please check and try again."
                }
                return false
            }

            let foundCompanyId = companyDTO.id

            // Update user's company_id and profile in Supabase
            let userRepo = UserRepository(companyId: foundCompanyId)
            try await userRepo.updateFields(userId: currentUserId, fields: [
                "company_id": .string(foundCompanyId),
                "first_name": .string(firstName),
                "last_name": .string(lastName),
                "phone": .string(formattedPhone),
                "role": .string("field_crew"),
                "is_company_admin": .bool(false)
            ])

            // Add user to company's seated_employee_ids
            var seatIds = companyDTO.seatedEmployeeIds ?? []
            if !seatIds.contains(currentUserId) {
                seatIds.append(currentUserId)
                try? await companyRepo.updateSeatedEmployees(companyId: foundCompanyId, userIds: seatIds)
            }
            
            // Store data and update SwiftData
            await MainActor.run {
                isCompanyJoined = true
                companyName = companyDTO.name

                // Store in UserDefaults
                UserDefaults.standard.set(companyDTO.name, forKey: "Company Name")
                UserDefaults.standard.set(foundCompanyId, forKey: "company_id")
                UserDefaults.standard.set(foundCompanyId, forKey: "currentUserCompanyId")
                UserDefaults.standard.set(firstName, forKey: "user_first_name")
                UserDefaults.standard.set(lastName, forKey: "user_last_name")
                UserDefaults.standard.set(formattedPhone, forKey: "user_phone_number")
                UserDefaults.standard.set(companyCode, forKey: "company_code")

                if let modelContext = dataController?.modelContext {
                    // Create or update Company in SwiftData
                    let companyDescriptor = FetchDescriptor<Company>(
                        predicate: #Predicate<Company> { $0.id == foundCompanyId }
                    )
                    if let existing = try? modelContext.fetch(companyDescriptor).first {
                        existing.name = companyDTO.name
                        existing.email = companyDTO.email
                        existing.phone = companyDTO.phone
                        existing.address = companyDTO.address
                        existing.lastSyncedAt = Date()
                    } else {
                        let companyObject = Company(id: foundCompanyId, name: companyDTO.name)
                        companyObject.email = companyDTO.email
                        companyObject.phone = companyDTO.phone
                        companyObject.address = companyDTO.address
                        modelContext.insert(companyObject)
                    }
                    try? modelContext.save()

                    // Update User in SwiftData with company and profile data
                    let userDescriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { $0.id == currentUserId }
                    )
                    if let user = try? modelContext.fetch(userDescriptor).first {
                        user.companyId = foundCompanyId
                        user.firstName = firstName
                        user.lastName = lastName
                        user.phone = formattedPhone
                        user.lastSyncedAt = Date()
                        try? modelContext.save()

                        dataController?.currentUser = user
                        print("[ONBOARDING] ✅ Updated user in SwiftData before sync")
                    } else {
                        print("[ONBOARDING] ⚠️ Could not find user in SwiftData to update companyId")
                    }
                }
            }

            // Perform full sync after successful join
            if isCompanyJoined {
                print("[ONBOARDING] Employee joined company successfully, triggering full sync")

                guard let dataController = dataController else {
                    print("[ONBOARDING] ❌ DataController is nil - cannot sync")
                    await MainActor.run {
                        errorMessage = "App initialization error. Please restart and try again."
                        isLoading = false
                    }
                    return false
                }

                let healthManager = await DataHealthManager(
                    dataController: dataController,
                    authManager: dataController.authManager
                )

                let (healthState, recoveryAction) = await healthManager.performHealthCheck(duringOnboarding: true)

                if !healthState.isHealthy {
                    print("[ONBOARDING] ❌ Data health check failed after joining company: \(healthState)")
                    await healthManager.executeRecoveryAction(recoveryAction)

                    await MainActor.run {
                        errorMessage = "Unable to complete setup. Please try again."
                        isLoading = false
                    }
                    return false
                }

                guard let syncManager = dataController.syncManager else {
                    print("[ONBOARDING] ❌ SyncManager is nil - cannot sync")
                    await MainActor.run {
                        errorMessage = "Sync initialization error. Please restart and try again."
                        isLoading = false
                    }
                    return false
                }

                await syncManager.performOnboardingSync()
                print("[ONBOARDING] ✅ Full sync completed after joining company")

                await reloadCurrentUser()
            }

            return isCompanyJoined

        } catch {
            await MainActor.run {
                isCompanyJoined = false
                errorMessage = "Failed to join company: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    // Save phone number validation
    func validatePhoneNumber() -> Bool {
        // Format phone number
        let digitsOnly = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        phoneNumber = digitsOnly
        
        // Check if valid
        return isPhoneValid
    }
    
    // Skip company code step
    func skipCompanyCode() {
        companyCode = ""
        moveToNextStep()
    }
    
    // Request location permission
    func requestLocationPermission(completion: ((Bool) -> Void)? = nil) {
        
        // Check current status first
        let currentStatus = locationManager.authorizationStatus
        
        // If already granted, just update the state
        if currentStatus == .authorizedAlways || currentStatus == .authorizedWhenInUse {
            DispatchQueue.main.async {
                self.isLocationPermissionGranted = true
            }
            UserDefaults.standard.set(true, forKey: "location_permission_granted")
            completion?(true)
            return
        }
        
        // If denied or restricted, call completion with false
        if currentStatus == .denied || currentStatus == .restricted {
            DispatchQueue.main.async {
                self.isLocationPermissionGranted = false
            }
            UserDefaults.standard.set(false, forKey: "location_permission_granted")
            completion?(false)
            return
        }
        
        // Request permission with completion handler
        locationManager.requestPermissionIfNeeded(requestAlways: true) { [weak self] isAllowed in
            if !isAllowed {
                // Permission was denied, call completion
                DispatchQueue.main.async {
                    self?.isLocationPermissionGranted = false
                    UserDefaults.standard.set(false, forKey: "location_permission_granted")
                    completion?(false)
                }
            }
        }
        
        // Observe authorization changes
        locationManager.$authorizationStatus
            .sink { [weak self] status in
                DispatchQueue.main.async {
                    self?.isLocationPermissionGranted = (status == .authorizedAlways || status == .authorizedWhenInUse)
                    
                    // Store permission status in UserDefaults
                    UserDefaults.standard.set(self?.isLocationPermissionGranted ?? false, forKey: "location_permission_granted")
                    
                    // Call completion if status changed to denied/restricted
                    if status == .denied || status == .restricted {
                        completion?(false)
                    } else if status == .authorizedAlways || status == .authorizedWhenInUse {
                        completion?(true)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Helper Methods
    
    /// Load stored user type from various sources
    private static func loadStoredUserType() -> UserType? {
        // First check the selected_user_type key
        if let savedType = UserDefaults.standard.string(forKey: "selected_user_type"),
           let userType = UserType(rawValue: savedType) {
            return userType
        }
        
        // Check the alternate user_type key
        if let savedType = UserDefaults.standard.string(forKey: "user_type"),
           let userType = UserType(rawValue: savedType) {
            return userType
        }
        
        // Check the raw API response
        if let rawType = UserDefaults.standard.string(forKey: "user_type_raw") {
            if rawType.lowercased() == "company" {
                return .company
            } else if rawType.lowercased() == "employee" {
                return .employee
            }
        }
        
        return nil
    }
    
    // MARK: - Navigation Methods
    
    // Request notifications permission
    func requestNotificationsPermission() {
        // Use the real NotificationManager to request permissions
        NotificationManager.shared.requestPermission { granted in
            DispatchQueue.main.async {
                self.isNotificationsPermissionGranted = granted
                
                // Store permission status in UserDefaults
                UserDefaults.standard.set(granted, forKey: "notifications_permission_granted")
            }
        }
    }
    
    // Check if user can proceed from account setup screen (combined email/password)
    var canProceedFromAccountSetup: Bool {
        // Allow proceeding if already authenticated (resuming onboarding)
        let isAlreadyAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
        
        return isAlreadyAuthenticated || (isEmailValid && isPasswordValid)
    }
    
    // Check if user can proceed from user details screen
    var canProceedFromUserDetails: Bool {
        // Allow proceeding if resuming onboarding with existing user info
        let isResuming = UserDefaults.standard.bool(forKey: "resume_onboarding")
        let hasUserInfo = UserDefaults.standard.string(forKey: "user_first_name") != nil
        
        if isResuming && hasUserInfo {
            // Load saved values if resuming
            if firstName.isEmpty {
                firstName = UserDefaults.standard.string(forKey: "user_first_name") ?? ""
            }
            if lastName.isEmpty {
                lastName = UserDefaults.standard.string(forKey: "user_last_name") ?? ""
            }
            if phoneNumber.isEmpty {
                phoneNumber = UserDefaults.standard.string(forKey: "user_phone_number") ?? ""
            }
            return true
        }
        
        return !firstName.isEmpty && !lastName.isEmpty && isPhoneValid
    }
    
    // Make this a computed property to maintain compatibility with existing code
    var currentStepV2: OnboardingStep {
        get { return currentStep }
        set { currentStep = newValue }
    }
    
    // Move to the next step in the flow
    func moveToNextStep() {
        
        // Special handling for resuming onboarding or existing users
        let isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
        
        // Check if we can skip certain steps based on existing data
        if currentStep == .welcome {
            // When starting, check if we can skip directly to a later step based on what's already done
            
            // If user type is already known, skip user type selection
            if selectedUserType != nil {
                
                // If user is already signed up, skip account setup too
                if isSignedUp && !userId.isEmpty {
                    
                    // If user already has personal info, skip to the appropriate step
                    if !firstName.isEmpty && !lastName.isEmpty && !phoneNumber.isEmpty {
                        
                        // For employees, go to company code if not joined
                        if selectedUserType == .employee && !isCompanyJoined {
                            let skipToStep = OnboardingStep.companyCode
                            DispatchQueue.main.async {
                                self.currentStep = skipToStep
                            }
                            return
                        }
                        
                        // If company is joined, go to permissions
                        if isCompanyJoined {
                            let skipToStep = OnboardingStep.permissions
                            DispatchQueue.main.async {
                                self.currentStep = skipToStep
                            }
                            return
                        }
                    } else {
                        // Skip to user details if account exists but no personal info
                        let skipToStep = OnboardingStep.userDetails
                        DispatchQueue.main.async {
                            self.currentStep = skipToStep
                        }
                        return
                    }
                } else {
                    // Skip to account setup if user type is known but not signed up
                    let skipToStep = OnboardingStep.accountSetup
                    DispatchQueue.main.async {
                        self.currentStep = skipToStep
                    }
                    return
                }
            }
        }
        
        // Skip user type selection if already known
        if currentStep == .userTypeSelection && selectedUserType != nil {
            // Check if user is already authenticated (e.g., from Apple Sign-In)
            if isSignedUp && isAuthenticated {
                // Show the account created screen briefly before moving to next step (organizationJoin is the "Account Created" screen)
                DispatchQueue.main.async {
                    self.currentStep = .organizationJoin
                }
                // Auto-advance after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let nextStep = self.selectedUserType == .employee ? OnboardingStep.userDetails : OnboardingStep.userDetails
                    self.currentStep = nextStep
                }
            } else {
                // Continue to account setup if not authenticated
                DispatchQueue.main.async {
                    self.currentStep = .accountSetup
                }
            }
            return
        }
        
        // Skip account setup if already authenticated
        if currentStep == .accountSetup && isSignedUp && isAuthenticated {
            // Show the account created screen briefly before moving to next step (organizationJoin is the "Account Created" screen)
            DispatchQueue.main.async {
                self.currentStep = .organizationJoin
            }
            // Auto-advance after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let nextStep = self.selectedUserType == .employee ? OnboardingStep.userDetails : OnboardingStep.userDetails
                self.currentStep = nextStep
            }
            return
        }
        
        // Skip user details if already have the information
        if currentStep == .userDetails && !firstName.isEmpty && !lastName.isEmpty && !phoneNumber.isEmpty {
            // Check if company is already joined before deciding next step
            let nextStep: OnboardingStep
            if selectedUserType == .employee {
                if isCompanyJoined {
                    // Skip to permissions if already have a company
                    nextStep = .permissions
                } else {
                    // Go to company code if no company yet
                    nextStep = .companyCode
                }
            } else {
                // Company owner flow
                nextStep = .companyBasicInfo
            }
            DispatchQueue.main.async {
                self.currentStep = nextStep
            }
            return
        }
        
        // Normal flow - get the next step
        if var nextStep = currentStep.nextStep(userType: selectedUserType) {
            
            // Special check: if the next step is company code but user already has a company, skip to permissions
            // Only apply this logic for employees, not company owners
            if nextStep == .companyCode && selectedUserType == .employee && isCompanyJoined {
                nextStep = .permissions
            }
            
            // Save the step to UserDefaults for potential resume later
            UserDefaults.standard.set(nextStep.rawValue, forKey: "last_onboarding_step_v2")
            
            DispatchQueue.main.async {
                self.currentStep = nextStep
            }
        } else {
        }
    }
    
    // Move to a specific step
    func moveTo(step: OnboardingStep) {
        
        // Save the step to UserDefaults for potential resume later
        UserDefaults.standard.set(step.rawValue, forKey: "last_onboarding_step_v2")
        
        DispatchQueue.main.async {
            self.currentStep = step
        }
    }
    
    // Move back one step
    func moveToPreviousStep() {
        
        // Special case: if we're at the company code step and we loaded directly into it
        // because the user needs to complete it, don't allow going back
        if currentStep == .companyCode && UserDefaults.standard.string(forKey: "user_id") != nil {
            
            // Set error message to explain why
            DispatchQueue.main.async {
                self.errorMessage = "You must complete company registration to continue. Please enter your company code."
            }
            return
        }
        
        if var prevStep = currentStep.previousStep(userType: selectedUserType) {
            
            // Special handling: if going back to company code but user already has a company, skip it
            if prevStep == .companyCode && selectedUserType == .employee && isCompanyJoined {
                // Go back one more step to user details
                if let skipStep = prevStep.previousStep(userType: selectedUserType) {
                    prevStep = skipStep
                }
            }
            
            // Save the step to UserDefaults for potential resume later
            UserDefaults.standard.set(prevStep.rawValue, forKey: "last_onboarding_step_v2")
            
            DispatchQueue.main.async {
                self.currentStep = prevStep
            }
        } else {
        }
    }
    
    
    // MARK: - Company Creation Methods
    
    func createCompany() async throws {
        
        guard isCompanyNameValid else {
            throw OnboardingError.invalidCompanyName
        }
        
        guard isCompanyEmailValid else {
            throw OnboardingError.invalidCompanyEmail
        }
        
        guard isCompanyPhoneValid else {
            throw OnboardingError.invalidCompanyPhone
        }
        
        guard let industry = companyIndustry else {
            throw OnboardingError.missingIndustry
        }
        
        guard let size = companySize else {
            throw OnboardingError.missingCompanySize
        }
        
        guard let age = companyAge else {
            throw OnboardingError.missingCompanyAge
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            // Generate a unique company code for the join flow
            let newCompanyCode = generateCompanyCode()
            let now = ISO8601DateFormatter().string(from: Date())
            let trialEnd = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 14, to: Date())!)

            // Insert company into Supabase
            let companyRepo = CompanyRepository()
            let payload = NewCompanyPayload(
                name: companyName,
                email: companyEmail.isEmpty ? nil : companyEmail,
                phone: companyPhone.isEmpty ? nil : companyPhone,
                address: companyAddress.isEmpty ? nil : companyAddress,
                company_code: newCompanyCode,
                admin_ids: [userId],
                account_holder_id: userId,
                industries: companyIndustry != nil ? [industry.rawValue] : nil,
                company_size: size.rawValue,
                company_age: age.rawValue,
                subscription_status: "trialing",
                trial_start_date: now,
                trial_end_date: trialEnd,
                max_seats: 5,
                created_at: now,
                updated_at: now
            )
            let createdCompany = try await companyRepo.insert(payload)
            let companyId = createdCompany.id

            // Update user's company_id in Supabase
            let userRepo = UserRepository(companyId: companyId)
            try await userRepo.updateFields(userId: userId, fields: [
                "company_id": .string(companyId),
                "role": .string("admin"),
                "is_company_admin": .bool(true),
                "first_name": .string(firstName),
                "last_name": .string(lastName),
                "phone": .string(phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression))
            ])

            // Store company data and update SwiftData
            await MainActor.run {
                isLoading = false
                UserDefaults.standard.set(companyName, forKey: "Company Name")
                UserDefaults.standard.set(true, forKey: "company_created")
                UserDefaults.standard.set(companyId, forKey: "company_id")
                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")

                if let modelContext = dataController?.modelContext {
                    // Create Company object in SwiftData
                    let companyObject = Company(id: companyId, name: companyName)
                    companyObject.email = companyEmail
                    companyObject.phone = companyPhone
                    companyObject.address = companyAddress
                    companyObject.companySize = size.rawValue
                    companyObject.companyAge = age.rawValue
                    companyObject.setIndustries([industry.rawValue])
                    companyObject.subscriptionStatus = "trialing"
                    companyObject.trialStartDate = Date()
                    companyObject.trialEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())
                    companyObject.maxSeats = 5
                    modelContext.insert(companyObject)
                    try? modelContext.save()
                    print("[ONBOARDING] ✅ Company saved to SwiftData")

                    // Update User object with company ID
                    let userDescriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { $0.id == userId }
                    )
                    if let userObject = try? modelContext.fetch(userDescriptor).first {
                        userObject.companyId = companyId
                        userObject.role = .admin
                        userObject.firstName = firstName
                        userObject.lastName = lastName
                        userObject.phone = phoneNumber
                        userObject.hasCompletedAppOnboarding = false
                        try? modelContext.save()
                        dataController?.currentUser = userObject
                        print("[ONBOARDING] ✅ User updated with company ID")
                    } else {
                        errorMessage = "User account not found. Please restart onboarding."
                    }
                }

                self.companyCode = newCompanyCode
                UserDefaults.standard.set(newCompanyCode, forKey: "company_code")
            }

            // Trigger sync
            print("[ONBOARDING] Company created successfully, triggering full sync")

            guard let dataController = dataController else {
                await MainActor.run {
                    errorMessage = "App initialization error. Please restart and try again."
                    isLoading = false
                }
                return
            }

            if dataController.syncManager == nil {
                if let modelContext = dataController.modelContext {
                    await dataController.setModelContext(modelContext)
                }
            }

            let healthManager = await DataHealthManager(
                dataController: dataController,
                authManager: dataController.authManager
            )
            let (healthState, recoveryAction) = await healthManager.performHealthCheck(duringOnboarding: true)
            if !healthState.isHealthy {
                await healthManager.executeRecoveryAction(recoveryAction)
                await MainActor.run {
                    errorMessage = "Unable to complete setup. Please try again."
                    isLoading = false
                }
                return
            }

            guard let syncManager = dataController.syncManager else {
                await MainActor.run {
                    errorMessage = "Sync initialization error. Please restart and try again."
                    isLoading = false
                }
                return
            }

            await syncManager.performOnboardingSync()
            print("[ONBOARDING] ✅ Full sync completed after company creation")

            await reloadCurrentUser()

            await MainActor.run {
                isCompanyCreationComplete = true
                print("[ONBOARDING] ✅ Company creation marked complete")
            }
        } catch {
            await MainActor.run {
                isLoading = false
                isShowingCompanyCreationLoading = false
                isCompanyCreationComplete = false
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func sendTeamInvitations() async throws {
        guard !teamInviteEmails.isEmpty else { return }
        
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            let companyId = UserDefaults.standard.string(forKey: "company_id") ?? ""
            _ = try await onboardingService.sendInvites(emails: teamInviteEmails, companyId: companyId)
            
            await MainActor.run {
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Upload user profile picture if one was selected during onboarding
    func uploadProfilePictureIfNeeded() async {
        guard let profileImage = profileImage,
              let user = dataController?.currentUser else {
            print("[ONBOARDING] No profile picture to upload or user not found")
            return
        }

        print("[ONBOARDING] Uploading profile picture...")
        do {
            let _ = try await dataController?.uploadUserProfileImage(profileImage, for: user)
            print("[ONBOARDING] ✅ Profile picture uploaded successfully")
        } catch {
            print("[ONBOARDING] ⚠️ Failed to upload profile picture: \(error)")
            // Don't block onboarding - user can upload later
        }
    }

    /// Upload company logo if one was selected during onboarding
    func uploadCompanyLogoIfNeeded() async {
        guard let companyLogo = companyLogo,
              let companyId = UserDefaults.standard.string(forKey: "company_id"),
              let dataController = dataController else {
            print("[ONBOARDING] No company logo to upload or company not found")
            return
        }

        // Get company from SwiftData
        guard let modelContext = dataController.modelContext else {
            print("[ONBOARDING] ⚠️ ModelContext not available")
            return
        }

        let descriptor = FetchDescriptor<Company>(
            predicate: #Predicate<Company> { $0.id == companyId }
        )

        guard let company = try? modelContext.fetch(descriptor).first else {
            print("[ONBOARDING] ⚠️ Company not found in SwiftData")
            return
        }

        print("[ONBOARDING] Uploading company logo...")
        do {
            let _ = try await dataController.uploadCompanyLogo(companyLogo, for: company)
            print("[ONBOARDING] ✅ Company logo uploaded successfully")
        } catch {
            print("[ONBOARDING] ⚠️ Failed to upload company logo: \(error)")
            // Don't block onboarding - user can upload later
        }
    }

    func completeOnboarding() {
        // Upload images before completing onboarding
        Task {
            // Upload profile picture if available
            await uploadProfilePictureIfNeeded()

            // Upload company logo if available (for company owners)
            await uploadCompanyLogoIfNeeded()

            await MainActor.run {
                // Mark onboarding as completed
                UserDefaults.standard.set(true, forKey: "onboarding_completed")
                UserDefaults.standard.set(false, forKey: "resume_onboarding")

                // Store final user type
                if let userType = selectedUserType {
                    UserDefaults.standard.set(userType.rawValue, forKey: "user_type")
                }

                // Set authentication flag to enter the app
                UserDefaults.standard.set(true, forKey: "is_authenticated")
            }

            // Update the server with onboarding completion status
            if let userId = UserDefaults.standard.string(forKey: "user_id"),
               let dataController = dataController {
                do {
                    let fields: [String: AnyJSON] = [
                        "has_completed_onboarding": .bool(true)
                    ]
                    try await dataController.syncManager.updateUserFields(userId: userId, fields: fields)

                    // Update the local user model
                    await MainActor.run {
                        if let user = dataController.currentUser {
                            user.hasCompletedAppOnboarding = true
                        }
                    }
                } catch {
                    // Continue anyway - we don't want to block the user
                }

                // NOTE: Full sync already happened in createCompany() before reaching this point
                // No need to sync again here - all data is already loaded
                print("[ONBOARDING] Onboarding complete, data already synced from createCompany()")
            }

            // Update DataController if available
            await MainActor.run {
                if let dataController = dataController {
                    dataController.isAuthenticated = true
                }

                // Track onboarding completion for Google Ads
                let hasCompany = dataController?.currentUser?.companyId != nil && !(dataController?.currentUser?.companyId ?? "").isEmpty
                AnalyticsManager.shared.trackCompleteOnboarding(userType: selectedUserType, hasCompany: hasCompany)

                // Track trial start for company owners
                if selectedUserType == .company {
                    AnalyticsManager.shared.trackBeginTrial(userType: selectedUserType, trialDays: 30)
                }

                // Dismiss the onboarding overlay
                NotificationCenter.default.post(name: Notification.Name("DismissOnboarding"), object: nil)
            }
        }
    }
    
    /// Performs a data health check when welcome pages load
    /// This ensures all required data is present when returning to onboarding mid-flow
    func performDataHealthCheck() async {
        print("[ONBOARDING] 🏥 Performing data health check on welcome page load...")

        guard let dataController = dataController else {
            print("[ONBOARDING] ❌ DataController is nil")
            await MainActor.run {
                errorMessage = "App initialization error. Please restart."
            }
            return
        }

        let healthManager = await DataHealthManager(
            dataController: dataController,
            authManager: AuthManager()
        )

        let (healthState, recoveryAction) = await healthManager.performHealthCheck(duringOnboarding: true)

        if !healthState.isHealthy {
            print("[ONBOARDING] ❌ Data health check failed: \(healthState)")
            print("[ONBOARDING] 🔧 Executing recovery action: \(recoveryAction)")
            await healthManager.executeRecoveryAction(recoveryAction)
        } else {
            print("[ONBOARDING] ✅ Data health check passed")
        }
    }

    private func reloadCurrentUser() async {
        guard let userId = UserDefaults.standard.string(forKey: "user_id"),
              let modelContext = dataController?.modelContext,
              let dataController = dataController else {
            print("[ONBOARDING] Cannot reload user - missing userId, modelContext, or dataController")
            return
        }

        // Add a small delay to ensure SwiftData has finished persisting
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        do {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { $0.id == userId }
            )

            let users = try modelContext.fetch(descriptor)

            if let user = users.first {
                print("[ONBOARDING] ✅ Reloaded user from SwiftData")
                print("[ONBOARDING]    - User ID: \(user.id)")
                print("[ONBOARDING]    - Name: \(user.fullName)")
                print("[ONBOARDING]    - Role: \(user.role)")
                print("[ONBOARDING]    - Company ID: \(user.companyId ?? "none")")

                // Update currentUser on main thread
                await MainActor.run {
                    dataController.currentUser = user
                    // Force views to update
                    dataController.objectWillChange.send()
                }

                // Also verify the company is accessible
                if let companyId = user.companyId {
                    let companyDescriptor = FetchDescriptor<Company>(
                        predicate: #Predicate<Company> { $0.id == companyId }
                    )
                    if let company = try? modelContext.fetch(companyDescriptor).first {
                        print("[ONBOARDING]    - Company: \(company.name)")
                        print("[ONBOARDING]    - Subscription Status: \(company.subscriptionStatus ?? "none")")
                    } else {
                        print("[ONBOARDING]    - ⚠️ Company not found in SwiftData")
                    }
                }
            } else {
                print("[ONBOARDING] ❌ User not found in SwiftData after sync")
            }
        } catch {
            print("[ONBOARDING] ❌ Error reloading user: \(error.localizedDescription)")
        }
    }

    func logoutAndReturnToLogin() {

        // Use DataController's logout method to properly clean everything
        if let dataController = dataController {
            Task { @MainActor in
                dataController.logout()
            }
        } else {
            // Fallback if no DataController - manually clear critical data
            clearUserData()
            
            // Clear all stored user type data
            UserDefaults.standard.removeObject(forKey: "selected_user_type")
            UserDefaults.standard.removeObject(forKey: "user_type_raw")
            UserDefaults.standard.removeObject(forKey: "apple_user_identifier")
            
            // Clear authentication and onboarding state
            UserDefaults.standard.removeObject(forKey: "is_authenticated")
            UserDefaults.standard.removeObject(forKey: "user_id")
            UserDefaults.standard.removeObject(forKey: "resume_onboarding")
            UserDefaults.standard.removeObject(forKey: "onboarding_completed")
            UserDefaults.standard.removeObject(forKey: "company_id")
            UserDefaults.standard.removeObject(forKey: "Company Name")
            UserDefaults.standard.removeObject(forKey: "has_joined_company")
            UserDefaults.standard.removeObject(forKey: "company_created")
            UserDefaults.standard.removeObject(forKey: "user_type")
        }
        
        // Reset all view model properties
        DispatchQueue.main.async {
            self.selectedUserType = nil
            self.currentStep = .welcome
            self.isSignedUp = false
            self.isCompanyJoined = false
            self.errorMessage = ""
            self.isLoading = false
            
            // Reset company data
            self.companyName = ""
            self.companyAddress = ""
            self.companyEmail = ""
            self.companyPhone = ""
            self.companyIndustry = nil
            self.companySize = nil
            self.companyAge = nil
            self.teamInviteEmails = []
        }
        
        // Dismiss onboarding and return to login
        NotificationCenter.default.post(name: Notification.Name("DismissOnboarding"), object: nil)
    }
}

enum OnboardingError: Error, LocalizedError {
    case invalidCompanyName
    case invalidCompanyEmail
    case invalidCompanyPhone
    case missingIndustry
    case missingCompanySize
    case missingCompanyAge
    
    var errorDescription: String? {
        switch self {
        case .invalidCompanyName:
            return "Please enter a valid company name"
        case .invalidCompanyEmail:
            return "Please enter a valid company email"
        case .invalidCompanyPhone:
            return "Please enter a valid company phone number"
        case .missingIndustry:
            return "Please select your company's industry"
        case .missingCompanySize:
            return "Please select your company size"
        case .missingCompanyAge:
            return "Please select how long your company has been in business"
        }
    }
}
