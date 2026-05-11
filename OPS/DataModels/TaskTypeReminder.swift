//
//  TaskTypeReminder.swift
//  OPS
//
//  Reminder template attached to a TaskType. Each row defines a per-template
//  reminder that gets materialized into a `TaskReminder` instance for every
//  open ProjectTask of that type. Server-side triggers handle propagation —
//  see ops-software-bible §23 and docs/superpowers/specs/2026-05-10-task-reminders-design.md.
//

import Foundation
import SwiftData

/// Allowed recipient modes for a task reminder template. Mirrors the CHECK
/// constraint on `task_type_reminders.recipient_mode`.
enum ReminderRecipientMode: String, Codable, CaseIterable {
    case taskCrew    = "task_crew"
    case admins      = "admins"
    case permission  = "permission"
    case users       = "users"

    var displayLabel: String {
        switch self {
        case .taskCrew:   return "TASK CREW"
        case .admins:     return "ADMINS"
        case .permission: return "PERMISSION"
        case .users:      return "SPECIFIC USERS"
        }
    }
}

/// Decoded shape of `recipient_config`. Empty for task_crew/admins; carries
/// a permission key for `permission` mode; carries a user_ids array for
/// `users` mode.
struct ReminderRecipientConfig: Codable, Equatable {
    var permission: String?
    var userIds: [String]?

    enum CodingKeys: String, CodingKey {
        case permission
        case userIds = "user_ids"
    }

    static let empty = ReminderRecipientConfig(permission: nil, userIds: nil)
}

@Model
final class TaskTypeReminder: Identifiable {
    @Attribute(.unique) var id: String
    var taskTypeId: String
    var companyId: String
    var label: String
    var leadTimeDays: Int
    var fireTimeLocalSeconds: Int            // seconds since midnight (0..86399)
    var requiresAck: Bool
    var recipientModeRaw: String             // ReminderRecipientMode.rawValue
    var recipientConfigJSON: String          // JSON-encoded ReminderRecipientConfig
    var displayOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    @Relationship(deleteRule: .nullify)
    var taskType: TaskType?

    init(
        id: String,
        taskTypeId: String,
        companyId: String,
        label: String,
        leadTimeDays: Int = 1,
        fireTimeLocalSeconds: Int = 9 * 3600,
        requiresAck: Bool = true,
        recipientMode: ReminderRecipientMode = .taskCrew,
        recipientConfig: ReminderRecipientConfig = .empty,
        displayOrder: Int = 0
    ) {
        self.id = id
        self.taskTypeId = taskTypeId
        self.companyId = companyId
        self.label = label
        self.leadTimeDays = leadTimeDays
        self.fireTimeLocalSeconds = fireTimeLocalSeconds
        self.requiresAck = requiresAck
        self.recipientModeRaw = recipientMode.rawValue
        self.displayOrder = displayOrder
        let data = (try? JSONEncoder().encode(recipientConfig)) ?? Data("{}".utf8)
        self.recipientConfigJSON = String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Computed

    var recipientMode: ReminderRecipientMode {
        get { ReminderRecipientMode(rawValue: recipientModeRaw) ?? .taskCrew }
        set { recipientModeRaw = newValue.rawValue }
    }

    var recipientConfig: ReminderRecipientConfig {
        get {
            guard let data = recipientConfigJSON.data(using: .utf8) else { return .empty }
            return (try? JSONDecoder().decode(ReminderRecipientConfig.self, from: data)) ?? .empty
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8)
            recipientConfigJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    /// Time-of-day display string (e.g. "09:00"). Time-only encoding lives in
    /// `fireTimeLocalSeconds`; we expose a Date-of-day for SwiftUI DatePicker.
    var fireTimeOfDay: Date {
        get {
            let comp = DateComponents(
                hour: fireTimeLocalSeconds / 3600,
                minute: (fireTimeLocalSeconds % 3600) / 60
            )
            return Calendar.current.date(from: comp) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            fireTimeLocalSeconds = (comps.hour ?? 9) * 3600 + (comps.minute ?? 0) * 60
        }
    }

    /// Pretty lead-time label for the editor list.
    var leadTimeDisplay: String {
        switch leadTimeDays {
        case 0:  return "Day of"
        case 1:  return "1 day before"
        case 7:  return "1 week before"
        case 14: return "2 weeks before"
        default: return "\(leadTimeDays) days before"
        }
    }
}
