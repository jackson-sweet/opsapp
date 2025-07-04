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
                print("🔵 Loaded user type in dataController didSet: \(selectedUserType?.rawValue ?? "nil")")
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
                print("🔵 OnboardingViewModel: User type changed to \(userType.rawValue)")
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
    
    // State management
    @Published var isLoading: Bool = false
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
            
            print("\n🔍 OnboardingViewModel init (shouldLoadExistingData = true):")
            print("  - Loaded userId: '\(self.userId)'")
            print("  - userId is empty: \(self.userId.isEmpty)")
            print("  - email: \(self.email)")
            
            // Mark as signed up if we have a valid user ID
            self.isSignedUp = !self.userId.isEmpty && !self.email.isEmpty
            
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
                print("✅ OnboardingViewModel: User type is already set to: \(userType.rawValue)")
            } else {
                print("⚠️ OnboardingViewModel: No user type set after loading from storage")
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
                print("🔵 OnboardingViewModel: Updating user type from User object: \(userType.rawValue)")
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
        print("🔵 OnboardingViewModel: Populating from company: \(company.name)")
        
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
            
            if !isSignedUp || userId.isEmpty {
                // User type known but not signed up - skip to account setup
                DispatchQueue.main.async {
                    self.currentStep = .accountSetup
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
        
        // Make the API call - only email and password at this stage
        
        do {
            let response = try await onboardingService.signUpUser(
                email: email,
                password: password,
                userType: selectedUserType ?? .employee
            )
            
            // Store data and update state
            await MainActor.run {
                // We got a successful HTTP response, now check if the API considers it successful
                if response.wasSuccessful {
                    // Extract and save user ID from the response, using our helper method
                    if let userIdValue = response.extractedUserId, !userIdValue.isEmpty {
                        isSignedUp = true
                        userId = userIdValue
                        UserDefaults.standard.set(userIdValue, forKey: "user_id")
                        
                        // Print detailed success information for debugging
                        print("\n✅ SIGNUP SUCCESS - userId stored:")
                        print("  - userId instance variable: '\(userId)'")
                        print("  - UserDefaults user_id: '\(UserDefaults.standard.string(forKey: "user_id") ?? "nil")'")
                        
                        // Store email and password in UserDefaults for later (crucial for API calls)
                        UserDefaults.standard.set(email, forKey: "user_email")
                        UserDefaults.standard.set(password, forKey: "user_password")
                        
                        // Save user type now that signup is successful
                        if let userType = selectedUserType {
                            UserDefaults.standard.set(userType.rawValue, forKey: "selected_user_type")
                            print("🔵 Saved user type to UserDefaults after successful signup: \(userType.rawValue)")
                        }
                        
                        // Log that we've saved these important credentials
                        
                        // DO NOT mark as authenticated yet - wait until onboarding is complete
                        // This prevents access to the app with test data
                        UserDefaults.standard.set(false, forKey: "is_authenticated")
                        UserDefaults.standard.set(false, forKey: "onboarding_completed")
                        
                        // Save the current onboarding step - at this point they've completed account setup
                        UserDefaults.standard.set(OnboardingStep.organizationJoin.rawValue, forKey: "last_onboarding_step_v2")
                    } else {
                        // API reported success but didn't provide a user ID - this is a failure
                        isSignedUp = false
                        errorMessage = "Account creation failed. Server did not return a user ID."
                        print("ERROR: API reported success but no user_id was returned")
                    }
                } else {
                    isSignedUp = false
                    if let errMsg = response.error_message, !errMsg.isEmpty {
                        errorMessage = errMsg
                    } else {
                        errorMessage = "Account creation failed. Please try a different email."
                    }
                    print("API returned error message: \(errorMessage)")
                }
            }
            
            return isSignedUp
            
        } catch let signupError as SignUpError {
            await MainActor.run {
                isSignedUp = false
                
                // Display appropriate error message based on error type
                switch signupError {
                case .serverError(let message):
                    // This will display the "message" field from 400 errors
                    errorMessage = message
                    print("Server error during signup: \(message)")
                default:
                    errorMessage = signupError.localizedDescription
                    print("Signup error: \(signupError)")
                }
            }
            return false
        } catch {
            await MainActor.run {
                isSignedUp = false
                errorMessage = "Network error: \(error.localizedDescription)"
                print("Network error during signup: \(error)")
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
        
        // Ensure we have email and password
        guard !email.isEmpty else {
            await MainActor.run {
                errorMessage = "Email is required"
            }
            return false
        }
        
        // Handle missing password (try to get from UserDefaults)
        if password.isEmpty {
            if let savedPassword = UserDefaults.standard.string(forKey: "user_password"), !savedPassword.isEmpty {
                await MainActor.run {
                    password = savedPassword
                }
            } else {
                await MainActor.run {
                    errorMessage = "Password is missing. Please restart the onboarding process."
                }
                return false
            }
        }
        
        // Format phone number
        let formattedPhone = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        
        do {
            // Make the API call with all user details
            let response = try await onboardingService.joinCompany(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                phoneNumber: formattedPhone,
                companyCode: companyCode
            )
            
            // Process and store data
            await MainActor.run {
                if response.wasSuccessful {
                    isCompanyJoined = true
                    
                    // Print detailed success information for debugging
                    
                    // Extract company data from wherever it might be in the response
                    if let companyData = response.extractedCompanyData {
                        companyName = companyData.name
                        
                        // Store company data in UserDefaults
                        UserDefaults.standard.set(companyData.name, forKey: "Company Name")
                        UserDefaults.standard.set(companyData.id, forKey: "company_id")
                        
                        // Also store Company object in SwiftData for employees
                        if let modelContext = dataController?.modelContext {
                            var companyObject: Company
                            
                            // Check if we have the full CompanyDTO in the response
                            if let fullCompanyDTO = response.company {
                                // Use the full company DTO to create/update the model
                                companyObject = fullCompanyDTO.toModel()
                                
                                // Check if company already exists in database
                                let companyId = companyObject.id
                                let descriptor = FetchDescriptor<Company>(
                                    predicate: #Predicate<Company> { $0.id == companyId }
                                )
                                if let existingCompanies = try? modelContext.fetch(descriptor),
                                   let existing = existingCompanies.first {
                                    // Copy properties to existing object instead of inserting new
                                    existing.name = companyObject.name
                                    existing.address = companyObject.address
                                    existing.phone = companyObject.phone
                                    existing.email = companyObject.email
                                    existing.website = companyObject.website
                                    existing.companyDescription = companyObject.companyDescription
                                    existing.industryString = companyObject.industryString
                                    existing.companySize = companyObject.companySize
                                    existing.companyAge = companyObject.companyAge
                                    existing.projectIdsString = companyObject.projectIdsString
                                    existing.teamIdsString = companyObject.teamIdsString
                                    existing.adminIdsString = companyObject.adminIdsString
                                    existing.lastSyncedAt = Date()
                                    companyObject = existing
                                } else {
                                    // Insert new company
                                    modelContext.insert(companyObject)
                                }
                            } else {
                                // Fallback: create basic company with limited data
                                let companyDataId = companyData.id
                                let descriptor = FetchDescriptor<Company>(
                                    predicate: #Predicate<Company> { $0.id == companyDataId }
                                )
                                let existingCompanies = try? modelContext.fetch(descriptor)
                                
                                if let existing = existingCompanies?.first {
                                    // Update existing company
                                    companyObject = existing
                                } else {
                                    // Create new company
                                    companyObject = Company(id: companyData.id, name: companyData.name)
                                    modelContext.insert(companyObject)
                                }
                                
                                // Update company name
                                companyObject.name = companyData.name
                            }
                            
                            // Save to database
                            try? modelContext.save()
                        }
                    } else {
                        // Use a default company name if we couldn't extract it
                        companyName = "Your Company"
                    }
                    
                    // Store user data in UserDefaults
                    UserDefaults.standard.set(firstName, forKey: "user_first_name")
                    UserDefaults.standard.set(lastName, forKey: "user_last_name")
                    UserDefaults.standard.set(formattedPhone, forKey: "user_phone_number")
                    UserDefaults.standard.set(companyCode, forKey: "company_code")
                    
                    // Log all stored user data for verification
                } else {
                    isCompanyJoined = false
                    if let errMsg = response.error_message, !errMsg.isEmpty {
                        errorMessage = errMsg
                    } else {
                        errorMessage = "Failed to join company. Please check your company code and try again."
                    }
                    print("Company join failed: \(errorMessage)")
                }
            }
            
            return isCompanyJoined
            
        } catch let joinError as SignUpError {
            await MainActor.run {
                isCompanyJoined = false
                
                // Display appropriate error message based on error type
                switch joinError {
                case .serverError(let message):
                    // This will display the "message" field from 400 errors
                    errorMessage = message
                    print("Server error during company join: \(message)")
                case .companyJoinFailed:
                    errorMessage = "Failed to join company. Please check your company code."
                    print("Company join failed error")
                default:
                    errorMessage = joinError.localizedDescription
                    print("Company join error: \(joinError)")
                }
            }
            return false
        } catch {
            await MainActor.run {
                isCompanyJoined = false
                errorMessage = "Network error: \(error.localizedDescription)"
                print("Network error during company join: \(error)")
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
            print("🔵 OnboardingViewModel: Loaded user type from 'selected_user_type': \(userType.rawValue)")
            return userType
        }
        
        // Check the alternate user_type key
        if let savedType = UserDefaults.standard.string(forKey: "user_type"),
           let userType = UserType(rawValue: savedType) {
            print("🔵 OnboardingViewModel: Loaded user type from 'user_type': \(userType.rawValue)")
            return userType
        }
        
        // Check the raw API response
        if let rawType = UserDefaults.standard.string(forKey: "user_type_raw") {
            print("🟡 OnboardingViewModel: Found raw user type: \(rawType)")
            if rawType.lowercased() == "company" {
                print("🟢 OnboardingViewModel: Loaded user type as company from raw value")
                return .company
            } else if rawType.lowercased() == "employee" {
                print("🟢 OnboardingViewModel: Loaded user type as employee from raw value")
                return .employee
            }
        }
        
        print("⚠️ OnboardingViewModel: No stored user type found")
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
        print("🔵 moveToNextStep called from step: \(currentStep)")
        print("🔵 selectedUserType: \(selectedUserType?.rawValue ?? "nil")")
        
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
            // Continue to account setup
            DispatchQueue.main.async {
                self.currentStep = .accountSetup
            }
            return
        }
        
        // Skip account setup if already authenticated
        if currentStep == .accountSetup && isSignedUp && isAuthenticated {
            // Move to the appropriate next step based on user type
            let nextStep = selectedUserType == .employee ? OnboardingStep.organizationJoin : OnboardingStep.userDetails
            DispatchQueue.main.async {
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
            print("🔵 Next step determined: \(nextStep)")
            print("🔵 Current step: \(currentStep), User type: \(selectedUserType?.rawValue ?? "nil")")
            
            // Special check: if the next step is company code but user already has a company, skip to permissions
            // Only apply this logic for employees, not company owners
            if nextStep == .companyCode && selectedUserType == .employee && isCompanyJoined {
                print("🔵 Skipping company code for employee with company")
                nextStep = .permissions
            }
            
            // Save the step to UserDefaults for potential resume later
            UserDefaults.standard.set(nextStep.rawValue, forKey: "last_onboarding_step_v2")
            
            print("🔵 Moving to step: \(nextStep)")
            DispatchQueue.main.async {
                self.currentStep = nextStep
            }
        } else {
            print("⚠️ No next step available from \(currentStep) for user type \(selectedUserType?.rawValue ?? "nil")")
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
            // Format phone number for API
            let formattedPhone = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            
            // Get existing company ID if available
            let existingCompanyId = UserDefaults.standard.string(forKey: "company_id")
            
            // DEBUG: Log what userId we're sending
            print("\n🔍 OnboardingViewModel - updateCompany:")
            print("  - userId from instance variable: '\(userId)'")
            print("  - userId is empty: \(userId.isEmpty)")
            print("  - firstName: \(firstName)")
            print("  - lastName: \(lastName)")
            print("  - existingCompanyId: \(existingCompanyId ?? "nil")")
            
            let response = try await onboardingService.updateCompany(
                companyId: existingCompanyId,
                name: companyName,
                email: companyEmail,
                phone: companyPhone,
                industry: industry.rawValue,
                size: size.rawValue,
                age: age.rawValue,
                address: companyAddress,
                userId: userId,
                firstName: firstName,
                lastName: lastName,
                userPhone: formattedPhone
            )
            
            await MainActor.run {
                isLoading = false
                // Store company data
                UserDefaults.standard.set(companyName, forKey: "Company Name")
                UserDefaults.standard.set(true, forKey: "company_created")
                
                // Store company ID and code if available
                if let company = response.extractedCompany {
                    
                    // Store company ID first
                    if let companyId = company.extractedId, !companyId.isEmpty {
                        UserDefaults.standard.set(companyId, forKey: "company_id")
                        
                        // Create or update Company object in SwiftData
                        if let modelContext = dataController?.modelContext {
                            // Check if company already exists
                            let descriptor = FetchDescriptor<Company>(
                                predicate: #Predicate<Company> { $0.id == companyId }
                            )
                            let existingCompanies = try? modelContext.fetch(descriptor)
                            
                            var companyObject: Company
                            if let existing = existingCompanies?.first {
                                // Update existing company
                                companyObject = existing
                            } else {
                                // Create new company
                                companyObject = Company(id: companyId, name: companyName)
                                modelContext.insert(companyObject)
                            }
                            
                            // Update company properties from response
                            companyObject.name = company.extractedName ?? companyName
                            companyObject.email = company.officeEmail ?? company.email ?? companyEmail
                            companyObject.phone = company.phone ?? companyPhone
                            companyObject.address = companyAddress
                            companyObject.companySize = company.companySize ?? company.size ?? companySize?.rawValue
                            companyObject.companyAge = company.companyAge ?? company.age ?? companyAge?.rawValue
                            
                            // Set industries
                            if let industries = company.industry {
                                companyObject.setIndustries(industries)
                            } else if let industry = companyIndustry {
                                companyObject.setIndustries([industry.rawValue])
                            }
                            
                            // Save to database
                            try? modelContext.save()
                        }
                    }
                    
                    // Store company code - prefer the actual code field if available
                    if let companyCode = company.extractedCode, !companyCode.isEmpty {
                        self.companyCode = companyCode
                        UserDefaults.standard.set(companyCode, forKey: "company_code")
                    } else if let companyId = company.extractedId, !companyId.isEmpty {
                        // Fallback: Use company ID as the code if no specific code field
                        self.companyCode = companyId
                        UserDefaults.standard.set(companyId, forKey: "company_code")
                    }
                } else {
                    print("ERROR: No company object in update_company response")
                    print("ERROR: Unable to store company code - response.extractedCompany is nil")
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
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
    
    func completeOnboarding() {
        // Mark onboarding as completed
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        UserDefaults.standard.set(false, forKey: "resume_onboarding")
        
        // Store final user type
        if let userType = selectedUserType {
            UserDefaults.standard.set(userType.rawValue, forKey: "user_type")
        }
        
        // Set authentication flag to enter the app
        UserDefaults.standard.set(true, forKey: "is_authenticated")
        
        
        // Update the server with onboarding completion status
        if let userId = UserDefaults.standard.string(forKey: "user_id"),
           let dataController = dataController {
            Task {
                do {
                    let updateData = ["hasCompletedAppOnboarding": true]
                    try await dataController.apiService.updateUser(id: userId, userData: updateData)
                    
                    // Update the local user model
                    await MainActor.run {
                        if let user = dataController.currentUser {
                            user.hasCompletedAppOnboarding = true
                        }
                    }
                } catch {
                    print("Failed to update server with onboarding status: \(error)")
                    // Continue anyway - we don't want to block the user
                }
            }
        }
        
        // Update DataController if available
        if let dataController = dataController {
            DispatchQueue.main.async {
                dataController.isAuthenticated = true
            }
        }
        
        // Dismiss the onboarding overlay
        NotificationCenter.default.post(name: Notification.Name("DismissOnboarding"), object: nil)
    }
    
    func logoutAndReturnToLogin() {
        
        // Clear all user data and reset onboarding state
        clearUserData()
        
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
