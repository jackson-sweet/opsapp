//
//  CalendarEvent.swift
//  OPS
//
//  CalendarEvent model for unified calendar display
//

import Foundation
import SwiftData
import SwiftUI

/// CalendarEvent model - represents task schedules displayed on the calendar
@Model
final class CalendarEvent {
    // MARK: - Properties
    var id: String
    var color: String  // Hex color code
    var companyId: String
    var projectId: String
    var taskId: String?  // Optional - links to task
    var duration: Int  // Days
    var endDate: Date?
    var startDate: Date?
    var title: String

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

    // Soft delete support
    var deletedAt: Date?

    // MARK: - Initialization
    init(
        id: String,
        projectId: String,
        companyId: String,
        title: String,
        startDate: Date?,
        endDate: Date?,
        color: String
    ) {
        self.id = id
        self.projectId = projectId
        self.companyId = companyId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.color = color
        self.taskId = nil
        if let start = startDate, let end = endDate {
            let daysDiff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            self.duration = daysDiff + 1  // Add 1 to include both start and end days
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

    /// Get the display color hex string
    var displayColor: String {
        return color
    }

    /// Get display icon based on task type
    var displayIcon: String? {
        return task?.taskType?.icon
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

    /// Create from a Task
    static func fromTask(_ task: ProjectTask, startDate: Date?, endDate: Date?) -> CalendarEvent {
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
            color: task.effectiveColor
        )

        print("[CAL_EVENT_FROM_TASK] ✅ Calendar event created with color: \(event.color)")

        event.taskId = task.id
        event.task = task
        event.project = task.project
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
