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
    
    var displayName: String {
        return self.rawValue
    }
}

enum UserType: String, CaseIterable, Codable {
    case employee = "Employee"
    case company = "Company"
    
    var displayName: String {
        switch self {
        case .employee:
            return "Employee"
        case .company:
            return "Business Owner"
        }
    }
}