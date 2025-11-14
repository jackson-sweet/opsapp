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
    var phone: String?
    var profileImageURL: String?
    var profileImageData: Data?
    var role: UserRole
    var companyId: String?
    
    // Additional fields to match your Bubble structure
    var userType: UserType?
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var homeAddress: String?  // User's home address
    var clientId: String?
    var isActive: Bool?
    var userColor: String?  // User's unique color in HEX
    var devPermission: Bool = false  // Dev permission for testing features
    var hasCompletedAppOnboarding: Bool = false  // Track if user has completed onboarding
    var isCompanyAdmin: Bool = false  // Whether user is an admin for their company
    
    // Stripe integration
    var stripeCustomerId: String?  // User's Stripe customer ID (for plan holders)
    
    // Fixed relationship with proper inverse that matches Project's declaration
    @Relationship(deleteRule: .noAction, inverse: \Project.teamMembers)
    var assignedProjects: [Project]
    
    // Offline/sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    init(id: String, firstName: String, lastName: String, role: UserRole, companyId: String) {
         self.id = id
         self.firstName = firstName
         self.lastName = lastName
         self.role = role
         self.companyId = companyId
         self.assignedProjects = []
         self.isActive = true
     }
    
    // Computed properties for convenience
    var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    // Check if user is the plan holder (their Stripe ID matches company's)
    func isPlanHolder(for company: Company) -> Bool {
        guard let userStripeId = stripeCustomerId,
              let companyStripeId = company.stripeCustomerId else {
            return false
        }
        return userStripeId == companyStripeId
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
        case .admin:
            return .green
        }
    }
    
    // Computed property for role display
    var roleDisplay: String {
        role.rawValue
    }
}
