//
//  TaskDTO.swift
//  OPS
//
//  Data Transfer Object for Task from Bubble API
//

import Foundation

/// Data Transfer Object for Task from Bubble API
struct TaskDTO: Codable {
    // Task properties from Bubble
    let id: String
    let calendarEventId: String?
    let companyId: String
    let projectId: String
    let status: String
    let taskColor: String
    let taskNotes: String?
    let taskTypeId: String
    let teamMembers: [String]?  // Array of User IDs
    let displayOrder: Int?
    
    // Metadata
    let createdDate: String?
    let modifiedDate: String?
    
    // Coding keys to match Bubble field names
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case calendarEventId = "Calendar Event"
        case companyId = "Company"
        case projectId = "Project"
        case status = "Status"
        case taskColor = "Task Color"
        case taskNotes = "Task Notes"
        case taskTypeId = "Task Type"
        case teamMembers = "Team Members"
        case displayOrder = "Display Order"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: projectId,
            taskTypeId: taskTypeId,
            companyId: companyId,
            status: TaskStatus(rawValue: status) ?? .scheduled,
            taskColor: taskColor
        )
        
        task.calendarEventId = calendarEventId
        task.taskNotes = taskNotes
        task.displayOrder = displayOrder ?? 0
        
        if let teamMembers = teamMembers {
            task.setTeamMemberIds(teamMembers)
        }
        
        return task
    }
    
    /// Create DTO from SwiftData model
    static func from(_ task: ProjectTask) -> TaskDTO {
        return TaskDTO(
            id: task.id,
            calendarEventId: task.calendarEventId,
            companyId: task.companyId,
            projectId: task.projectId,
            status: task.status.rawValue,
            taskColor: task.taskColor,
            taskNotes: task.taskNotes,
            taskTypeId: task.taskTypeId,
            teamMembers: task.getTeamMemberIds(),
            displayOrder: task.displayOrder,
            createdDate: nil,
            modifiedDate: nil
        )
    }
}