//
//  PipelineStage.swift
//  OPS
//
//  Pipeline deal stages
//

import Foundation

enum PipelineStage: String, Codable, CaseIterable, Identifiable {
    case newLead      = "new_lead"
    case qualifying   = "qualifying"
    case quoting      = "quoting"
    case quoted       = "quoted"
    case followUp     = "follow_up"
    case negotiation  = "negotiation"
    case won          = "won"
    case lost         = "lost"
    case discarded    = "discarded"   // junk state (migration 045); terminal, never in the triage queue. Operator-settable from iOS via the Discard action (move_opportunity_stage).

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newLead:     return "NEW LEAD"
        case .qualifying:  return "QUALIFYING"
        case .quoting:     return "QUOTING"
        case .quoted:      return "QUOTED"
        case .followUp:    return "FOLLOW-UP"
        case .negotiation: return "NEGOTIATION"
        case .won:         return "WON"
        case .lost:        return "LOST"
        case .discarded:   return "DISCARDED"
        }
    }

    var isTerminal: Bool {
        self == .won || self == .lost || self == .discarded
    }

    var next: PipelineStage? {
        switch self {
        case .newLead:     return .qualifying
        case .qualifying:  return .quoting
        case .quoting:     return .quoted
        case .quoted:      return .followUp
        case .followUp:    return .negotiation
        case .negotiation: return .won
        case .won, .lost, .discarded:  return nil
        }
    }

    var winProbability: Int {
        switch self {
        case .newLead:     return 10
        case .qualifying:  return 20
        case .quoting:     return 40
        case .quoted:      return 60
        case .followUp:    return 50
        case .negotiation: return 75
        case .won:         return 100
        case .lost:        return 0
        case .discarded:   return 0
        }
    }

    var staleThresholdDays: Int {
        switch self {
        case .newLead:     return 3
        case .qualifying:  return 7
        case .quoting:     return 5
        case .quoted:      return 7
        case .followUp:    return 3
        case .negotiation: return 2
        case .won, .lost, .discarded:  return Int.max
        }
    }

    /// Compact 3–7 char variant of `displayName` for dense captions — triage
    /// card meta rows, stage-history chains, the by-stage strip. `displayName`
    /// is the full uppercase name ("NEW LEAD", "QUALIFYING", …); this trims it
    /// so a stage cell stays on one line. (Promoted here from the retired
    /// LeadActionCard; consumed by LeadTriageCard, LeadsByStageRow, StageTimeline,
    /// and the Books command grid.)
    var shortLabel: String {
        switch self {
        case .newLead:     return "NEW"
        case .qualifying:  return "QUAL"
        case .quoting:     return "QUOTING"
        case .quoted:      return "QUOTED"
        case .followUp:    return "FOLLOW"
        case .negotiation: return "NEGOT"
        case .won:         return "WON"
        case .lost:        return "LOST"
        case .discarded:   return "DISC"
        }
    }
}
