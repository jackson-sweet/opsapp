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

struct ConvertOpportunityParams: Encodable {
    let companyId: String
    let opportunityId: String
    let actualValue: Double?
    let expectedStage: String
    let decidedBy: String?
    let notes: String?
    let titleOverride: String?
    let linkToProjectId: String?
    let sourcePath: String
    let winOpportunity: Bool
    let projectStatus: String?
    let evidence: [String: String]
    let expectedAssignmentVersion: Int64

    init(
        companyId: String,
        opportunityId: String,
        actualValue: Double?,
        expectedStage: String,
        decidedBy: String?,
        notes: String?,
        titleOverride: String?,
        linkToProjectId: String?,
        sourcePath: String,
        winOpportunity: Bool,
        projectStatus: String?,
        evidence: [String: String],
        expectedAssignmentVersion: Int64
    ) {
        precondition(expectedAssignmentVersion >= 0, "Assignment versions cannot be negative")
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.actualValue = actualValue
        self.expectedStage = expectedStage
        self.decidedBy = decidedBy
        self.notes = notes
        self.titleOverride = titleOverride
        self.linkToProjectId = linkToProjectId
        self.sourcePath = sourcePath
        self.winOpportunity = winOpportunity
        self.projectStatus = projectStatus
        self.evidence = evidence
        self.expectedAssignmentVersion = expectedAssignmentVersion
    }

    enum CodingKeys: String, CodingKey {
        case companyId                   = "p_company_id"
        case opportunityId               = "p_opportunity_id"
        case actualValue                 = "p_actual_value"
        case expectedStage               = "p_expected_stage"
        case decidedBy                   = "p_decided_by"
        case notes                       = "p_notes"
        case titleOverride               = "p_title_override"
        case linkToProjectId             = "p_link_to_project_id"
        case sourcePath                  = "p_source_path"
        case winOpportunity              = "p_win_opportunity"
        case projectStatus               = "p_project_status"
        case evidence                    = "p_evidence"
        case expectedAssignmentVersion   = "p_expected_assignment_version"
    }
}

@MainActor
final class LeadConversionService {
    private let client: SupabaseClient
    private let projectRepo: ProjectRepository
    private let companyId: String
    /// The local store the committed project must land in. Required, not
    /// optional: a conversion whose project is never cached leaves every
    /// project-by-id lookup in the app empty-handed (bug 4cbf2efe).
    private let modelContext: ModelContext

    init(companyId: String, modelContext: ModelContext) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
        self.projectRepo = ProjectRepository(companyId: companyId)
        self.modelContext = modelContext
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

    // MARK: - Server preflight (read-only)

    /// Read-only conversion preflight. Wraps the `get_conversion_preflight`
    /// Postgres RPC (won-conversion dedup + auto-naming, live on prod) which is
    /// the SERVER source of truth for the convert sheet's render state:
    ///
    ///   - `existingLinkedProject`  this opportunity already converted → the
    ///                              sheet renders DUPLICATE-EXISTS.
    ///   - `duplicateCandidates`    high/medium-confidence likely-the-same
    ///                              projects (address/title heuristics).
    ///   - `otherClientProjects`    other live projects under the same client.
    ///   - `suggestedName`          `derive_project_name(address, client)` base
    ///                              preview (no `#N` dedup suffix).
    ///
    /// Replaces the previous LOCAL SwiftData duplicate/other-projects checks so
    /// detection matches what the unified convert RPC will actually do.
    func getConversionPreflight(for lead: Opportunity) async throws -> ConversionPreflight {
        struct Params: Encodable {
            let p_opportunity_id: String
            let p_company_id: String
        }
        do {
            return try await client
                .rpc("get_conversion_preflight", params: Params(
                    p_opportunity_id: lead.id,
                    p_company_id: companyId
                ))
                .execute()
                .value
        } catch {
            throw Self.mapRPCError(error)
        }
    }

    /// Every project an operator may explicitly link to this lead. Duplicate
    /// preflight remains the authority for CREATE safety; this read is the
    /// authority for MANUAL choice, where address/client are ranking signals
    /// rather than eligibility gates.
    func manualProjectLinkCandidates(
        for lead: Opportunity
    ) async throws -> [ManualProjectLinkCandidate] {
        struct Params: Encodable {
            let p_opportunity_id: String
        }
        do {
            return try await client
                .rpc(
                    "get_manual_project_link_candidates",
                    params: Params(p_opportunity_id: lead.id)
                )
                .execute()
                .value
        } catch {
            throw Self.mapRPCError(error)
        }
    }

    // MARK: - Unified convert transaction (RPC-backed)

    /// THE convert transaction. Calls the unified `convert_opportunity_to_project`
    /// Postgres RPC directly (won-conversion superset, live on prod) — NOT the
    /// legacy `convert_lead_to_project` shim. The RPC runs the entire conversion
    /// (project insert, estimate relink, task materialization, site-visit photo
    /// attach, won transition + stage_transitions row, disposition audit) in one
    /// transaction and is idempotent: a row that already converted returns its
    /// existing `project_id` with `alreadyConverted = true` rather than creating
    /// a second project.
    ///
    /// Auto-naming: `titleOverride == nil` ⇒ the project is AUTO-named — the RPC
    /// sets `title_is_auto = true` and the `projects_autoname` BEFORE trigger
    /// derives the name from the opportunity address/client. A non-nil
    /// `titleOverride` is a hand-set name (`title_is_auto = false`).
    ///
    /// NOTE: the RPC reads `address`/`latitude`/`longitude` from the opportunity
    /// row (it has no address param). Callers who let the operator edit the
    /// address MUST persist it to the opportunity BEFORE calling this, or the
    /// edit is dropped from both the project and the derived name.
    ///
    /// The post-RPC fetch that hydrates the returned Project is best-effort.
    /// Once commit is proven, an inaccessible or temporarily unhydratable
    /// project returns a committed outcome with no project identity so callers
    /// cannot navigate or retry the transaction.
    func convertOpportunityToProject(
        lead: Opportunity,
        actualValue: Double?,
        titleOverride: String?,
        notes: String?,
        linkToProjectId: String?,
        userId: String?,
        expectedStage: String? = nil,
        expectedAssignmentVersion: Int64? = nil
    ) async throws -> LeadConversionOutcome {
        let params = ConvertOpportunityParams(
            companyId: companyId,
            opportunityId: lead.id,
            actualValue: actualValue,
            expectedStage: expectedStage ?? lead.stage.rawValue,
            decidedBy: userId,
            notes: notes,
            titleOverride: titleOverride,   // nil ⇒ auto-named
            linkToProjectId: linkToProjectId,
            sourcePath: "ios",
            winOpportunity: true,
            projectStatus: "accepted",
            evidence: ["surface": "convert_sheet"],
            expectedAssignmentVersion: expectedAssignmentVersion ?? lead.assignmentVersion
        )

        let result: ConvertOpportunityResult
        do {
            result = try await client
                .rpc("convert_opportunity_to_project", params: params)
                .execute()
                .value
        } catch {
            throw Self.mapRPCError(error)
        }

        switch try LeadConversionOutcomeResolver.disposition(for: result) {
        case .committedWithoutAccessibleProject:
            return .committedWithoutAccessibleProject

        case .fetchProject(let projectId):
            do {
                return .project(try await hydrateAndCacheProject(projectId))
            } catch {
                // The guarded transaction already committed. A secondary read
                // failure must never invite a retry of the conversion or leak a
                // project identifier the operator cannot currently use.
                print("[CONVERT] Project committed; hydration unavailable: \(error)")
                return .committedWithoutAccessibleProject
            }

        case .recoverConvertedProject(let projectId):
            do {
                return .project(try await hydrateAndCacheProject(projectId))
            } catch {
                // The idempotent branch already told us WHICH project this lead
                // owns; only the hydrating read failed. Surfacing that as "no
                // accessible project" is what let the client wipe the lead's
                // local link (bug ced5b3cb-B). Keep the identity.
                print("[CONVERT] Already-converted project \(projectId) not hydratable: \(error)")
                return .committedWithKnownProject(projectId: projectId)
            }
        }
    }

    /// Fetches the authoritative project row and writes it into the local
    /// store through the same seam realtime uses, returning the CACHED model.
    /// A detached `toModel()` result is precisely the bug this replaces.
    private func hydrateAndCacheProject(_ projectId: String) async throws -> Project {
        let dto = try await projectRepo.fetchOne(projectId)
        let project = try ProjectCacheMerge.apply(dto: dto, context: modelContext)
        InboundChangeSignal.post(entityNames: ["Project"])
        return project
    }

    // MARK: - Error mapping

    /// Translates the Postgres exception codes raised by the RPC into typed
    /// Swift errors. Kept internal so the live error-contract mapping remains
    /// directly regression-testable.
    nonisolated static func mapRPCError(_ error: Error) -> Error {
        let description = String(describing: error)
        if description.contains("opportunity_not_found") {
            return LeadConversionError.opportunityNotFound
        }
        if description.contains("access_denied") {
            return LeadConversionError.accessDenied
        }
        if description.contains("project_link_unavailable")
            || description.contains("project_link_ambiguous")
            || description.contains("belongs to another opportunity")
            || description.contains("opportunity is already linked to another project")
            || description.contains("opportunity project mirrors disagree") {
            // The RPC suffixes `project_link_unavailable` with WHY the door is
            // closed. Collapsing all four into one message told the operator
            // nothing about which corrective action was theirs to take.
            let reason = ProjectLinkFailureReason.allCases.first {
                description.contains($0.rawValue)
            }
            return LeadConversionError.projectLinkUnavailable(reason: reason)
        }
        if description.contains("invalid_assignment_snapshot") {
            return LeadConversionError.assignmentChanged
        }
        if description.contains("opportunity_client_snapshot_mismatch") {
            return LeadConversionError.leadChanged
        }
        return error
    }
}

// MARK: - Errors

enum LeadConversionOutcome {
    case project(Project)
    /// Committed, and the server named the project — but the row could not be
    /// hydrated on this attempt. The identity is authoritative: callers keep
    /// the lead's local link and let the project sheet self-heal.
    case committedWithKnownProject(projectId: String)
    /// The conversion is committed, but there is no project identity the
    /// current operator may safely use for navigation or retry behavior.
    case committedWithoutAccessibleProject
}

enum LeadConversionDisposition: Equatable {
    /// Fresh commit whose `project_accessible` was genuinely computed.
    case fetchProject(projectId: String)
    /// Idempotent already-converted branch. It returns a REAL project id while
    /// hardcoding `project_accessible = false` (verified in prod 2026-07-29 —
    /// only the success branch computes the flag). Its access answer proves
    /// nothing, so recover by identity and never destroy local link state.
    /// A drafted server migration makes the flag honest; this disposition
    /// simply stops being reached once it lands.
    case recoverConvertedProject(projectId: String)
    case committedWithoutAccessibleProject
}

enum LeadConversionOutcomeResolver {
    static func disposition(
        for result: ConvertOpportunityResult
    ) throws -> LeadConversionDisposition {
        switch result.guardDecision {
        case .assignmentChanged:
            throw LeadConversionError.assignmentChanged
        case .leadChanged:
            throw LeadConversionError.leadChanged
        case .proceed:
            break
        }

        guard result.won == true,
              result.converted == true || result.alreadyConverted == true,
              let projectAccessible = result.projectAccessible else {
            throw LeadConversionError.unverifiedResult
        }

        let projectId = result.projectId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        guard projectAccessible else {
            // Only the already-converted branch pairs a real id with a
            // hardcoded-false flag. A FRESH commit reporting inaccessible is a
            // computed answer and keeps withholding the identity.
            if result.alreadyConverted == true, let projectId {
                return .recoverConvertedProject(projectId: projectId)
            }
            return .committedWithoutAccessibleProject
        }
        guard let projectId else {
            throw LeadConversionError.unverifiedResult
        }
        return .fetchProject(projectId: projectId)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The reason suffix the RPC appends to `project_link_unavailable`. Each is a
/// different closed door, and each has a different corrective action.
enum ProjectLinkFailureReason: String, CaseIterable, Equatable {
    /// A nil-link CREATE was blocked by an active project at the same address.
    case matchingProjectRequiresReview = "matching_project_requires_review"
    /// Candidates exist, but this lead has no address to prove sameness with.
    case addressRequiredForProjectMatch = "address_required_for_project_match"
    /// The chosen target already belongs to a different lead.
    case matchingProjectLinkConflict = "matching_project_link_conflict"
    /// The server could not establish the dedupe evidence it needs.
    case dedupeProofUnavailable = "dedupe_proof_unavailable"
}

enum LeadConversionError: LocalizedError {
    /// The opportunity row could not be read (deleted, archived, or never existed).
    case opportunityNotFound
    /// Caller's user is not a member of the opportunity's company.
    case accessDenied
    /// The assignee changed after the convert sheet loaded.
    case assignmentChanged
    /// The stage or another guarded lead snapshot changed after sheet load.
    case leadChanged
    /// The selected project changed, disappeared, or no longer satisfies the
    /// server's guarded evidence/link contract. The reason, when the server
    /// named one, selects the operator copy.
    case projectLinkUnavailable(reason: ProjectLinkFailureReason?)
    /// The server did not provide enough authoritative fields to prove commit.
    case unverifiedResult

    var errorDescription: String? {
        switch self {
        case .opportunityNotFound:
            return "Lead not found. It may have been deleted."
        case .accessDenied:
            return "You don't have access to convert this lead."
        case .assignmentChanged:
            return "Lead assignment changed. Refresh before converting."
        case .leadChanged:
            return "Lead changed. Refresh before converting."
        case .projectLinkUnavailable(let reason):
            switch reason {
            case .matchingProjectRequiresReview:
                return "A project already exists at this address."
            case .addressRequiredForProjectMatch:
                return "Add an address before matching a project."
            case .matchingProjectLinkConflict:
                return "That project is already linked to another lead."
            case .dedupeProofUnavailable:
                return "Duplicate projects could not be confirmed. Try again."
            case nil:
                return "The project changed and must be reviewed before matching."
            }
        case .unverifiedResult:
            return "Conversion could not be verified. Refresh before trying again."
        }
    }
}

// MARK: - Server preflight payload

/// Typed mirror of the `get_conversion_preflight` jsonb result. All fields are
/// defensively optional — the RPC always returns the keys, but decoding stays
/// resilient if the contract gains/loses a field during a phased rollout.
struct ConversionPreflight: Decodable {
    /// Non-nil ⇒ this opportunity already converted to the named project.
    let existingLinkedProject: PreflightLinkedProject?
    /// Likely-the-same projects (address/title heuristics), high confidence first.
    let duplicateCandidates: [PreflightCandidate]
    /// Other live projects under the same client.
    let otherClientProjects: [PreflightClientProject]
    /// Why a nil-target create is unsafe even though no selectable candidate
    /// can be shown. The sheet turns this into a corrective action instead of
    /// offering a conversion that the final transaction must reject.
    let creationBlocker: ConversionPreflightCreationBlocker?
    /// `derive_project_name(address, client)` base preview (no `#N` suffix).
    let suggestedName: String?
    /// Recovery signal for a prior committed conversion. When the linked
    /// project is inaccessible, its identity and all alternatives are absent.
    let alreadyConverted: Bool
    let projectAccessible: Bool
    let assignmentVersion: Int64?

    var isCommittedWithoutAccessibleProject: Bool {
        alreadyConverted && !projectAccessible
    }

    enum CodingKeys: String, CodingKey {
        case existingLinkedProject = "existing_linked_project"
        case duplicateCandidates   = "duplicate_candidates"
        case otherClientProjects   = "other_client_projects"
        case creationBlocker       = "creation_blocker"
        case suggestedName         = "suggested_name"
        case alreadyConverted      = "already_converted"
        case projectAccessible     = "project_accessible"
        case assignmentVersion     = "assignment_version"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        existingLinkedProject = try c.decodeIfPresent(PreflightLinkedProject.self, forKey: .existingLinkedProject)
        duplicateCandidates = try c.decodeIfPresent([PreflightCandidate].self, forKey: .duplicateCandidates) ?? []
        otherClientProjects = try c.decodeIfPresent([PreflightClientProject].self, forKey: .otherClientProjects) ?? []
        creationBlocker = try c.decodeIfPresent(
            ConversionPreflightCreationBlocker.self,
            forKey: .creationBlocker
        )
        suggestedName = try c.decodeIfPresent(String.self, forKey: .suggestedName)
        alreadyConverted = try c.decodeIfPresent(Bool.self, forKey: .alreadyConverted) ?? false
        projectAccessible = try c.decodeIfPresent(Bool.self, forKey: .projectAccessible) ?? false
        assignmentVersion = try c.decodeIfPresent(Int64.self, forKey: .assignmentVersion)
    }
}

enum ConversionPreflightCreationBlocker: String, Decodable, Equatable {
    /// Another active project exists for this client, but the lead has no
    /// address with which to prove whether it is the same job.
    case addressRequired = "address_required"
    /// An active same-address project exists but cannot be offered as a safe
    /// MATCH target (access, link ownership, or mirror integrity requires an
    /// administrator to resolve it).
    case projectReviewRequired = "project_review_required"
}

/// The project this opportunity already converted to (DUPLICATE-EXISTS state).
struct PreflightLinkedProject: Decodable {
    let id: String
    let title: String?
}

/// A likely-duplicate project surfaced by the server heuristics.
struct PreflightCandidate: Decodable {
    let projectId: String
    let title: String?
    let address: String?
    /// "high" | "medium".
    let confidence: String?
    let signals: [String]

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title, address, confidence, signals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try c.decode(String.self, forKey: .projectId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
        signals = try c.decodeIfPresent([String].self, forKey: .signals) ?? []
    }
}

/// Another live project under the same client.
struct PreflightClientProject: Decodable {
    let projectId: String
    let title: String?
    let address: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title, address, status
    }
}

/// One server-authorized manual project target. `sameAddress` and
/// `sameClient` only explain ordering; neither can make a project ineligible.
struct ManualProjectLinkCandidate: Decodable, Equatable {
    let projectId: String
    let title: String?
    let address: String?
    let status: String?
    let sameAddress: Bool
    let sameClient: Bool

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title, address, status
        case sameAddress = "same_address"
        case sameClient = "same_client"
    }
}

// MARK: - Unified convert result payload

/// Typed mirror of the `convert_opportunity_to_project` jsonb result. The count
/// fields are absent on the guard/already-converted branches, so all are
/// optional except the booleans that the create branch always emits.
enum OpportunityConversionGuardDecision: Equatable {
    case proceed
    case assignmentChanged
    case leadChanged
}

struct ConvertOpportunityResult: Decodable {
    let converted: Bool?
    let alreadyConverted: Bool?
    let projectId: String?
    let dispositionId: String?
    let relinkedEstimates: Int?
    let materializedTasks: Int?
    let attachedPhotos: Int?
    let linkedExisting: Bool?
    let won: Bool?
    let guardReason: String?
    let assignedTo: String?
    let assignmentVersion: Int64?
    let projectAccessible: Bool?

    /// The conversion RPC uses `already_converted` as the idempotent recovery
    /// path for a project that was committed previously. It is not a stale-row
    /// guard and must continue through the project-access check and fetch.
    var guardDecision: OpportunityConversionGuardDecision {
        switch guardReason {
        case nil, "already_converted":
            return .proceed
        case "assignment_snapshot_mismatch":
            return .assignmentChanged
        case "snapshot_mismatch", "manual_stage_override":
            return .leadChanged
        case .some:
            return .leadChanged
        }
    }

    enum CodingKeys: String, CodingKey {
        case converted
        case alreadyConverted   = "already_converted"
        case projectId          = "project_id"
        case dispositionId      = "disposition_id"
        case relinkedEstimates  = "relinked_estimates"
        case materializedTasks  = "materialized_tasks"
        case attachedPhotos     = "attached_photos"
        case linkedExisting     = "linked_existing"
        case won
        case guardReason        = "guard_reason"
        case assignedTo         = "assigned_to"
        case assignmentVersion  = "assignment_version"
        case projectAccessible  = "project_accessible"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        converted = try container.decodeIfPresent(Bool.self, forKey: .converted)
        alreadyConverted = try container.decodeIfPresent(Bool.self, forKey: .alreadyConverted)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        dispositionId = try container.decodeIfPresent(String.self, forKey: .dispositionId)
        relinkedEstimates = try container.decodeIfPresent(Int.self, forKey: .relinkedEstimates)
        materializedTasks = try container.decodeIfPresent(Int.self, forKey: .materializedTasks)
        attachedPhotos = try container.decodeIfPresent(Int.self, forKey: .attachedPhotos)
        linkedExisting = try container.decodeIfPresent(Bool.self, forKey: .linkedExisting)
        won = try container.decodeIfPresent(Bool.self, forKey: .won)
        guardReason = try container.decodeIfPresent(String.self, forKey: .guardReason)
        assignedTo = try container.decodeIfPresent(String.self, forKey: .assignedTo)
        projectAccessible = try container.decodeIfPresent(Bool.self, forKey: .projectAccessible)

        let decodedVersion = try container.decodeIfPresent(Int64.self, forKey: .assignmentVersion)
        if let decodedVersion, decodedVersion < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .assignmentVersion,
                in: container,
                debugDescription: "Assignment versions cannot be negative"
            )
        }
        assignmentVersion = decodedVersion
    }
}
