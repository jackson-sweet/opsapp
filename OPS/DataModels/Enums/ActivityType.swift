//
//  ActivityType.swift
//  OPS
//
//  Activity types for pipeline timeline
//

import Foundation

enum ActivityType: String, Codable, CaseIterable {
    case note             = "note"
    case email            = "email"
    case call             = "call"
    case meeting          = "meeting"
    case estimateSent     = "estimate_sent"
    case estimateApproved = "estimate_accepted"
    case estimateDeclined = "estimate_declined"
    case invoiceSent      = "invoice_sent"
    case paymentReceived  = "payment_received"
    case stageChange      = "stage_change"
    case created          = "created"
    case won              = "won"
    case lost             = "lost"
    case siteVisit        = "site_visit"
    case system           = "system"

    var icon: String {
        switch self {
        case .note:             return "note.text"
        case .email:            return "envelope.fill"
        case .call:             return "phone.fill"
        case .meeting:          return "person.2.fill"
        case .estimateSent:     return "doc.text.fill"
        case .estimateApproved: return "checkmark.circle.fill"
        case .estimateDeclined: return "xmark.circle.fill"
        case .invoiceSent:      return "receipt"
        case .paymentReceived:  return "dollarsign.circle.fill"
        case .stageChange:      return "arrow.forward.circle.fill"
        case .created:          return "plus.circle.fill"
        case .won:              return "checkmark.seal.fill"
        case .lost:             return "xmark.seal.fill"
        case .siteVisit:        return "mappin.circle.fill"
        case .system:           return "gear"
        }
    }

    var isSystemGenerated: Bool {
        switch self {
        case .stageChange, .created, .won, .lost, .system,
             .estimateSent, .estimateApproved, .estimateDeclined,
             .invoiceSent, .paymentReceived: return true
        default: return false
        }
    }
}
