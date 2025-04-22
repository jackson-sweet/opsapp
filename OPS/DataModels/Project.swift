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
/// Renamed from Job to match your Bubble structure
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
    
    // Additional fields to match your Bubble structure
    var teamMemberIds: [String]
        var projectDescription: String?
    
    // Fix for circular reference issue - proper relationship definition
    @Relationship(deleteRule: .nullify, inverse: \User.assignedProjects)
    var teamMembers: [User]?
    
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
        self.teamMemberIds = []
        self.allDay = false
        self.teamMembers = []
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
        switch status {
        case .rfq:
            return .gray
        case .estimated:
            return .blue
        case .accepted:
            return .purple
        case .inProgress:
            return .orange
        case .completed:
            return .green
        case .closed:
            return .red
        }
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
