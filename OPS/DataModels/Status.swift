//
//  Status.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import SwiftUI

/// Status enum matching your Bubble Job Status exactly
enum Status: String, Codable {
    case rfq = "RFQ"
    case estimated = "Estimated"
    case accepted = "Accepted"
    case inProgress = "In Progress"
    case completed = "Completed"
    case closed = "Closed"
    
    var displayName: String {
        return self.rawValue
    }
    
    var color: Color {
        switch self {
        case .rfq:
            return .gray
        case .estimated:
            return .blue
        case .accepted:
            return .purple
        case .inProgress:
            return .orange
        case .completed:
            return .green
        case .closed:
            return .red
        }
    }
    
    var isActive: Bool {
        return self == .inProgress || self == .accepted
    }
    
    var isCompleted: Bool {
        return self == .completed || self == .closed
    }
}

/// User role enum matching your Bubble Employee Type
enum UserRole: String, Codable {
    case fieldCrew = "Field Crew"
    case officeCrew = "Office Crew"
    
    var displayName: String {
        return self.rawValue
    }
}

/// User type enum matching your Bubble User Type
enum UserType: String, Codable {
    case company = "Company"
    case employee = "Employee"
    case client = "Client"
    case admin = "Admin"
}
