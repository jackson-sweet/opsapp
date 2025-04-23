//
//  Project.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
//
//  Project.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import SwiftUI
import SwiftData
import CoreLocation

/// Project model - central entity for field crew
@Model
final class Project {
    var id: String
    var title: String
    var clientName: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var startDate: Date?
    var endDate: Date?
    var status: Status
    var notes: String?
    var companyId: String
    var clientId: String?
    var allDay: Bool
    
    // Store team member IDs as string
    var teamMemberIdsString: String = ""
    var projectDescription: String?
    
    // Store relationships to team members with proper inverse
    @Relationship(deleteRule: .noAction)
    var teamMembers: [User]
    
    // Offline/sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var syncPriority: Int = 1 // Higher numbers = higher priority
    
    init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
        self.address = ""
        self.clientName = ""
        self.companyId = ""
        self.teamMemberIdsString = ""
        self.teamMembers = []
        self.allDay = false
    }
    
    // Array accessor methods
    func getTeamMemberIds() -> [String] {
        return teamMemberIdsString.isEmpty ? [] : teamMemberIdsString.components(separatedBy: ",")
    }
    
    func setTeamMemberIds(_ ids: [String]) {
        teamMemberIdsString = ids.joined(separator: ",")
    }
    
    // Computed property for location
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = latitude,
              let longitude = longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Computed property for display status - matches your Bubble status colors
    var statusColor: Color {
        return status.color
    }
    
    // Computed property for formatting start time
    var formattedStartDate: String {
        guard let startDate = startDate else { return "No date set" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
}
