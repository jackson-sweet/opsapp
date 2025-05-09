//
//  Company.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import SwiftUI
import SwiftData
import CoreLocation

/// Company model - matches your Bubble Company structure exactly
@Model
final class Company {
    var id: String
    var name: String
    var logoURL: String?
    var logoData: Data?
    
    // Additional fields to match your Bubble structure
    var externalId: String?
    var companyDescription: String?
    var address: String?
    var phone: String?
    var email: String?
    var website: String?
    var latitude: Double?
    var longitude: Double?
    var openHour: String?
    var closeHour: String?
    
    // Array storage
    var projectIdsString: String = ""
    var teamIdsString: String = ""
    
    // Relationship to team members
    @Relationship(deleteRule: .cascade)
    var teamMembers: [TeamMember] = []
    
    // Flag to track if team members have been synced
    var teamMembersSynced: Bool = false
    
    // Offline/sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.projectIdsString = ""
        self.teamIdsString = ""
        self.teamMembers = []
    }
    
    // Array accessor methods
    func getProjectIds() -> [String] {
        return projectIdsString.isEmpty ? [] : projectIdsString.components(separatedBy: ",")
    }
    
    func setProjectIds(_ ids: [String]) {
        projectIdsString = ids.joined(separator: ",")
    }
    
    func getTeamIds() -> [String] {
        return teamIdsString.isEmpty ? [] : teamIdsString.components(separatedBy: ",")
    }
    
    func setTeamIds(_ ids: [String]) {
        teamIdsString = ids.joined(separator: ",")
    }
    
    // Computed property for location
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = latitude,
              let longitude = longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Computed property for hours
    var hoursDisplay: String {
        if let open = openHour, let close = closeHour {
            return "\(open) - \(close)"
        }
        return "Hours not set"
    }
}
