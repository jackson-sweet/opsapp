//
//  TaskReminder.swift
//  OPS
//
//  Per-ProjectTask reminder instance. Materialized server-side via the
//  task_type_reminders → project_tasks live-link triggers. Carries snapshotted
//  template fields plus per-instance state (acknowledged_at, dismissed_at,
//  notified_at, fires_at). See docs/superpowers/specs/2026-05-10-task-reminders-design.md.
//

import Foundation
import SwiftData

@Model
final class TaskReminder: Identifiable {
    @Attribute(.unique) var id: String
    var taskId: String
    var companyId: String
    var sourceTemplateId: String?

    // Snapshot/live-link mirror of the template
    var label: String
    var leadTimeDays: Int
    var fireTimeLocalSeconds: Int
    var requiresAck: Bool
    var recipientModeRaw: String
    var recipientConfigJSON: String

    // State
    var firesAt: Date?
    var acknowledgedAt: Date?
    var acknowledgedBy: String?
    var dismissedAt: Date?
    var notifiedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    @Relationship(deleteRule: .nullify)
    var task: ProjectTask?

    init(
        id: String,
        taskId: String,
        companyId: String,
        sourceTemplateId: String?,
        label: String,
        leadTimeDays: Int,
        fireTimeLocalSeconds: Int,
        requiresAck: Bool,
        recipientMode: ReminderRecipientMode,
        recipientConfig: ReminderRecipientConfig,
        firesAt: Date? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.companyId = companyId
        self.sourceTemplateId = sourceTemplateId
        self.label = label
        self.leadTimeDays = leadTimeDays
        self.fireTimeLocalSeconds = fireTimeLocalSeconds
        self.requiresAck = requiresAck
        self.recipientModeRaw = recipientMode.rawValue
        let data = (try? JSONEncoder().encode(recipientConfig)) ?? Data("{}".utf8)
        self.recipientConfigJSON = String(data: data, encoding: .utf8) ?? "{}"
        self.firesAt = firesAt
    }

    // MARK: - Computed

    var recipientMode: ReminderRecipientMode {
        ReminderRecipientMode(rawValue: recipientModeRaw) ?? .taskCrew
    }

    var recipientConfig: ReminderRecipientConfig {
        guard let data = recipientConfigJSON.data(using: .utf8) else { return .empty }
        return (try? JSONDecoder().decode(ReminderRecipientConfig.self, from: data)) ?? .empty
    }

    /// True when the user has explicitly checked the reminder off. For
    /// `requiresAck` reminders this is the terminal cleared state; for
    /// non-ack reminders it indicates the optional "I did this" tick.
    var isAcknowledged: Bool { acknowledgedAt != nil }

    /// True when a non-ack reminder has been swiped/dismissed without ticking.
    var isDismissed: Bool { dismissedAt != nil }

    /// Cleared from the active checklist when acknowledged or dismissed or
    /// soft-deleted.
    var isCleared: Bool {
        isAcknowledged || isDismissed || deletedAt != nil
    }

    /// Display label for the lead-time badge in the checklist row.
    var leadTimeDisplay: String {
        switch leadTimeDays {
        case 0:  return "DAY OF"
        case 1:  return "1D BEFORE"
        case 7:  return "1W BEFORE"
        case 14: return "2W BEFORE"
        default: return "\(leadTimeDays)D BEFORE"
        }
    }

    /// Formatted due date for the row subhead, e.g. "due May 12".
    var dueDisplay: String? {
        guard let firesAt = firesAt else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "due \(fmt.string(from: firesAt))"
    }
}
