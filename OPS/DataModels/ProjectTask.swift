//
//  Task.swift
//  OPS
//
//  Task model for task-based scheduling system
//

import Foundation
import SwiftData

/// Status enum for tasks
enum TaskStatus: String, Codable, CaseIterable {
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"
    
    var displayName: String {
        return self.rawValue
    }
}

/// Task model - represents a sub-component of a project
@Model
final class ProjectTask {
    // MARK: - Properties
    var id: String
    var projectId: String
    var calendarEventId: String?
    var companyId: String
    var status: TaskStatus
    var taskColor: String  // Hex color code
    var taskNotes: String?
    var taskTypeId: String
    var displayOrder: Int = 0
    
    // Store team member IDs as string (for compatibility with existing patterns)
    var teamMemberIdsString: String = ""
    
    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var project: Project?
    
    @Relationship(deleteRule: .cascade)
    var calendarEvent: CalendarEvent?
    
    @Relationship(deleteRule: .nullify)
    var taskType: TaskType?
    
    @Relationship(deleteRule: .noAction)
    var teamMembers: [User] = []
    
    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    
    // MARK: - Initialization
    init(
        id: String,
        projectId: String,
        taskTypeId: String,
        companyId: String,
        status: TaskStatus = .scheduled,
        taskColor: String = "#59779F"
    ) {
        self.id = id
        self.projectId = projectId
        self.taskTypeId = taskTypeId
        self.companyId = companyId
        self.status = status
        self.taskColor = taskColor
        self.taskNotes = nil
        self.calendarEventId = nil
        self.displayOrder = 0
        self.teamMemberIdsString = ""
        self.teamMembers = []
    }
    
    // MARK: - Helper Methods
    
    /// Get team member IDs as array
    func getTeamMemberIds() -> [String] {
        return teamMemberIdsString.isEmpty ? [] : teamMemberIdsString.components(separatedBy: ",")
    }
    
    /// Set team member IDs from array
    func setTeamMemberIds(_ ids: [String]) {
        teamMemberIdsString = ids.joined(separator: ",")
    }
    
    /// Get display title (from TaskType or fallback)
    var displayTitle: String {
        return taskType?.display ?? "Task"
    }
    
    /// Get effective color (from TaskType or task color)
    var effectiveColor: String {
        if let taskType = taskType, !taskType.color.isEmpty {
            return taskType.color
        }
        return taskColor
    }
    
    /// Check if user can edit this task
    func canEdit(user: User) -> Bool {
        return user.role == .admin || user.role == .officeCrew
    }
    
    /// Check if user can update status
    func canUpdateStatus(user: User) -> Bool {
        // All users can update task status
        return true
    }
}