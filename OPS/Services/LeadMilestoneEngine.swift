//
//  LeadMilestoneEngine.swift
//  OPS
//
//  The day sheet's stage → event map. Each open stage has exactly one next
//  real-world event worth stamping; the stage advances as a consequence of
//  the stamp, never the other way around. Pure, dependency-free, and the
//  single source for the milestone button's copy and its stage write.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §4
//

import Foundation

/// Spec §4 — the next real-world event worth stamping, per stage.
/// A stamp advances the stage as a consequence; it is never a picker.
enum LeadMilestone: Equatable {
    case contacted        // new_lead   -> qualifying
    case siteVisited      // qualifying -> quoting
    case quoteSent        // quoting    -> quoted
    case won              // quoted / follow_up / negotiation -> won flow

    var label: String {
        switch self {
        case .contacted:   return "CONTACTED"
        case .siteVisited: return "SITE VISITED"
        case .quoteSent:   return "QUOTE SENT"
        case .won:         return "WON"
        }
    }

    var confirmationLabel: String {
        switch self {
        case .contacted:   return "CONTACTED ✓"
        case .siteVisited: return "VISITED ✓"
        case .quoteSent:   return "QUOTED ✓"
        case .won:         return "WON"
        }
    }

    /// Stage written on stamp. `nil` = handled by the won flow, not a direct write.
    var targetStage: PipelineStage? {
        switch self {
        case .contacted:   return .qualifying
        case .siteVisited: return .quoting
        case .quoteSent:   return .quoted
        case .won:         return nil
        }
    }

    static func milestone(for stage: PipelineStage) -> LeadMilestone? {
        switch stage {
        case .newLead:      return .contacted
        case .qualifying:   return .siteVisited
        case .quoting:      return .quoteSent
        case .quoted, .followUp, .negotiation: return .won
        case .won, .lost, .discarded: return nil
        }
    }
}
