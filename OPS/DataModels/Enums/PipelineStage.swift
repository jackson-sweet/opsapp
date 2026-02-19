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
        }
    }

    var isTerminal: Bool {
        self == .won || self == .lost
    }

    var next: PipelineStage? {
        switch self {
        case .newLead:     return .qualifying
        case .qualifying:  return .quoting
        case .quoting:     return .quoted
        case .quoted:      return .followUp
        case .followUp:    return .negotiation
        case .negotiation: return .won
        case .won, .lost:  return nil
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
        case .won, .lost:  return Int.max
        }
    }
}
