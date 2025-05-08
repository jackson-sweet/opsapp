//
//  OnboardingViewModelV2.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import Foundation
import SwiftUI
import Combine
import SwiftData

/// View model for the consolidated onboarding flow
class OnboardingViewModel: ObservableObject {
    // Reference to DataController for database operations
    var dataController: DataController?
    
    // Current step in the onboarding process
    @Published var currentStepV2: OnboardingStepV2 = .welcome
    
    // User input data
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var phoneNumber: String = ""
    @Published var companyCode: String = ""
    
    // State management
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLocationPermissionGranted: Bool = false
    @Published var isNotificationsPermissionGranted: Bool = false
    
    // API response data
    @Published var isSignedUp: Bool = false
    @Published var isCompanyJoined: Bool = false
    @Published var companyName: String = ""
    @Published var userId: String = "" // Track user ID from sign-up response
    
    // Validation states
    @Published var isEmailValid: Bool = false
    @Published var isPasswordValid: Bool = false
    @Published var isPasswordMatching: Bool = false
    @Published var isPhoneValid: Bool = false
    
    // Services
    private let onboardingService = OnboardingService()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupValidations()
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
    }
    
    // MARK: - Navigation
    
    // Move to the next step in the flow
    func moveToNextStepV2() {
        print("OnboardingViewModel: Moving from V2 step: \(currentStepV2.title) (raw: \(currentStepV2.rawValue))")
        
        if let nextStep = currentStepV2.nextStep() {
            print("OnboardingViewModel: Found next V2 step: \(nextStep.title) (raw: \(nextStep.rawValue))")
            
            DispatchQueue.main.async {
                self.currentStepV2 = nextStep
                print("OnboardingViewModel: ✅ UPDATED currentStepV2 to: \(self.currentStepV2.title) (raw: \(self.currentStepV2.rawValue))")
            }
        } else {
            print("OnboardingViewModel: ❌ No next V2 step available after: \(currentStepV2.title)")
        }
    }
    
    // Move to a specific step
    func moveToV2(step: OnboardingStepV2) {
        print("OnboardingViewModel: Directly moving from \(currentStepV2.title) to \(step.title)")
        
        DispatchQueue.main.async {
            self.currentStepV2 = step
            print("OnboardingViewModel: ✅ DIRECTLY UPDATED currentStepV2 to: \(self.currentStepV2.title) (raw: \(self.currentStepV2.rawValue))")
        }
    }
    
    // Move back one step
    func moveToPreviousStepV2() {
        print("OnboardingViewModel: Moving back from V2 step: \(currentStepV2.title) (raw: \(currentStepV2.rawValue))")
        
        // Special case: if we're at the company code step and we loaded directly into it
        // because the user needs to complete it, don't allow going back
        if currentStepV2 == .companyCode && UserDefaults.standard.bool(forKey: "user_id") != nil {
            print("OnboardingViewModel: ❌ Cannot go back from company code step when resuming incomplete signup")
            
            // Set error message to explain why
            errorMessage = "You must complete company registration to continue. Please enter your company code."
            return
        }
        
        if let prevStep = currentStepV2.previousStep() {
            print("OnboardingViewModel: Found previous V2 step: \(prevStep.title) (raw: \(prevStep.rawValue))")
            
            DispatchQueue.main.async {
                self.currentStepV2 = prevStep
                print("OnboardingViewModel: ✅ UPDATED currentStepV2 to previous: \(self.currentStepV2.title) (raw: \(self.currentStepV2.rawValue))")
            }
        } else {
            print("OnboardingViewModel: ❌ No previous V2 step available before: \(currentStepV2.title)")
        }
    }
    
    // MARK: - Data Operations
    
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
                password: password
            )
            
            // Store data and update state
            await MainActor.run {
                // We got a successful HTTP response, now check if the API considers it successful
                if response.wasSuccessful {
                    isSignedUp = true
                    
                    // Extract and save user ID from the response, using our helper method
                    if let userIdValue = response.extractedUserId, !userIdValue.isEmpty {
                        userId = userIdValue
                        UserDefaults.standard.set(userIdValue, forKey: "user_id")
                        
                        // Print detailed success information for debugging
                        print("API Response - Sign Up: SUCCESS")
                        print("Email: \(email) successfully registered")
                        print("User ID: \(userIdValue) saved")
                    } else {
                        print("WARNING: No user_id found in successful signup response")
                        // We need to proceed even without a user_id since the API said success
                        
                        // Attempt to set a placeholder user ID so the flow can continue
                        let placeholderId = "\(Date().timeIntervalSince1970)"
                        print("Creating placeholder user_id for flow: \(placeholderId)")
                        userId = placeholderId
                        UserDefaults.standard.set(placeholderId, forKey: "user_id")
                    }
                    
                    // Store email in UserDefaults for later
                    UserDefaults.standard.set(email, forKey: "user_email")
                    UserDefaults.standard.set(password, forKey: "user_password")
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
            errorMessage = "First name is required"
            return false
        }
        
        guard !lastName.isEmpty else {
            errorMessage = "Last name is required"
            return false
        }
        
        guard isPhoneValid else {
            errorMessage = "A valid phone number is required"
            return false
        }
        
        guard !companyCode.isEmpty else {
            errorMessage = "Company code is required"
            return false
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
    
    // MARK: - Permissions
    
    // Request notifications permission
    func requestNotificationsPermission() {
        // This would integrate with your actual notification manager
        // For now, we'll simulate granting permission
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isNotificationsPermissionGranted = true
        }
    }
    
    // MARK: - Validation Helpers
    
    // Check if user can proceed from account setup screen (combined email/password)
    var canProceedFromAccountSetup: Bool {
        return isEmailValid && isPasswordValid && isPasswordMatching
    }
    
    // Check if user can proceed from user details screen
    var canProceedFromUserDetails: Bool {
        return !firstName.isEmpty && !lastName.isEmpty && isPhoneValid
    }
}