//
//  TeamMember.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import Foundation
import SwiftUI
import SwiftData

/// Lightweight team member model for storing within Company
/// This reduces the need to fetch full User objects when just displaying team members
@Model
final class TeamMember {
    var id: String
    var firstName: String
    var lastName: String
    var role: String
    var avatarURL: String?
    var email: String?
    var phone: String?
    
    // Reference to the parent company
    @Relationship(deleteRule: .cascade, inverse: \Company.teamMembers)
    var company: Company?
    
    // Timestamp for tracking freshness
    var lastUpdated: Date
    
    init(id: String, firstName: String, lastName: String, role: String, avatarURL: String? = nil, email: String? = nil, phone: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.avatarURL = avatarURL
        self.email = email
        self.phone = phone
        self.lastUpdated = Date()
    }
    
    /// Create a TeamMember from a UserDTO
    static func fromUserDTO(_ dto: UserDTO, isAdmin: Bool = false) -> TeamMember {
        // First try to get the email from the authentication object, then from the direct email field
        let email = dto.authentication?.email?.email ?? dto.email
        
        // Determine role - check if user is admin first, then userType, then employeeType
        let role: String
        if isAdmin {
            role = "Admin"
        } else if dto.userType == "Admin" {
            role = "Admin"
        } else if let employeeType = dto.employeeType {
            role = employeeType
        } else {
            role = "Unassigned"
        }
        
        // Debug: Log phone data
        if let phone = dto.phone, !phone.isEmpty {
            print("📱 TeamMember.fromUserDTO: Found phone number for \(dto.nameFirst ?? "") \(dto.nameLast ?? ""): \(phone)")
        } else {
            print("📱 TeamMember.fromUserDTO: No phone number for \(dto.nameFirst ?? "") \(dto.nameLast ?? "")")
        }
        
        return TeamMember(
            id: dto.id,
            firstName: dto.nameFirst ?? "",
            lastName: dto.nameLast ?? "",
            role: role,
            avatarURL: dto.avatar,
            email: email,
            phone: dto.phone
        )
    }
    
    /// Full name computed property
    var fullName: String {
        return "\(firstName) \(lastName)"
    }
    
    /// Initials computed property
    var initials: String {
        let firstInitial = firstName.first?.uppercased() ?? ""
        let lastInitial = lastName.first?.uppercased() ?? ""
        return "\(firstInitial)\(lastInitial)"
    }
}