//
//  CalendarEvent.swift
//  OPS
//
//  CalendarEvent model for unified calendar display
//

import Foundation
import SwiftData
import SwiftUI

/// Type of calendar event
enum CalendarEventType: String, Codable {
    case project = "project"
    case task = "task"
}

/// CalendarEvent model - represents items displayed on the calendar
@Model
final class CalendarEvent {
    // MARK: - Properties
    var id: String
    var color: String  // Hex color code
    var companyId: String
    var projectId: String
    var taskId: String?  // Optional - nil means project-level event
    var duration: Int  // Days
    var endDate: Date
    var startDate: Date
    var title: String
    var type: CalendarEventType
    
    // Store team member IDs as string (for compatibility)
    var teamMemberIdsString: String = ""
    
    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var project: Project?
    
    @Relationship(deleteRule: .nullify, inverse: \ProjectTask.calendarEvent)
    var task: ProjectTask?
    
    @Relationship(deleteRule: .noAction)
    var teamMembers: [User] = []
    
    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    
    // MARK: - Initialization
    init(
        id: String,
        projectId: String,
        companyId: String,
        title: String,
        startDate: Date,
        endDate: Date,
        color: String,
        type: CalendarEventType
    ) {
        self.id = id
        self.projectId = projectId
        self.companyId = companyId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.color = color
        self.type = type
        self.taskId = nil
        self.duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1
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
    
    /// Get SwiftUI Color from hex string
    var swiftUIColor: Color {
        return Color(hex: color) ?? Color.blue
    }
    
    /// Get display icon based on type
    var displayIcon: String? {
        if type == .task, let task = task {
            return task.taskType?.icon
        }
        return nil
    }
    
    /// Get subtitle for display
    var subtitle: String {
        if let project = project {
            return project.clientName
        }
        return ""
    }
    
    /// Check if event spans multiple days
    var isMultiDay: Bool {
        return !Calendar.current.isDate(startDate, inSameDayAs: endDate)
    }
    
    /// Get all dates this event spans
    var spannedDates: [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        var currentDate = startDate
        
        // For single-day events
        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return [startDate]
        }
        
        // For multi-day events
        while currentDate <= endDate {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dates
    }
    
    /// Create from a Project (for projects without tasks)
    static func fromProject(_ project: Project, companyDefaultColor: String) -> CalendarEvent? {
        guard let startDate = project.startDate else { return nil }
        
        let endDate = project.effectiveEndDate ?? startDate
        
        let event = CalendarEvent(
            id: "project-\(project.id)",
            projectId: project.id,
            companyId: project.companyId,
            title: project.title,
            startDate: startDate,
            endDate: endDate,
            color: companyDefaultColor,
            type: .project
        )
        
        event.project = project
        event.teamMembers = project.teamMembers
        event.setTeamMemberIds(project.getTeamMemberIds())
        
        return event
    }
    
    /// Create from a Task
    static func fromTask(_ task: ProjectTask, startDate: Date, endDate: Date) -> CalendarEvent {
        let event = CalendarEvent(
            id: "task-\(task.id)",
            projectId: task.projectId,
            companyId: task.companyId,
            title: task.displayTitle,
            startDate: startDate,
            endDate: endDate,
            color: task.effectiveColor,
            type: .task
        )
        
        event.taskId = task.id
        event.task = task
        event.project = task.project
        event.teamMembers = task.teamMembers
        event.setTeamMemberIds(task.getTeamMemberIds())
        
        return event
    }
}