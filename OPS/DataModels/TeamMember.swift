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
    
    /// Create a TeamMember from a User model
    static func fromUser(_ user: User) -> TeamMember {
        return TeamMember(
            id: user.id,
            firstName: user.firstName,
            lastName: user.lastName,
            role: user.role.displayName,
            avatarURL: user.profileImageURL,
            email: user.email,
            phone: user.phone
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