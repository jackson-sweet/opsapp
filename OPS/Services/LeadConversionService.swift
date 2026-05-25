//
//  LeadConversionService.swift
//  OPS
//
//  Orchestrates the lead → project conversion that lands when an operator
//  marks a pipeline opportunity won. Wraps the canonical `convert_lead_to_project`
//  Postgres RPC (migrations/2026-05-19-convert-lead-to-project-rpc.sql, extended
//  by 2026-05-20-extend-convert-lead-to-project-site-visit-photos.sql) which
//  runs the entire conversion in a single transaction:
//
//    1. Insert projects row (status='accepted', opportunity_id back-link)
//    2. Forward-link estimates (project_id + project_ref)
//    3. Materialize LABOR line items as project_tasks rows
//    4. Auto-attach site visit photos as project_photos rows with
//       source='site_visit' and site_visit_id back-link (added 2026-05-20)
//    5. Update opportunity (stage='won', actual_value, actual_close_date,
//       project_id, project_ref, stage_entered_at, stage_manually_set)
//    6. Insert stage_transitions row (duration_in_stage captured)
//
//  Atomicity is the whole point — partial failure cannot leave the lead in an
//  inconsistent state (e.g. project created but tasks missing). The RPC either
//  commits everything or rolls back the entire transaction.
//
//  Behavior parallels the canonical 'won' flow documented in
//  ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md § 'won'.
//  The Task Generation modal (bible §10:290) remains deferred; v1 silently
//  materializes every LABOR line item with no per-task toggle. Historical
//  wins (leads converted before 2026-05-20) keep their site visit photos
//  unattached — backfill is out of scope here.
//

import Foundation
import SwiftData
import Supabase

@MainActor
final class LeadConversionService {
    private let client: SupabaseClient
    private let opportunityRepo: OpportunityRepository
    private let projectRepo: ProjectRepository
    private let estimateRepo: EstimateRepository
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
        self.opportunityRepo = OpportunityRepository(companyId: companyId)
        self.projectRepo = ProjectRepository(companyId: companyId)
        self.estimateRepo = EstimateRepository(companyId: companyId)
    }

    // MARK: - SwiftData lookups (pre-flight UI states)

    /// Returns the locally-cached Project that already back-links to `lead`, if any.
    /// Used by `ConvertToProjectSheet` to render the DUPLICATE-EXISTS state instead
    /// of the form. Server-side the RPC is idempotent — a re-conversion that races
    /// past this check will return the same existing project id rather than create
    /// a second one.
    func existingProject(for lead: Opportunity, in context: ModelContext) -> Project? {
        let leadId = lead.id
        var descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.opportunityId == leadId && project.deletedAt == nil
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Returns OTHER projects under the same client (excluding any project that
    /// back-links to this lead). Drives the CLIENT-HAS-OTHERS warning banner so
    /// the operator sees they're about to create a second project for an existing
    /// client. Returns an empty array if the lead has no client linked yet.
    func clientProjectsSummary(for lead: Opportunity, in context: ModelContext) -> [Project] {
        guard let clientId = lead.clientId, !clientId.isEmpty else { return [] }
        let leadId = lead.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.clientId == clientId
                    && project.deletedAt == nil
                    && project.opportunityId != leadId
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Network fetches

    /// Fetches the estimates linked to `lead` from Supabase and refreshes the
    /// local SwiftData cache as a side-effect of the standard
    /// `EstimateDTO.toModel()` mapping. Returns the in-memory models.
    func estimates(for lead: Opportunity) async throws -> [Estimate] {
        let dtos: [EstimateDTO] = try await fetchEstimateDTOs(for: lead)
        return dtos.map { $0.toModel() }
    }

    /// Bundle of estimates + their line items, materialised in one round-trip.
    /// `ConvertToProjectSheet` uses this to surface line-item counts in the
    /// "ATTACHED ESTIMATES" section and to render LABOR rows in the
    /// "TASKS TO BE CREATED" preview. `Estimate.toModel()` discards the
    /// line-item array; this method keeps it.
    struct EstimateBundle {
        let estimate: Estimate
        let lineItems: [EstimateLineItem]

        /// LABOR-typed line items only — the rows that become `ProjectTask`s
        /// when the RPC materialises tasks.
        var laborItems: [EstimateLineItem] {
            lineItems.filter { $0.type == .labor }
        }
    }

    func estimateBundles(for lead: Opportunity) async throws -> [EstimateBundle] {
        let dtos: [EstimateDTO] = try await fetchEstimateDTOs(for: lead)
        return dtos.map { dto in
            let estimate = dto.toModel()
            let lineItems = (dto.lineItems ?? []).map { $0.toModel() }
            return EstimateBundle(estimate: estimate, lineItems: lineItems)
        }
    }

    private func fetchEstimateDTOs(for lead: Opportunity) async throws -> [EstimateDTO] {
        try await client
            .from("estimates")
            .select("*, line_items(*)")
            .eq("company_id", value: companyId)
            .eq("opportunity_id", value: lead.id)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Convert transaction (RPC-backed)

    /// THE convert transaction. Calls the `convert_lead_to_project` Postgres
    /// RPC, then fetches the freshly-created project row to return as a Project
    /// model. The RPC runs in one transaction; this function is therefore
    /// all-or-nothing as far as Supabase is concerned. The fetch step that
    /// follows the RPC is best-effort cosmetics — if it fails the conversion
    /// still committed and the next sync will hydrate the new project locally.
    func convertLeadToProject(
        lead: Opportunity,
        actualValue: Double?,
        title: String,
        address: String?,
        notes: String?,
        userId: String?
    ) async throws -> Project {
        struct RpcParams: Codable {
            let p_opportunity_id: String
            let p_actual_value: Double?
            let p_title: String
            let p_address: String?
            let p_user_id: String?
        }

        let params = RpcParams(
            p_opportunity_id: lead.id,
            p_actual_value: actualValue,
            p_title: title,
            p_address: address,
            p_user_id: userId
        )

        let newProjectId: String
        do {
            newProjectId = try await client
                .rpc("convert_lead_to_project", params: params)
                .execute()
                .value
        } catch {
            throw Self.mapRPCError(error)
        }

        // Optional notes patch — the RPC signature doesn't take notes, so we
        // PATCH them after the transaction commits. Skipped when nil/empty so
        // we don't pointlessly bump updated_at.
        if let notes = notes, !notes.isEmpty {
            try? await projectRepo.updateNotes(newProjectId, notes: notes)
        }

        // Fetch the canonical row and map to SwiftData model. The conversion
        // already committed, so any failure here is post-success.
        let dto: SupabaseProjectDTO
        do {
            dto = try await projectRepo.fetchOne(newProjectId)
        } catch {
            throw LeadConversionError.projectCreatedButFetchFailed(
                projectId: newProjectId,
                underlying: error
            )
        }

        return dto.toModel()
    }

    // MARK: - Mark-won escape hatches

    /// Called when the operator dismisses `ConvertToProjectSheet` without
    /// creating a project (e.g. quoted-then-won deals where the project already
    /// exists, or won-but-not-tracked deals). Sets the lead to won + records
    /// actualValue and actualCloseDate, but does not link a project. Wraps
    /// `OpportunityRepository.markWon` with projectId = nil.
    func markWonNoProject(
        lead: Opportunity,
        actualValue: Double?,
        userId: String?
    ) async throws {
        _ = try await opportunityRepo.markWon(
            opportunityId: lead.id,
            actualValue: actualValue,
            projectId: nil,
            userId: userId
        )
    }

    /// Called when the duplicate-project state opens an already-existing
    /// project that back-links to this lead. The lead still needs the canonical
    /// WON transition, but must keep/forward the existing project_id so it
    /// leaves the unconverted-won queue.
    func markWonWithExistingProject(
        lead: Opportunity,
        projectId: String,
        actualValue: Double?,
        userId: String?
    ) async throws {
        _ = try await opportunityRepo.markWon(
            opportunityId: lead.id,
            actualValue: actualValue,
            projectId: projectId,
            userId: userId
        )
    }

    // MARK: - Error mapping

    /// Translates the Postgres exception codes raised by the RPC into typed
    /// Swift errors. The RPC raises `opportunity_not_found` (SQLSTATE P0002)
    /// and `access_denied` (SQLSTATE 42501); everything else passes through
    /// as the original Supabase error.
    private static func mapRPCError(_ error: Error) -> Error {
        let description = String(describing: error)
        if description.contains("opportunity_not_found") {
            return LeadConversionError.opportunityNotFound
        }
        if description.contains("access_denied") {
            return LeadConversionError.accessDenied
        }
        return error
    }
}

// MARK: - Errors

enum LeadConversionError: LocalizedError {
    /// The opportunity row could not be read (deleted, archived, or never existed).
    case opportunityNotFound
    /// Caller's user is not a member of the opportunity's company.
    case accessDenied
    /// The RPC committed (the project + tasks + stage transition all landed)
    /// but the post-RPC fetch failed. The project_id is included so the
    /// caller can retry just the fetch instead of re-running the conversion.
    case projectCreatedButFetchFailed(projectId: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .opportunityNotFound:
            return "Lead not found. It may have been deleted."
        case .accessDenied:
            return "You don't have access to convert this lead."
        case .projectCreatedButFetchFailed:
            return "Project created. Refresh to see it."
        }
    }
}
