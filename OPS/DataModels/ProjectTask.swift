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
    case active = "active"
    case completed = "completed"
    case cancelled = "cancelled"

    // Custom decoder to handle legacy values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "Scheduled", "Booked", "booked", "In Progress", "in_progress": self = .active
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
        case .active: return "Active"
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

    // MARK: - Precise Scheduling (time-of-day)
    var startTime: Date = {
        Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    }()
    var endTime: Date = {
        Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
    }()

    // MARK: - Dependency Overrides
    var dependencyOverridesJSON: String?  // JSON array of TaskTypeDependency; nil = use taskType defaults

    // MARK: - Pair Linkage
    /// ID of the predecessor task that auto-spawned this task. nil if this
    /// task was created manually or by another path (line-item generation, sync).
    /// Used for cascading delete/cancel and unambiguous pairing when a project
    /// has multiple instances of the same predecessor type.
    var pairedFromTaskId: String?

    /// True after the user has manually edited this task's start date.
    /// The dependency cascade respects this flag — once locked, predecessor
    /// movements no longer auto-shift this task. Reset by deleting/recreating.
    var scheduleLocked: Bool = false

    // Store team member IDs as string (for compatibility with existing patterns)
    var teamMemberIdsString: String = ""
    
    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var project: Project?
    
    @Relationship(deleteRule: .nullify)
    var taskType: TaskType?
    
    @Relationship(deleteRule: .noAction)
    var teamMembers: [User] = []

    /// Reminder instances on this task. Materialized server-side via triggers
    /// from the parent TaskType's reminder templates. See bug 4f00c2d7.
    @Relationship(deleteRule: .cascade, inverse: \TaskReminder.task)
    var reminders: [TaskReminder] = []

    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    // Audit — when this task was created. Added 2026-05-10 to give
    // recency-sorted task type and team-member pickers a stable signal that
    // doesn't drift on every edit-sync (unlike `lastSyncedAt`).
    var createdAt: Date?

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
    
    var schedulingTeamMemberIds: Set<String> {
        Set(getTeamMemberIds())
    }

    var schedulingProjectId: String {
        projectId
    }

    /// SchedulableTask conformance — surfaces `scheduleLocked` to
    /// `SchedulingEngine` so the cascade can skip user-edited paired tasks.
    var schedulingLocked: Bool {
        scheduleLocked
    }

    /// SchedulableTask conformance — only active tasks are eligible for
    /// auto-schedule placement. Completed/cancelled tasks are never placed,
    /// even if their dates are null.
    var schedulingIsActive: Bool {
        status == .active
    }

    /// Get team member IDs as array
    func getTeamMemberIds() -> [String] {
        return teamMemberIdsString.isEmpty ? [] : teamMemberIdsString.components(separatedBy: ",")
    }
    
    /// Set team member IDs from array. Canonicalizes each id to lowercase so
    /// the CSV matches Postgres's stored uuid casing, which is what
    /// `linkAllRelationships` and merge-path rewires look up User by.
    func setTeamMemberIds(_ ids: [String]) {
        teamMemberIdsString = ids.map { $0.lowercased() }.joined(separator: ",")
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
        return PermissionStore.shared.can("tasks.edit")
    }
    
    /// Check if user can update status
    func canUpdateStatus(user: User) -> Bool {
        // All users can update task status
        return true
    }
    
    // MARK: - Dependency Helpers

    /// Returns per-task overrides if set, otherwise falls back to taskType.dependencies.
    var effectiveDependencies: [TaskTypeDependency] {
        if let json = dependencyOverridesJSON,
           let data = json.data(using: .utf8),
           let overrides = try? JSONDecoder().decode([TaskTypeDependency].self, from: data) {
            return overrides
        }
        return taskType?.dependencies ?? []
    }

    /// Persist dependency overrides as JSON string.
    func setDependencyOverrides(_ deps: [TaskTypeDependency]) {
        if let data = try? JSONEncoder().encode(deps),
           let json = String(data: data, encoding: .utf8) {
            dependencyOverridesJSON = json
        }
    }

    /// Check if this task depends on a given task type.
    func dependsOn(taskTypeId: String) -> Bool {
        return effectiveDependencies.contains { $0.dependsOnTaskTypeId == taskTypeId }
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

// MARK: - SchedulableTask Conformance
extension ProjectTask: SchedulableTask {}