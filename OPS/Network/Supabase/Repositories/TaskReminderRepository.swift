//
//  TaskReminderRepository.swift
//  OPS
//
//  Repository for task reminder template + instance operations via Supabase.
//  Tables: task_type_reminders (template), task_reminders (instance).
//
//  Live-link propagation is handled server-side via triggers — see
//  migration task_reminders_schema.sql. iOS writes template rows and
//  acknowledges/dismisses instances; the materialization happens in Postgres.
//

import Foundation
import Supabase

class TaskReminderRepository {
    static let shared = TaskReminderRepository()

    private let client: SupabaseClient

    init() {
        self.client = SupabaseService.shared.client
    }

    // MARK: - Templates

    /// Fetch all reminder templates for a company. Used by InboundProcessor
    /// to hydrate the local SwiftData store.
    func fetchTemplates(companyId: String, since: Date? = nil) async throws -> [TaskTypeReminderDTO] {
        var query = client
            .from("task_type_reminders")
            .select()
            .eq("company_id", value: companyId)
        if let since = since {
            query = query.gte("updated_at", value: SupabaseDate.format(since))
        }
        return try await query
            .order("display_order", ascending: true)
            .execute()
            .value
    }

    /// Fetch templates for a single task type — used when the user opens the
    /// editor sheet and needs a fresh list (in case web added templates in
    /// the background).
    func fetchTemplatesForTaskType(_ taskTypeId: String) async throws -> [TaskTypeReminderDTO] {
        try await client
            .from("task_type_reminders")
            .select()
            .eq("task_type_id", value: taskTypeId)
            .is("deleted_at", value: nil)
            .order("display_order", ascending: true)
            .execute()
            .value
    }

    func createTemplate(_ payload: CreateTaskTypeReminderDTO) async throws -> TaskTypeReminderDTO {
        try await client
            .from("task_type_reminders")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateTemplate(id: String, payload: UpdateTaskTypeReminderDTO) async throws -> TaskTypeReminderDTO {
        try await client
            .from("task_type_reminders")
            .update(payload)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func softDeleteTemplate(id: String) async throws {
        try await client
            .from("task_type_reminders")
            .update(SoftDeleteDTO())
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Instances

    /// Fetch reminder instances for a company. Used by InboundProcessor.
    func fetchInstances(companyId: String, since: Date? = nil) async throws -> [TaskReminderDTO] {
        var query = client
            .from("task_reminders")
            .select()
            .eq("company_id", value: companyId)
        if let since = since {
            query = query.gte("updated_at", value: SupabaseDate.format(since))
        }
        return try await query
            .order("fires_at", ascending: true)
            .execute()
            .value
    }

    /// Fetch instances for a specific task. Used by the project detail view
    /// when reading just-in-time on first render.
    func fetchInstancesForTask(_ taskId: String) async throws -> [TaskReminderDTO] {
        try await client
            .from("task_reminders")
            .select()
            .eq("task_id", value: taskId)
            .is("deleted_at", value: nil)
            .order("fires_at", ascending: true)
            .execute()
            .value
    }

    /// Mark a reminder acknowledged. Shared checkbox — last writer wins by
    /// design.
    func acknowledge(id: String, userId: String) async throws {
        let payload = AcknowledgeReminderDTO(userId: userId)
        try await client
            .from("task_reminders")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    /// Clear acknowledgement (un-tick). Used when the user accidentally
    /// taps and needs to undo before sync flushes.
    func unacknowledge(id: String) async throws {
        struct ClearAck: Codable {
            let acknowledged_at: String?
            let acknowledged_by: String?
        }
        try await client
            .from("task_reminders")
            .update(ClearAck(acknowledged_at: nil, acknowledged_by: nil))
            .eq("id", value: id)
            .execute()
    }

    func dismiss(id: String) async throws {
        try await client
            .from("task_reminders")
            .update(DismissReminderDTO())
            .eq("id", value: id)
            .execute()
    }
}
