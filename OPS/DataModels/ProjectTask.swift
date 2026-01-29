//
//  Task.swift
//  OPS
//
//  Task model for task-based scheduling system
//

import Foundation
import SwiftData
import SwiftUI

/// Status enum for tasks - simplified 3-state system
enum TaskStatus: String, Codable, CaseIterable {
    case active = "Active"
    case completed = "Completed"
    case cancelled = "Cancelled"

    // Custom decoder to handle migration from legacy statuses
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle legacy statuses by mapping to "Active"
        switch rawValue {
        case "Scheduled", "Booked", "In Progress":
            self = .active
        case "Completed":
            self = .completed
        case "Cancelled":
            self = .cancelled
        default:
            if let status = TaskStatus(rawValue: rawValue) {
                self = status
            } else {
                // Default unknown statuses to active
                self = .active
            }
        }
    }

    var displayName: String {
        return self.rawValue
    }

    var color: Color {
        switch self {
        case .active:
            return Color("StatusInProgress")
        case .completed:
            return Color("StatusCompleted")
        case .cancelled:
            return Color("StatusInactive")
        }
    }

    /// Toggle between active and completed
    func toggled() -> TaskStatus {
        switch self {
        case .active: return .completed
        case .completed: return .active
        case .cancelled: return .active // Reactivate cancelled tasks
        }
    }

    /// Whether this task can be toggled (cancelled tasks can be reactivated)
    var canToggle: Bool {
        return true
    }

    /// Whether this task is in a terminal state
    var isTerminal: Bool {
        return self == .completed || self == .cancelled
    }

    var sortOrder: Int {
        switch self {
        case .active: return 0
        case .completed: return 1
        case .cancelled: return 2
        }
    }

    // MARK: - Swipe Navigation (for UniversalJobBoardCard)

    /// Next status when swiping right (forward)
    func nextStatus() -> TaskStatus? {
        switch self {
        case .active: return .completed
        case .completed: return nil // Already complete
        case .cancelled: return .active // Reactivate
        }
    }

    /// Previous status when swiping left (backward)
    func previousStatus() -> TaskStatus? {
        switch self {
        case .active: return nil // Can't go back from active
        case .completed: return .active // Reopen
        case .cancelled: return nil // Can't go back from cancelled
        }
    }

    var canSwipeForward: Bool {
        return nextStatus() != nil
    }

    var canSwipeBackward: Bool {
        return previousStatus() != nil
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
    var taskIndex: Int?  // Index for task ordering within project (based on startDate)
    var displayOrder: Int = 0
    var customTitle: String?  // Optional custom title for task (overrides taskType.display)

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

    // Soft delete support
    var deletedAt: Date?
    
    // MARK: - Initialization
    init(
        id: String,
        projectId: String,
        taskTypeId: String,
        companyId: String,
        status: TaskStatus = .active,
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
    
    /// Get display title (custom title, TaskType, or fallback)
    var displayTitle: String {
        if let customTitle = customTitle, !customTitle.isEmpty {
            return customTitle
        }
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
    
    // MARK: - Computed Properties for Dates
    
    /// Get scheduled date from calendar event
    var scheduledDate: Date? {
        return calendarEvent?.startDate
    }
    
    /// Get completion/end date from calendar event
    var completionDate: Date? {
        return calendarEvent?.endDate
    }
    
    /// Check if task is overdue
    var isOverdue: Bool {
        guard status != .completed && status != .cancelled,
              let endDate = completionDate else { return false }
        return Date() > endDate
    }
    
    /// Check if task is happening today
    var isToday: Bool {
        guard let startDate = scheduledDate else { return false }
        return Calendar.current.isDateInToday(startDate)
    }
    
    // MARK: - Calendar Event Date Synchronization
    
    /// Update calendar event dates when task needs rescheduling
    func updateCalendarEventDates(startDate: Date, endDate: Date) {
        guard let calendarEvent = calendarEvent else { return }
        
        // Update calendar event to match new task dates
        calendarEvent.startDate = startDate
        calendarEvent.endDate = endDate
        calendarEvent.duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1
    }
    
    /// Sync task metadata with calendar event
    func syncWithCalendarEvent() {
        guard let calendarEvent = calendarEvent else { return }
        
        // Update calendar event metadata
        calendarEvent.title = displayTitle
        calendarEvent.color = effectiveColor
        calendarEvent.setTeamMemberIds(getTeamMemberIds())
        calendarEvent.teamMembers = teamMembers
    }
}