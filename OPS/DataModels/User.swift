//
//  User.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import SwiftUI
import SwiftData
import CoreLocation

/// User model - matches your Bubble User structure
@Model
final class User {
    var id: String
    var firstName: String
    var lastName: String
    var email: String?
    var profileImageURL: String?
    var profileImageData: Data?
    var role: UserRole
    var companyId: String
    
    // Additional fields to match your Bubble structure
    var userType: UserType?
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var clientId: String?
    
    // Fixed relationship to assigned projects that avoids circular reference
    // Use delete rules from SwiftData's documented options
    @Relationship(deleteRule: .noAction, inverse: \Project.teamMembers)
    var assignedProjects: [Project]?
    
    // Offline/sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    
    init(id: String, firstName: String, lastName: String, role: UserRole, companyId: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.companyId = companyId
    }
    
    // Computed properties for convenience
    var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    // Computed property for location
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = latitude,
              let longitude = longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Computed property for user display color based on role
    var roleColor: Color {
        switch role {
        case .fieldCrew:
            return .blue
        case .officeCrew:
            return .orange
        }
    }
    
    // Computed property for role display
    var roleDisplay: String {
        role.rawValue
    }
}
