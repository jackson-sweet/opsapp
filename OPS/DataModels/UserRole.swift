//
//  UserRole.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import Foundation

enum UserRole: String, Codable {
    case fieldCrew = "field_crew"
    case officeCrew = "office_crew"
    case admin = "admin"

    // Handle legacy title-case values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "Field Crew": self = .fieldCrew
        case "Office Crew": self = .officeCrew
        case "Admin": self = .admin
        default:
            guard let role = UserRole(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid UserRole value: \(rawValue)"
                )
            }
            self = role
        }
    }

    var displayName: String {
        switch self {
        case .fieldCrew: return "Field Crew"
        case .officeCrew: return "Office Crew"
        case .admin: return "Admin"
        }
    }
}

enum UserType: String, CaseIterable, Codable {
    case employee = "employee"
    case company = "company"

    // Handle legacy title-case values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue.lowercased() {
        case "employee": self = .employee
        case "company": self = .company
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid UserType value: \(rawValue)"
            )
        }
    }

    var displayName: String {
        switch self {
        case .employee:
            return "Employee"
        case .company:
            return "Business Owner"
        }
    }
}