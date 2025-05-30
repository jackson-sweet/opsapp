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
    let authentication: Authentication?
    
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
        case nameFirst = "Name First" // User first name. String
        case nameLast = "Name Last" // Last name, string.
        case employeeType = "Employee Type" // Employee type. This is type Employee Type, which is a string, either "Office Crew", or "Field Crew".
        case userType = "User Type" // User type, which is of type User Type, which is a string, either Company, Employee, Client or Admin. Admin in this context refers to an OPS admin. in version X (some later version) we will allow users to register as clients to track their project progress etc.
        case avatar = "Avatar" // User's avatar or profile picture. type Image.
        case company = "Company" // The user's company. Type Company.
        case authentication // this is not a bubble field.
        case email // the user's email address, which is what they registered with. It is used for contact purposes, and also as a login field.
        case homeAddress = "Home Address" // The user's home address, of type 'geographic address'.
        case phone = "Phone" // The user's contact phone number.
        case userColor = "User Color" // The user's unique color in HEX.
        case devPermission = "Dev Permission" // Bool indicating if user has dev permission for testing features.
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> User {
        // Extract the role from Bubble's employee type
        let role: UserRole
        if let employeeTypeString = employeeType {
            role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
        } else {
            // Default to field crew if no role specified
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
        
        // Handle phone number if available
        if let phoneNumber = phone {
            user.phone = phoneNumber
        }
        
        // Handle profile image if available
        if let avatarUrl = avatar {
            user.profileImageURL = avatarUrl
            // Note: Actual image data will need to be downloaded separately
        }
        
        user.lastSyncedAt = Date()
        
        return user
    }
}
