import Foundation

/// Data Transfer Object for User from Bubble API
/// Designed to exactly match your Bubble data structure
struct UserDTO: Codable {
    // Use Bubble's exact field names in our CodingKeys
    
    // User properties
    let id: String
    let nameFirst: String?
    let nameLast: String?
    let employeeType: String?
    let userType: String?
    let avatar: String?
    let company: String?
    let email: String?
    let homeAddress: BubbleAddress?
    let phone: String?
    let userColor: String?
    let devPermission: Bool?
    let hasCompletedAppOnboarding: Bool?
    let authentication: Authentication?
    let stripeCustomerId: String?

    // Soft delete support
    let deletedAt: String?

    // Authentication information
    struct Authentication: Codable {
        let email: EmailAuth?
        
        struct EmailAuth: Codable {
            let email: String?
            let emailConfirmed: Bool?
            
            enum CodingKeys: String, CodingKey {
                case email
                case emailConfirmed = "email_confirmed"
            }
        }
    }
    
    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id" // Unique id assigned by bubble. This is known colloquially as user ID.
        case nameFirst = "nameFirst" // User first name. String
        case nameLast = "nameLast" // Last name, string.
        case employeeType = "employeeType" // Employee type. This is type Employee Type, which is a string, either "Office Crew", or "Field Crew".
        case userType = "userType" // User type, which is of type User Type, which is a string, either Company, Employee, Client or Admin. Admin in this context refers to an OPS admin. in version X (some later version) we will allow users to register as clients to track their project progress etc.
        case avatar = "avatar" // User's avatar or profile picture. type Image.
        case company = "company" // The user's company. Type Company.
        case authentication // this is not a bubble field.
        case email // the user's email address, which is what they registered with. It is used for contact purposes, and also as a login field.
        case homeAddress = "homeAddress" // The user's home address, of type 'geographic address'.
        case phone = "phone" // The user's contact phone number.
        case userColor = "userColor" // The user's unique color in HEX.
        case devPermission = "devPermission" // Bool indicating if user has dev permission for testing features.
        case hasCompletedAppOnboarding = "hasCompletedAppOnboarding" // Bool indicating if user has completed app onboarding.
        case stripeCustomerId = "stripeCustomerId" // User's Stripe customer ID
        case deletedAt = "deletedAt" // Soft delete timestamp
    }
    
    /// Convert DTO to SwiftData model
    /// - Parameter companyAdminIds: Optional array of admin user IDs from the company. If provided, 
    ///   takes precedence over userType for determining admin role.
    func toModel(companyAdminIds: [String]? = nil) -> User {
        // Extract the role from company admin status first, then user type and employee type
        let role: UserRole
        
        // FIRST: Check if user ID is in company.adminIds array → set to UserRole.admin
        if let adminIds = companyAdminIds, adminIds.contains(id) {
            role = .admin
        } else if let employeeTypeString = employeeType {
            // If NOT in company.adminIds, then check employeeType field
            role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
        } else {
            // If employeeType is empty/nil, default to Field Crew
            role = .fieldCrew
        }
        
        // Extract company ID if available
        let companyId = company ?? ""
        
        // Create user
        let user = User(
            id: id,
            firstName: nameFirst ?? "",
            lastName: nameLast ?? "",
            role: role,
            companyId: companyId
        )
        
        // Handle additional fields
        if let emailAuth = authentication?.email?.email {
            user.email = emailAuth
        } else {
            user.email = email
        }
        
        // Handle home address if available
        if let address = homeAddress {
            user.homeAddress = address.formattedAddress
            // Could also store lat/lng if needed in the future
        }
        
        // Handle new fields
        user.userColor = userColor
        user.devPermission = devPermission ?? false
        user.hasCompletedAppOnboarding = hasCompletedAppOnboarding ?? false
        
        // Handle Stripe customer ID
        user.stripeCustomerId = stripeCustomerId
        
        // Handle phone number if available
        if let phoneNumber = phone {
            user.phone = phoneNumber
        }
        
        // Handle profile image if available
        if let avatarUrl = avatar {
            user.profileImageURL = avatarUrl
            // Note: Actual image data will need to be downloaded separately
        }

        // Parse deletedAt if present
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            user.deletedAt = formatter.date(from: deletedAtString)
        }

        user.lastSyncedAt = Date()

        return user
    }
}
