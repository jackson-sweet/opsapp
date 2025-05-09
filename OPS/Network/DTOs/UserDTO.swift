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
    let homeAddress: String?
    let phone: String?
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
        case id = "_id"
        case nameFirst = "Name First"
        case nameLast = "Name Last"
        case employeeType = "Employee Type"
        case userType = "User Type"
        case avatar = "Avatar"
        case company = "Company"
        case authentication
        case email
        case homeAddress = "Home Address"
        case phone = "Phone"
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
            user.homeAddress = address
        }
        
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
