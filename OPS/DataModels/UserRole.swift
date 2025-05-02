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

enum UserType: String, Codable {
    case company = "Company"
    case employee = "Employee"
    case client = "Client"
    case admin = "Admin"
    case contractor = "Contractor"
    case other = "Other"
}