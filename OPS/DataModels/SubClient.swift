//
//  SubClient.swift
//  OPS
//
//  Sub-client model for storing contact information of client team members
//

import Foundation
import SwiftData

@Model
final class SubClient: Identifiable {
    // MARK: - Properties
    var id: String
    var name: String
    var title: String?
    var email: String?
    var phoneNumber: String?
    var address: String?
    
    // MARK: - Relationships
    var client: Client?
    
    // MARK: - Metadata
    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    // MARK: - Initialization
    init(
        id: String,
        name: String,
        title: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        address: String? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.email = email
        self.phoneNumber = phoneNumber
        self.address = address
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Computed Properties
    
    /// Full display name with title if available
    var displayName: String {
        if let title = title, !title.isEmpty {
            return "\(name) - \(title)"
        }
        return name
    }
    
    /// Initials for avatar display
    var initials: String {
        let names = name.components(separatedBy: " ")
        let firstInitial = names.first?.first?.uppercased() ?? ""
        let lastInitial = names.count > 1 ? names.last?.first?.uppercased() ?? "" : ""
        return "\(firstInitial)\(lastInitial)"
    }
    
    /// Check if sub-client has any contact information
    var hasContactInfo: Bool {
        return email != nil || phoneNumber != nil
    }
    
    /// Format phone number for display
    var formattedPhoneNumber: String? {
        guard let phone = phoneNumber else { return nil }
        
        // Extract only digits
        let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Format based on length
        if cleaned.count == 10 {
            let areaCode = cleaned.prefix(3)
            let prefix = cleaned.dropFirst(3).prefix(3)
            let number = cleaned.dropFirst(6)
            return "(\(areaCode)) \(prefix)-\(number)"
        } else if cleaned.count == 11 && cleaned.first == "1" {
            let countryCode = cleaned.prefix(1)
            let areaCode = cleaned.dropFirst().prefix(3)
            let prefix = cleaned.dropFirst(4).prefix(3)
            let number = cleaned.dropFirst(7)
            return "+\(countryCode) (\(areaCode)) \(prefix)-\(number)"
        }
        
        return phoneNumber
    }
}

// MARK: - Hashable
extension SubClient: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SubClient, rhs: SubClient) -> Bool {
        return lhs.id == rhs.id
    }
}