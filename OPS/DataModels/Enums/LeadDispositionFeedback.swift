//
//  LeadDispositionFeedback.swift
//  OPS
//
//  Shared iOS vocabulary for the actor-authorized Phase C lead correction
//  contract. The server re-validates every mapping and derives all evidence;
//  these values drive presentation and decode the authoritative RPC receipt.
//

import Foundation

enum LeadDispositionOutcome: String, Codable, Equatable {
    case discarded
    case lost
    case duplicateReview = "duplicate_review"
    case reviewDeferred = "review_deferred"
}

enum LeadDispositionSelectionBehavior: Equatable {
    case submitImmediately
}

enum LeadDispositionReason: String, Codable, CaseIterable, Hashable {
    case spam
    case jobApplicant = "job_applicant"
    case vendorSales = "vendor_sales"
    case internalMessage = "internal"
    case platformNotification = "platform_notification"
    case testTraffic = "test_traffic"
    case duplicate
    case notAFit = "not_a_fit"
    case other
    case legacyUnspecified = "legacy_unspecified"

    static let standardReasons: [LeadDispositionReason] = [
        .spam,
        .jobApplicant,
        .vendorSales,
        .internalMessage,
        .platformNotification,
        .testTraffic,
        .duplicate,
        .notAFit,
        .other,
    ]

    var label: String {
        switch self {
        case .spam: return "SPAM OR SCAM"
        case .jobApplicant: return "JOB APPLICANT"
        case .vendorSales: return "VENDOR OR SALES PITCH"
        case .internalMessage: return "INTERNAL MESSAGE"
        case .platformNotification: return "PLATFORM NOTIFICATION"
        case .testTraffic: return "TEST OR AUTOMATED TRAFFIC"
        case .duplicate: return "DUPLICATE"
        case .notAFit: return "NOT A FIT"
        case .other: return "SOMETHING ELSE"
        case .legacyUnspecified: return "DISCARD"
        }
    }

    var detail: String {
        switch self {
        case .spam: return "Junk, scam, or unsolicited traffic"
        case .jobApplicant: return "Someone looking for work"
        case .vendorSales: return "Someone selling to your company"
        case .internalMessage: return "Your team or company traffic"
        case .platformNotification: return "Receipt, alert, or status update"
        case .testTraffic: return "System-generated or test message"
        case .duplicate: return "Hold for duplicate review"
        case .notAFit: return "Real inquiry — mark it lost"
        case .other: return "Keep it for human review"
        case .legacyUnspecified: return "Off your board; never a lost deal"
        }
    }

    var expectedOutcome: LeadDispositionOutcome {
        switch self {
        case .spam, .jobApplicant, .vendorSales, .internalMessage,
             .platformNotification, .testTraffic, .legacyUnspecified:
            return .discarded
        case .duplicate:
            return .duplicateReview
        case .notAFit:
            return .lost
        case .other:
            return .reviewDeferred
        }
    }

    var changesLifecycle: Bool {
        expectedOutcome == .discarded || expectedOutcome == .lost
    }

    var selectionBehavior: LeadDispositionSelectionBehavior {
        .submitImmediately
    }

    var requiresSecondConfirmation: Bool { false }
}

enum LeadDispositionInteractionRoute: Equatable {
    case structuredReason
    case legacyExplainer
    case legacyConfirmation
}

enum LeadDispositionInteractionPolicy {
    static let noteLimit = 280

    static func route(
        phaseCEnabled: Bool,
        explainerSeen: Bool
    ) -> LeadDispositionInteractionRoute {
        if phaseCEnabled { return .structuredReason }
        return explainerSeen ? .legacyConfirmation : .legacyExplainer
    }

    static func normalizedNote(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(noteLimit))
    }
}

struct LeadDispositionIdempotencyKeys {
    private var applyKeys: [String: String] = [:]
    private var undoKeys: [String: String] = [:]

    mutating func applyKey(
        for opportunityId: String,
        make: () -> String = {
            "lead-disposition:\(UUID().uuidString)"
        }
    ) -> String {
        if let existing = applyKeys[opportunityId] { return existing }
        let key = make()
        applyKeys[opportunityId] = key
        return key
    }

    mutating func undoKey(
        for feedbackId: String,
        make: () -> String = {
            "lead-disposition-undo:\(UUID().uuidString)"
        }
    ) -> String {
        if let existing = undoKeys[feedbackId] { return existing }
        let key = make()
        undoKeys[feedbackId] = key
        return key
    }

    mutating func completeApply(for opportunityId: String) {
        applyKeys[opportunityId] = nil
    }

    mutating func completeUndo(for feedbackId: String) {
        undoKeys[feedbackId] = nil
    }
}

struct LeadDispositionContext: Decodable, Equatable {
    let phaseCEnabled: Bool
    let policyVersion: String

    enum CodingKeys: String, CodingKey {
        case phaseCEnabled = "phase_c_enabled"
        case policyVersion = "policy_version"
    }
}

struct LeadDispositionResult: Decodable, Equatable {
    let feedbackId: String
    let outcome: LeadDispositionOutcome
    let priorStage: PipelineStage
    let currentStage: PipelineStage
    let currentStageEnteredAt: String
    let currentStageManuallySet: Bool
    let currentLostReason: String?
    let currentLostNotes: String?
    let currentActualCloseDate: String?
    let lifecycleChanged: Bool
    let idempotentReplay: Bool

    enum CodingKeys: String, CodingKey {
        case feedbackId = "feedback_id"
        case outcome
        case priorStage = "prior_stage"
        case currentStage = "current_stage"
        case currentStageEnteredAt = "current_stage_entered_at"
        case currentStageManuallySet = "current_stage_manually_set"
        case currentLostReason = "current_lost_reason"
        case currentLostNotes = "current_lost_notes"
        case currentActualCloseDate = "current_actual_close_date"
        case lifecycleChanged = "lifecycle_changed"
        case idempotentReplay = "idempotent_replay"
    }
}

@MainActor
enum LeadDispositionLocalState {
    static func apply(_ result: LeadDispositionResult, to opportunity: Opportunity) {
        opportunity.stage = result.currentStage
        opportunity.stageEnteredAt =
            SupabaseDate.parse(result.currentStageEnteredAt) ?? opportunity.stageEnteredAt
        opportunity.stageManuallySet = result.currentStageManuallySet
        opportunity.lostReason = result.currentLostReason
        opportunity.lostNotes = result.currentLostNotes
        opportunity.actualCloseDate =
            result.currentActualCloseDate.flatMap(SupabaseDate.parseDateOnly)
    }

    static func applyUndo(_ result: LeadDispositionResult, to opportunity: Opportunity) {
        apply(result, to: opportunity)
    }
}
