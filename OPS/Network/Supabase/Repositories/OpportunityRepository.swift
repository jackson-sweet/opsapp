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
    enum RPC {
        static let createGuarded = "create_opportunity_guarded"
        static let changeAssignment = "change_opportunity_assignment"
        static let listAssignmentCandidates = "list_opportunity_assignment_candidates"
    }

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

    /// Returns an existing active opportunity linked to a client, if one
    /// exists. Client-lead delivery calls this before insert so an ambiguous
    /// timeout cannot create a duplicate lead on retry.
    func fetchFirstActiveLinked(toClientId clientId: String) async throws -> OpportunityDTO? {
        let rows: [OpportunityDTO] = try await client
            .from("opportunities")
            .select()
            .eq("company_id", value: companyId)
            .eq("client_id", value: clientId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// All non-deleted opportunities linked to a client, across every stage
    /// (open + terminal). The client Leads section splits open vs. closed in
    /// memory. Mirror of `fetchFirstActiveLinked` without the `.limit(1)`.
    func fetchAllLinked(toClientId clientId: String) async throws -> [OpportunityDTO] {
        try await client
            .from("opportunities")
            .select()
            .eq("company_id", value: companyId)
            .eq("client_id", value: clientId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Resolve a durable ingestion key regardless of active/deleted state.
    /// The database uniquely constrains `(company_id, source_thread_key)`, so
    /// this is the authoritative readback after an ambiguous insert response.
    func fetchBySourceThreadKey(_ sourceThreadKey: String) async throws -> OpportunityDTO? {
        let rows: [OpportunityDTO] = try await client
            .from("opportunities")
            .select()
            .eq("company_id", value: companyId)
            .eq("source_thread_key", value: sourceThreadKey)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Resolve an email-thread id to its linked opportunity id.
    ///
    /// Lead notifications whose `action_url` is `/inbox/<thread-uuid>` carry no
    /// opportunity id in the payload — the id lives on `email_threads.opportunity_id`
    /// (verified in prod: every `/inbox/<uuid>` lead notification joins to a
    /// thread row whose `opportunity_id` is set). iOS does not model
    /// `email_threads` in SwiftData, so this is a direct single-column Supabase
    /// select — additive, with no schema or sync impact.
    ///
    /// Returns nil when the thread row is missing or not lead-linked, so the
    /// caller can fall back to the Job Board instead of dropping the tap.
    func opportunityId(forEmailThreadId threadId: String) async throws -> String? {
        struct ThreadOpportunityRow: Decodable {
            let opportunityId: String?
            enum CodingKeys: String, CodingKey {
                case opportunityId = "opportunity_id"
            }
        }
        let rows: [ThreadOpportunityRow] = try await client
            .from("email_threads")
            .select("opportunity_id")
            .eq("id", value: threadId)
            .limit(1)
            .execute()
            .value
        return rows.first?.opportunityId
    }

    /// Latest email-thread subject for a lead — powers the EMAIL quick action's
    /// "Re:" compose and the detail CONTACT sheet. Nil when the lead has no
    /// correspondence.
    func latestCorrespondenceSubject(for opportunityId: String) async throws -> String? {
        struct Row: Decodable { let subject: String? }
        let rows: [Row] = try await client
            .from("opportunity_correspondence_events")
            .select("subject")
            .eq("opportunity_id", value: opportunityId)
            .not("subject", operator: .is, value: "null")
            .order("occurred_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.subject
    }

    /// FILES rows for the lead detail — email attachments the pipeline
    /// attributed to this lead. Only actionable rows: `stored` (streamed via
    /// the authenticated ops-web proxy) and `external` (source_url).
    ///
    /// `email_attachments` went SERVER-ONLY on 2026-07-20 (migration
    /// `email_attachment_lead_files_client_access`): the raw table is REVOKEd
    /// from clients because it carries private bucket keys and provider
    /// identities. Clients read safe attributed descriptors through this
    /// sanctioned SECURITY DEFINER RPC, which also enforces lead + mailbox
    /// visibility server-side. Direct table selects now fail for every user —
    /// never revert this to `.from("email_attachments")`.
    func fetchEmailAttachments(for opportunityId: String) async throws -> [LeadAttachment] {
        try await client
            .rpc("get_opportunity_lead_files", params: ["p_opportunity_id": opportunityId])
            .execute()
            .value
    }

    /// Latest MEANINGFUL correspondence event for a lead — either party, noise
    /// (auto-replies, bounces) excluded. Powers the LAST WORD row on the lead
    /// document. Reads the correspondence-events projection, the same ledger
    /// the chase strip's counters are built from.
    func latestCorrespondence(for opportunityId: String) async throws -> LeadCorrespondence? {
        struct Row: Decodable {
            let subject: String?
            let direction: String?
            let occurredAt: String?
            let source: String?
            enum CodingKeys: String, CodingKey {
                case subject, direction, source
                case occurredAt = "occurred_at"
            }
        }
        let rows: [Row] = try await client
            .from("opportunity_correspondence_events")
            .select("subject, direction, occurred_at, source")
            .eq("opportunity_id", value: opportunityId)
            .eq("is_meaningful", value: true)
            .order("occurred_at", ascending: false)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first,
              let at = row.occurredAt.flatMap({ SupabaseDate.parse($0) }) else { return nil }
        return LeadCorrespondence(
            subject: row.subject,
            direction: row.direction ?? "inbound",
            occurredAt: at,
            source: row.source
        )
    }

    /// Sets or clears the lead's linked project. A dedicated patch because
    /// `UpdateOpportunityDTO` omits nil fields entirely — which can never
    /// UNLINK. This encodes an explicit JSON null when clearing.
    func updateProjectAssociation(_ opportunityId: String, projectId: String?) async throws -> OpportunityDTO {
        struct Patch: Encodable {
            let projectId: String?
            enum CodingKeys: String, CodingKey { case projectId = "project_id" }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(projectId, forKey: .projectId) // nil → JSON null
            }
        }
        return try await update(opportunityId, patch: Patch(projectId: projectId))
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

    // MARK: - Create

    func create(_ dto: CreateOpportunityDTO) async throws -> OpportunityDTO {
        let result: GuardedOpportunityCreateResult = try await client
            .rpc(
                RPC.createGuarded,
                params: GuardedOpportunityCreateParams(opportunity: dto)
            )
            .execute()
            .value
        guard result.ok else {
            throw OpportunityRepositoryError.guardedCreateRejected
        }
        return result.opportunity
    }

    /// The only iOS assignment mutation path. The server compares both the
    /// expected assignee and monotonic assignment version, then returns the
    /// canonical row snapshot (including conflicts). Callers must render this
    /// response; this repository never mutates a local Opportunity optimistically.
    func changeAssignment(
        opportunityId: String,
        expectedAssignmentVersion: Int64,
        expectedAssignedTo: String?,
        newAssignedTo: String?,
        source: OpportunityAssignmentSource = .manual,
        suggestionId: String? = nil,
        metadata: [String: AnyJSON] = [:]
    ) async throws -> OpportunityAssignmentChangeResult {
        let params = try ChangeOpportunityAssignmentParams(
            opportunityId: opportunityId,
            expectedAssignmentVersion: expectedAssignmentVersion,
            expectedAssignedTo: expectedAssignedTo,
            newAssignedTo: newAssignedTo,
            source: source,
            suggestionId: suggestionId,
            metadata: metadata
        )
        return try await client
            .rpc(RPC.changeAssignment, params: params)
            .execute()
            .value
    }

    /// Returns only assignment targets authorized by the guarded server RPC.
    /// Local `User` rows are display fallbacks, never a picker data source.
    func listAssignmentCandidates(
        opportunityId: String
    ) async throws -> OpportunityAssignmentCandidates {
        struct Params: Encodable {
            let p_opportunity_id: String
        }

        return try await client
            .rpc(
                RPC.listAssignmentCandidates,
                params: Params(p_opportunity_id: opportunityId)
            )
            .execute()
            .value
    }

    /// Refetches the canonical assignment tuple after an optimistic-concurrency
    /// conflict. The full row fetch retains the existing opportunity RLS gate;
    /// callers project only the two non-PII fields below.
    func fetchAssignmentSnapshot(
        opportunityId: String
    ) async throws -> OpportunityAssignmentSnapshot {
        let opportunity = try await fetchOne(opportunityId)
        return OpportunityAssignmentSnapshot(
            assignedTo: opportunity.assignedTo,
            assignmentVersion: opportunity.assignmentVersion
        )
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

    /// Hard-delete an activity row. Used to UNDO an auto-logged call (the
    /// activities table has no soft-delete column). Company-scoped by RLS.
    func deleteActivity(_ activityId: String) async throws {
        try await client
            .from("activities")
            .delete()
            .eq("id", value: activityId)
            .execute()
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
        try Self.validateDirectStageMutation(stage)
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

    /// The won transition is authorization-sensitive: it creates or links the
    /// project and pins the assignment version in one guarded transaction.
    /// Keeping this rejection at the repository boundary prevents a future UI
    /// from accidentally reviving the legacy `move_opportunity_stage('won')`
    /// escape hatch.
    static func validateDirectStageMutation(_ stage: PipelineStage) throws {
        guard stage != .won else {
            throw OpportunityRepositoryError.guardedConversionRequired
        }
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

    /// Update via an arbitrary Encodable patch. Used by the edit form's
    /// `EditOpportunityPatch`, whose custom encoder emits explicit nulls so
    /// cleared fields persist. The `fields:` overload (UpdateOpportunityDTO)
    /// stays the partial-update path for mark-lost / archive. (review I-12)
    func update<Patch: Encodable>(_ opportunityId: String, patch: Patch) async throws -> OpportunityDTO {
        try await client
            .from("opportunities")
            .update(patch)
            .eq("id", value: opportunityId)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Images

    /// Append image URLs against the SERVER row: fetch → merge → update, so a
    /// device holding a stale local array can never blow away photos another
    /// device (or the web email-extract pipeline) already landed. Duplicate
    /// URLs are dropped. Returns the updated row.
    func appendImages(_ urls: [String], to opportunityId: String) async throws -> OpportunityDTO {
        let current = try await fetchOne(opportunityId)
        var merged = current.images ?? []
        for url in urls where !url.isEmpty && !merged.contains(url) {
            merged.append(url)
        }
        return try await update(opportunityId, patch: ["images": merged])
    }

    /// Remove one image URL — same server-state read-modify-write contract.
    func removeImage(_ url: String, from opportunityId: String) async throws -> OpportunityDTO {
        let current = try await fetchOne(opportunityId)
        let merged = (current.images ?? []).filter { $0 != url }
        return try await update(opportunityId, patch: ["images": merged])
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
    /// write actualValue or actualCloseDate. Won is deliberately rejected by
    /// `moveToStage` and must use the guarded conversion service.
    @available(*, deprecated, message: "Use moveToStage / markLost; won requires guarded conversion")
    func advanceStage(opportunityId: String, to stage: PipelineStage, lostReason: String? = nil) async throws -> OpportunityDTO {
        try await moveToStage(opportunityId: opportunityId, to: stage, userId: nil)
    }
}

enum OpportunityRepositoryError: LocalizedError, Equatable {
    case guardedCreateRejected
    case guardedConversionRequired

    var errorDescription: String? {
        switch self {
        case .guardedCreateRejected:
            return "Lead was not created. Refresh and try again."
        case .guardedConversionRequired:
            return "Marking a lead won requires guarded project conversion."
        }
    }
}
