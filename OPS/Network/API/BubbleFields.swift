//
//  BubbleFields.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation

/// Exact field mappings from Bubble to Swift
/// This ensures our code matches your Bubble database structure perfectly
struct BubbleFields {
    
    /// Entity types in Bubble
    struct Types {
        static let client = "Client"
        static let company = "Company"
        static let project = "Project"
        static let user = "User"
    }
    
    /// Job status values (from your Job Status custom type)
    struct JobStatus {
        static let rfq = "RFQ"
        static let estimated = "Estimated"
        static let accepted = "Accepted"
        static let inProgress = "In Progress"
        static let completed = "Completed"
        static let closed = "Closed"
        
        static func toSwiftEnum(_ bubbleStatus: String) -> Status {
            switch bubbleStatus {
            case rfq: return .rfq
            case estimated: return .estimated
            case accepted: return .accepted
            case inProgress: return .inProgress
            case completed: return .completed
            case closed: return .closed
            default: return .rfq // Default to RFQ if unknown
            }
        }
    }
    
    /// Employee Type values (from your Employee Type custom type)
    struct EmployeeType {
        static let officeCrew = "Office Crew"
        static let fieldCrew = "Field Crew"
        
        static func toSwiftEnum(_ bubbleType: String) -> UserRole {
            switch bubbleType {
            case officeCrew: return .officeCrew
            case fieldCrew: return .fieldCrew
            default: return .fieldCrew // Default to field crew if unknown
            }
        }
    }
    
    /// User Type values (from your User Type custom type)
    struct UserType {
        static let company = "Company"
        static let employee = "Employee"
        static let client = "Client"
        static let admin = "Admin"
    }
    
    /// Project entity fields (match your Bubble field names exactly)
    struct Project {
        static let id = "_id" // Bubble uses _id for internal ID
        static let address = "Address"
        static let allDay = "All Day"
        static let client = "Client"
        static let company = "Company"
        static let completion = "Completion"
        static let description = "Description"
        static let projectName = "Project Name"
        static let startDate = "Start Date"
        static let status = "Status"
        static let teamMembers = "Team Members"
        static let teamNotes = "Team Notes"
    }
    
    /// User entity fields (match your Bubble field names exactly)
    struct User {
        static let id = "_id" // Bubble uses _id for internal ID
        static let clientID = "Client ID"
        static let company = "Company"
        static let currentLocation = "Current Location"
        static let employeeType = "Employee Type"
        static let nameFirst = "Name First"
        static let nameLast = "Name Last"
        static let userType = "User Type"
        static let avatar = "Avatar"
        static let email = "email" // Bubble's built-in field
    }
    
    /// Company entity fields (match your Bubble field names exactly)
    struct Company {
        static let id = "_id" // Bubble uses _id for internal ID
        static let companyName = "Company Name"
        static let companyID = "companyID"
        static let location = "Location"
        static let logo = "Logo"
        static let projects = "Projects"
        static let teams = "Teams"
    }
    
    /// Client entity fields (match your Bubble field names exactly)
    struct Client {
        static let id = "_id" // Bubble uses _id for internal ID
        static let address = "Address"
        static let name = "Name"
        static let phoneNumber = "Phone Number"
        static let emailAddress = "Email Address"
        static let projectsList = "Projects List"
    }
}

/// Corresponding Swift enums to match your Bubble custom types
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
    
    var isActive: Bool {
        return self == .inProgress || self == .accepted
    }
    
    var isCompleted: Bool {
        return self == .completed || self == .closed
    }
}

/// Matching your Employee Type custom type
enum UserRole: String, Codable {
    case fieldCrew = "Field Crew"
    case officeCrew = "Office Crew"
    
    var displayName: String {
        return self.rawValue
    }
}

/// Matching your User Type custom type
enum UserType: String, Codable {
    case company = "Company"
    case employee = "Employee" 
    case client = "Client"
    case admin = "Admin"
}