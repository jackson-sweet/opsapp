//
//  UserRole.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import Foundation

enum UserRole: String, Codable {
    case fieldCrew = "Field Crew"
    case officeCrew = "Office Crew"
    case admin = "Admin"
    
    var displayName: String {
        return self.rawValue
    }
}

enum UserType: String, CaseIterable, Codable {
    case employee = "employee"
    case company = "company"
    
    var displayName: String {
        switch self {
        case .employee:
            return "Employee"
        case .company:
            return "Business Owner"
        }
    }
    
    // Custom decoding to handle migration from old capitalized values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        // Handle old capitalized values
        switch rawValue.lowercased() {
        case "employee":
            self = .employee
        case "company":
            self = .company
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid UserType value: \(rawValue)"
            )
        }
    }
}