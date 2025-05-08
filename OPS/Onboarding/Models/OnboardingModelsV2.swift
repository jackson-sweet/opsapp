//
//  OnboardingModelsV2.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import Foundation

// API Response Models

/// Response from sign_user_up endpoint
struct SignUpResponse: Codable {
    let success: String? // "yes" or "no"
    let error_message: String?
    let user_id: String? // User ID returned when signup is successful
    let response: ResponseData? // Additional response data that might contain user_id
    
    // On Bubble, we may get 200 status codes with different response formats
    var wasSuccessful: Bool {
        // Check primary success flag
        if let success = success, success.lowercased() == "yes" {
            return true
        }
        
        // Check if we have a direct user_id
        if let userId = user_id, !userId.isEmpty {
            return true
        }
        
        // Check if user_id is in the response data object
        if let responseData = response, let userId = responseData.user_id, !userId.isEmpty {
            return true
        }
        
        return false
    }
    
    // Extract user ID from wherever it might be located
    var extractedUserId: String? {
        // Direct user_id has priority
        if let userId = user_id, !userId.isEmpty {
            return userId
        }
        
        // Check response data object
        if let responseData = response, let userId = responseData.user_id, !userId.isEmpty {
            return userId
        }
        
        return nil
    }
}

/// Additional response data that might be nested in the API response
struct ResponseData: Codable {
    let user_id: String?
}

/// Company object in the join_company response
struct CompanyData: Codable {
    // Make all properties optional to handle flexible API responses
    let id: String?
    let _id: String?
    let name: String?
    let companyID: String?
    
    // Using CodingKeys to map "Company Name" to our name property
    private enum CodingKeys: String, CodingKey {
        case id
        case _id
        case companyID
        case name = "Company Name"
    }
    
    // Add computed properties to handle different field naming conventions
    var companyId: String? {
        return id ?? _id ?? companyID
    }
    
    // Check if we have valid company data
    var isValid: Bool {
        return (companyId != nil && !companyId!.isEmpty)
    }
}

/// Response from join_company endpoint
struct JoinCompanyResponse: Codable {
    let company_joined: String? // "yes" or "no"
    let error_message: String?
    let company: CompanyData?
    let response: JoinCompanyResponseData? // Additional response data that might be nested

    // Root-level company properties for alternate formats
    private let rootCompanyName: String?
    private let id: String?
    private let _id: String?
    private let companyID: String?
    
    // Using CodingKeys to map "Company Name" to our rootCompanyName property
    private enum CodingKeys: String, CodingKey {
        case company_joined
        case error_message
        case company
        case response
        case id
        case _id
        case companyID
        case rootCompanyName = "Company Name"
    }
    
    var wasSuccessful: Bool {
        // Check primary success flag
        if let joined = company_joined, joined.lowercased() == "yes" {
            return true
        }
        
        // Check if we have valid company data in company object
        if let company = company, company.isValid {
            return true
        }
        
        // Check root-level company properties
        if (id != nil && !id!.isEmpty) || (_id != nil && !_id!.isEmpty) || (companyID != nil && !companyID!.isEmpty) {
            return true
        }
        
        // Check response data
        if let responseData = response, responseData.wasSuccessful {
            return true
        }
        
        return false
    }
    
    // Get the effective company data regardless of where it's located in the response
    var extractedCompanyData: (id: String, name: String)? {
        // Get from company object first
        if let company = company, company.isValid {
            let companyId = company.companyId ?? ""
            let companyName = company.name ?? "Your Company"
            
            if !companyId.isEmpty {
                return (companyId, companyName)
            }
        }
        
        // Try root-level properties
        let rootId = id ?? _id ?? companyID
        if let rootId = rootId, !rootId.isEmpty {
            let rootName = rootCompanyName ?? "Your Company"
            return (rootId, rootName)
        }
        
        // Try response data
        if let responseData = response, let companyInfo = responseData.extractedCompanyData {
            return companyInfo
        }
        
        return nil
    }
}

/// Additional response data for company join
struct JoinCompanyResponseData: Codable {
    let company: CompanyData?
    let company_id: String?
    let companyName: String?
    
    // Using CodingKeys to map "Company Name" to our companyName property
    private enum CodingKeys: String, CodingKey {
        case company
        case company_id
        case companyName = "Company Name"
    }
    
    var wasSuccessful: Bool {
        return (company?.isValid ?? false) || (company_id != nil && !company_id!.isEmpty)
    }
    
    var extractedCompanyData: (id: String, name: String)? {
        if let company = company, company.isValid {
            let companyId = company.companyId ?? ""
            let companyName = company.name ?? "Your Company"
            
            if !companyId.isEmpty {
                return (companyId, companyName)
            }
        }
        
        if let companyId = company_id, !companyId.isEmpty {
            let companyName = companyName ?? "Your Company"
            return (companyId, companyName)
        }
        
        return nil
    }
}

// Error Handling

/// Custom errors for sign up process
enum SignUpError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case companyJoinFailed
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .companyJoinFailed:
            return "Could not join company. Please check your company code."
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// Onboarding Flow Definition

/// Consolidated Onboarding Steps (7-step flow)
enum OnboardingStepV2: Int, CaseIterable {
    case welcome = 0
    case accountSetup = 1     // Combined email/password
    case organizationJoin = 2 // Organization join screen
    case userDetails = 3      // Combined personal info
    case companyCode = 4      // Company code verification
    case permissions = 5      // Consolidated permissions
    case fieldSetup = 6       // Sync preferences
    case completion = 7       // Completion
    
    // Display title for the step
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .accountSetup: return "Account Setup"
        case .organizationJoin: return "Organization Connection"
        case .userDetails: return "Your Information"
        case .companyCode: return "Company Connection"
        case .permissions: return "App Permissions"
        case .fieldSetup: return "Field Setup"
        case .completion: return "Complete"
        }
    }
    
    // User-friendly step indicator text
    var stepIndicator: String {
        switch self {
        case .welcome:
            return ""
        case .accountSetup:
            return "Step 1 of 7"
        case .organizationJoin:
            return "Step 2 of 7"
        case .userDetails:
            return "Step 3 of 7"
        case .companyCode:
            return "Step 4 of 7"
        case .permissions:
            return "Step 5 of 7"
        case .fieldSetup:
            return "Step 6 of 7"
        case .completion:
            return "Step 7 of 7"
        }
    }
    
    // Subtitle for each step
    var subtitle: String {
        switch self {
        case .welcome:
            return ""
        case .accountSetup:
            return "Create your account to get started with OPS."
        case .organizationJoin:
            return "Your account has been created successfully. Now let's get you connected."
        case .userDetails:
            return "Tell us who you are so your team can recognize you."
        case .companyCode:
            return "Enter your company code to join your team's projects."
        case .permissions:
            return "These permissions help OPS work better in the field."
        case .fieldSetup:
            return "Prepare OPS for field use where connectivity is limited."
        case .completion:
            return "Your operational control center is ready for the field."
        }
    }
    
    // Get the next step in the flow
    func nextStep() -> OnboardingStepV2? {
        switch self {
        case .welcome:
            return .accountSetup
        case .accountSetup:
            return .organizationJoin
        case .organizationJoin:
            return .userDetails
        case .userDetails:
            return .companyCode
        case .companyCode:
            return .permissions
        case .permissions:
            return .fieldSetup
        case .fieldSetup:
            return .completion
        case .completion:
            return nil
        }
    }
    
    // Get the previous step in the flow
    func previousStep() -> OnboardingStepV2? {
        switch self {
        case .welcome:
            return nil
        case .accountSetup:
            return .welcome
        case .organizationJoin:
            return .accountSetup
        case .userDetails:
            return .organizationJoin
        case .companyCode:
            return .userDetails
        case .permissions:
            return .companyCode
        case .fieldSetup:
            return .permissions
        case .completion:
            return .fieldSetup
        }
    }
}