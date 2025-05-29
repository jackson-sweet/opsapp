//
//  OnboardingModels.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import Foundation

// Models for onboarding process

// Response from sign_company_up and sign_employee_up endpoints
struct SignUpResponse: Codable {
    let success: Bool? // true or false
    let user_id: String? // User ID returned when signup is successful
    let error_message: String?
    let response: ResponseData? // Additional response data that might contain user_id
    
    // Check if signup was successful based on new API format
    var wasSuccessful: Bool {
        // Check new success boolean field first
        if let success = success {
            return success
        }
        
        // Fallback: Check if we have a valid user_id
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

// Additional response data that might be nested in the API response
struct ResponseData: Codable {
    let user_id: String?
}

// Company object in the join_company response
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

// Response from join_company endpoint
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

// Additional response data for company join
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

// Custom errors for sign up process
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

// UserType is defined in DataModels/UserRole.swift

// MARK: - Company Data Models
enum CompanySize: String, CaseIterable, Identifiable, Hashable {
    case oneToTwo = "1-2"
    case threeToFive = "3-5"
    case sixToTen = "6-10"
    case elevenToTwenty = "11-20"
    case twentyPlus = "20+"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .oneToTwo:
            return "1-2 employees"
        case .threeToFive:
            return "3-5 employees"
        case .sixToTen:
            return "6-10 employees"
        case .elevenToTwenty:
            return "11-20 employees"
        case .twentyPlus:
            return "20+ employees"
        }
    }
    
    var value: String {
        return self.rawValue
    }
}

enum CompanyAge: String, CaseIterable, Identifiable, Hashable {
    case lessThanOne = "<1"
    case oneToTwo = "1-2"
    case twoToFive = "2-5"
    case fiveToTen = "5-10"
    case tenPlus = "10+"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .lessThanOne:
            return "Less than 1 year"
        case .oneToTwo:
            return "1-2 years"
        case .twoToFive:
            return "2-5 years"
        case .fiveToTen:
            return "5-10 years"
        case .tenPlus:
            return "10+ years"
        }
    }
    
    var value: String {
        return self.rawValue
    }
}

enum Industry: String, CaseIterable, Identifiable, Hashable {
    case architecture = "Architecture"
    case bricklaying = "Bricklaying"
    case cabinetry = "Cabinetry"
    case carpentry = "Carpentry"
    case ceilingInstallations = "Ceiling Installations"
    case concreteFinishing = "Concrete Finishing"
    case consulting = "Consulting"
    case craneOperation = "Crane Operation"
    case deckConstruction = "Deck Construction"
    case deckSurfacing = "Deck Surfacing"
    case demolition = "Demolition"
    case drywall = "Drywall"
    case electrical = "Electrical"
    case excavation = "Excavation"
    case flooring = "Flooring"
    case glazing = "Glazing"
    case hvac = "HVAC"
    case insulation = "Insulation"
    case landscaping = "Landscaping"
    case masonry = "Masonry"
    case metalFabrication = "Metal Fabrication"
    case millwrighting = "Millwrighting"
    case painting = "Painting"
    case plumbing = "Plumbing"
    case railings = "Railings"
    case rebar = "Rebar"
    case renovations = "Renovations"
    case roofing = "Roofing"
    case scaffolding = "Scaffolding"
    case sheetMetal = "Sheet Metal"
    case siding = "Siding"
    case stonework = "Stonework"
    case surveying = "Surveying"
    case tileSetting = "Tile Setting"
    case vinylDeckMembranes = "Vinyl Deck Membranes"
    case waterproofing = "Waterproofing"
    case welding = "Welding"
    case windows = "Windows"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        return self.rawValue
    }
}

// MARK: - Onboarding Steps

// V2 version of the onboarding steps - consolidated flow
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case userTypeSelection = 1 // New: Employee vs Business Owner
    case accountSetup = 2     // Combined email/password
    case organizationJoin = 3 // For employees only
    case userDetails = 4      // Combined personal info
    case companyCode = 5      // For employees only
    // Business owner steps
    case companyBasicInfo = 6    // Company name + logo
    case companyAddress = 7      // Address + map
    case companyContact = 8      // Email + phone
    case companyDetails = 9      // Industry + size + age
    case teamInvites = 10        // Invite team members
    case permissions = 11        // Consolidated permissions
    case fieldSetup = 12         // New screen
    case completion = 13
    case welcomeGuide = 14       // Multi-page intro for business owners
    
    // Display title for the step
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .userTypeSelection: return "Account Type"
        case .accountSetup: return "Account Setup"
        case .organizationJoin: return "Organization Connection"
        case .userDetails: return "Your Information"
        case .companyCode: return "Company Connection"
        case .companyBasicInfo: return "Company Information"
        case .companyAddress: return "Company Address"
        case .companyContact: return "Company Contact"
        case .companyDetails: return "Company Details"
        case .teamInvites: return "Invite Team"
        case .permissions: return "App Permissions"
        case .fieldSetup: return "Field Setup"
        case .completion: return "Complete"
        case .welcomeGuide: return "Welcome Guide"
        }
    }
    
    // User-friendly step indicator text
    var stepIndicator: String {
        switch self {
        case .welcome:
            return ""
        case .userTypeSelection:
            return ""
        case .accountSetup:
            return "Step 1 of 7"
        case .organizationJoin:
            return "Step 2 of 7"
        case .userDetails:
            return "Step 3 of 7"
        case .companyCode:
            return "Step 4 of 7"
        case .companyBasicInfo:
            return "Step 1 of 6"
        case .companyAddress:
            return "Step 2 of 6"
        case .companyContact:
            return "Step 3 of 6"
        case .companyDetails:
            return "Step 4 of 6"
        case .teamInvites:
            return "Step 5 of 6"
        case .welcomeGuide:
            return "Step 6 of 6"
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
        case .userTypeSelection:
            return "Choose how you'll be using OPS."
        case .accountSetup:
            return "Create your account to get started with OPS."
        case .organizationJoin:
            return "Your account has been created successfully. Now let's get you connected."
        case .userDetails:
            return "Tell us who you are so your team can recognize you."
        case .companyCode:
            return "Your unique company code for employees to join."
        case .companyBasicInfo:
            return "Set up your company profile basics."
        case .companyAddress:
            return "Where is your company located?"
        case .companyContact:
            return "How can customers reach you?"
        case .companyDetails:
            return "Tell us about your business."
        case .teamInvites:
            return "Invite your team to join OPS."
        case .welcomeGuide:
            return "Learn how to get the most out of OPS."
        case .permissions:
            return "These permissions help OPS work better in the field."
        case .fieldSetup:
            return "Prepare OPS for field use where connectivity is limited."
        case .completion:
            return "Your operational control center is ready for the field."
        }
    }
    
    // Get the next step in the flow
    func nextStep(userType: UserType? = nil) -> OnboardingStep? {
        switch self {
        case .welcome:
            return .userTypeSelection
        case .userTypeSelection:
            return .accountSetup
        case .accountSetup:
            // Branch based on user type
            if let userType = userType {
                switch userType {
                case .employee:
                    return .organizationJoin
                case .company:
                    return .userDetails
                }
            }
            return .organizationJoin // Default to employee flow
        case .organizationJoin:
            return .userDetails
        case .userDetails:
            // Branch based on user type
            if let userType = userType {
                switch userType {
                case .employee:
                    return .companyCode
                case .company:
                    return .companyBasicInfo
                }
            }
            return .companyCode // Default to employee flow
        case .companyCode:
            return .permissions
        case .companyBasicInfo:
            return .companyAddress
        case .companyAddress:
            return .companyContact
        case .companyContact:
            return .companyDetails
        case .companyDetails:
            // Show company code page after details for business owners
            return .companyCode
        case .companyCode:
            // For business owners, show team invites after company code
            if let userType = userType, userType == .company {
                return .teamInvites
            }
            // For employees, go to permissions
            return .permissions
        case .teamInvites:
            return .permissions
        case .permissions:
            return .fieldSetup
        case .fieldSetup:
            return .completion
        case .completion:
            return .welcomeGuide
        case .welcomeGuide:
            return nil
        }
    }
    
    // Get the previous step in the flow
    func previousStep(userType: UserType? = nil) -> OnboardingStep? {
        switch self {
        case .welcome:
            return nil
        case .userTypeSelection:
            return .welcome
        case .accountSetup:
            return .userTypeSelection
        case .organizationJoin:
            return .accountSetup
        case .userDetails:
            // Branch based on user type
            if let userType = userType {
                switch userType {
                case .employee:
                    return .organizationJoin
                case .company:
                    return .accountSetup
                }
            }
            return .organizationJoin // Default to employee flow
        case .companyCode:
            // For business owners coming from company details
            if let userType = userType, userType == .company {
                return .companyDetails
            }
            // For employees
            return .userDetails
        case .companyBasicInfo:
            return .userDetails
        case .companyAddress:
            return .companyBasicInfo
        case .companyContact:
            return .companyAddress
        case .companyDetails:
            return .companyContact
        case .teamInvites:
            return .companyCode
        case .permissions:
            // Branch based on user type
            if let userType = userType {
                switch userType {
                case .employee:
                    return .companyCode
                case .company:
                    return .teamInvites
                }
            }
            return .companyCode // Default to employee flow
        case .fieldSetup:
            return .permissions
        case .completion:
            return .fieldSetup
        case .welcomeGuide:
            return .completion
        }
    }
}

// No duplicate enums here - we already have OnboardingStep defined above