//
//  TaskRepository.swift
//  OPS
//
//  Repository for ProjectTask entity operations via Supabase.
//  Table: project_tasks
//
//  Column note: task_notes (not notes), custom_title (not title), task_color (not color).
//  Scheduling dates (start_date, end_date, duration) are stored directly on project_tasks.
//

import Foundation
import Supabase

protocol ProjectTaskSyncing: AnyObject {
    func create(_ dto: SupabaseProjectTaskDTO) async throws -> SupabaseProjectTaskDTO
    func updateFields(_ taskId: String, fields: [String: AnyJSON]) async throws
    func softDelete(_ taskId: String) async throws
    func restore(_ taskId: String) async throws
    func completeProjectTask(
        taskId: String,
        idempotencyKey: String,
        materialAdjustments: [String: AnyJSON]
    ) async throws -> CompleteProjectTaskResponseDTO
}

class TaskRepository: ProjectTaskSyncing {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll(since: Date? = nil, scope: String = "all", userId: String? = nil) async throws -> [SupabaseProjectTaskDTO] {
        var query = client
            .from("project_tasks")
            .select()
            .eq("company_id", value: companyId)

        if let since = since {
            query = query.gte("updated_at", value: isoString(since))
        }

        // Permission scope filtering
        if scope == "assigned", let userId = userId {
            query = query.contains("team_member_ids", value: [userId])
        } else if scope == "own", let userId = userId {
            query = query.eq("created_by", value: userId)
        }

        let assigned: [SupabaseProjectTaskDTO] = try await query
            .order("display_order", ascending: true)
            .executeResilient(label: "project_tasks")

        // Bug G9 — tasks on mention-granted projects.
        // Mirror ProjectRepository: at "assigned" scope also pull tasks whose
        // project_id is in the user's mention-granted project set. RLS enforces.
        guard scope == "assigned", let userId = userId else {
            return assigned
        }
        let mentioned = try await fetchTasksOnMentionGrantedProjects(userId: userId, since: since)
        return unionByID(assigned, mentioned)
    }

    /// Fetch tasks on projects the user has mention-based view access to (Bug G9).
    private func fetchTasksOnMentionGrantedProjects(userId: String, since: Date?) async throws -> [SupabaseProjectTaskDTO] {
        struct NoteIdRow: Decodable { let project_id: String }
        let noteRows: [NoteIdRow] = try await client
            .from("project_notes")
            .select("project_id")
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .contains("mentioned_user_ids", value: [userId])
            .execute()
            .value
        let projectIds = Array(Set(noteRows.map(\.project_id)))
        guard !projectIds.isEmpty else { return [] }

        var taskQuery = client
            .from("project_tasks")
            .select()
            .eq("company_id", value: companyId)
            .in("project_id", values: projectIds)
        if let since = since {
            taskQuery = taskQuery.gte("updated_at", value: isoString(since))
        }
        return try await taskQuery
            .order("display_order", ascending: true)
            .execute()
            .value
    }

    private func unionByID(_ a: [SupabaseProjectTaskDTO], _ b: [SupabaseProjectTaskDTO]) -> [SupabaseProjectTaskDTO] {
        var seen = Set<String>()
        var result: [SupabaseProjectTaskDTO] = []
        for dto in a + b where seen.insert(dto.id).inserted {
            result.append(dto)
        }
        return result
    }

    func fetchForProject(_ projectId: String) async throws -> [SupabaseProjectTaskDTO] {
        let response: [SupabaseProjectTaskDTO] = try await client
            .from("project_tasks")
            .select()
            .eq("project_id", value: projectId)
            .order("display_order", ascending: true)
            .execute()
            .value
        return response
    }

    func fetchOne(_ id: String) async throws -> SupabaseProjectTaskDTO {
        try await client
            .from("project_tasks")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Create

    func create(_ dto: SupabaseProjectTaskDTO) async throws -> SupabaseProjectTaskDTO {
        let shouldComplete = dto.status == TaskStatus.completed.rawValue
        let createDTO = shouldComplete ? dto.replacingStatus(TaskStatus.active.rawValue) : dto
        let created: SupabaseProjectTaskDTO = try await client
            .from("project_tasks")
            .insert(createDTO)
            .select()
            .single()
            .execute()
            .value

        if shouldComplete {
            _ = try await completeProjectTask(
                taskId: dto.id,
                idempotencyKey: TaskCompletionSync.stableCompletionIdempotencyKey(taskId: dto.id),
                materialAdjustments: [:]
            )
        }

        return created
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseProjectTaskDTO) async throws {
        try await client
            .from("project_tasks")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update

    func updateStatus(_ taskId: String, status: String) async throws {
        if status == TaskStatus.completed.rawValue {
            _ = try await completeProjectTask(
                taskId: taskId,
                idempotencyKey: TaskCompletionSync.stableCompletionIdempotencyKey(taskId: taskId),
                materialAdjustments: [:]
            )
            return
        }

        struct StatusUpdate: Codable {
            let status: String
            let updated_at: String
        }
        let payload = StatusUpdate(status: status, updated_at: isoNow())
        try await client
            .from("project_tasks")
            .update(payload)
            .eq("id", value: taskId)
            .execute()
    }

    /// Updates the task_notes column (not `notes` — that column does not exist on project_tasks).
    func updateNotes(_ taskId: String, notes: String) async throws {
        struct NotesUpdate: Codable {
            let task_notes: String
            let updated_at: String
        }
        let payload = NotesUpdate(task_notes: notes, updated_at: isoNow())
        try await client
            .from("project_tasks")
            .update(payload)
            .eq("id", value: taskId)
            .execute()
    }

    func updateFields(_ taskId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        let shouldComplete = TaskCompletionSync.isCompletionStatus(payload["status"])
        if shouldComplete {
            payload.removeValue(forKey: "status")
        }

        if !payload.isEmpty {
            payload["updated_at"] = .string(isoNow())
            let response = try await client
                .from("project_tasks")
                .update(payload)
                .eq("id", value: taskId)
                .select("id")
                .execute()
            try SupabaseWriteGuard.requireAffectedRow(
                response: response.data,
                table: "project_tasks",
                id: taskId,
                fields: payload
            )
        }

        if shouldComplete {
            _ = try await completeProjectTask(
                taskId: taskId,
                idempotencyKey: TaskCompletionSync.stableCompletionIdempotencyKey(taskId: taskId),
                materialAdjustments: [:]
            )
        }
    }

    // MARK: - Completion RPC

    func completeProjectTask(
        taskId: String,
        idempotencyKey: String,
        materialAdjustments: [String: AnyJSON] = [:]
    ) async throws -> CompleteProjectTaskResponseDTO {
        let params = CompleteProjectTaskRPCParams(
            p_task_id: taskId,
            p_idempotency_key: idempotencyKey,
            p_material_adjustments: materialAdjustments
        )
        return try await client
            .rpc("complete_project_task", params: params)
            .execute()
            .value
    }

    func updateTeamMembers(_ taskId: String, memberIds: [String]) async throws {
        struct TeamUpdate: Codable {
            let team_member_ids: [String]
            let updated_at: String
        }
        let payload = TeamUpdate(team_member_ids: memberIds, updated_at: isoNow())
        try await client
            .from("project_tasks")
            .update(payload)
            .eq("id", value: taskId)
            .execute()
    }

    // MARK: - Soft Delete / Restore

    /// Tombstone a task through the definer-owned RPC.
    ///
    /// The direct PATCH is structurally impossible, not merely unlucky: since
    /// ledger 20260818014340 `project_tasks.role_scope_read` judges the row's own
    /// `deleted_at`, and Postgres attaches SELECT policies as WITH CHECK options
    /// to any UPDATE whose target requires ACL_SELECT — `where id = $1` requires
    /// it. RETURNING is not the trigger and `Prefer: return=minimal` does not
    /// help; no client role can set the column through PostgREST at all.
    ///
    /// `public.soft_delete_project_task` (ledger 20260902160624) enforces the
    /// same `private.user_can_edit_task` ladder the PATCH was supposed to satisfy
    /// and is idempotent — a second delete answers `deleted: false`. Bug db15baf2.
    func softDelete(_ taskId: String) async throws {
        _ = try await client
            .rpc(
                "soft_delete_project_task",
                params: SoftDeleteTaskRPCParams(p_task_id: taskId.lowercased())
            )
            .execute()
    }

    /// Clear a task's tombstone.
    ///
    /// A direct PATCH does not fail here — it matches zero rows, because the
    /// tombstoned row is invisible to the read policy the USING clause consults,
    /// and PostgREST answers 200 with an empty body. Every restore from Settings
    /// ▸ Trash therefore un-tombstoned the local row and left the server's
    /// tombstone standing, with no error anywhere.
    ///
    /// `public.restore_project_task` re-states the tasks.edit ladder against the
    /// tombstoned row (`private.user_can_edit_task` filters `deleted_at is null`
    /// and would refuse every restore) and requires a live parent project.
    func restore(_ taskId: String) async throws {
        _ = try await client
            .rpc(
                "restore_project_task",
                params: SoftDeleteTaskRPCParams(p_task_id: taskId.lowercased())
            )
            .execute()
    }
}

// MARK: - ISO8601 Helpers

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
