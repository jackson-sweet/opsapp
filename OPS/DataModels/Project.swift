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
final class Project: Identifiable {
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
    
    // Store project images as comma-separated string
    var projectImagesString: String = ""
    
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
        self.projectImagesString = ""
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
    
    // Project images accessor methods
    func getProjectImageURLs() -> [String] {
        return projectImagesString.isEmpty ? [] : projectImagesString.components(separatedBy: ",")
    }
    
    func setProjectImageURLs(_ urls: [String]) {
        projectImagesString = urls.joined(separator: ",")
    }
    
    // Accessor for project images
    func getProjectImages() -> [String] {
        let images = projectImagesString.isEmpty ? [] : projectImagesString.components(separatedBy: ",")
        print("Project[\(id)] - getProjectImages() returning \(images.count) images")
        return images
    }
    
    // Debug method to show project state
    func debugProjectState() {
        print("Project Debug Info:")
        print("  - ID: \(id)")
        print("  - Title: \(title)")
        print("  - Status: \(status.rawValue)")
        print("  - Images String: \(projectImagesString)")
        print("  - Images Count: \(getProjectImages().count)")
        print("  - Needs Sync: \(needsSync)")
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
