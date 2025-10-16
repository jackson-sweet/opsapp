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
    let companyId: String?
    let completionDate: String?  // ISO 8601 date string
    let projectId: String?
    let scheduledDate: String?  // ISO 8601 date string
    let status: String?  // Made optional to handle missing field
    let taskColor: String?
    let taskIndex: Int?
    let taskNotes: String?
    let teamMembers: [String]?  // Array of User IDs
    let type: String?  // This is the Task Type ID in Bubble
    
    // Metadata
    let createdDate: String?
    let modifiedDate: String?
    
    // Coding keys to match Bubble field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case calendarEventId = "calendarEventId"
        case companyId = "companyId"
        case completionDate = "completionDate"
        case projectId = "projectID"  // Note: capital ID
        case scheduledDate = "scheduledDate"
        case status = "status"
        case taskColor = "taskColor"
        case taskIndex = "taskIndex"
        case taskNotes = "taskNotes"
        case teamMembers = "Team Members"
        case type = "type"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
    }
    
    /// Convert DTO to SwiftData model
    /// - Parameter defaultColor: Default color to use if taskColor is nil (usually company.defaultProjectColor)
    func toModel(defaultColor: String = "#59779F") -> ProjectTask {
        // Log Task details for debugging
        
        // Validate required fields
        let projectIdValue: String
        if let pid = projectId, !pid.isEmpty {
            projectIdValue = pid
        } else {
            projectIdValue = ""
        }
        
        let companyIdValue: String
        if let cid = companyId, !cid.isEmpty {
            companyIdValue = cid
        } else {
            companyIdValue = ""
        }
        
        // Validate color
        let validColor: String
        if let colorValue = taskColor, !colorValue.isEmpty {
            // Ensure color starts with #
            validColor = colorValue.hasPrefix("#") ? colorValue : "#\(colorValue)"
        } else {
            validColor = defaultColor
        }
        
        let task = ProjectTask(
            id: id,
            projectId: projectIdValue,
            taskTypeId: type ?? "",  // 'type' field in Bubble is the task type ID
            companyId: companyIdValue,
            status: TaskStatus(rawValue: status ?? "") ?? .scheduled,
            taskColor: validColor
        )
        
        task.calendarEventId = calendarEventId
        task.taskNotes = taskNotes
        task.displayOrder = taskIndex ?? 0
        
        if let teamMembers = teamMembers {
            task.setTeamMemberIds(teamMembers)
        }
        
        return task
    }
    
    /// Create DTO from SwiftData model
    static func from(_ task: ProjectTask) -> TaskDTO {
        // Convert dates to ISO 8601 strings if available
        let dateFormatter = ISO8601DateFormatter()
        let scheduledDateString = task.scheduledDate != nil ? dateFormatter.string(from: task.scheduledDate!) : nil
        let completionDateString = task.completionDate != nil ? dateFormatter.string(from: task.completionDate!) : nil

        print("[TASK_DTO] 🎨 Creating TaskDTO from ProjectTask")
        print("[TASK_DTO] Task ID: \(task.id)")
        print("[TASK_DTO] Task Color: \(task.taskColor)")
        print("[TASK_DTO] Task Type ID: \(task.taskTypeId)")
        print("[TASK_DTO] Task Type Display: \(task.taskType?.display ?? "nil")")
        print("[TASK_DTO] Task Type Color: \(task.taskType?.color ?? "nil")")

        return TaskDTO(
            id: task.id,
            calendarEventId: task.calendarEventId,
            companyId: task.companyId.isEmpty ? nil : task.companyId,
            completionDate: completionDateString,
            projectId: task.projectId.isEmpty ? nil : task.projectId,
            scheduledDate: scheduledDateString,
            status: task.status.rawValue,
            taskColor: task.taskColor,
            taskIndex: task.displayOrder,
            taskNotes: task.taskNotes,
            teamMembers: task.getTeamMemberIds().isEmpty ? nil : task.getTeamMemberIds(),
            type: task.taskTypeId.isEmpty ? nil : task.taskTypeId,  // taskTypeId maps to 'type' in Bubble
            createdDate: nil,
            modifiedDate: nil
        )
    }
}