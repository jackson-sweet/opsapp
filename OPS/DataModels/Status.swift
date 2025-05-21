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
    case pending = "Pending" 
    case archived = "Archived"
    
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
}

// UserRole and UserType have been moved to UserRole.swift
