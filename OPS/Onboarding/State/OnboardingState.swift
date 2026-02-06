//
//  OnboardingState.swift
//  OPS
//
//  New onboarding state model for the simplified flow.
//  Part of the v3 onboarding system.
//

import Foundation

// MARK: - Screen Enum

/// Screens in the new onboarding flow
enum OnboardingScreen: String, Codable, CaseIterable {
    case welcome           // Hero screen with LOG IN / GET STARTED
    case login             // Full page login
    case signup            // CREATE / JOIN company selection
    case userTypeSelection // For returning users without userType
    case credentials       // Email/password signup
    case profile           // Personal profile (name, phone, avatar)
    case companySetup      // Company basics (name, logo, email, phone)
    case companyDetails    // Company details (industry, size, age)
    case companyCode       // Company code display after creation
    case codeEntry         // Employee: Enter crew code to join
    case profileCompany    // Legacy: Profile + create company (deprecated)
    case profileJoin       // Legacy: Profile + join company with code (deprecated)
    case ready             // Welcome guide / billing
    case tutorial          // Interactive tutorial for new users
    case preSignupTutorial // Tutorial shown before account creation
    case postTutorialCTA   // CTA screen after pre-signup tutorial

    /// Display title for debugging
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .login: return "Login"
        case .signup: return "Sign Up"
        case .userTypeSelection: return "User Type Selection"
        case .credentials: return "Credentials"
        case .profile: return "Profile"
        case .companySetup: return "Company Setup"
        case .companyDetails: return "Company Details"
        case .companyCode: return "Company Code"
        case .codeEntry: return "Code Entry"
        case .profileCompany: return "Profile & Company"
        case .profileJoin: return "Profile & Join"
        case .ready: return "Ready"
        case .tutorial: return "Tutorial"
        case .preSignupTutorial: return "Pre-Signup Tutorial"
        case .postTutorialCTA: return "Post-Tutorial CTA"
        }
    }
}

// MARK: - Flow Enum

/// The two main onboarding flows
enum OnboardingFlow: String, Codable {
    case companyCreator  // User creating a new company
    case employee        // User joining an existing company

    /// Corresponding UserType value
    var userType: UserType {
        switch self {
        case .companyCreator: return .company
        case .employee: return .employee
        }
    }

    /// Create from UserType
    init?(from userType: UserType?) {
        guard let userType = userType else { return nil }
        switch userType {
        case .company: self = .companyCreator
        case .employee: self = .employee
        }
    }
}

// MARK: - User Data

/// User data collected during onboarding
struct OnboardingUserData: Codable, Equatable {
    var email: String = ""
    var firstName: String = ""
    var lastName: String = ""
    var phone: String = ""
    var avatarURL: String?
    var avatarData: Data?
    var userId: String?

    /// Check if profile is complete (required fields filled)
    var hasRequiredProfileFields: Bool {
        !firstName.isEmpty && !lastName.isEmpty && !phone.isEmpty
    }

    /// Check if user has a name
    var hasName: Bool {
        !firstName.isEmpty || !lastName.isEmpty
    }
}

// MARK: - Company Data

/// Company data collected during onboarding
struct OnboardingCompanyData: Codable, Equatable {
    var name: String = ""
    var industry: String = ""
    var size: String = ""
    var age: String = ""
    var address: String = ""
    var logoURL: String?
    var logoData: Data?
    var companyId: String?
    var companyCode: String?
    var phone: String = ""
    var email: String = ""

    /// Check if company profile is complete (required fields for company creator)
    var hasRequiredCompanyFields: Bool {
        !name.isEmpty && !industry.isEmpty && !size.isEmpty && !age.isEmpty
    }
}

// MARK: - Phase Tracking

/// Phases within ProfileCompany screen
enum ProfileCompanyPhase: String, Codable {
    case form       // Collecting data
    case processing // API call in progress
    case success    // Company created, showing code
}

/// Phases within ProfileJoin screen
enum ProfileJoinPhase: String, Codable {
    case form       // Collecting data
    case joining    // API call in progress
}

/// Phases within Credentials screen
enum CredentialsPhase: String, Codable {
    case input       // Entering email/password or selecting social
    case verification // Email verification (if required)
}

// MARK: - Main State Model

/// Complete onboarding state for persistence and tracking
struct OnboardingState: Codable, Equatable {
    var currentScreen: OnboardingScreen
    var flow: OnboardingFlow?
    var userData: OnboardingUserData
    var companyData: OnboardingCompanyData

    // Phase tracking for multi-phase screens
    var credentialsPhase: CredentialsPhase = .input
    var profileCompanyPhase: ProfileCompanyPhase = .form
    var profileJoinPhase: ProfileJoinPhase = .form

    // Flags
    var isAuthenticated: Bool = false
    var hasExistingCompany: Bool = false
    var hasCompletedPreSignupTutorial: Bool = false

    /// Create default initial state
    static var initial: OnboardingState {
        OnboardingState(
            currentScreen: .welcome,
            flow: nil,
            userData: OnboardingUserData(),
            companyData: OnboardingCompanyData()
        )
    }

    /// Reset state while keeping user authentication
    mutating func resetForNewFlow() {
        flow = nil
        companyData = OnboardingCompanyData()
        profileCompanyPhase = .form
        profileJoinPhase = .form
        credentialsPhase = .input
        hasExistingCompany = false
    }
}

// MARK: - UserDefaults Keys

enum OnboardingStorageKeys {
    static let stateV3 = "onboarding_state_v3"
    static let completed = "onboarding_completed"
    static let preSignupTutorialCompleted = "pre_signup_tutorial_completed"

    // Legacy keys (for cleanup)
    static let stateV2 = "onboarding_state_v2"
    static let lastStepV2 = "last_onboarding_step_v2"
    static let resumeOnboarding = "resume_onboarding"
}

// MARK: - State Persistence Extension

extension OnboardingState {

    /// Save state to UserDefaults
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: OnboardingStorageKeys.stateV3)
            print("[ONBOARDING_STATE] State saved to UserDefaults")
        } catch {
            print("[ONBOARDING_STATE] Failed to save state: \(error)")
        }
    }

    /// Load state from UserDefaults
    static func load() -> OnboardingState? {
        guard let data = UserDefaults.standard.data(forKey: OnboardingStorageKeys.stateV3) else {
            print("[ONBOARDING_STATE] No saved state found")
            return nil
        }

        do {
            let state = try JSONDecoder().decode(OnboardingState.self, from: data)
            print("[ONBOARDING_STATE] State loaded from UserDefaults")
            return state
        } catch {
            print("[ONBOARDING_STATE] Failed to load state: \(error)")
            return nil
        }
    }

    /// Clear saved state
    static func clear() {
        UserDefaults.standard.removeObject(forKey: OnboardingStorageKeys.stateV3)
        print("[ONBOARDING_STATE] State cleared from UserDefaults")
    }

    /// Mark onboarding as completed
    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: OnboardingStorageKeys.completed)
        clear() // Also clear the state
        print("[ONBOARDING_STATE] Onboarding marked as completed")
    }

    /// Check if onboarding is completed (quick check)
    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: OnboardingStorageKeys.completed)
    }
}
