//
//  OpsContact.swift
//  OPS
//
//  Model for OPS support contacts fetched from Bubble option set
//

import Foundation
import SwiftData

@Model
final class OpsContact {
    var id: String
    var email: String
    var name: String
    var phone: String
    var display: String
    var role: String // jack, priority support, data setup, general support, web app auto send
    var lastSynced: Date
    
    init(
        id: String,
        email: String,
        name: String,
        phone: String,
        display: String,
        role: String,
        lastSynced: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.phone = phone
        self.display = display
        self.role = role
        self.lastSynced = lastSynced
    }
}

// MARK: - Support Methods
extension OpsContact {
    /// Get the support contact for a specific role
    static func contact(for role: OpsContactRole) -> OpsContact? {
        // This would be fetched from SwiftData
        return nil // Placeholder
    }
    
    /// Check if this is a priority support contact
    var isPrioritySupport: Bool {
        return role.lowercased() == "priority support"
    }
    
    /// Check if this is the main support contact
    var isGeneralSupport: Bool {
        return role.lowercased() == "general support"
    }
}

// MARK: - Contact Roles
enum OpsContactRole: String, CaseIterable {
    case jack = "jack"
    case prioritySupport = "Priority Support"
    case dataSetup = "Data Setup"
    case generalSupport = "General Support"
    case webAppAutoSend = "Web App Auto Send"
    
    var displayName: String {
        switch self {
        case .jack:
            return "Jack"
        case .prioritySupport:
            return "Priority Support"
        case .dataSetup:
            return "Data Setup"
        case .generalSupport:
            return "General Support"
        case .webAppAutoSend:
            return "Automated Messages"
        }
    }
}