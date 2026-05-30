//
//  TaskType.swift
//  OPS
//
//  TaskType model for defining reusable task templates
//

import Foundation
import SwiftData

/// TaskType model - reusable task templates for a company
@Model
final class TaskType: Identifiable {
    // MARK: - Properties
    var id: String
    var color: String  // Hex color code
    var display: String  // Display name (e.g., "Quote", "Installation")
    var icon: String?  // SF Symbol name
    var isDefault: Bool
    var companyId: String
    var displayOrder: Int = 0
    var defaultTeamMemberIdsString: String = ""  // Default crew user IDs for auto-generated tasks
    var dependenciesJSON: String = "[]"  // JSON array of TaskTypeDependency objects
    var isWeatherDependent: Bool = false  // Stub for future weather-aware scheduling
    /// Default duration in days for newly-created tasks of this type. Used by
    /// `TaskPairSpawner` when auto-spawning paired tasks; also used as a hint
    /// when generating tasks from line items. Editable in TaskTypeSheet.
    var defaultDuration: Int = 1

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify, inverse: \ProjectTask.taskType)
    var tasks: [ProjectTask] = []

    /// Reminder templates attached to this TaskType — instantiated as
    /// `TaskReminder` rows on every ProjectTask of this type. See bug 4f00c2d7.
    @Relationship(deleteRule: .cascade, inverse: \TaskTypeReminder.taskType)
    var reminderTemplates: [TaskTypeReminder] = []

    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    // MARK: - Initialization
    init(
        id: String,
        display: String,
        color: String,
        companyId: String,
        isDefault: Bool = false,
        icon: String? = nil
    ) {
        self.id = id
        self.display = display
        self.color = color
        self.companyId = companyId
        self.isDefault = isDefault
        self.icon = icon
        self.displayOrder = 0
    }
    
    // MARK: - Dependencies (computed from JSON)

    /// Decoded dependency list. SwiftData can't store Codable arrays directly,
    /// so we persist as JSON string and decode on access.
    var dependencies: [TaskTypeDependency] {
        get {
            guard let data = dependenciesJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TaskTypeDependency].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                dependenciesJSON = json
            }
        }
    }

    // MARK: - Helper Methods

    /// Check if user can edit this task type
    func canEdit(user: User) -> Bool {
        return PermissionStore.shared.can("tasks.create")
    }
    
    /// Check if this task type can be deleted
    var canDelete: Bool {
        // Default task types cannot be deleted
        // Also block if any active tasks are using this type
        return !isDefault && tasks.allSatisfy { $0.deletedAt != nil }
    }
    
    // MARK: - Default Task Types
    
    /// Predefined icons for task types (used in sequence)
    static let predefinedIcons = [
        "hammer.fill",         // General construction/installation
        "wrench.fill",        // Service/repair
        "paintbrush.fill",    // Painting/finishing
        "ruler.fill",         // Measurement/planning
        "doc.text.fill",      // Documentation/quotes
        "checkmark.circle.fill", // Inspection/completion
        "shippingbox.fill",   // Materials/delivery
        "bolt.fill",          // Electrical
        "drop.fill",          // Plumbing
        "house.fill"          // General/other
    ]
    
    /// Get an icon for a task type based on its display order or index
    static func getIcon(for index: Int) -> String {
        let iconIndex = index % predefinedIcons.count
        return predefinedIcons[iconIndex]
    }
    
    /// Assign icons to task types that don't have them
    static func assignIconsToTaskTypes(_ taskTypes: [TaskType]) {
        let sorted = taskTypes.sorted { $0.displayOrder < $1.displayOrder }
        for (index, taskType) in sorted.enumerated() {
            if taskType.icon == nil || taskType.icon?.isEmpty == true {
                taskType.icon = getIcon(for: index)
            }
        }
    }
    
    /// Create default task types for a company
    static func createDefaults(companyId: String) -> [TaskType] {
        return [
            TaskType(
                id: UUID().uuidString,
                display: "Site Estimate",
                color: "#A5B368",  // Green
                companyId: companyId,
                isDefault: true,
                icon: "clipboard.fill"
            ),
            TaskType(
                id: UUID().uuidString,
                display: "Quote/Proposal",
                color: "#59779F",  // Blue
                companyId: companyId,
                isDefault: true,
                icon: "doc.text.fill"
            ),
            TaskType(
                id: UUID().uuidString,
                display: "Material Order",
                color: "#C4A868",  // Amber
                companyId: companyId,
                isDefault: true,
                icon: "shippingbox.fill"
            ),
            TaskType(
                id: UUID().uuidString,
                display: "Installation",
                color: "#931A32",  // Red
                companyId: companyId,
                isDefault: true,
                icon: "hammer.fill"
            ),
            TaskType(
                id: UUID().uuidString,
                display: "Inspection",
                color: "#7B68A6",  // Purple
                companyId: companyId,
                isDefault: true,
                icon: "magnifyingglass"
            ),
            TaskType(
                id: UUID().uuidString,
                display: "Completion",
                color: "#4A4A4A",  // Gray
                companyId: companyId,
                isDefault: true,
                icon: "checkmark.circle.fill"
            )
        ]
    }
}

// MARK: - Hashable
extension TaskType: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TaskType, rhs: TaskType) -> Bool {
        lhs.id == rhs.id
    }
}
