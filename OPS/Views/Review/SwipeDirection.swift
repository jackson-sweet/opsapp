//
//  SwipeDirection.swift
//  OPS
//

import SwiftUI

/// Swipe directions for the project payment review card stack.
enum SwipeDirection {
    case right   // Close (paid)
    case left    // Skip
    case up      // Send reminder (financial access only)
    case down    // Write off (financial access only)

    var label: String {
        switch self {
        case .right: return "CLOSED"
        case .left:  return "SKIP"
        case .up:    return "SEND REMINDER"
        case .down:  return "CLOSE & MARK BAD DEBT"
        }
    }

    var icon: String {
        switch self {
        case .right: return "checkmark.circle.fill"
        case .left:  return "arrow.right.circle"
        case .up:    return "bell.fill"
        case .down:  return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .right: return OPSStyle.Colors.successStatus
        case .left:  return OPSStyle.Colors.tertiaryText
        case .up:    return OPSStyle.Colors.primaryAccent
        case .down:  return OPSStyle.Colors.errorStatus
        }
    }

    var stampRotation: Double {
        switch self {
        case .right: return -15
        case .left:  return 15
        case .up, .down: return 0
        }
    }
}
