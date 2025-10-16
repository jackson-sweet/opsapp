//
//  CalendarEventDTO.swift
//  OPS
//
//  Data Transfer Object for CalendarEvent from Bubble API
//

import Foundation

/// Data Transfer Object for CalendarEvent from Bubble API
struct CalendarEventDTO: Codable {
    // CalendarEvent properties from Bubble
    let id: String
    let color: String?
    let companyId: String?  // Company ID
    let projectId: String?  // Project ID
    let taskId: String?  // Task ID
    let duration: Double?  // Changed from Int to handle decimal values
    let endDate: String?  // ISO 8601 date string
    let startDate: String?  // ISO 8601 date string
    let teamMembers: [String]?  // Array of User IDs
    let title: String?
    let type: String?  // "project" or "task"
    let active: Bool?  // Whether this event is active (based on project scheduling mode)

    // Metadata
    let createdDate: String?
    let modifiedDate: String?
    
    // Coding keys to match Bubble field names
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case color = "Color"
        case companyId = "companyId"  // lowercase 'c'
        case projectId = "projectId"  // lowercase 'p'
        case taskId = "taskId"  // lowercase 't'
        case duration = "Duration"
        case endDate = "End Date"
        case startDate = "Start Date"
        case teamMembers = "Team Members"
        case title = "Title"
        case type = "Type"
        case active = "active"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> CalendarEvent? {

        // Parse dates with validation
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Also try without fractional seconds if first attempt fails
        let alternativeFormatter = ISO8601DateFormatter()
        alternativeFormatter.formatOptions = [.withInternetDateTime]

        var startDateObj: Date? = nil
        var endDateObj: Date? = nil

        // Handle start date (optional - may be nil for unscheduled projects)
        if let startDateString = startDate {
            if let parsedStart = dateFormatter.date(from: startDateString) {
                startDateObj = parsedStart
            } else if let parsedStart = alternativeFormatter.date(from: startDateString) {
                startDateObj = parsedStart
            } else {
                // Try one more format - Bubble sometimes sends dates differently
                let bubbleFormatter = DateFormatter()
                bubbleFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                if let parsedStart = bubbleFormatter.date(from: startDateString) {
                    startDateObj = parsedStart
                } else {
                    print("[CalendarEventDTO] ⚠️ Failed to parse start date: \(startDateString)")
                }
            }
        }
        
        // Handle end date (optional - may be nil for unscheduled projects)
        if let endDateString = endDate {
            if let parsedEnd = dateFormatter.date(from: endDateString) {
                endDateObj = parsedEnd
            } else if let parsedEnd = alternativeFormatter.date(from: endDateString) {
                endDateObj = parsedEnd
            } else {
                // Try Bubble format
                let bubbleFormatter = DateFormatter()
                bubbleFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                if let parsedEnd = bubbleFormatter.date(from: endDateString) {
                    endDateObj = parsedEnd
                } else {
                    print("[CalendarEventDTO] ⚠️ Failed to parse end date: \(endDateString)")
                }
            }
        }

        // Validate date order if both dates exist - end must be on or after start
        if let start = startDateObj, let end = endDateObj, end < start {
            endDateObj = start
        }

        // Validate duration only if we have dates
        if startDateObj != nil && endDateObj != nil {
            if let durationValue = duration {
                if durationValue < 0 {
                    endDateObj = startDateObj
                } else if durationValue == 0 {
                    endDateObj = startDateObj
                }
            }
        }
        
        // Validate required fields
        guard let projectIdValue = projectId, !projectIdValue.isEmpty else {
            return nil
        }
        
        guard let companyIdValue = companyId, !companyIdValue.isEmpty else {
            return nil
        }
        
        // Validate and clean color
        let validColor: String
        if let colorValue = color, !colorValue.isEmpty {
            // Ensure color starts with #
            validColor = colorValue.hasPrefix("#") ? colorValue : "#\(colorValue)"
        } else {
            validColor = "#59779F" // Default blue
        }
        
        // Validate title
        let validTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Event"
        
        // Validate type and ensure consistency with taskId
        let eventType = CalendarEventType(rawValue: type?.lowercased() ?? "project") ?? .project
        
        
        let event = CalendarEvent(
            id: id,
            projectId: projectIdValue,
            companyId: companyIdValue,
            title: validTitle,
            startDate: startDateObj,
            endDate: endDateObj,
            color: validColor,
            type: eventType,
            active: active ?? true  // Default to active if not specified
        )
        
        event.taskId = taskId
        event.duration = Int(duration ?? 1)  // Convert Double to Int, defaulting to 1
        
        if let teamMembers = teamMembers {
            event.setTeamMemberIds(teamMembers)
        }
        
        return event
    }
    
    /// Create DTO from SwiftData model
    static func from(_ event: CalendarEvent) -> CalendarEventDTO {
        let dateFormatter = ISO8601DateFormatter()
        
        return CalendarEventDTO(
            id: event.id,
            color: event.color,
            companyId: event.companyId,
            projectId: event.projectId,
            taskId: event.taskId,
            duration: Double(event.duration),  // Convert Int to Double
            endDate: event.endDate.map { dateFormatter.string(from: $0) },
            startDate: event.startDate.map { dateFormatter.string(from: $0) },
            teamMembers: event.getTeamMemberIds(),
            title: event.title,
            type: event.type.rawValue,
            active: event.active,
            createdDate: nil,
            modifiedDate: nil
        )
    }
}