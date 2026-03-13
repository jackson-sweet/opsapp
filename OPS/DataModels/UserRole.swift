//
//  UserRole.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import Foundation

enum UserRole: String, Codable, CaseIterable {
    case admin = "admin"
    case owner = "owner"
    case office = "office"
    case `operator` = "operator"
    case crew = "crew"
    case unassigned = "unassigned"

    // Handle legacy and title-case values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "Admin", "admin": self = .admin
        case "Owner", "owner": self = .owner
        case "Office Crew", "Office", "office_crew", "office": self = .office
        case "Operator", "operator": self = .operator
        case "Field Crew", "Crew", "field_crew", "crew": self = .crew
        case "Unassigned", "unassigned": self = .unassigned
        default:
            guard let role = UserRole(rawValue: rawValue) else {
                // Fall back to unassigned for unknown roles instead of crashing
                self = .unassigned
                return
            }
            self = role
        }
    }

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .owner: return "Owner"
        case .office: return "Office"
        case .operator: return "Operator"
        case .crew: return "Crew"
        case .unassigned: return "Unassigned"
        }
    }

    var roleDescription: String {
        switch self {
        case .admin: return "Full system access including billing and team roles."
        case .owner: return "Full access to projects, clients, and company settings."
        case .office: return "Office staff. Full project and financial access."
        case .operator: return "Lead tech. Quotes jobs, manages assigned work."
        case .crew: return "Field access. Views assigned work and logs time."
        case .unassigned: return "New team member. Role not yet assigned by admin."
        }
    }

    var hierarchy: Int {
        switch self {
        case .admin: return 1
        case .owner: return 2
        case .office: return 3
        case .operator: return 4
        case .crew: return 5
        case .unassigned: return 6
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