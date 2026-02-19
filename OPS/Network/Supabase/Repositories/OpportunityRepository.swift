//
//  OpportunityRepository.swift
//  OPS
//
//  Repository for Pipeline CRM operations via Supabase.
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
        let response: [OpportunityDTO] = try await client
            .from("opportunities")
            .select()
            .eq("company_id", value: companyId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
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
        let response: [ActivityDTO] = try await client
            .from("activities")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func fetchFollowUps(for opportunityId: String) async throws -> [FollowUpDTO] {
        let response: [FollowUpDTO] = try await client
            .from("follow_ups")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("due_at", ascending: true)
            .execute()
            .value
        return response
    }

    // MARK: - Create

    func create(_ dto: CreateOpportunityDTO) async throws -> OpportunityDTO {
        let response: OpportunityDTO = try await client
            .from("opportunities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func logActivity(_ dto: CreateActivityDTO) async throws -> ActivityDTO {
        let response: ActivityDTO = try await client
            .from("activities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func createFollowUp(_ dto: CreateFollowUpDTO) async throws -> FollowUpDTO {
        let response: FollowUpDTO = try await client
            .from("follow_ups")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    // MARK: - Update

    func advanceStage(opportunityId: String, to stage: PipelineStage, lossReason: String? = nil) async throws -> OpportunityDTO {
        var updates: [String: AnyJSON] = ["stage": .string(stage.rawValue)]
        if let reason = lossReason { updates["loss_reason"] = .string(reason) }
        let response: OpportunityDTO = try await client
            .from("opportunities")
            .update(updates)
            .eq("id", value: opportunityId)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func update(_ opportunityId: String, fields: UpdateOpportunityDTO) async throws -> OpportunityDTO {
        let response: OpportunityDTO = try await client
            .from("opportunities")
            .update(fields)
            .eq("id", value: opportunityId)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    // MARK: - Delete

    func delete(_ opportunityId: String) async throws {
        try await client
            .from("opportunities")
            .delete()
            .eq("id", value: opportunityId)
            .execute()
    }
}
