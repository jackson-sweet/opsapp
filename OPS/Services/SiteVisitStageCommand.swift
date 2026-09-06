import Foundation
import Supabase

struct SiteVisitStageSnapshot: Codable, Equatable, Sendable {
    let contractVersion: Int
    let capability: String
    let actorId: String
    let companyId: String
    let opportunityId: String
    let stage: String
    let stageRevision: String
    let stageEnteredAt: String
    let canMove: Bool
    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version", capability
        case actorId = "actor_id", companyId = "company_id"
        case opportunityId = "opportunity_id", stage, stageRevision = "stage_revision"
        case stageEnteredAt = "stage_entered_at", canMove = "can_move"
    }
    var isSupported: Bool {
        contractVersion == 1 && capability == "site_visit_stage_command_v1" && !stageRevision.isEmpty
    }
}

/// Stored inside the existing outbox payload, atomically with completion.
/// Missing snapshot is deliberate parked custody; a retry never obtains a new one.
struct SiteVisitStageCommand: Codable, Equatable, Sendable {
    let commandId: String
    let companyId: String
    let actorId: String
    let siteVisitId: String
    let opportunityId: String
    let targetStage: String
    let snapshot: SiteVisitStageSnapshot?

    static let allowedStages = Set(["qualifying", "quoting", "quoted", "follow_up", "negotiation"])
    var canDeliver: Bool {
        guard let snapshot else { return false }
        return snapshot.isSupported && snapshot.canMove
            && snapshot.opportunityId.lowercased() == opportunityId.lowercased()
            && snapshot.actorId.lowercased() == actorId.lowercased()
            && snapshot.companyId.lowercased() == companyId.lowercased()
            && Self.allowedStages.contains(targetStage)
            && !actorId.isEmpty && !companyId.isEmpty
    }
}

struct SiteVisitStageCommandResult: Decodable, Equatable, Sendable {
    struct Receipt: Decodable, Equatable, Sendable {
        let opportunityId: String
        let stage: String
        let stageRevision: String
        let stageEnteredAt: String
        let transitionId: String?
        let recordedAt: String
        enum CodingKeys: String, CodingKey {
            case opportunityId = "opportunity_id", stage, stageRevision = "stage_revision"
            case stageEnteredAt = "stage_entered_at", transitionId = "transition_id", recordedAt = "recorded_at"
        }
    }
    let contractVersion: Int
    let commandId: String
    let outcome: String
    let reason: String?
    let receipt: Receipt?
    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version", commandId = "command_id", outcome, reason, receipt
    }

    /// A replay receipt is historical. Callers settle the command only and do
    /// not merge its stage over a possibly newer in-memory opportunity.
    func validate(for command: SiteVisitStageCommand) throws {
        guard contractVersion == 1, commandId.lowercased() == command.commandId.lowercased() else {
            throw SyncError.encodingFailed(detail: "Unsupported stage delivery response")
        }
        switch outcome {
        case "applied", "already_applied":
            guard let receipt, receipt.opportunityId.lowercased() == command.opportunityId.lowercased(),
                  receipt.stage == command.targetStage, receipt.transitionId != nil else {
                throw SyncError.encodingFailed(detail: "Stage delivery receipt is incomplete")
            }
        case "conflict":
            throw SyncError.serverError(statusCode: 409, message: "STAGE CHANGED · REVIEW LEAD")
        case "not_ready":
            throw SyncError.serverError(statusCode: 503, message: "Visit completion has not reached the server")
        default: throw SyncError.encodingFailed(detail: "Unknown stage delivery outcome")
        }
    }
}

enum SiteVisitStageTransport {
    typealias ReadSnapshot = (String) async throws -> SiteVisitStageSnapshot
    typealias Deliver = (SiteVisitStageCommand) async throws -> SiteVisitStageCommandResult

    static func readSnapshot(opportunityId: String) async throws -> SiteVisitStageSnapshot {
        let client = await MainActor.run { SupabaseService.shared.client }
        let snapshot: SiteVisitStageSnapshot = try await client.rpc("read_site_visit_stage_snapshot",
            params: ["p_opportunity_id": opportunityId]).execute().value
        guard snapshot.isSupported, snapshot.opportunityId.lowercased() == opportunityId.lowercased() else {
            throw SyncError.encodingFailed(detail: "Stage snapshot capability unavailable")
        }
        return snapshot
    }

    static func isRetryableSQLCode(_ code: String?) -> Bool {
        ["55P03", "40P01", "40001"].contains(code ?? "")
    }

    static func deliver(_ command: SiteVisitStageCommand) async throws -> SiteVisitStageCommandResult {
        guard command.canDeliver, let snapshot = command.snapshot else {
            throw SyncError.serverError(statusCode: 409, message: "STAGE REVIEW REQUIRED · OPEN LEAD")
        }
        let client = await MainActor.run { SupabaseService.shared.client }
        do {
            return try await client.rpc("apply_site_visit_stage_command", params: [
                "p_command_id": command.commandId,
                "p_site_visit_id": command.siteVisitId,
                "p_opportunity_id": command.opportunityId,
                "p_to_stage": command.targetStage,
                "p_expected_stage": snapshot.stage,
                "p_expected_revision": snapshot.stageRevision,
                "p_expected_actor_id": command.actorId,
                "p_expected_company_id": command.companyId
            ]).execute().value
        } catch let error as PostgrestError where isRetryableSQLCode(error.code) {
            throw SyncError.serverError(statusCode: 503, message: "Stage delivery is waiting for another update")
        } catch let error as PostgrestError where ["PGRST202", "42883", "42501", "22023"].contains(error.code ?? "") {
            throw SyncError.serverError(statusCode: 409, message: "STAGE DELIVERY UNAVAILABLE · REVIEW LEAD")
        }
    }
}
