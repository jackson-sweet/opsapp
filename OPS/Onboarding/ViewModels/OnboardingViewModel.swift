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
        }
    }
    
    // Current step in the onboarding process
    @Published var currentStep: OnboardingStep = .welcome
    
    // User input data
    @Published var selectedUserType: UserType? = nil {
        didSet {
            if let userType = selectedUserType {
                UserDefaults.standard.set(userType.rawValue, forKey: "selected_user_type")
                print("OnboardingViewModel: Saved user type: \(userType.rawValue)")
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
        return selectedUserType == .employee
    }
    
    init() {
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
            }
            
            // Load the saved user type if available
            if let userTypeRaw = UserDefaults.standard.string(forKey: "selected_user_type"),
               let userType = UserType(rawValue: userTypeRaw) {
                self.selectedUserType = userType
                print("OnboardingViewModel: Loaded saved user type: \(userType.rawValue)")
            } else if let userTypeRaw = UserDefaults.standard.string(forKey: "user_type") {
                // Try to load from the alternate key used after onboarding completion
                if let userType = UserType(rawValue: userTypeRaw) {
                    self.selectedUserType = userType
                    print("OnboardingViewModel: Loaded user type from user_type key: \(userType.rawValue)")
                }
            }
            
            // If we still don't have a user type but have company info, infer it
            if selectedUserType == nil && isCompanyJoined {
                // Default to employee if they're joining an existing company
                self.selectedUserType = .employee
                print("OnboardingViewModel: Inferred user type as employee based on company join")
            }
            
            // Load the last saved step if available
            let lastStepRaw = UserDefaults.standard.integer(forKey: "last_onboarding_step_v2")
            if lastStepRaw > 0, let savedStep = OnboardingStep(rawValue: lastStepRaw) {
                self.currentStep = savedStep
                print("OnboardingViewModel: Resuming at saved step: \(savedStep.title)")
            }
            
            print("OnboardingViewModel: Initialized with existing data - User ID: \(userId), Email: \(email), Authenticated: \(isAuthenticated)")
        } else if !isAuthenticated {
            // Only clear data if this is truly a new signup (not authenticated at all)
            print("OnboardingViewModel: Starting fresh onboarding flow - no authentication found")
            clearUserData()
        } else {
            // Authenticated user with completed onboarding shouldn't be here
            print("OnboardingViewModel: WARNING - Authenticated user with completed onboarding in onboarding flow")
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
        }
        
        // Clear data from UserDefaults (only onboarding-specific fields)
        UserDefaults.standard.removeObject(forKey: "user_email")
        UserDefaults.standard.removeObject(forKey: "user_password")
        UserDefaults.standard.removeObject(forKey: "user_first_name")
        UserDefaults.standard.removeObject(forKey: "user_last_name")
        UserDefaults.standard.removeObject(forKey: "user_phone_number")
        UserDefaults.standard.removeObject(forKey: "company_code")
        
        print("OnboardingViewModel: Cleared all user data for new onboarding flow")
    }
    
    // Populate data from an existing user
    func populateFromUser(_ user: User) {
        print("OnboardingViewModel: Populating data from existing user")
        
        // Set user type based on role
        if user.role == .fieldCrew || user.role == .officeCrew {
            self.selectedUserType = .employee
            print("OnboardingViewModel: Set user type to employee based on role: \(user.role.displayName)")
        } else if user.role == .admin {
            // Admin might be company owner, but check if they have a company
            if let companyId = user.companyId, !companyId.isEmpty {
                // If admin has a company, they might be an employee admin
                self.selectedUserType = .employee
            } else {
                self.selectedUserType = .company
            }
            print("OnboardingViewModel: Set user type based on admin role")
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
        }
        
        // Mark as signed up
        self.isSignedUp = true
        self.userId = user.id
        UserDefaults.standard.set(user.id, forKey: "user_id")
        
        print("OnboardingViewModel: Data populated - Name: \(firstName) \(lastName), Company: \(isCompanyJoined), Type: \(selectedUserType?.rawValue ?? "none")")
    }
    
    // Check and skip to the appropriate step based on existing data
    private func checkAndSkipToAppropriateStep() {
        print("OnboardingViewModel: Checking what step to skip to based on existing data")
        
        // If we're at welcome and have data, determine the right step
        if currentStep == .welcome {
            // Check what data we have to determine where to skip
            if selectedUserType == nil {
                // No user type - start from user type selection
                print("OnboardingViewModel: No user type set, will start from user type selection")
                return
            }
            
            if !isSignedUp || userId.isEmpty {
                // User type known but not signed up - skip to account setup
                DispatchQueue.main.async {
                    self.currentStep = .accountSetup
                    print("OnboardingViewModel: Skipping to account setup (user type known but not signed up)")
                }
                return
            }
            
            if firstName.isEmpty || lastName.isEmpty || phoneNumber.isEmpty {
                // Signed up but missing personal info - skip to user details
                DispatchQueue.main.async {
                    self.currentStep = .userDetails
                    print("OnboardingViewModel: Skipping to user details (missing personal info)")
                }
                return
            }
            
            if selectedUserType == .employee && !isCompanyJoined {
                // Employee without company - skip to company code
                DispatchQueue.main.async {
                    self.currentStep = .companyCode
                    print("OnboardingViewModel: Skipping to company code (employee without company)")
                }
                return
            }
            
            if selectedUserType == .company && !isCompanyJoined {
                // Company owner without company setup - skip to company basic info
                DispatchQueue.main.async {
                    self.currentStep = .companyBasicInfo
                    print("OnboardingViewModel: Skipping to company basic info (company owner without company)")
                }
                return
            }
            
            // If everything is complete, skip to permissions
            if isCompanyJoined {
                DispatchQueue.main.async {
                    self.currentStep = .permissions
                    print("OnboardingViewModel: Skipping to permissions (all data complete)")
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
        print("OnboardingViewModel: Initial location permission status: \(locationStatus.rawValue), granted: \(isGranted)")
        
        // Check notification permission
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isNotificationsPermissionGranted = (settings.authorizationStatus == .authorized)
                print("OnboardingViewModel: Initial notification permission granted: \(self?.isNotificationsPermissionGranted ?? false)")
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
    
    // Move to the next step in the onboarding flow
    func moveToNextStep() {
        moveToNextStepV2()
    }
    
    // Move to a specific step
    func moveTo(step: OnboardingStep) {
        moveToV2(step: step)
    }
    
    // Move back one step
    func moveToPreviousStep() {
        moveToPreviousStepV2()
    }
    
    // Format and validate phone number
    func formatPhoneNumber() {
        // Format phone number (remove any non-digits)
        let digitsOnly = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        phoneNumber = digitsOnly
        
        // Store phone number in UserDefaults for later use
        if isPhoneValid {
            UserDefaults.standard.set(phoneNumber, forKey: "user_phone_number")
            print("OnboardingViewModel: Stored phone number in UserDefaults")
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
        print("OnboardingViewModel: Submitting initial sign-up for email: \(email)")
        
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
                        print("API Response - Sign Up: SUCCESS")
                        print("Email: \(email) successfully registered")
                        print("User ID: \(userIdValue) saved")
                        
                        // Store email and password in UserDefaults for later (crucial for API calls)
                        UserDefaults.standard.set(email, forKey: "user_email")
                        UserDefaults.standard.set(password, forKey: "user_password")
                        
                        // Log that we've saved these important credentials
                        print("OnboardingViewModel: Saved email and password to UserDefaults for future API calls")
                        
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
                print("OnboardingViewModel: Found password in UserDefaults, using that for company join")
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
        
        print("OnboardingViewModel: Submitting company join - Email: \(email), User ID: \(userId), Company Code: \(companyCode)")
        
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
                    print("API Response - Join Company: SUCCESS")
                    print("User: \(firstName) \(lastName) successfully joined company")
                    
                    // Extract company data from wherever it might be in the response
                    if let companyData = response.extractedCompanyData {
                        companyName = companyData.name
                        print("Company joined: \(companyData.name) (ID: \(companyData.id))")
                        
                        // Store company data in UserDefaults
                        UserDefaults.standard.set(companyData.name, forKey: "Company Name")
                        UserDefaults.standard.set(companyData.id, forKey: "company_id")
                    } else {
                        // Use a default company name if we couldn't extract it
                        companyName = "Your Company"
                        print("Company data not found in response, using default name")
                    }
                    
                    // Store user data in UserDefaults
                    UserDefaults.standard.set(firstName, forKey: "user_first_name")
                    UserDefaults.standard.set(lastName, forKey: "user_last_name")
                    UserDefaults.standard.set(formattedPhone, forKey: "user_phone_number")
                    UserDefaults.standard.set(companyCode, forKey: "company_code")
                    
                    // Log all stored user data for verification
                    print("User data stored in UserDefaults:")
                    print("- Email: \(email)")
                    print("- Name: \(firstName) \(lastName)")
                    print("- Phone: \(formattedPhone)")
                    print("- Company: \(companyName)")
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
        moveToNextStepV2()
    }
    
    // Request location permission
    func requestLocationPermission(completion: ((Bool) -> Void)? = nil) {
        print("OnboardingViewModel: Requesting location permission")
        
        // Check current status first
        let currentStatus = locationManager.authorizationStatus
        print("OnboardingViewModel: Current location status: \(currentStatus.rawValue)")
        
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
                    print("OnboardingViewModel: Location permission updated - status: \(status.rawValue), granted: \(self?.isLocationPermissionGranted ?? false)")
                    
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
    
    // MARK: - Navigation Methods
    
    // Request notifications permission
    func requestNotificationsPermission() {
        // Use the real NotificationManager to request permissions
        NotificationManager.shared.requestPermission { granted in
            DispatchQueue.main.async {
                self.isNotificationsPermissionGranted = granted
                print("OnboardingViewModel: Notifications permission \(granted ? "granted" : "denied")")
                
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
    func moveToNextStepV2() {
        print("OnboardingViewModel: Moving from step: \(currentStep.title) (raw: \(currentStep.rawValue))")
        
        // Special handling for resuming onboarding or existing users
        let isAuthenticated = UserDefaults.standard.bool(forKey: "is_authenticated")
        
        // Check if we can skip certain steps based on existing data
        if currentStep == .welcome {
            // When starting, check if we can skip directly to a later step based on what's already done
            
            // If user type is already known, skip user type selection
            if selectedUserType != nil {
                print("OnboardingViewModel: User type already known: \(selectedUserType!.rawValue), skipping type selection")
                
                // If user is already signed up, skip account setup too
                if isSignedUp && !userId.isEmpty {
                    print("OnboardingViewModel: User already signed up, checking what to skip to")
                    
                    // If user already has personal info, skip to the appropriate step
                    if !firstName.isEmpty && !lastName.isEmpty && !phoneNumber.isEmpty {
                        print("OnboardingViewModel: User info already complete")
                        
                        // For employees, go to company code if not joined
                        if selectedUserType == .employee && !isCompanyJoined {
                            let skipToStep = OnboardingStep.companyCode
                            DispatchQueue.main.async {
                                self.currentStep = skipToStep
                                print("OnboardingViewModel: ✅ SKIPPED to: \(self.currentStep.title)")
                            }
                            return
                        }
                        
                        // If company is joined, go to permissions
                        if isCompanyJoined {
                            let skipToStep = OnboardingStep.permissions
                            DispatchQueue.main.async {
                                self.currentStep = skipToStep
                                print("OnboardingViewModel: ✅ SKIPPED to: \(self.currentStep.title)")
                            }
                            return
                        }
                    } else {
                        // Skip to user details if account exists but no personal info
                        let skipToStep = OnboardingStep.userDetails
                        DispatchQueue.main.async {
                            self.currentStep = skipToStep
                            print("OnboardingViewModel: ✅ SKIPPED to: \(self.currentStep.title)")
                        }
                        return
                    }
                } else {
                    // Skip to account setup if user type is known but not signed up
                    let skipToStep = OnboardingStep.accountSetup
                    DispatchQueue.main.async {
                        self.currentStep = skipToStep
                        print("OnboardingViewModel: ✅ SKIPPED to: \(self.currentStep.title)")
                    }
                    return
                }
            }
        }
        
        // Skip user type selection if already known
        if currentStep == .userTypeSelection && selectedUserType != nil {
            print("OnboardingViewModel: User type already set, skipping type selection")
            // Continue to account setup
            DispatchQueue.main.async {
                self.currentStep = .accountSetup
                print("OnboardingViewModel: ✅ SKIPPED user type selection")
            }
            return
        }
        
        // Skip account setup if already authenticated
        if currentStep == .accountSetup && isSignedUp && isAuthenticated {
            print("OnboardingViewModel: Already authenticated, skipping account setup")
            // Move to the appropriate next step based on user type
            let nextStep = selectedUserType == .employee ? OnboardingStep.organizationJoin : OnboardingStep.userDetails
            DispatchQueue.main.async {
                self.currentStep = nextStep
                print("OnboardingViewModel: ✅ SKIPPED account setup to: \(self.currentStep.title)")
            }
            return
        }
        
        // Skip user details if already have the information
        if currentStep == .userDetails && !firstName.isEmpty && !lastName.isEmpty && !phoneNumber.isEmpty {
            print("OnboardingViewModel: User details already complete, skipping")
            // Check if company is already joined before deciding next step
            let nextStep: OnboardingStep
            if selectedUserType == .employee {
                if isCompanyJoined {
                    // Skip to permissions if already have a company
                    nextStep = .permissions
                    print("OnboardingViewModel: Employee already has company, skipping to permissions")
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
                print("OnboardingViewModel: ✅ SKIPPED user details to: \(self.currentStep.title)")
            }
            return
        }
        
        // Normal flow - get the next step
        if var nextStep = currentStep.nextStep(userType: selectedUserType) {
            print("OnboardingViewModel: Found next step: \(nextStep.title) (raw: \(nextStep.rawValue))")
            
            // Special check: if the next step is company code but user already has a company, skip to permissions
            if nextStep == .companyCode && selectedUserType == .employee && isCompanyJoined {
                nextStep = .permissions
                print("OnboardingViewModel: Employee already has company, changing next step from companyCode to permissions")
            }
            
            // Save the step to UserDefaults for potential resume later
            UserDefaults.standard.set(nextStep.rawValue, forKey: "last_onboarding_step_v2")
            
            DispatchQueue.main.async {
                self.currentStep = nextStep
                print("OnboardingViewModel: ✅ UPDATED currentStep to: \(self.currentStep.title) (raw: \(self.currentStep.rawValue))")
            }
        } else {
            print("OnboardingViewModel: ❌ No next step available after: \(currentStep.title)")
        }
    }
    
    // Move to a specific step
    func moveToV2(step: OnboardingStep) {
        print("OnboardingViewModel: Directly moving from \(currentStep.title) to \(step.title)")
        
        // Save the step to UserDefaults for potential resume later
        UserDefaults.standard.set(step.rawValue, forKey: "last_onboarding_step_v2")
        
        DispatchQueue.main.async {
            self.currentStep = step
            print("OnboardingViewModel: ✅ DIRECTLY UPDATED currentStep to: \(self.currentStep.title) (raw: \(self.currentStep.rawValue))")
        }
    }
    
    // Move back one step
    func moveToPreviousStepV2() {
        print("OnboardingViewModel: Moving back from step: \(currentStep.title) (raw: \(currentStep.rawValue))")
        
        // Special case: if we're at the company code step and we loaded directly into it
        // because the user needs to complete it, don't allow going back
        if currentStep == .companyCode && UserDefaults.standard.string(forKey: "user_id") != nil {
            print("OnboardingViewModel: ❌ Cannot go back from company code step when resuming incomplete signup")
            
            // Set error message to explain why
            DispatchQueue.main.async {
                self.errorMessage = "You must complete company registration to continue. Please enter your company code."
            }
            return
        }
        
        if var prevStep = currentStep.previousStep(userType: selectedUserType) {
            print("OnboardingViewModel: Found previous step: \(prevStep.title) (raw: \(prevStep.rawValue))")
            
            // Special handling: if going back to company code but user already has a company, skip it
            if prevStep == .companyCode && selectedUserType == .employee && isCompanyJoined {
                print("OnboardingViewModel: Employee already has company, skipping company code when going back")
                // Go back one more step to user details
                if let skipStep = prevStep.previousStep(userType: selectedUserType) {
                    prevStep = skipStep
                    print("OnboardingViewModel: Changed previous step to: \(prevStep.title)")
                }
            }
            
            // Save the step to UserDefaults for potential resume later
            UserDefaults.standard.set(prevStep.rawValue, forKey: "last_onboarding_step_v2")
            
            DispatchQueue.main.async {
                self.currentStep = prevStep
                print("OnboardingViewModel: ✅ UPDATED currentStep to previous: \(self.currentStep.title) (raw: \(self.currentStep.rawValue))")
            }
        } else {
            print("OnboardingViewModel: ❌ No previous step available before: \(currentStep.title)")
        }
    }
    
    // MARK: - New Navigation Methods for Updated Flow
    
    func nextStep() {
        moveToNextStepV2()
    }
    
    func previousStep() {
        moveToPreviousStepV2()
    }
    
    // MARK: - Company Creation Methods
    
    func createCompany() async throws {
        print("=== CREATE COMPANY DEBUG ===")
        print("userId: '\(userId)'")
        print("companyName: '\(companyName)'")
        print("companyEmail: '\(companyEmail)'")
        print("companyPhone: '\(companyPhone)'")
        print("===========================")
        
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
            
            let response = try await onboardingService.updateCompany(
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
                    print("DEBUG: Company object received from API")
                    print("DEBUG: Company _id: \(company._id ?? "nil")")
                    print("DEBUG: Company id: \(company.id ?? "nil")")
                    print("DEBUG: Company extractedId: \(company.extractedId ?? "nil")")
                    print("DEBUG: Company companyId (code): \(company.companyId ?? "nil")")
                    print("DEBUG: Company code: \(company.code ?? "nil")")
                    print("DEBUG: Company extractedCode: \(company.extractedCode ?? "nil")")
                    print("DEBUG: Company name: \(company.extractedName ?? "nil")")
                    
                    // Store company ID first
                    if let companyId = company.extractedId, !companyId.isEmpty {
                        UserDefaults.standard.set(companyId, forKey: "company_id")
                        print("Stored company_id: \(companyId)")
                    }
                    
                    // Store company code - prefer the actual code field if available
                    if let companyCode = company.extractedCode, !companyCode.isEmpty {
                        self.companyCode = companyCode
                        UserDefaults.standard.set(companyCode, forKey: "company_code")
                        print("Company code found and stored: \(companyCode)")
                    } else if let companyId = company.extractedId, !companyId.isEmpty {
                        // Fallback: Use company ID as the code if no specific code field
                        self.companyCode = companyId
                        UserDefaults.standard.set(companyId, forKey: "company_code")
                        print("No company code found, using company ID as code: \(companyId)")
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
        
        print("OnboardingViewModel: Onboarding completed successfully, setting is_authenticated = true")
        
        // Update the server with onboarding completion status
        if let userId = UserDefaults.standard.string(forKey: "user_id"),
           let dataController = dataController {
            Task {
                do {
                    let updateData = ["hasCompletedAppOnboarding": true]
                    try await dataController.apiService.updateUser(id: userId, userData: updateData)
                    print("Successfully updated server with onboarding completion status")
                    
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
        print("OnboardingViewModel: User requested logout, clearing all data")
        
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
        
        print("OnboardingViewModel: All data cleared, returning to login")
        
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
