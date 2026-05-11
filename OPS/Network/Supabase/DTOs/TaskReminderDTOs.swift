//
//  TaskReminderDTOs.swift
//  OPS
//
//  Wire-format DTOs for task_type_reminders (template) and task_reminders
//  (per-task instance). Mirrors the Postgres tables added in migration
//  task_reminders_schema. See ops-software-bible §23 and
//  docs/superpowers/specs/2026-05-10-task-reminders-design.md.
//

import Foundation

// MARK: - Helpers

/// Wire format for the time-of-day column. Postgres returns `HH:mm:ss` text.
private enum ReminderTime {
    /// Parse 'HH:mm[:ss]' into seconds-since-midnight. Returns 9*3600 (09:00)
    /// on any malformed input so a bad row doesn't crash the row decoder.
    static func parseSeconds(_ s: String?) -> Int {
        guard let s = s else { return 9 * 3600 }
        let parts = s.split(separator: ":").map(String.init)
        let h = parts.count > 0 ? Int(parts[0]) ?? 9 : 9
        let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let sec = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        return h * 3600 + m * 60 + sec
    }

    /// Render seconds-since-midnight back to `HH:mm:ss`.
    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

private enum ReminderJSONB {
    /// jsonb is sent over the wire as either a raw object (when fetched) or
    /// any-codable. Postgrest with Supabase-Swift typically decodes jsonb as
    /// `AnyJSON` — we re-encode it back to a JSON string for storage in the
    /// SwiftData column. Returns "{}" on any failure.
    static func encode(_ config: ReminderRecipientConfig) -> String {
        guard let data = try? JSONEncoder().encode(config),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func decode(_ json: String?) -> ReminderRecipientConfig {
        guard let json = json, let data = json.data(using: .utf8) else { return .empty }
        return (try? JSONDecoder().decode(ReminderRecipientConfig.self, from: data)) ?? .empty
    }
}

// MARK: - Template

struct TaskTypeReminderDTO: Codable, Identifiable {
    let id: String
    let taskTypeId: String
    let companyId: String
    let label: String
    let leadTimeDays: Int
    let fireTimeLocal: String           // "HH:mm:ss"
    let requiresAck: Bool
    let recipientMode: String
    let recipientConfig: ReminderRecipientConfig
    let displayOrder: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskTypeId       = "task_type_id"
        case companyId        = "company_id"
        case label
        case leadTimeDays     = "lead_time_days"
        case fireTimeLocal    = "fire_time_local"
        case requiresAck      = "requires_ack"
        case recipientMode    = "recipient_mode"
        case recipientConfig  = "recipient_config"
        case displayOrder     = "display_order"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case deletedAt        = "deleted_at"
    }

    /// Hydrate or update a local SwiftData row from this DTO.
    func apply(to row: TaskTypeReminder) {
        row.taskTypeId           = taskTypeId
        row.companyId            = companyId
        row.label                = label
        row.leadTimeDays         = leadTimeDays
        row.fireTimeLocalSeconds = ReminderTime.parseSeconds(fireTimeLocal)
        row.requiresAck          = requiresAck
        row.recipientModeRaw     = recipientMode
        row.recipientConfigJSON  = ReminderJSONB.encode(recipientConfig)
        row.displayOrder         = displayOrder
        row.deletedAt            = deletedAt.flatMap(SupabaseDate.parse)
        row.lastSyncedAt         = Date()
        row.needsSync            = false
    }

    /// Build a new SwiftData row from this DTO.
    func makeLocalRow() -> TaskTypeReminder {
        let row = TaskTypeReminder(
            id: id,
            taskTypeId: taskTypeId,
            companyId: companyId,
            label: label,
            leadTimeDays: leadTimeDays,
            fireTimeLocalSeconds: ReminderTime.parseSeconds(fireTimeLocal),
            requiresAck: requiresAck,
            recipientMode: ReminderRecipientMode(rawValue: recipientMode) ?? .taskCrew,
            recipientConfig: recipientConfig,
            displayOrder: displayOrder
        )
        row.deletedAt    = deletedAt.flatMap(SupabaseDate.parse)
        row.lastSyncedAt = Date()
        row.needsSync    = false
        return row
    }
}

struct CreateTaskTypeReminderDTO: Codable {
    let taskTypeId: String
    let companyId: String
    let label: String
    let leadTimeDays: Int
    let fireTimeLocal: String
    let requiresAck: Bool
    let recipientMode: String
    let recipientConfig: ReminderRecipientConfig
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case taskTypeId       = "task_type_id"
        case companyId        = "company_id"
        case label
        case leadTimeDays     = "lead_time_days"
        case fireTimeLocal    = "fire_time_local"
        case requiresAck      = "requires_ack"
        case recipientMode    = "recipient_mode"
        case recipientConfig  = "recipient_config"
        case displayOrder     = "display_order"
    }

    init(from row: TaskTypeReminder) {
        self.taskTypeId      = row.taskTypeId
        self.companyId       = row.companyId
        self.label           = row.label
        self.leadTimeDays    = row.leadTimeDays
        self.fireTimeLocal   = ReminderTime.format(row.fireTimeLocalSeconds)
        self.requiresAck     = row.requiresAck
        self.recipientMode   = row.recipientModeRaw
        self.recipientConfig = row.recipientConfig
        self.displayOrder    = row.displayOrder
    }
}

struct UpdateTaskTypeReminderDTO: Codable {
    let label: String
    let leadTimeDays: Int
    let fireTimeLocal: String
    let requiresAck: Bool
    let recipientMode: String
    let recipientConfig: ReminderRecipientConfig
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case label
        case leadTimeDays     = "lead_time_days"
        case fireTimeLocal    = "fire_time_local"
        case requiresAck      = "requires_ack"
        case recipientMode    = "recipient_mode"
        case recipientConfig  = "recipient_config"
        case displayOrder     = "display_order"
    }

    init(from row: TaskTypeReminder) {
        self.label           = row.label
        self.leadTimeDays    = row.leadTimeDays
        self.fireTimeLocal   = ReminderTime.format(row.fireTimeLocalSeconds)
        self.requiresAck     = row.requiresAck
        self.recipientMode   = row.recipientModeRaw
        self.recipientConfig = row.recipientConfig
        self.displayOrder    = row.displayOrder
    }
}

struct SoftDeleteDTO: Codable {
    let deletedAt: String
    enum CodingKeys: String, CodingKey { case deletedAt = "deleted_at" }
    init(at date: Date = Date()) {
        self.deletedAt = SupabaseDate.format(date)
    }
}

// MARK: - Instance

struct TaskReminderDTO: Codable, Identifiable {
    let id: String
    let taskId: String
    let companyId: String
    let sourceTemplateId: String?
    let label: String
    let leadTimeDays: Int
    let fireTimeLocal: String
    let requiresAck: Bool
    let recipientMode: String
    let recipientConfig: ReminderRecipientConfig
    let firesAt: String?
    let acknowledgedAt: String?
    let acknowledgedBy: String?
    let dismissedAt: String?
    let notifiedAt: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId              = "task_id"
        case companyId           = "company_id"
        case sourceTemplateId    = "source_template_id"
        case label
        case leadTimeDays        = "lead_time_days"
        case fireTimeLocal       = "fire_time_local"
        case requiresAck         = "requires_ack"
        case recipientMode       = "recipient_mode"
        case recipientConfig     = "recipient_config"
        case firesAt             = "fires_at"
        case acknowledgedAt      = "acknowledged_at"
        case acknowledgedBy      = "acknowledged_by"
        case dismissedAt         = "dismissed_at"
        case notifiedAt          = "notified_at"
        case createdAt           = "created_at"
        case updatedAt           = "updated_at"
        case deletedAt           = "deleted_at"
    }

    func apply(to row: TaskReminder) {
        row.taskId              = taskId
        row.companyId           = companyId
        row.sourceTemplateId    = sourceTemplateId
        row.label               = label
        row.leadTimeDays        = leadTimeDays
        row.fireTimeLocalSeconds = ReminderTime.parseSeconds(fireTimeLocal)
        row.requiresAck         = requiresAck
        row.recipientModeRaw    = recipientMode
        row.recipientConfigJSON = ReminderJSONB.encode(recipientConfig)
        row.firesAt             = firesAt.flatMap(SupabaseDate.parse)
        row.acknowledgedAt      = acknowledgedAt.flatMap(SupabaseDate.parse)
        row.acknowledgedBy      = acknowledgedBy
        row.dismissedAt         = dismissedAt.flatMap(SupabaseDate.parse)
        row.notifiedAt          = notifiedAt.flatMap(SupabaseDate.parse)
        row.deletedAt           = deletedAt.flatMap(SupabaseDate.parse)
        row.lastSyncedAt        = Date()
        row.needsSync           = false
    }

    func makeLocalRow() -> TaskReminder {
        let row = TaskReminder(
            id: id,
            taskId: taskId,
            companyId: companyId,
            sourceTemplateId: sourceTemplateId,
            label: label,
            leadTimeDays: leadTimeDays,
            fireTimeLocalSeconds: ReminderTime.parseSeconds(fireTimeLocal),
            requiresAck: requiresAck,
            recipientMode: ReminderRecipientMode(rawValue: recipientMode) ?? .taskCrew,
            recipientConfig: recipientConfig,
            firesAt: firesAt.flatMap(SupabaseDate.parse)
        )
        row.acknowledgedAt = acknowledgedAt.flatMap(SupabaseDate.parse)
        row.acknowledgedBy = acknowledgedBy
        row.dismissedAt    = dismissedAt.flatMap(SupabaseDate.parse)
        row.notifiedAt     = notifiedAt.flatMap(SupabaseDate.parse)
        row.deletedAt      = deletedAt.flatMap(SupabaseDate.parse)
        row.lastSyncedAt   = Date()
        row.needsSync      = false
        return row
    }
}

struct AcknowledgeReminderDTO: Codable {
    let acknowledgedAt: String
    let acknowledgedBy: String

    enum CodingKeys: String, CodingKey {
        case acknowledgedAt = "acknowledged_at"
        case acknowledgedBy = "acknowledged_by"
    }

    init(userId: String, at date: Date = Date()) {
        self.acknowledgedAt = SupabaseDate.format(date)
        self.acknowledgedBy = userId
    }
}

struct DismissReminderDTO: Codable {
    let dismissedAt: String
    enum CodingKeys: String, CodingKey { case dismissedAt = "dismissed_at" }
    init(at date: Date = Date()) {
        self.dismissedAt = SupabaseDate.format(date)
    }
}
