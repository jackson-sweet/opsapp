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
    var endDate: Date?
    var startDate: Date?
    var title: String
    var type: CalendarEventType
    var projectEventType: CalendarEventType? // Cached from parent project for efficient filtering
    var active: Bool = true  // Whether this event is active (based on project scheduling mode)

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
        startDate: Date?,
        endDate: Date?,
        color: String,
        type: CalendarEventType,
        active: Bool = true
    ) {
        self.id = id
        self.projectId = projectId
        self.companyId = companyId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.color = color
        self.type = type
        self.active = active
        self.taskId = nil
        self.projectEventType = nil // Will be set when linked to project
        if let start = startDate, let end = endDate {
            self.duration = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
        } else {
            self.duration = 1
        }
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
            return project.effectiveClientName
        }
        return ""
    }
    
    /// Check if event spans multiple days
    var isMultiDay: Bool {
        guard let start = startDate, let end = endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }
    
    /// Get all dates this event spans
    var spannedDates: [Date] {
        guard let start = startDate, let end = endDate else { return [] }

        var dates: [Date] = []
        let calendar = Calendar.current
        var currentDate = start

        // For single-day events
        if calendar.isDate(start, inSameDayAs: end) {
            return [start]
        }

        // For multi-day events
        while currentDate <= end {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return dates
    }
    
    // MARK: - Display Logic
    
    /// Determines if this calendar event should be displayed
    var shouldDisplay: Bool {
        // First check if the event is active
        guard active else { return false }

        // We need to check the parent project's scheduling mode to determine
        // which type of calendar events to show

        // If we have cached the project's eventType, use it for efficient filtering
        if let projectEventType = projectEventType {
            if projectEventType == .project {
                // Project uses traditional scheduling - show only project-level events
                return type == .project && taskId == nil
            } else {
                // Project uses task-based scheduling - show only task events
                return type == .task && taskId != nil
            }
        }

        // Fallback: if projectEventType not cached, try to get it from the relationship
        if let project = project {
            // Note: We cannot cache here since this is a computed property
            // The caching should happen during sync in SyncManager

            if project.effectiveEventType == .project {
                // Project uses traditional scheduling - show only project-level events
                return type == .project && taskId == nil
            } else {
                // Project uses task-based scheduling - show only task events
                return type == .task && taskId != nil
            }
        }

        // If we can't determine the project's scheduling mode, default to showing
        // project-level events only (to avoid duplication)
        return type == .project && taskId == nil
    }
    
    /// Updates the cached project event type for efficient filtering
    func updateProjectEventTypeCache(from project: Project) {
        self.projectEventType = project.effectiveEventType
        // Update active status based on project's scheduling mode
        updateActiveStatus(for: project)
    }

    /// Updates the active status based on project's scheduling mode
    func updateActiveStatus(for project: Project) {
        if project.effectiveEventType == .project {
            // Project uses traditional scheduling - activate project events, deactivate task events
            self.active = (type == .project && taskId == nil)
        } else {
            // Project uses task-based scheduling - activate task events, deactivate project events
            self.active = (type == .task && taskId != nil)
        }
    }
    
    /// Determines if this calendar event should be displayed for a given project
    func shouldDisplay(for project: Project) -> Bool {
        // Must belong to this project
        guard projectId == project.id else { return false }
        
        // Cache the project's eventType for future use
        updateProjectEventTypeCache(from: project)
        
        if project.effectiveEventType == .project {
            // Project uses traditional scheduling - show only project-level events
            return type == .project && taskId == nil
        } else {
            // Project uses task-based scheduling - show only task events
            return type == .task && taskId != nil
        }
    }
    
    /// Check if this is a project-level event (not task-based)
    var isProjectLevelEvent: Bool {
        return type == .project && taskId == nil
    }
    
    /// Check if this is a task-based event
    var isTaskEvent: Bool {
        return type == .task && taskId != nil
    }
    
    /// Create from a Project (for projects without tasks)
    static func fromProject(_ project: Project, companyDefaultColor: String) -> CalendarEvent? {
        guard let startDate = project.startDate else { return nil }

        let endDate = project.effectiveEndDate ?? startDate

        // Determine if this project event should be active
        let isActive = project.effectiveEventType == .project

        let event = CalendarEvent(
            id: "project-\(project.id)",
            projectId: project.id,
            companyId: project.companyId,
            title: project.title,
            startDate: startDate,
            endDate: endDate,
            color: companyDefaultColor,
            type: .project,
            active: isActive
        )

        event.project = project
        event.projectEventType = project.effectiveEventType // Cache the project's scheduling mode
        event.teamMembers = project.teamMembers
        event.setTeamMemberIds(project.getTeamMemberIds())

        return event
    }
    
    /// Create from a Task
    static func fromTask(_ task: ProjectTask, startDate: Date?, endDate: Date?) -> CalendarEvent {
        // Determine if this task event should be active
        let isActive = task.project?.effectiveEventType == .task

        // Use project's client name as the title
        let eventTitle = task.project?.effectiveClientName ?? task.displayTitle

        print("[CAL_EVENT_FROM_TASK] 🎨 Creating calendar event from task")
        print("[CAL_EVENT_FROM_TASK] Task ID: \(task.id)")
        print("[CAL_EVENT_FROM_TASK] Task Color: \(task.taskColor)")
        print("[CAL_EVENT_FROM_TASK] Task Type: \(task.taskType?.display ?? "nil")")
        print("[CAL_EVENT_FROM_TASK] Task Type Color: \(task.taskType?.color ?? "nil")")
        print("[CAL_EVENT_FROM_TASK] Effective Color: \(task.effectiveColor)")

        let event = CalendarEvent(
            id: "task-\(task.id)",
            projectId: task.projectId,
            companyId: task.companyId,
            title: eventTitle,
            startDate: startDate,
            endDate: endDate,
            color: task.effectiveColor,
            type: .task,
            active: isActive
        )

        print("[CAL_EVENT_FROM_TASK] ✅ Calendar event created with color: \(event.color)")

        event.taskId = task.id
        event.task = task
        event.project = task.project
        event.projectEventType = task.project?.effectiveEventType // Cache the project's scheduling mode
        event.teamMembers = task.teamMembers
        event.setTeamMemberIds(task.getTeamMemberIds())

        return event
    }
}

// MARK: - Hashable Conformance
extension CalendarEvent: Hashable {
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}