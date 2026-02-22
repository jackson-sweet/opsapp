//
//  Status.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI

/// Status enum matching your Bubble Job Status exactly
enum Status: String, Codable, CustomStringConvertible, CaseIterable {
    case rfq = "rfq"
    case estimated = "estimated"
    case accepted = "accepted"
    case inProgress = "in_progress"
    case completed = "completed"
    case closed = "closed"
    case archived = "archived"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle legacy title-case values from Bubble
        switch rawValue {
        case "Pending": self = .rfq
        case "RFQ": self = .rfq
        case "Estimated": self = .estimated
        case "Accepted": self = .accepted
        case "In Progress": self = .inProgress
        case "Completed": self = .completed
        case "Closed": self = .closed
        case "Archived": self = .archived
        default:
            if let status = Status(rawValue: rawValue) {
                self = status
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot initialize Status from invalid String value \(rawValue)"
                )
            }
        }
    }

    var displayName: String {
        switch self {
        case .rfq: return "RFQ"
        case .estimated: return "Estimated"
        case .accepted: return "Accepted"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .closed: return "Closed"
        case .archived: return "Archived"
        }
    }

    var description: String {
        return displayName
    }

    var color: Color {
        // Use the app's styled status colors from OPSStyle
        return OPSStyle.Colors.statusColor(for: self)
    }

    var isActive: Bool {
        return self == .inProgress || self == .accepted
    }

    var isCompleted: Bool {
        return self == .completed || self == .closed || self == .archived
    }

    func nextStatus() -> Status? {
        switch self {
        case .rfq: return .estimated
        case .estimated: return .accepted
        case .accepted: return .inProgress
        case .inProgress: return .completed
        case .completed: return .closed
        case .closed: return nil
        case .archived: return .accepted
        }
    }

    func previousStatus() -> Status? {
        switch self {
        case .rfq: return nil
        case .estimated: return .rfq
        case .accepted: return .estimated
        case .inProgress: return .accepted
        case .completed: return .inProgress
        case .closed: return .completed
        case .archived: return nil
        }
    }

    var canSwipeForward: Bool {
        return nextStatus() != nil
    }

    var canSwipeBackward: Bool {
        return previousStatus() != nil
    }

    var sortOrder: Int {
        switch self {
        case .rfq: return 0
        case .estimated: return 1
        case .accepted: return 2
        case .inProgress: return 3
        case .completed: return 4
        case .closed: return 5
        case .archived: return 6
        }
    }
}

// UserRole and UserType have been moved to UserRole.swift
