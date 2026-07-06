//
//  ActivityRepository.swift
//  OPS
//
//  The single high-level write path for the `activities` table. Replaces the
//  three scattered loggers that funnelled through `OpportunityRepository`.
//
//  An activity is parented to EXACTLY ONE of a lead (opportunity), a client, or
//  a job (project) — enforced by `ActivityTarget.parentKey`. `company_id` and
//  `created_by` are always stamped (`company_id` is NOT NULL with no default and
//  gates RLS; `created_by` is the Supabase `users.id`, never the Firebase UID).
//  `direction` is DB-CHECK-constrained to inbound/outbound (else nil); this repo
//  clamps it so a stray value can never 500 the insert.
//

import Foundation
import Supabase

final class ActivityRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String, client: SupabaseClient = SupabaseService.shared.client) {
        self.client = client
        self.companyId = companyId
    }

    // MARK: - Write

    /// Log an activity against a single target. Normalizes every constrained
    /// field (direction clamp, blank-outcome → nil, non-positive duration → nil)
    /// before inserting, and returns the persisted row (subject may be backfilled
    /// server-side by `trg_activities_default_subject`).
    ///
    /// `createdBy` MUST be the operator's Supabase `users.id`
    /// (`dataController.currentUser?.id`) — never the Firebase UID.
    @discardableResult
    func logActivity(
        target: ActivityTarget,
        type: ActivityType,
        subject: String? = nil,
        body: String? = nil,
        direction: String? = nil,
        outcome: String? = nil,
        durationMinutes: Int? = nil,
        callSource: String? = nil,
        callerNumber: String? = nil,
        callStartedAt: Date? = nil,
        siteVisitId: String? = nil,
        createdBy: String?
    ) async throws -> ActivityDTO {
        let dto = Self.buildDTO(
            target: target,
            companyId: companyId,
            type: type.rawValue,
            subject: subject,
            body: body,
            direction: direction,
            outcome: outcome,
            durationMinutes: durationMinutes,
            callSource: callSource,
            callerNumber: callerNumber,
            // `call_started_at` is a timestamptz column — format the Date at the
            // boundary (mirrors LeadDetailViewModel.logActivity).
            callStartedAt: callStartedAt.map(SupabaseDate.format),
            siteVisitId: siteVisitId,
            createdBy: createdBy
        )
        return try await client
            .from("activities")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }

    /// Hard-delete an activity row. The `activities` table has no soft-delete
    /// column; used to UNDO an auto-logged call. Company-scoped by RLS.
    func deleteActivity(_ activityId: String) async throws {
        try await client
            .from("activities")
            .delete()
            .eq("id", value: activityId)
            .execute()
    }

    // MARK: - Fetch (one parent per query)

    func fetchActivities(byOpportunity opportunityId: String) async throws -> [ActivityDTO] {
        try await client
            .from("activities")
            .select()
            .eq("opportunity_id", value: opportunityId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchActivities(byClient clientId: String) async throws -> [ActivityDTO] {
        try await client
            .from("activities")
            .select()
            .eq("client_id", value: clientId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchActivities(byProject projectId: String) async throws -> [ActivityDTO] {
        try await client
            .from("activities")
            .select()
            .eq("project_id", value: projectId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - Pure DTO builder (testable without a client)

    /// Build the insert DTO for a target, setting EXACTLY ONE parent column and
    /// normalizing every constrained field. Pure + static so it is unit-testable
    /// without a live SupabaseClient.
    static func buildDTO(
        target: ActivityTarget,
        companyId: String,
        type: String,
        subject: String?,
        body: String?,
        direction: String?,
        outcome: String?,
        durationMinutes: Int?,
        callSource: String?,
        callerNumber: String?,
        callStartedAt: String?,
        siteVisitId: String?,
        createdBy: String?
    ) -> CreateActivityDTO {
        // Exactly one parent — driven by the target's parentKey.
        let opportunityId: String?
        let clientId: String?
        let projectId: String?
        switch target.parentKey {
        case .opportunity(let id):
            opportunityId = id; clientId = nil; projectId = nil
        case .client(let id):
            opportunityId = nil; clientId = id; projectId = nil
        case .project(let id):
            opportunityId = nil; clientId = nil; projectId = id
        case nil:
            opportunityId = nil; clientId = nil; projectId = nil
        }

        return CreateActivityDTO(
            opportunityId: opportunityId,
            companyId: companyId,
            type: type,
            subject: subject,
            bodyText: body,
            direction: clampDirection(direction),
            outcome: normalizeBlank(outcome),
            durationMinutes: normalizeDuration(durationMinutes),
            callSource: callSource,
            callerNumber: callerNumber,
            callStartedAt: callStartedAt,
            clientId: clientId,
            projectId: projectId,
            siteVisitId: siteVisitId,
            createdBy: createdBy
        )
    }

    // MARK: - Field normalizers

    /// `direction` is DB-CHECK-constrained to inbound/outbound. Anything else
    /// (including a wrong case or empty string) becomes nil so the insert stays
    /// legal.
    static func clampDirection(_ direction: String?) -> String? {
        (direction == "inbound" || direction == "outbound") ? direction : nil
    }

    /// Trim and collapse a blank string to nil (empty outcome is not a value).
    private static func normalizeBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A duration of zero (or negative) is not a real duration — send nil.
    private static func normalizeDuration(_ minutes: Int?) -> Int? {
        guard let minutes, minutes > 0 else { return nil }
        return minutes
    }
}
