//
//  ProjectRepository.swift
//  OPS
//
//  Repository for Project entity operations via Supabase.
//  Table: projects
//

import Foundation
import Supabase

struct ProjectTeamAssignmentRPCResult: Decodable {
    let updatedAt: String?
    let teamMemberIds: [String]?
    let taskId: String?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case teamMemberIds = "team_member_ids"
        case taskId = "task_id"
    }
}

class ProjectRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll(since: Date? = nil, scope: String = "all", userId: String? = nil) async throws -> [SupabaseProjectDTO] {
        var query = client
            .from("projects")
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

        let assigned: [SupabaseProjectDTO] = try await query
            .order("created_at", ascending: false)
            .executeResilient(label: "projects")

        // Bug G9 — mention-based project view grant.
        // At "assigned" scope, also fetch projects where the user is tagged in
        // any live note. At "all" scope the primary query already returns
        // everything. "own" intentionally stays tight (own-created only).
        guard scope == "assigned", let userId = userId else {
            return assigned
        }
        let mentioned = try await fetchMentionGrantedProjects(userId: userId, since: since)
        return unionByID(assigned, mentioned)
    }

    /// Fetch projects the user has mention-based view access to (Bug G9).
    /// Two-step query: collect project_ids from live notes mentioning the user,
    /// then fetch those project rows (RLS enforces the grant server-side).
    private func fetchMentionGrantedProjects(userId: String, since: Date?) async throws -> [SupabaseProjectDTO] {
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

        var projectQuery = client
            .from("projects")
            .select()
            .eq("company_id", value: companyId)
            .in("id", values: projectIds)
        if let since = since {
            projectQuery = projectQuery.gte("updated_at", value: isoString(since))
        }
        return try await projectQuery
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    private func unionByID(_ a: [SupabaseProjectDTO], _ b: [SupabaseProjectDTO]) -> [SupabaseProjectDTO] {
        var seen = Set<String>()
        var result: [SupabaseProjectDTO] = []
        for dto in a + b where seen.insert(dto.id).inserted {
            result.append(dto)
        }
        return result
    }

    func fetchOne(_ id: String) async throws -> SupabaseProjectDTO {
        try await client
            .from("projects")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: - Create

    /// Deliberately asks for NO representation — same defect as
    /// `ClientRepository.create`, same reasoning (see its doc comment).
    ///
    /// `projects.role_scope_read` resolves the row through
    /// `private.user_can_view_project`, whose first statement re-reads
    /// `public.projects` by id. Requesting a representation makes PostgREST emit
    /// `INSERT … RETURNING`, Postgres evaluates that SELECT policy against the
    /// new row before it exists, the self-lookup finds nothing, and the create is
    /// rejected with 42501 — losing the job.
    ///
    /// Both callers — `OutboundProcessor.handleProject` and
    /// `DataActor.handleProject` — discarded the returned DTO.
    func create(_ dto: SupabaseProjectDTO) async throws {
        try await client
            .from("projects")
            .insert(dto)
            .execute()
    }

    // MARK: - Upsert

    func upsert(_ dto: SupabaseProjectDTO) async throws {
        try await client
            .from("projects")
            .upsert(dto)
            .execute()
    }

    // MARK: - Update

    func updateStatus(_ projectId: String, status: String) async throws {
        struct StatusUpdate: Codable {
            let status: String
            let updated_at: String
        }
        let payload = StatusUpdate(status: status, updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    func updateNotes(_ projectId: String, notes: String) async throws {
        struct NotesUpdate: Codable {
            let notes: String
            let updated_at: String
        }
        let payload = NotesUpdate(notes: notes, updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    func updateDates(_ projectId: String, startDate: Date?, endDate: Date?) async throws {
        struct DatesUpdate: Codable {
            let start_date: String?
            let end_date: String?
            let updated_at: String
        }
        let payload = DatesUpdate(
            start_date: startDate.map { isoString($0) },
            end_date: endDate.map { isoString($0) },
            updated_at: isoNow()
        )
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    func updateAddress(_ projectId: String, address: String) async throws {
        struct AddressUpdate: Codable {
            let address: String
            let updated_at: String
        }
        let payload = AddressUpdate(address: address, updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    @available(*, unavailable, message: "projects.team_member_ids is server-derived. Persist crew changes through project_tasks or the project-team RPCs.")
    func updateTeamMembers(_ projectId: String, memberIds: [String]) async throws {
        struct TeamUpdate: Codable {
            let team_member_ids: [String]
            let updated_at: String
        }
        let payload = TeamUpdate(team_member_ids: memberIds, updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    func createProjectTableAssignmentTask(
        projectId: String,
        title: String,
        expectedUpdatedAt: String
    ) async throws -> ProjectTeamAssignmentRPCResult {
        struct Params: Encodable {
            let p_project_id: String
            let p_title: String
            let p_expected_updated_at: String
        }

        return try await client
            .rpc(
                "create_project_table_assignment_task",
                params: Params(
                    p_project_id: projectId,
                    p_title: title,
                    p_expected_updated_at: expectedUpdatedAt
                )
            )
            .execute()
            .value
    }

    func assignProjectTeamMember(
        projectId: String,
        userId: String,
        taskIds: [String],
        expectedUpdatedAt: String
    ) async throws -> ProjectTeamAssignmentRPCResult {
        struct Params: Encodable {
            let p_project_id: String
            let p_user_id: String
            let p_task_ids: [String]
            let p_expected_updated_at: String
        }

        return try await client
            .rpc(
                "assign_project_team_member",
                params: Params(
                    p_project_id: projectId,
                    p_user_id: userId,
                    p_task_ids: taskIds,
                    p_expected_updated_at: expectedUpdatedAt
                )
            )
            .execute()
            .value
    }

    func removeProjectTeamMember(
        projectId: String,
        userId: String,
        taskIds: [String]? = nil,
        expectedUpdatedAt: String
    ) async throws -> ProjectTeamAssignmentRPCResult {
        struct Params: Encodable {
            let p_project_id: String
            let p_user_id: String
            let p_task_ids: [String]?
            let p_expected_updated_at: String
        }

        return try await client
            .rpc(
                "remove_project_team_member",
                params: Params(
                    p_project_id: projectId,
                    p_user_id: userId,
                    p_task_ids: taskIds,
                    p_expected_updated_at: expectedUpdatedAt
                )
            )
            .execute()
            .value
    }

    /// Replays the exact durable command through the guarded RPC. Internal
    /// command metadata never enters the legacy table-update path below.
    @discardableResult
    func reopenForTask(_ projectId: String, fields: [String: AnyJSON]) async throws -> ProjectTaskReopenReceipt {
        let command = try ProjectTaskReopenCommand(
            projectId: projectId, companyId: companyId, fields: fields
        )
        let response = try await client
            .rpc("reopen_project_for_task", params: command.rpcParameters)
            .execute()
            .data
        return try command.validateReceipt(response)
    }

    func updateFields(_ projectId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())
        let response = try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .select("id")
            .execute()
        try SupabaseWriteGuard.requireAffectedRow(
            response: response.data,
            table: "projects",
            id: projectId,
            fields: payload
        )
    }

    // MARK: - Soft Delete / Restore

    /// Tombstone a project through the definer-owned RPC.
    ///
    /// `projects.role_scope_read` is a RESTRICTIVE SELECT policy that judges the
    /// row's own `deleted_at`, and Postgres attaches SELECT policies as WITH
    /// CHECK options to any UPDATE whose target requires ACL_SELECT — which
    /// `where id = $1` does. The PATCH this replaces was therefore refused
    /// `42501` for every client role, which also broke the client-deletion flow
    /// end to end: `ClientDeletionSheet` deletes each of the client's projects
    /// before deleting the client itself.
    ///
    /// INVARIANT PRESERVED, DELIBERATELY: `public.enforce_project_opportunity_link`
    /// fires on `deleted_at` and, for a project carrying an opportunity link,
    /// still demands `pipeline.manage all` from the JWT caller — the trigger reads
    /// the session's claims, not the definer's role, so moving the write inside an
    /// RPC does not and must not suppress it. A user without that permission gets
    /// a real `access_denied` (42501) rather than a silent success. Clearing the
    /// tombstone trips the same check, so restore carries the same requirement.
    func softDelete(_ projectId: String) async throws {
        _ = try await client
            .rpc(
                "soft_delete_project",
                params: SoftDeleteProjectRPCParams(p_project_id: projectId.lowercased())
            )
            .execute()
    }

    /// Clear a project's tombstone.
    ///
    /// The PATCH this replaces matched zero rows rather than failing — the
    /// tombstoned project is invisible to the read policy the USING clause
    /// consults — so every restore from Settings ▸ Trash reported success while
    /// the server kept its tombstone.
    func restore(_ projectId: String) async throws {
        _ = try await client
            .rpc(
                "restore_project",
                params: SoftDeleteProjectRPCParams(p_project_id: projectId.lowercased())
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
