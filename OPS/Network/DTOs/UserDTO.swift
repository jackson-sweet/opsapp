//
//  UserDTO.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
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
    let currentLocation: BubbleAddress?
    let avatar: BubbleImage?
    let company: BubbleReference?
    let clientId: BubbleReference?
    let email: String?
    
    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nameFirst = "Name First"
        case nameLast = "Name Last"
        case employeeType = "Employee Type"
        case userType = "User Type"
        case currentLocation = "Current Location"
        case avatar = "Avatar"
        case company = "Company"
        case clientId = "Client ID"
        case email
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
        let companyId = company?.uniqueID ?? ""
        
        // Create user
        let user = User(
            id: id,
            firstName: nameFirst ?? "",
            lastName: nameLast ?? "",
            role: role,
            companyId: companyId
        )
        
        // Handle additional fields
        user.email = email
        
        // Geographic location needs special handling
        if let location = currentLocation {
            user.latitude = location.lat
            user.longitude = location.lng
            user.locationName = location.formattedAddress
        }
        
        // Handle profile image if available
        if let avatarImage = avatar, let imageUrl = avatarImage.url {
            user.profileImageURL = imageUrl
            // Note: Actual image data will need to be downloaded separately
        }
        
        user.lastSyncedAt = Date()
        
        return user
    }
}
