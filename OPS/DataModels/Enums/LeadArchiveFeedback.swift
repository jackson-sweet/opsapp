//
//  LeadArchiveFeedback.swift
//  OPS
//
//  Archive is the reversible way a lead leaves the board. Discard says "this was
//  never a job"; archive says "real job, not now". Bug e0c8084f: archive
//  captured neither — one confirm dialog, a bare `archived_at` stamp, and the
//  reason the owner parked it was gone by the time they found it again.
//
//  The vocabulary stays deliberately separate from `LeadDispositionReason`. If
//  archive borrowed the discard reasons it would become a second, softer
//  discard, and the two would stop meaning different things.
//
//  Reason and note are BOTH optional. Archiving is cheap and undoable, so the
//  one-tap path is first-class — a reason is a bonus, never a toll.
//

import Foundation
import Supabase

enum LeadArchiveReason: String, Codable, CaseIterable, Hashable {
    case notNow = "not_now"
    case seasonal
    case waitingOnClient = "waiting_on_client"
    case other
    /// What the server records when the operator archived without choosing.
    case unspecified = "archive_unspecified"

    /// The chips the sheet offers. `unspecified` is the no-selection state, so
    /// it is never a chip.
    static let selectableReasons: [LeadArchiveReason] = [
        .notNow,
        .seasonal,
        .waitingOnClient,
        .other,
    ]

    var label: String {
        switch self {
        case .notNow: return "NOT NOW"
        case .seasonal: return "NEXT SEASON"
        case .waitingOnClient: return "WAITING ON THEM"
        case .other: return "SOMETHING ELSE"
        case .unspecified: return "ARCHIVE"
        }
    }

    var detail: String {
        switch self {
        case .notNow: return "Real job, wrong time"
        case .seasonal: return "Comes back around next season"
        case .waitingOnClient: return "Ball is in their court"
        case .other: return "Parked for your own reason"
        case .unspecified: return "Off your board; nothing else recorded"
        }
    }

    /// What actually goes to the server. No selection is a legitimate answer.
    static func submittedCode(for reason: LeadArchiveReason?) -> String {
        (reason ?? .unspecified).rawValue
    }
}

/// The authoritative receipt from `apply_lead_archive_feedback` /
/// `undo_lead_archive_feedback`.
struct LeadArchiveResult: Decodable, Equatable {
    let feedbackId: String
    let outcome: String
    let priorArchivedAt: Date?
    let currentArchivedAt: Date?
    let currentOpportunityUpdatedAt: Date?
    let lifecycleChanged: Bool
    let idempotentReplay: Bool

    enum CodingKeys: String, CodingKey {
        case feedbackId = "feedback_id"
        case outcome
        case priorArchivedAt = "prior_archived_at"
        case currentArchivedAt = "current_archived_at"
        case currentOpportunityUpdatedAt = "current_opportunity_updated_at"
        case lifecycleChanged = "lifecycle_changed"
        case idempotentReplay = "idempotent_replay"
    }

    init(
        feedbackId: String,
        outcome: String,
        priorArchivedAt: Date?,
        currentArchivedAt: Date?,
        currentOpportunityUpdatedAt: Date?,
        lifecycleChanged: Bool,
        idempotentReplay: Bool
    ) {
        self.feedbackId = feedbackId
        self.outcome = outcome
        self.priorArchivedAt = priorArchivedAt
        self.currentArchivedAt = currentArchivedAt
        self.currentOpportunityUpdatedAt = currentOpportunityUpdatedAt
        self.lifecycleChanged = lifecycleChanged
        self.idempotentReplay = idempotentReplay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedbackId = try c.decode(String.self, forKey: .feedbackId)
        outcome = try c.decode(String.self, forKey: .outcome)
        // Timestamps arrive as PostgREST strings, not epochs — same convention
        // as every other DTO in this app.
        priorArchivedAt = try c.decodeIfPresent(String.self, forKey: .priorArchivedAt)
            .flatMap(SupabaseDate.parse)
        currentArchivedAt = try c.decodeIfPresent(String.self, forKey: .currentArchivedAt)
            .flatMap(SupabaseDate.parse)
        currentOpportunityUpdatedAt = try c
            .decodeIfPresent(String.self, forKey: .currentOpportunityUpdatedAt)
            .flatMap(SupabaseDate.parse)
        lifecycleChanged = try c.decode(Bool.self, forKey: .lifecycleChanged)
        idempotentReplay = try c.decode(Bool.self, forKey: .idempotentReplay)
    }
}

@MainActor
enum LeadArchiveLocalState {
    static func apply(_ result: LeadArchiveResult, to opportunity: Opportunity) {
        opportunity.archivedAt = result.currentArchivedAt
    }

    static func applyUndo(_ result: LeadArchiveResult, to opportunity: Opportunity) {
        opportunity.archivedAt = result.currentArchivedAt
    }
}

/// Whether a failed archive RPC means "this server has not been migrated yet"
/// (degrade to the legacy `archived_at` PATCH) or a real refusal (surface it).
///
/// The distinction matters: falling back on a permission denial would archive a
/// lead the server just refused to archive, and falling back offline would write
/// half the contract with no feedback row.
enum LeadArchiveCapability {
    static func shouldFallBackToLegacyArchive(forRPCError error: Error) -> Bool {
        // PostgREST answers PGRST202 for an undeployed function. Same detection
        // PhotoAnnotationRepository uses for its soft-delete RPC.
        if let postgrest = error as? PostgrestError {
            return postgrest.code == "PGRST202"
        }
        if case OpportunityRepositoryError.archiveRPCUnavailable = error {
            return true
        }
        return false
    }
}
