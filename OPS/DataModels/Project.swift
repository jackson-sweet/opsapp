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
    var clientName: String // Keep for backward compatibility and quick access
    var clientEmail: String? // Keep for backward compatibility
    var clientPhone: String? // Keep for backward compatibility
    var address: String
    var latitude: Double?
    var longitude: Double?
    var startDate: Date?
    var endDate: Date?
    var duration: Int? // Duration in days from API
    var status: Status
    var notes: String?
    var companyId: String
    var clientId: String? // Store the client's Bubble ID
    var allDay: Bool
    var eventType: CalendarEventType? // Optional to handle migration - defaults to .project when nil
    
    // Relationship to Client object
    @Relationship(deleteRule: .nullify)
    var client: Client?
    
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
    
    // Relationship to tasks (for task-based scheduling)
    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    var tasks: [ProjectTask] = []
    
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
        self.eventType = .project // Default to project scheduling
        self.client = nil
    }
    
    // Computed properties to get client info from Client object if available
    var effectiveClientName: String {
        return client?.name ?? clientName
    }
    
    var effectiveClientEmail: String? {
        // First check if client has email
        if let clientEmail = client?.email, !clientEmail.isEmpty {
            return clientEmail
        }
        
        // Check sub-clients for email
        if let subClients = client?.subClients {
            for subClient in subClients {
                if let email = subClient.email, !email.isEmpty {
                    return email // Return first available sub-client email
                }
            }
        }
        
        // Fall back to legacy field
        return clientEmail
    }
    
    var effectiveClientPhone: String? {
        // First check if client has phone
        if let clientPhone = client?.phoneNumber, !clientPhone.isEmpty {
            return clientPhone
        }
        
        // Check sub-clients for phone
        if let subClients = client?.subClients {
            for subClient in subClients {
                if let phone = subClient.phoneNumber, !phone.isEmpty {
                    return phone // Return first available sub-client phone
                }
            }
        }
        
        // Fall back to legacy field
        return clientPhone
    }
    
    // Check if any contact info is available (including sub-clients)
    var hasAnyClientContactInfo: Bool {
        return effectiveClientEmail != nil || effectiveClientPhone != nil
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
        if images.count > 0 {
            for (index, url) in images.enumerated() {
            }
        }
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
    }
    
    // MARK: - Task-Based Scheduling Properties
    
    /// Get the effective eventType (defaults to .project if nil)
    var effectiveEventType: CalendarEventType {
        return eventType ?? .project
    }
    
    /// Check if this project uses task-based scheduling
    var usesTaskBasedScheduling: Bool {
        return effectiveEventType == .task
    }
    
    /// Check if this project uses traditional project scheduling
    var usesProjectScheduling: Bool {
        return effectiveEventType == .project
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
    
    // MARK: - Multi-Day Calendar Support
    
    /// Computed property that returns the effective end date
    /// If endDate is before startDate, calculates based on duration
    /// If no duration is provided, defaults to single day
    var effectiveEndDate: Date? {
        guard let start = startDate else { return nil }
        
        // If we have a valid end date (after or equal to start date), use it
        if let end = endDate, end >= start {
            return end
        }
        
        // If end date is invalid (before start date) or missing, use duration
        let calendar = Calendar.current
        
        // Use duration if available, otherwise default to 1 day
        let daysToAdd = (duration ?? 1) - 1 // Subtract 1 because start date counts as day 1
        
        // Calculate end date based on duration
        return calendar.date(byAdding: .day, value: max(0, daysToAdd), to: start)
    }
    
    /// Returns true if this project spans multiple days
    var isMultiDay: Bool {
        guard let start = startDate, let end = effectiveEndDate else { return false }
        let calendar = Calendar.current
        return !calendar.isDate(start, inSameDayAs: end)
    }
    
    /// Returns the number of days this project spans
    /// Note: Completion date is the day AFTER work ends, except when start = end (single day project)
    var daySpan: Int {
        guard let start = startDate, let end = effectiveEndDate else { return 1 }
        let calendar = Calendar.current
        
        // If start and end are the same day, it's a single-day project
        if calendar.isDate(start, inSameDayAs: end) {
            return 1
        }
        
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        return max(1, days) // Don't add 1 since completion date is day after work ends
    }
    
    /// Returns an array of dates that this project spans
    /// Note: Completion date is the day AFTER work ends, except when start = end (single day project)
    var spannedDates: [Date] {
        guard let start = startDate, let end = effectiveEndDate else {
            if let start = startDate {
                return [start]
            }
            return []
        }
        
        var dates: [Date] = []
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        
        // If start and end are the same day, it's a single-day project
        if calendar.isDate(start, inSameDayAs: end) {
            return [currentDate]
        }
        
        // Otherwise, stop BEFORE the completion date (completion is day after work ends)
        while currentDate < endDay {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dates
    }
    
    /// Check if project is active on a specific date
    /// Note: Completion date is the day AFTER work ends, except when start = end (single day project)
    func isActiveOn(date: Date) -> Bool {
        let calendar = Calendar.current
        let checkDate = calendar.startOfDay(for: date)
        
        // If no dates set, not active
        guard let start = startDate else { return false }
        
        let startDay = calendar.startOfDay(for: start)
        
        // Use effective end date instead of raw endDate
        guard let end = effectiveEndDate else {
            return calendar.isDate(startDay, inSameDayAs: checkDate)
        }
        
        let endDay = calendar.startOfDay(for: end)
        
        // If start and end are the same day, it's a single-day project
        if calendar.isDate(startDay, inSameDayAs: endDay) {
            return calendar.isDate(startDay, inSameDayAs: checkDate)
        }
        
        // Otherwise, check if date falls within range (exclusive of completion date)
        return checkDate >= startDay && checkDate < endDay
    }
    
    /// Get the day number for a specific date (e.g., "Day 2 of 5")
    func dayNumber(for date: Date) -> Int? {
        guard let start = startDate, isActiveOn(date: date) else { return nil }
        
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let checkDay = calendar.startOfDay(for: date)
        
        let dayDiff = calendar.dateComponents([.day], from: startDay, to: checkDay).day ?? 0
        return dayDiff + 1 // Make it 1-based
    }
    
    // MARK: - Task-Based Scheduling Support
    
    /// Check if project has tasks
    var hasTasks: Bool {
        return !tasks.isEmpty
    }
    
    /// Get computed status based on task statuses
    var computedStatus: Status {
        // If no tasks, use the project's own status
        if !hasTasks {
            return status
        }
        
        // If any task is in progress, project is in progress
        if tasks.contains(where: { $0.status == .inProgress }) {
            return .inProgress
        }
        
        // If all tasks are completed, project is completed
        if !tasks.isEmpty && tasks.allSatisfy({ $0.status == .completed }) {
            return .completed
        }
        
        // If all tasks are cancelled, project status doesn't change
        if tasks.allSatisfy({ $0.status == .cancelled }) {
            return status
        }
        
        // Otherwise, keep current project status
        return status
    }
    
    /// Get effective start date (from tasks or project)
    var effectiveStartDate: Date? {
        if hasTasks {
            // Get earliest task start date
            let taskDates = tasks.compactMap { task in
                task.calendarEvent?.startDate
            }
            return taskDates.min() ?? startDate
        }
        return startDate
    }
    
    /// Get effective completion date (from tasks or project)
    var effectiveCompletionDate: Date? {
        if hasTasks {
            // Get latest task end date
            let taskDates = tasks.compactMap { task in
                task.calendarEvent?.endDate
            }
            return taskDates.max() ?? endDate
        }
        return effectiveEndDate
    }
}
