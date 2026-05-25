//
//  OpportunityRepository.swift
//  OPS
//
//  Repository for Pipeline CRM operations via Supabase.
//  - Soft-delete via deleted_at (no hard deletes)
//  - Atomic stage moves via move_opportunity_stage RPC
//  - Schema parity with public.opportunities
//

import Foundation
import Supabase

class OpportunityRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Fetch

    func fetchAll() async throws -> [OpportunityDTO] {
        try await client
            .from("opportunities")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchOne(_ opportunityId: String) async throws -> OpportunityDTO {
        try await client
            .from("opportunities")
            .select()
            .eq("id", value: opportunityId)
            .single()
            .execute()
            .value
    }

    func fetchActivities(for opportunityId: String) async throws -> [ActivityDTO] {
        try await client
            .from("activities")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchFollowUps(for opportunityId: String) async throws -> [FollowUpDTO] {
        try await client
            .from("follow_ups")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("due_at", ascending: true)
            .execute()
            .value
    }

    func fetchStageTransitions(for opportunityId: String) async throws -> [StageTransitionDTO] {
        try await client
            .from("stage_transitions")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("transitioned_at", ascending: false)
            .execute()
            .value
    }

    /// Bulk-fetch every stage_transitions row for the company. Used by the
    /// LEADS hero widget to reconstruct the weighted-forecast baseline 30 days
    /// ago (Option A — "what it would have been" — per LEADS rebuild polish P1-3).
    /// Ascending order so consumers can scan chronologically and find the
    /// latest-on-or-before(date) per opportunity in a single pass.
    func fetchAllStageTransitions() async throws -> [StageTransitionDTO] {
        try await client
            .from("stage_transitions")
            .select()
            .eq("company_id", value: companyId)
            .order("transitioned_at", ascending: true)
            .execute()
            .value
    }

    // MARK: - Create

    func create(_ dto: CreateOpportunityDTO) async throws -> OpportunityDTO {
        try await client
            .from("opportunities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func logActivity(_ dto: CreateActivityDTO) async throws -> ActivityDTO {
        try await client
            .from("activities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    func createFollowUp(_ dto: CreateFollowUpDTO) async throws -> FollowUpDTO {
        try await client
            .from("follow_ups")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Update

    /// Atomic stage move via Postgres RPC.
    /// Updates stage + stage_entered_at + stage_manually_set AND inserts a
    /// stage_transitions row in one transaction. Returns the updated opportunity.
    func moveToStage(opportunityId: String, to stage: PipelineStage, userId: String?) async throws -> OpportunityDTO {
        struct RpcParams: Codable {
            let p_opportunity_id: String
            let p_to_stage: String
            let p_user_id: String?
        }
        let params = RpcParams(
            p_opportunity_id: opportunityId,
            p_to_stage: stage.rawValue,
            p_user_id: userId
        )
        return try await client
            .rpc("move_opportunity_stage", params: params)
            .single()
            .execute()
            .value
    }

    /// Mark won. Sets stage to .won, stores actualValue + actualCloseDate,
    /// and writes the stage_transitions row via moveToStage.
    func markWon(opportunityId: String, actualValue: Double?, projectId: String?, userId: String?) async throws -> OpportunityDTO {
        // First the stage move (writes transition row)
        _ = try await moveToStage(opportunityId: opportunityId, to: .won, userId: userId)

        // Then patch the won-specific fields
        var fields = UpdateOpportunityDTO()
        fields.actualValue = actualValue
        fields.actualCloseDate = SupabaseDate.formatDate(Date())
        if let projectId { fields.projectId = projectId }
        return try await update(opportunityId, fields: fields)
    }

    /// Mark lost. Sets stage to .lost, stores lost_reason + lost_notes + actualCloseDate,
    /// and writes the stage_transitions row via moveToStage.
    func markLost(opportunityId: String, reason: LossReason, notes: String?, userId: String?) async throws -> OpportunityDTO {
        _ = try await moveToStage(opportunityId: opportunityId, to: .lost, userId: userId)

        var fields = UpdateOpportunityDTO()
        fields.lostReason = reason.rawValue
        fields.lostNotes = notes
        fields.actualCloseDate = SupabaseDate.formatDate(Date())
        return try await update(opportunityId, fields: fields)
    }

    func update(_ opportunityId: String, fields: UpdateOpportunityDTO) async throws -> OpportunityDTO {
        try await client
            .from("opportunities")
            .update(fields)
            .eq("id", value: opportunityId)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Soft Delete + Archive

    /// Soft-delete via deleted_at. Replaces the prior HARD delete.
    func softDelete(_ opportunityId: String) async throws {
        var fields = UpdateOpportunityDTO()
        fields.deletedAt = SupabaseDate.format(Date())
        _ = try await update(opportunityId, fields: fields)
    }

    /// Archive without deleting — used for "long-dormant but maybe-revisit" leads.
    func archive(_ opportunityId: String) async throws {
        var fields = UpdateOpportunityDTO()
        fields.archivedAt = SupabaseDate.format(Date())
        _ = try await update(opportunityId, fields: fields)
    }

    /// Restore from archive.
    func unarchive(_ opportunityId: String) async throws {
        struct UnarchivePatch: Codable {
            let archived_at: String? = nil
        }
        try await client
            .from("opportunities")
            .update(UnarchivePatch())
            .eq("id", value: opportunityId)
            .execute()
    }

    // MARK: - Deprecated

    /// Kept for backward compatibility. Forwards to moveToStage; does NOT
    /// write actualValue or actualCloseDate. Prefer markWon / markLost.
    @available(*, deprecated, message: "Use moveToStage / markWon / markLost")
    func advanceStage(opportunityId: String, to stage: PipelineStage, lostReason: String? = nil) async throws -> OpportunityDTO {
        try await moveToStage(opportunityId: opportunityId, to: stage, userId: nil)
    }
}
