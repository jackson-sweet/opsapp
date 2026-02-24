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
    case booked = "booked"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"

    // Custom decoder to handle legacy title-case values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "Scheduled", "Booked": self = .booked
        case "In Progress": self = .inProgress
        case "Completed": self = .completed
        case "Cancelled": self = .cancelled
        default:
            if let status = TaskStatus(rawValue: rawValue) {
                self = status
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot initialize TaskStatus from invalid String value \(rawValue)"
                )
            }
        }
    }

    var displayName: String {
        switch self {
        case .booked: return "Booked"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
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
    var companyId: String
    var status: TaskStatus
    var taskColor: String  // Hex color code
    var taskNotes: String?
    var taskTypeId: String
    var taskIndex: Int?  // Index for task ordering within project (based on startDate)
    var displayOrder: Int = 0
    var customTitle: String?  // Optional custom title for task (overrides taskType.display)
    var sourceLineItemId: String?   // Supabase LineItem UUID this task was generated from
    var sourceEstimateId: String?   // Supabase Estimate UUID this task was generated from

    // MARK: - Scheduling (merged from CalendarEvent)
    var startDate: Date?
    var endDate: Date?
    var duration: Int = 1  // Duration in days

    // Store team member IDs as string (for compatibility with existing patterns)
    var teamMemberIdsString: String = ""
    
    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var project: Project?
    
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
        self.startDate = nil
        self.endDate = nil
        self.duration = 1
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

    var scheduledDate: Date? { startDate }
    var completionDate: Date? { endDate }

    var isOverdue: Bool {
        guard status != .completed && status != .cancelled,
              let end = endDate else { return false }
        return Date() > end
    }

    var isToday: Bool {
        guard let start = startDate else { return false }
        return Calendar.current.isDateInToday(start)
    }

    /// Update scheduling dates
    func updateDates(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
        self.duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1
    }

    // MARK: - Scheduling Display Helpers (migrated from CalendarEvent)

    var swiftUIColor: Color {
        return Color(hex: effectiveColor) ?? Color.blue
    }

    var isMultiDay: Bool {
        guard let start = startDate, let end = endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }

    var spannedDates: [Date] {
        guard let start = startDate, let end = endDate else { return [] }
        let calendar = Calendar.current
        if calendar.isDate(start, inSameDayAs: end) { return [start] }
        var dates: [Date] = []
        var currentDate = start
        while currentDate <= end {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        return dates
    }

    var calendarSubtitle: String {
        if let project = project { return project.effectiveClientName }
        return ""
    }

    var displayIcon: String? { taskType?.icon }
}