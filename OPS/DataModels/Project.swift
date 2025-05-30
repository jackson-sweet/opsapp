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
    var clientEmail: String?
    var clientPhone: String?
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
    
    // Store unsynced images (those captured while offline) as comma-separated string
    var unsyncedImagesString: String = ""
    
    // Store relationships to team members with proper inverse
    @Relationship(deleteRule: .noAction)
    var teamMembers: [User]
    
    // Offline/sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var syncPriority: Int = 1 // Higher numbers = higher priority
    
    // Transient properties (not persisted to database)
    @Transient var lastTapped: Date?
    @Transient var coordinatorData: [String: Any]?
    
    init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
        self.address = ""
        self.clientName = ""
        self.clientEmail = nil
        self.clientPhone = nil
        self.companyId = ""
        self.teamMemberIdsString = ""
        self.projectImagesString = ""
        self.unsyncedImagesString = ""
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
    
    // Get unsynced images
    func getUnsyncedImages() -> [String] {
        return unsyncedImagesString.isEmpty ? [] : unsyncedImagesString.components(separatedBy: ",")
    }
    
    // Add an image to unsynced list
    func addUnsyncedImage(_ imageURL: String) {
        var unsynced = getUnsyncedImages()
        if !unsynced.contains(imageURL) {
            unsynced.append(imageURL)
            unsyncedImagesString = unsynced.joined(separator: ",")
        }
    }
    
    // Mark an image as synced by removing from unsynced list
    func markImageAsSynced(_ imageURL: String) {
        var unsynced = getUnsyncedImages()
        if let index = unsynced.firstIndex(of: imageURL) {
            unsynced.remove(at: index)
            unsyncedImagesString = unsynced.joined(separator: ",")
        }
    }
    
    // Check if an image is synced
    func isImageSynced(_ imageURL: String) -> Bool {
        return !getUnsyncedImages().contains(imageURL)
    }
    
    // Clear all unsynced images
    func clearUnsyncedImages() {
        unsyncedImagesString = ""
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
    
    // Computed property for location with validation
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = latitude,
              let longitude = longitude else {
            return nil
        }
        
        // Validate coordinate ranges
        let validLatitude = max(-90.0, min(90.0, latitude))
        let validLongitude = max(-180.0, min(180.0, longitude))
        
        // Check if coordinates are meaningful (not 0,0 which often indicates missing data)
        if abs(validLatitude) < 0.0001 && abs(validLongitude) < 0.0001 {
            print("⚠️ Project \(id): Invalid coordinates (0,0), likely missing geocoding data")
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: validLatitude, longitude: validLongitude)
    }
    
    // Method to set coordinates with validation
    func setCoordinate(_ coordinate: CLLocationCoordinate2D) {
        // Validate and round to 6 decimal places (approximately 0.1 meter precision)
        let validLatitude = max(-90.0, min(90.0, coordinate.latitude))
        let validLongitude = max(-180.0, min(180.0, coordinate.longitude))
        
        self.latitude = round(validLatitude * 1_000_000) / 1_000_000
        self.longitude = round(validLongitude * 1_000_000) / 1_000_000
        
        print("📍 Project \(id): Set coordinates to (\(self.latitude!), \(self.longitude!))")
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
