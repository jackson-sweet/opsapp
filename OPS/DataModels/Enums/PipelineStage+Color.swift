//
//  PipelineStage+Color.swift
//  OPS
//
//  Stage color mapping from bible 09_FINANCIAL_SYSTEM.md § Pipeline Stages.
//  First iOS use of stage colors; previously web-only.
//

import SwiftUI

extension PipelineStage {
    /// Color identity for this stage.
    var color: Color {
        switch self {
        case .newLead:     return Color(red: 0.737, green: 0.737, blue: 0.737)  // #BCBCBC
        case .qualifying:  return Color(red: 0.506, green: 0.584, blue: 0.710)  // #8195B5
        case .quoting:     return Color(red: 0.769, green: 0.659, blue: 0.408)  // #C4A868
        case .quoted:      return Color(red: 0.710, green: 0.639, blue: 0.506)  // #B5A381
        case .followUp:    return Color(red: 0.631, green: 0.510, blue: 0.710)  // #A182B5
        case .negotiation: return Color(red: 0.710, green: 0.510, blue: 0.537)  // #B58289
        case .won:         return Color(red: 0.616, green: 0.710, blue: 0.510)  // #9DB582
        case .lost:        return Color(red: 0.420, green: 0.447, blue: 0.502)  // #6B7280
        case .discarded:   return Color(red: 0.345, green: 0.349, blue: 0.380)  // muted graphite
        }
    }
}
