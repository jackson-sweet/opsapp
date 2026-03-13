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
        case .right: return "checkmark.circle"
        case .left:  return "arrow.right.circle"
        case .up:    return "bell"
        case .down:  return "xmark.circle"
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

/// Configurable labels/icons/colors for swipe directions.
struct SwipeActionConfig {
    let label: String
    let icon: String
    let color: Color

    static func paymentConfig(for direction: SwipeDirection) -> SwipeActionConfig {
        SwipeActionConfig(label: direction.label, icon: direction.icon, color: direction.color)
    }

    static func taskConfig(for direction: SwipeDirection) -> SwipeActionConfig {
        switch direction {
        case .right:
            return SwipeActionConfig(label: "COMPLETE", icon: "checkmark.circle", color: OPSStyle.Colors.successStatus)
        case .left:
            return SwipeActionConfig(label: "SKIP", icon: "arrow.right.circle", color: OPSStyle.Colors.tertiaryText)
        case .up:
            return SwipeActionConfig(label: "RESCHEDULE", icon: "calendar.badge.clock", color: OPSStyle.Colors.primaryAccent)
        case .down:
            return SwipeActionConfig(label: "CANCEL", icon: "xmark.circle", color: OPSStyle.Colors.errorStatus)
        }
    }
}
