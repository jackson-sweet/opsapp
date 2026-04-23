//
//  WizardStateDTOs.swift
//  OPS
//
//  Data Transfer Objects for wizard_states Supabase table.
//  User-scoped (no company_id). Used for cross-device persistence of
//  per-wizard progress and completion state.
//

import Foundation

// MARK: - Read DTO

/// Maps 1:1 to the `wizard_states` Supabase table.
/// Used by WizardStateRepository.fetchForUser and InboundProcessor.syncWizardStates.
struct SupabaseWizardStateDTO: Codable, Identifiable {
    let id: String
    let wizardId: String
    let userId: String
    let status: String            // raw WizardStatus value (not_started | in_progress | completed | dismissed)
    let currentStepIndex: Int
    let doNotShow: Bool
    let completedAt: String?
    let totalDurationMs: Int
    let stepsSkipped: Int
    let lastActiveAt: String?
    let currentSessionId: String
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case wizardId         = "wizard_id"
        case userId           = "user_id"
        case status
        case currentStepIndex = "current_step_index"
        case doNotShow        = "do_not_show"
        case completedAt      = "completed_at"
        case totalDurationMs  = "total_duration_ms"
        case stepsSkipped     = "steps_skipped"
        case lastActiveAt     = "last_active_at"
        case currentSessionId = "current_session_id"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
    }

    /// Materializes a fresh WizardState SwiftData model from this DTO.
    /// Caller is responsible for inserting into ModelContext and clearing `needsSync`.
    func toModel() -> WizardState {
        let model = WizardState(wizardId: wizardId, userId: userId, id: id)
        model.statusRaw = status
        model.currentStepIndex = currentStepIndex
        model.doNotShow = doNotShow
        model.completedAt = completedAt.flatMap { SupabaseDate.parse($0) }
        model.totalDurationMs = totalDurationMs
        model.stepsSkipped = stepsSkipped
        model.lastActiveAt = lastActiveAt.flatMap { SupabaseDate.parse($0) }
        model.currentSessionId = currentSessionId
        return model
    }

    /// Produces a wire DTO from a local SwiftData model.
    /// Used when upserting local state to the server out-of-band.
    static func fromModel(_ model: WizardState) -> SupabaseWizardStateDTO {
        let iso = ISO8601DateFormatter()
        return SupabaseWizardStateDTO(
            id: model.id,
            wizardId: model.wizardId,
            userId: model.userId,
            status: model.statusRaw,
            currentStepIndex: model.currentStepIndex,
            doNotShow: model.doNotShow,
            completedAt: model.completedAt.map { iso.string(from: $0) },
            totalDurationMs: model.totalDurationMs,
            stepsSkipped: model.stepsSkipped,
            lastActiveAt: model.lastActiveAt.map { iso.string(from: $0) },
            currentSessionId: model.currentSessionId,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

// MARK: - Create DTO

/// Insert payload for `wizard_states`. Separate from the read DTO so the server
/// populates `created_at` / `updated_at` via its defaults instead of us sending
/// nullable timestamps that may not round-trip cleanly.
///
/// Note: `completed_at` and `last_active_at` are nullable timestamptz columns;
/// we keep them optional and encode ISO 8601 strings when present.
struct CreateWizardStateDTO: Codable {
    let id: String
    let wizardId: String
    let userId: String
    let status: String
    let currentStepIndex: Int
    let doNotShow: Bool
    let completedAt: String?
    let totalDurationMs: Int
    let stepsSkipped: Int
    let lastActiveAt: String?
    let currentSessionId: String

    enum CodingKeys: String, CodingKey {
        case id
        case wizardId         = "wizard_id"
        case userId           = "user_id"
        case status
        case currentStepIndex = "current_step_index"
        case doNotShow        = "do_not_show"
        case completedAt      = "completed_at"
        case totalDurationMs  = "total_duration_ms"
        case stepsSkipped     = "steps_skipped"
        case lastActiveAt     = "last_active_at"
        case currentSessionId = "current_session_id"
    }

    static func fromModel(_ model: WizardState) -> CreateWizardStateDTO {
        let iso = ISO8601DateFormatter()
        return CreateWizardStateDTO(
            id: model.id,
            wizardId: model.wizardId,
            userId: model.userId,
            status: model.statusRaw,
            currentStepIndex: model.currentStepIndex,
            doNotShow: model.doNotShow,
            completedAt: model.completedAt.map { iso.string(from: $0) },
            totalDurationMs: model.totalDurationMs,
            stepsSkipped: model.stepsSkipped,
            lastActiveAt: model.lastActiveAt.map { iso.string(from: $0) },
            currentSessionId: model.currentSessionId
        )
    }
}
