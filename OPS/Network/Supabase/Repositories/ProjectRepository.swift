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
            .execute()
            .value

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

    func create(_ dto: SupabaseProjectDTO) async throws -> SupabaseProjectDTO {
        try await client
            .from("projects")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
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

    func updateFields(_ projectId: String, fields: [String: AnyJSON]) async throws {
        var payload = fields
        payload["updated_at"] = .string(isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
            .execute()
    }

    // MARK: - Soft Delete

    func softDelete(_ projectId: String) async throws {
        struct SoftDelete: Codable {
            let deleted_at: String
            let updated_at: String
        }
        let payload = SoftDelete(deleted_at: isoNow(), updated_at: isoNow())
        try await client
            .from("projects")
            .update(payload)
            .eq("id", value: projectId)
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
