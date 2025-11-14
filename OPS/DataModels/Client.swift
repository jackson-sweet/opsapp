//
//  Client.swift
//  OPS
//
//  Client model for storing customer/client information
//

import Foundation
import SwiftData
import CoreLocation

/// Client model - represents a customer/client in the system
@Model
final class Client: Identifiable {
    var id: String // Bubble's unique ID (_id field)
    var name: String
    var email: String?
    var phoneNumber: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var profileImageURL: String? // Thumbnail/profile picture URL
    var notes: String? // Client notes
    
    // Company relationship
    var companyId: String?
    
    // Relationship to projects
    @Relationship(deleteRule: .noAction, inverse: \Project.client)
    var projects: [Project]
    
    // Relationship to sub-clients
    @Relationship(deleteRule: .cascade)
    var subClients: [SubClient]
    
    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    init(
        id: String,
        name: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        address: String? = nil,
        companyId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phoneNumber = phoneNumber
        self.address = address
        self.companyId = companyId
        self.notes = notes
        self.projects = []
        self.subClients = []
        self.lastSyncedAt = Date()
    }
    
    // Computed property for coordinate
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    // Set coordinate from address object
    func setCoordinate(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

// MARK: - Convenience Methods
extension Client {
    /// Returns the client's full display name
    var displayName: String {
        return name
    }
    
    /// Returns true if the client has any contact information
    var hasContactInfo: Bool {
        return email != nil || phoneNumber != nil
    }
    
    /// Returns a formatted address string
    var formattedAddress: String? {
        return address
    }
}