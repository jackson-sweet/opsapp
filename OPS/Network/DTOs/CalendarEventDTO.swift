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
    let color: String
    let companyId: String
    let projectId: String
    let taskId: String?
    let duration: Int
    let endDate: String  // ISO 8601 date string
    let startDate: String  // ISO 8601 date string
    let teamMembers: [String]?  // Array of User IDs
    let title: String
    let type: String  // "project" or "task"
    
    // Metadata
    let createdDate: String?
    let modifiedDate: String?
    
    // Coding keys to match Bubble field names
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case color = "Color"
        case companyId = "Company"
        case projectId = "Project"
        case taskId = "Task"
        case duration = "Duration"
        case endDate = "End Date"
        case startDate = "Start Date"
        case teamMembers = "Team Members"
        case title = "Title"
        case type = "Type"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> CalendarEvent? {
        // Parse dates
        let dateFormatter = ISO8601DateFormatter()
        guard let startDateObj = dateFormatter.date(from: startDate),
              let endDateObj = dateFormatter.date(from: endDate) else {
            print("Failed to parse dates for CalendarEvent \(id)")
            return nil
        }
        
        let event = CalendarEvent(
            id: id,
            projectId: projectId,
            companyId: companyId,
            title: title,
            startDate: startDateObj,
            endDate: endDateObj,
            color: color,
            type: CalendarEventType(rawValue: type) ?? .project
        )
        
        event.taskId = taskId
        event.duration = duration
        
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
            duration: event.duration,
            endDate: dateFormatter.string(from: event.endDate),
            startDate: dateFormatter.string(from: event.startDate),
            teamMembers: event.getTeamMemberIds(),
            title: event.title,
            type: event.type.rawValue,
            createdDate: nil,
            modifiedDate: nil
        )
    }
}