//
//  Status.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI

/// Status enum matching your Bubble Job Status exactly
enum Status: String, Codable, CustomStringConvertible, CaseIterable {
    case rfq = "RFQ"
    case estimated = "Estimated"
    case accepted = "Accepted"
    case inProgress = "In Progress"
    case completed = "Completed"
    case closed = "Closed"
    case archived = "Archived"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if rawValue == "Pending" {
            self = .rfq
        } else if let status = Status(rawValue: rawValue) {
            self = status
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize Status from invalid String value \(rawValue)"
            )
        }
    }

    var displayName: String {
        return self.rawValue
    }

    var description: String {
        return self.rawValue
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
